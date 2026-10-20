-- Secure, idempotent import of legacy transactions and expenses.
-- Historical imports retain the dates and amounts supplied by the owner. They
-- count toward membership at their historic paid date, without spending a
-- reward retroactively or changing today's stock.

create table if not exists private.historical_import_transactions (
  transaction_id uuid primary key references public.transactions(id) on delete cascade
);
revoke all on private.historical_import_transactions from public, anon, authenticated;

alter table public.expenses add column if not exists import_key text;
create unique index if not exists expenses_store_import_key_unique
  on public.expenses(store_id, import_key) where import_key is not null;

create or replace function public.guard_transaction_state_change()
returns trigger language plpgsql set search_path=''
as $$
begin
  if old.status='paid' then
    if new.payment_method is distinct from old.payment_method then
      raise exception 'Payment method cannot be changed after payment is accepted.';
    end if;
    if new.status not in ('paid','refunded','void') then
      raise exception 'A paid transaction can only remain paid, be refunded, or be voided.';
    end if;
    if new.status in ('refunded','void')
       and current_user not in ('postgres','supabase_admin')
       and (select private.current_role()) is distinct from 'owner' then
      raise exception 'Only the owner can refund or void a paid transaction.';
    end if;
  elsif old.status in ('unpaid','partial') then
    if new.status not in ('unpaid','partial','paid','void') then
      raise exception 'An open transaction can only remain open, be paid, or be voided.';
    end if;
  elsif new.status is distinct from old.status then
    raise exception 'A refunded or voided transaction cannot be reopened.';
  end if;
  return new;
end $$;

create or replace function public.validate_paid_transaction()
returns trigger language plpgsql security definer set search_path=''
as $$
begin
  if old.status='paid' or new.status<>'paid' then return new; end if;
  if exists(select 1 from private.historical_import_transactions h where h.transaction_id=new.id) then
    if not exists(select 1 from public.transaction_items i where i.transaction_id=new.id and i.store_id=new.store_id and i.line_total>0) then
      raise exception 'A paid transaction must contain at least one item with a positive total.';
    end if;
    return new;
  end if;
  if not exists (
    select 1 from public.transaction_items i
     where i.transaction_id=new.id and i.store_id=new.store_id
  ) then
    raise exception 'A paid transaction must contain at least one catalog item.';
  end if;
  if exists (
    select 1 from public.transaction_items i
      left join public.service_catalog s on s.id=i.service_id and s.store_id=i.store_id
     where i.transaction_id=new.id and i.store_id=new.store_id
       and (s.id is null or s.price_is_demo
            or i.scope<>s.category
            or i.unit_price<>s.price
            or i.unit_cost<>s.estimated_unit_cost
            or i.line_total<>round(i.quantity*i.unit_price,2)
            or (new.channel='self_service' and i.scope not in ('self_service_main','addon','product'))
            or (new.channel in ('kiloan_retail','b2b') and i.scope<>'kiloan_service')
            or (new.channel='shoe_service' and i.scope<>'shoe_service'))
  ) then
    raise exception 'Update demo prices in the catalog before accepting payment.';
  end if;
  return new;
end $$;
revoke all on function public.validate_paid_transaction() from public,anon,authenticated;

create or replace function public.count_membership_use()
returns trigger language plpgsql security definer set search_path=''
as $$
declare
  n integer;
  main_total numeric(12,2);
  reward_id uuid;
  chosen_reward public.membership_rewards%rowtype;
  is_legacy boolean;
  earned_at timestamptz;
