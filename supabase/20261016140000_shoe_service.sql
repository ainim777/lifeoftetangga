-- Add a dedicated shoe-care transaction type and demo catalog options.
-- Shoe transactions are deliberately excluded from membership counting and rewards.

alter table public.service_catalog
  drop constraint if exists service_catalog_category_check;
alter table public.service_catalog
  add constraint service_catalog_category_check
  check (category in ('self_service_main','addon','product','kiloan_service','shoe_service'));

alter table public.transaction_items
  drop constraint if exists transaction_items_scope_check;
alter table public.transaction_items
  add constraint transaction_items_scope_check
  check (scope in ('self_service_main','addon','product','kiloan_service','shoe_service'));

alter table public.transactions
  drop constraint if exists transactions_channel_check;
alter table public.transactions
  add constraint transactions_channel_check
  check (channel in ('self_service','kiloan_retail','b2b','shoe_service'));

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
            or (new.channel in ('kiloan_retail','b2b') and i.scope<>'kiloan_service')
            or (new.channel='shoe_service' and i.scope<>'shoe_service'))
  ) then
    raise exception 'Update demo prices in the catalog before accepting payment.';
  end if;
  return new;
end $$;
revoke all on function public.validate_paid_transaction() from public, anon, authenticated;

insert into public.service_catalog(store_id,name,category,price,unit,active,estimated_unit_cost,price_is_demo)
select s.id,v.name,'shoe_service',v.price,'pasang',true,0,true
from public.stores s
cross join (values
  ('Cuci Sepatu Reguler',35000::numeric),
  ('Deep Clean Sepatu',50000::numeric)
) as v(name,price)
where s.name='LifeofTetangga'
on conflict (store_id,name,category) do nothing;
