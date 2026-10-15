-- Keep SECURITY DEFINER helpers outside Supabase's exposed public API schema.
create schema if not exists private;
revoke all on schema private from public, anon;
grant usage on schema private to authenticated;

create or replace function private.current_store_id()
returns uuid language sql stable security definer set search_path=''
as $$ select p.store_id from public.profiles p where p.id=(select auth.uid()) and p.active $$;
create or replace function private.current_role()
returns text language sql stable security definer set search_path=''
as $$ select p.role from public.profiles p where p.id=(select auth.uid()) and p.active $$;
revoke all on function private.current_store_id() from public, anon;
revoke all on function private.current_role() from public, anon;
grant execute on function private.current_store_id() to authenticated;
grant execute on function private.current_role() to authenticated;

drop policy if exists store_read on public.stores;
create policy store_read on public.stores for select to authenticated
using(id=(select private.current_store_id()));
drop policy if exists store_owner_update on public.stores;
create policy store_owner_update on public.stores for update to authenticated
using(id=(select private.current_store_id()) and (select private.current_role())='owner')
with check(id=(select private.current_store_id()) and (select private.current_role())='owner');
drop policy if exists profiles_same_store on public.profiles;
create policy profiles_same_store on public.profiles for select to authenticated
using(store_id=(select private.current_store_id()));
drop policy if exists profiles_owner_manage on public.profiles;
create policy profiles_owner_manage on public.profiles for all to authenticated
using(store_id=(select private.current_store_id()) and (select private.current_role())='owner')
with check(store_id=(select private.current_store_id()) and (select private.current_role())='owner');
drop policy if exists customers_same_store on public.customers;
create policy customers_same_store on public.customers for all to authenticated
using(store_id=(select private.current_store_id())) with check(store_id=(select private.current_store_id()));
drop policy if exists catalog_read on public.service_catalog;
create policy catalog_read on public.service_catalog for select to authenticated
using(store_id=(select private.current_store_id()));
drop policy if exists catalog_owner_manage on public.service_catalog;
create policy catalog_owner_manage on public.service_catalog for all to authenticated
using(store_id=(select private.current_store_id()) and (select private.current_role())='owner')
with check(store_id=(select private.current_store_id()) and (select private.current_role())='owner');
drop policy if exists transactions_same_store on public.transactions;
create policy transactions_same_store on public.transactions for all to authenticated
using(store_id=(select private.current_store_id())) with check(store_id=(select private.current_store_id()));
drop policy if exists items_same_store on public.transaction_items;
create policy items_same_store on public.transaction_items for all to authenticated
using(store_id=(select private.current_store_id())) with check(store_id=(select private.current_store_id()));
drop policy if exists rewards_same_store on public.membership_rewards;
create policy rewards_same_store on public.membership_rewards for all to authenticated
using(store_id=(select private.current_store_id())) with check(store_id=(select private.current_store_id()));
drop policy if exists kiloan_same_store on public.kiloan_orders;
create policy kiloan_same_store on public.kiloan_orders for all to authenticated
using(store_id=(select private.current_store_id())) with check(store_id=(select private.current_store_id()));
drop policy if exists expenses_same_store on public.expenses;
create policy expenses_same_store on public.expenses for all to authenticated
using(store_id=(select private.current_store_id())) with check(store_id=(select private.current_store_id()));
drop policy if exists inventory_read on public.inventory_items;
create policy inventory_read on public.inventory_items for select to authenticated
using(store_id=(select private.current_store_id()));
drop policy if exists inventory_owner_manage on public.inventory_items;
create policy inventory_owner_manage on public.inventory_items for all to authenticated
using(store_id=(select private.current_store_id()) and (select private.current_role())='owner')
with check(store_id=(select private.current_store_id()) and (select private.current_role())='owner');
drop policy if exists closings_same_store on public.daily_closings;
create policy closings_same_store on public.daily_closings for all to authenticated
using(store_id=(select private.current_store_id())) with check(store_id=(select private.current_store_id()));
drop policy if exists membership_events_read on public.membership_events;
create policy membership_events_read on public.membership_events for select to authenticated
using(store_id=(select private.current_store_id()));
drop policy if exists daily_traffic_same_store on public.daily_traffic;
create policy daily_traffic_same_store on public.daily_traffic for all to authenticated
using(store_id=(select private.current_store_id())) with check(store_id=(select private.current_store_id()));

drop function public.current_store_id();
drop function public.current_role();
