-- Payment entry validates the outstanding balance and marks a ticket paid only
-- when the accumulated amount covers the full total; paid triggers then handle membership.
create or replace function public.apply_transaction_payment()
returns trigger language plpgsql security definer set search_path=''
as $$
declare t public.transactions%rowtype; paid numeric(12,2);
begin
  select * into t from public.transactions where id=new.transaction_id and store_id=new.store_id for update;
  if not found or t.status not in ('unpaid','partial') then raise exception 'Tagihan ini tidak lagi dapat menerima pembayaran.'; end if;
  select coalesce(sum(p.amount),0)-new.amount into paid from public.transaction_payments p where p.transaction_id=new.transaction_id;
  if paid+new.amount>t.total then raise exception 'Jumlah pembayaran melebihi sisa tagihan.'; end if;
  update public.transactions set status=case when paid+new.amount>=t.total then 'paid' else 'partial' end,
    payment_method=new.payment_method where id=t.id;
  return new;
end $$;
revoke all on function public.apply_transaction_payment() from public,anon,authenticated;
drop trigger if exists transaction_payment_apply on public.transaction_payments;
create trigger transaction_payment_apply after insert on public.transaction_payments for each row execute function public.apply_transaction_payment();

-- Product quantities are reduced once when an order becomes paid and restored once on refund/void.
create or replace function public.apply_product_stock_change()
returns trigger language plpgsql security definer set search_path=''
as $$
declare i record; stock public.inventory_items%rowtype;
begin
  if new.status='paid' and old.status<>'paid' and new.stock_deducted_at is null then
    for i in select ti.name,ti.quantity from public.transaction_items ti join public.service_catalog sc on sc.id=ti.service_id where ti.transaction_id=new.id and ti.scope='product' loop
      select * into stock from public.inventory_items where store_id=new.store_id and name=i.name and category='product' for update;
      if not found or stock.quantity<i.quantity then raise exception 'Stok produk % tidak mencukupi.',i.name; end if;
      update public.inventory_items set quantity=quantity-i.quantity where id=stock.id;
      insert into public.inventory_movements(store_id,inventory_item_id,direction,quantity,reason,transaction_id,created_by)
        values(new.store_id,stock.id,'keluar',i.quantity,'Penjualan produk',new.id,new.created_by);
    end loop;
    new.stock_deducted_at:=now();
  elsif old.status='paid' and new.status in ('refunded','void') and old.stock_deducted_at is not null and old.stock_reversed_at is null then
    for i in select ti.name,ti.quantity from public.transaction_items ti where ti.transaction_id=new.id and ti.scope='product' loop
      select * into stock from public.inventory_items where store_id=new.store_id and name=i.name and category='product' for update;
      if found then
        update public.inventory_items set quantity=quantity+i.quantity where id=stock.id;
        insert into public.inventory_movements(store_id,inventory_item_id,direction,quantity,reason,transaction_id,created_by)
          values(new.store_id,stock.id,'masuk',i.quantity,'Pembalikan transaksi produk',new.id,new.created_by);
      end if;
    end loop;
    new.stock_reversed_at:=now();
  end if;
  return new;
end $$;
revoke all on function public.apply_product_stock_change() from public,anon,authenticated;
drop trigger if exists transaction_product_stock on public.transactions;
create trigger transaction_product_stock before update of status on public.transactions for each row execute function public.apply_product_stock_change();

-- Permit staff to correct unpaid transaction items. Totals remain calculated from items.
create or replace function public.recalculate_unpaid_transaction()
returns trigger language plpgsql security definer set search_path=''
as $$
declare tx uuid; sid uuid; amount numeric(12,2);
begin
  tx:=coalesce(new.transaction_id,old.transaction_id);sid:=coalesce(new.store_id,old.store_id);
  select coalesce(sum(line_total),0) into amount from public.transaction_items where transaction_id=tx and store_id=sid;
  update public.transactions set subtotal=amount,total=amount where id=tx and store_id=sid and status='unpaid';
  if tg_op='DELETE' then return old; else return new; end if;
end $$;
revoke all on function public.recalculate_unpaid_transaction() from public,anon,authenticated;
drop trigger if exists transaction_items_recalculate_total on public.transaction_items;
create trigger transaction_items_recalculate_total after insert or update or delete on public.transaction_items for each row execute function public.recalculate_unpaid_transaction();

-- Permit payment and status updates for authorized outlet managers/cashiers;
-- keep audit ownership immutable and allow partial balances.
create or replace function public.guard_transaction_state_change()
returns trigger language plpgsql security definer set search_path=''
as $$
begin
  if new.store_id<>old.store_id or new.created_by<>old.created_by or new.invoice_no<>old.invoice_no then
    raise exception 'Outlet, pembuat, dan nomor nota tidak dapat diubah.';
  end if;
  if old.status in ('void','refunded') and new.status<>old.status then
    raise exception 'Transaksi batal atau refund tidak dapat diaktifkan kembali.';
  end if;
  if old.status='paid' and new.status not in ('paid','refunded','void') then
    raise exception 'Transaksi lunas hanya dapat di-refund atau dibatalkan.';
  end if;
  if old.status in ('unpaid','partial') and new.status='paid' and not exists(
    select 1 from public.transaction_payments p where p.transaction_id=old.id
  ) then
    raise exception 'Catat pembayaran melalui riwayat pembayaran agar total tercatat.';
  end if;
  if not private.has_store_role(old.store_id,array['master','outlet_manager','supervisor','admin']) then
    raise exception 'Akun ini tidak memiliki akses untuk mengubah transaksi.';
  end if;
  return new;
end $$;
revoke all on function public.guard_transaction_state_change() from public,anon,authenticated;
drop trigger if exists transactions_guard_state on public.transactions;
create trigger transactions_guard_state before update on public.transactions for each row execute function public.guard_transaction_state_change();

