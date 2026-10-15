-- Validate persisted transaction items against the active store catalog before payment.
create or replace function public.validate_paid_transaction()
returns trigger language plpgsql set search_path=''
as $$
begin
  if old.status='paid' or new.status<>'paid' then return new; end if;
  if not exists (
    select 1 from public.transaction_items i
     where i.transaction_id=new.id and i.store_id=new.store_id
  ) then
    raise exception 'A paid transaction must contain at least one catalog item.';
  end if;
  if exists (
    select 1
      from public.transaction_items i
      left join public.service_catalog s on s.id=i.service_id and s.store_id=i.store_id
     where i.transaction_id=new.id and i.store_id=new.store_id
       and (s.id is null or s.price_is_demo
            or i.scope<>s.category
            or i.unit_price<>s.price
            or i.unit_cost<>s.estimated_unit_cost
            or i.line_total<>round(i.quantity*i.unit_price,2)
            or (new.channel='self_service' and i.scope not in ('self_service_main','addon','product'))
            or (new.channel in ('kiloan_retail','b2b') and i.scope<>'kiloan_service'))
  ) then
    raise exception 'Update demo prices in the catalog before accepting payment.';
  end if;
  return new;
end $$;
revoke all on function public.validate_paid_transaction() from public, anon, authenticated;
drop trigger if exists a_paid_transaction_price_guard on public.transactions;
create trigger a_paid_transaction_price_guard
before update of status on public.transactions
for each row execute function public.validate_paid_transaction();
