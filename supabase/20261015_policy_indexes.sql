-- Avoid duplicate permissive SELECT policies and index remaining foreign keys.
drop policy if exists profiles_owner_manage on public.profiles;
create policy profiles_owner_update on public.profiles for update to authenticated
using(store_id=(select private.current_store_id()) and (select private.current_role())='owner')
with check(store_id=(select private.current_store_id()) and (select private.current_role())='owner');

drop policy if exists catalog_owner_manage on public.service_catalog;
create policy catalog_owner_insert on public.service_catalog for insert to authenticated
with check(store_id=(select private.current_store_id()) and (select private.current_role())='owner');
create policy catalog_owner_update on public.service_catalog for update to authenticated
using(store_id=(select private.current_store_id()) and (select private.current_role())='owner')
with check(store_id=(select private.current_store_id()) and (select private.current_role())='owner');
create policy catalog_owner_delete on public.service_catalog for delete to authenticated
using(store_id=(select private.current_store_id()) and (select private.current_role())='owner');

drop policy if exists inventory_owner_manage on public.inventory_items;
create policy inventory_owner_insert on public.inventory_items for insert to authenticated
with check(store_id=(select private.current_store_id()) and (select private.current_role())='owner');
create policy inventory_owner_update on public.inventory_items for update to authenticated
using(store_id=(select private.current_store_id()) and (select private.current_role())='owner')
with check(store_id=(select private.current_store_id()) and (select private.current_role())='owner');
create policy inventory_owner_delete on public.inventory_items for delete to authenticated
using(store_id=(select private.current_store_id()) and (select private.current_role())='owner');

create index if not exists daily_traffic_created_by_idx on public.daily_traffic(created_by);
create index if not exists membership_events_store_id_idx on public.membership_events(store_id);
create index if not exists transaction_items_store_id_idx on public.transaction_items(store_id);
