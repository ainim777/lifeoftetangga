-- Constrain browser writes to operational fields; keep totals and membership server-controlled.
revoke update, delete on public.customers from authenticated;
grant update(name,whatsapp,customer_type) on public.customers to authenticated;

revoke update, delete on public.transactions from authenticated;
grant update(status,payment_method) on public.transactions to authenticated;

revoke update, delete on public.transaction_items from authenticated;
grant select, insert on public.transaction_items to authenticated;

revoke insert, update, delete on public.membership_rewards from authenticated;
grant select on public.membership_rewards to authenticated;

revoke update, delete on public.kiloan_orders from authenticated;
grant update(status,picked_up_at) on public.kiloan_orders to authenticated;

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
  elsif old.status='unpaid' then
    if new.status not in ('unpaid','paid','void') then
      raise exception 'An unpaid transaction can only be paid or voided.';
    end if;
  elsif new.status is distinct from old.status then
    raise exception 'A refunded or voided transaction cannot be reopened.';
  end if;
  return new;
end $$;
revoke all on function public.guard_transaction_state_change() from public,anon,authenticated;
drop trigger if exists a_transaction_state_guard on public.transactions;
create trigger a_transaction_state_guard
before update of status,payment_method on public.transactions
for each row execute function public.guard_transaction_state_change();

create or replace function public.guard_paid_item_edits()
returns trigger language plpgsql set search_path=''
as $$
declare transaction_status text;
begin
  select t.status into transaction_status
    from public.transactions t
   where t.id=coalesce(new.transaction_id,old.transaction_id);
  if transaction_status is distinct from 'unpaid' then
    raise exception 'Transaction items cannot be changed after the transaction is paid or closed.';
  end if;
  if tg_op='DELETE' then return old; end if;
  return new;
end $$;
revoke all on function public.guard_paid_item_edits() from public,anon,authenticated;
drop trigger if exists transaction_item_lock_after_payment on public.transaction_items;
create trigger transaction_item_lock_after_payment
before update or delete on public.transaction_items
for each row execute function public.guard_paid_item_edits();