begin
  select exists(select 1 from private.historical_import_transactions h where h.transaction_id=new.id) into is_legacy;
  if tg_op='INSERT' and new.status='paid' then
    raise exception 'Create the transaction as unpaid, add its items, then mark it paid.';
  end if;

  if tg_op='UPDATE' and old.status<>'paid' and new.status='paid' then
    select coalesce(sum(i.line_total),0),
           coalesce(sum(i.line_total) filter (where i.scope='self_service_main'),0)
      into new.subtotal,main_total
      from public.transaction_items i where i.transaction_id=new.id and i.store_id=new.store_id;
    if new.subtotal<=0 then raise exception 'A paid transaction must have at least one item with a positive total.'; end if;

    if not is_legacy then
      new.membership_discount:=0;
      if new.channel='self_service' and new.customer_id is not null and main_total>0 then
        select * into chosen_reward from public.membership_rewards r
         where r.store_id=new.store_id and r.customer_id=new.customer_id
           and r.used_at is null and r.revoked_at is null and r.expires_at>now()
         order by r.expires_at,r.milestone limit 1 for update;
        if found then
          new.membership_discount:=round(main_total*chosen_reward.percent_off/100,2);
          update public.membership_rewards set used_transaction_id=new.id,used_at=now() where id=chosen_reward.id;
          insert into public.membership_events(store_id,customer_id,transaction_id,event_type,use_number,details)
          values(new.store_id,new.customer_id,new.id,'reward_used',chosen_reward.milestone,
                 jsonb_build_object('percent_off',chosen_reward.percent_off,'discount',new.membership_discount));
        end if;
      end if;
      new.total:=greatest(new.subtotal-new.membership_discount,0);
    end if;
    new.paid_at:=coalesce(new.paid_at,now());
  end if;

  if tg_op='UPDATE' and old.status='paid' and new.status in ('refunded','void')
     and old.membership_counted_at is not null and old.membership_reversed_at is null and old.customer_id is not null then
    update public.customers set membership_uses=greatest(membership_uses-1,0)
      where id=old.customer_id and store_id=old.store_id;
    new.membership_reversed_at:=now();
    insert into public.membership_events(store_id,customer_id,transaction_id,event_type,use_number,details)
      values(old.store_id,old.customer_id,old.id,'transaction_reversed',old.membership_use_number,jsonb_build_object('reason',new.status));
    if old.membership_use_number in (5,10) then
      update public.membership_rewards set revoked_at=now(),revoked_reason='Transaksi pemicu progres dibatalkan atau direfund.'
       where store_id=old.store_id and customer_id=old.customer_id and milestone=old.membership_use_number and used_at is null and revoked_at is null;
    end if;
  end if;

  if new.status='paid' and new.channel in ('self_service','kiloan_retail') and new.customer_id is not null
     and (new.membership_counted_at is null or new.membership_reversed_at is not null) then
    update public.customers set membership_uses=membership_uses+1 where id=new.customer_id and store_id=new.store_id returning membership_uses into n;
    if n is not null then
      earned_at:=case when is_legacy then coalesce(new.paid_at,new.created_at,now()) else now() end;
      new.membership_counted_at:=earned_at;
      new.membership_reversed_at:=null;
      new.membership_use_number:=n;
      insert into public.membership_events(store_id,customer_id,transaction_id,event_type,use_number)
        values(new.store_id,new.customer_id,new.id,'use_counted',n);
      if n in (5,10) then
        insert into public.membership_rewards(store_id,customer_id,milestone,earned_at,expires_at)
          values(new.store_id,new.customer_id,n,earned_at,earned_at+interval '30 days')
          on conflict(customer_id,milestone) do update
            set earned_at=excluded.earned_at,expires_at=excluded.expires_at,revoked_at=null,revoked_reason=null
            where membership_rewards.used_at is null
          returning id into reward_id;
        if found then
          insert into public.membership_events(store_id,customer_id,transaction_id,event_type,use_number,details)
          values(new.store_id,new.customer_id,new.id,'reward_earned',n,jsonb_build_object('percent_off',25,'valid_days',30,'scope','self_service_main'));
        end if;
      end if;
    end if;
  end if;
  return new;
end $$;
revoke all on function public.count_membership_use() from public,anon,authenticated;

create or replace function public.apply_product_stock_change()
returns trigger language plpgsql security definer set search_path=''
as $$
declare i record; stock public.inventory_items%rowtype;
begin
  if exists(select 1 from private.historical_import_transactions h where h.transaction_id=new.id) then return new; end if;
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

create or replace function public.import_historical_data(p_store_id uuid,p_transactions jsonb,p_expenses jsonb)
returns jsonb language plpgsql security definer set search_path=''
as $$
declare
  r jsonb; tx_id uuid; customer_id uuid; service_id uuid; invoice text; phone text;
  channel text; scope text; service_name text; q numeric; price numeric; subtotal numeric;
  discount numeric; total numeric; paid numeric; qty_weight numeric; order_status text;
  method text; imported_tx integer:=0; imported_exp integer:=0; skipped_tx integer:=0; skipped_exp integer:=0;
  created_on timestamptz; paid_on timestamptz; spent_on timestamptz; exp_key text;
begin
  if (select auth.uid()) is null or not private.has_store_role(p_store_id,array['master','outlet_manager']) then
    raise exception 'Hanya Master atau Manajer Outlet yang dapat mengimpor data.';
  end if;
  if jsonb_typeof(p_transactions)<>'array' or jsonb_typeof(p_expenses)<>'array'
     or jsonb_array_length(p_transactions)+jsonb_array_length(p_expenses)>500 then
    raise exception 'Format tidak sesuai atau jumlah baris melebihi 500.';
  end if;

  for r in select value from jsonb_array_elements(p_transactions) order by value->>'created_at' loop
    invoice:=nullif(btrim(r->>'invoice_no'),'');
    if invoice is null then raise exception 'Nomor nota wajib diisi.'; end if;
    if exists(select 1 from public.transactions t where t.store_id=p_store_id and t.invoice_no=invoice) then
      skipped_tx:=skipped_tx+1; continue;
    end if;
    channel:=r->>'channel'; scope:=r->>'scope'; service_name:=nullif(btrim(r->>'service_name'),'');
    created_on:=(r->>'created_at')::timestamptz;
    paid_on:=coalesce(nullif(r->>'paid_at','')::timestamptz,created_on);
    if created_on is null or channel not in ('self_service','kiloan_retail','b2b','shoe_service') or service_name is null then raise exception 'Tanggal, jenis layanan, atau nama layanan tidak valid pada nota %.',invoice; end if;
    if (channel='self_service' and scope not in ('self_service_main','addon','product'))
       or (channel in ('kiloan_retail','b2b') and scope<>'kiloan_service')
       or (channel='shoe_service' and scope<>'shoe_service') then raise exception 'Kategori layanan tidak sesuai dengan jenis layanan pada nota %.',invoice; end if;
    q:=nullif(r->>'quantity','')::numeric; price:=nullif(r->>'unit_price','')::numeric;
    subtotal:=coalesce(nullif(r->>'subtotal','')::numeric,q*price);
    discount:=coalesce(nullif(r->>'discount','')::numeric,0);
    total:=coalesce(nullif(r->>'total','')::numeric,subtotal-discount);
    paid:=coalesce(nullif(r->>'paid_amount','')::numeric,0);
    if q is null or q<=0 or price is null or price<0 or subtotal<=0 or discount<0 or total<0 or paid<0 or paid>total then raise exception 'Jumlah atau nominal tidak valid pada nota %.',invoice; end if;
    method:=coalesce(nullif(r->>'payment_method',''),'Tunai');
    if paid>0 and method not in ('Tunai','QR Mesin','QR Tetangga') then raise exception 'Metode pembayaran tidak valid pada nota %.',invoice; end if;
    phone:=nullif(btrim(r->>'whatsapp'),''); customer_id:=null;
    if phone is not null then
      insert into public.customers(store_id,name,whatsapp,customer_type)
        values(p_store_id,btrim(r->>'customer_name'),phone,case when channel='b2b' then 'b2b' else 'retail' end)
        on conflict(store_id,whatsapp) do update set name=excluded.name
        returning id into customer_id;
    end if;
    select s.id into service_id from public.service_catalog s where s.store_id=p_store_id and s.name=service_name and s.category=scope limit 1;
    insert into public.transactions(store_id,invoice_no,customer_id,channel,status,subtotal,membership_discount,total,payment_method,created_by,created_at,paid_at)
      values(p_store_id,invoice,customer_id,channel,'unpaid',subtotal,discount,total,nullif(method,''),auth.uid(),created_on,case when paid>=total and paid>0 then paid_on else null end)
      returning id into tx_id;
    insert into private.historical_import_transactions(transaction_id) values(tx_id);
    insert into public.transaction_items(store_id,transaction_id,service_id,name,scope,quantity,unit_price,unit_cost,line_total)
      values(p_store_id,tx_id,service_id,service_name,scope,q,price,coalesce(nullif(r->>'unit_cost','')::numeric,0),subtotal);
    if paid>0 then
      insert into public.transaction_payments(store_id,transaction_id,amount,payment_method,paid_at,received_by,legacy_import)
        values(p_store_id,tx_id,paid,method,paid_on,auth.uid(),true);
    end if;
    qty_weight:=coalesce(nullif(r->>'weight_kg','')::numeric,0);
    if channel='kiloan_retail' and qty_weight>0 then
      order_status:=coalesce(nullif(r->>'order_status',''),'Diambil');
      if order_status not in ('Masuk','Proses','Selesai','Diambil') then raise exception 'Status pesanan tidak dikenal pada nota %.',invoice; end if;
      insert into public.kiloan_orders(store_id,transaction_id,order_no,weight_kg,status)
        values(p_store_id,tx_id,invoice,qty_weight,order_status);
    end if;
    imported_tx:=imported_tx+1;
  end loop;

  for r in select value from jsonb_array_elements(p_expenses) loop
    exp_key:=nullif(r->>'import_key',''); spent_on:=(r->>'spent_at')::timestamptz;
    if exp_key is null or spent_on is null or coalesce(nullif(r->>'category',''),'')='' or coalesce(nullif(r->>'note',''),'')=''
       or coalesce(nullif(r->>'amount','')::numeric,0)<=0 or r->>'payment_method' not in ('Tunai','QR Mesin','QR Tetangga') then raise exception 'Tanggal, kategori, catatan, jumlah, atau metode pada data pengeluaran tidak valid.'; end if;
    if exists(select 1 from public.expenses e where e.store_id=p_store_id and e.import_key=exp_key) then skipped_exp:=skipped_exp+1; continue; end if;
    insert into public.expenses(store_id,category,note,amount,payment_method,spent_at,created_by,import_key)
      values(p_store_id,btrim(r->>'category'),btrim(r->>'note'),(r->>'amount')::numeric,r->>'payment_method',spent_on,auth.uid(),exp_key);
    imported_exp:=imported_exp+1;
  end loop;
  return jsonb_build_object('imported_transactions',imported_tx,'imported_expenses',imported_exp,'skipped_transactions',skipped_tx,'skipped_expenses',skipped_exp);
end $$;
revoke all on function public.import_historical_data(uuid,jsonb,jsonb) from public,anon;
grant execute on function public.import_historical_data(uuid,jsonb,jsonb) to authenticated;
