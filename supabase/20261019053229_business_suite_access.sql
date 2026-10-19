-- A store member can only view/write outlets to which their account is assigned.
create or replace function private.has_store_access(target_store uuid)
returns boolean language sql stable security definer set search_path=''
as $$ select exists(select 1 from public.store_memberships m where m.user_id=(select auth.uid()) and m.store_id=target_store and m.active) $$;
create or replace function private.has_store_role(target_store uuid, allowed_roles text[])
returns boolean language sql stable security definer set search_path=''
as $$ select exists(select 1 from public.store_memberships m where m.user_id=(select auth.uid()) and m.store_id=target_store and m.active and m.role=any(allowed_roles)) $$;
create or replace function private.can_create_store()
returns boolean language sql stable security definer set search_path=''
as $$ select exists(select 1 from public.store_memberships m where m.user_id=(select auth.uid()) and m.active and m.role='master') $$;
revoke all on function private.has_store_access(uuid),private.has_store_role(uuid,text[]),private.can_create_store() from public,anon;
grant execute on function private.has_store_access(uuid),private.has_store_role(uuid,text[]),private.can_create_store() to authenticated;

-- Replace single-outlet policies with membership-scoped access. Employee and
-- finance records have narrower role gates than everyday operational tables.
drop policy if exists store_read on public.stores;
drop policy if exists store_owner_update on public.stores;
create policy stores_member_read on public.stores for select to authenticated using((select private.has_store_access(id)));
create policy stores_master_insert on public.stores for insert to authenticated with check((select private.can_create_store()));
create policy stores_manager_update on public.stores for update to authenticated
  using((select private.has_store_role(id,array['master','outlet_manager'])))
  with check((select private.has_store_role(id,array['master','outlet_manager'])));
grant insert,select,update on public.stores to authenticated;

drop policy if exists profiles_same_store on public.profiles;
drop policy if exists profiles_owner_update on public.profiles;
create policy profiles_self_read on public.profiles for select to authenticated using(id=(select auth.uid()));
create policy profiles_shared_outlet_read on public.profiles for select to authenticated using(
  exists(select 1 from public.store_memberships a join public.store_memberships b on b.store_id=a.store_id where a.user_id=public.profiles.id and b.user_id=(select auth.uid()) and a.active and b.active)
);

drop policy if exists customers_same_store on public.customers;
create policy customers_member_access on public.customers for all to authenticated
  using((select private.has_store_access(store_id))) with check((select private.has_store_access(store_id)));
drop policy if exists catalog_read on public.service_catalog;
drop policy if exists catalog_owner_insert on public.service_catalog;
drop policy if exists catalog_owner_update on public.service_catalog;
drop policy if exists catalog_owner_delete on public.service_catalog;
create policy catalog_member_read on public.service_catalog for select to authenticated using((select private.has_store_access(store_id)));
create policy catalog_manager_insert on public.service_catalog for insert to authenticated with check((select private.has_store_role(store_id,array['master','outlet_manager','supervisor'])));
create policy catalog_manager_update on public.service_catalog for update to authenticated using((select private.has_store_role(store_id,array['master','outlet_manager','supervisor']))) with check((select private.has_store_role(store_id,array['master','outlet_manager','supervisor'])));
create policy catalog_manager_delete on public.service_catalog for delete to authenticated using((select private.has_store_role(store_id,array['master','outlet_manager'])));

drop policy if exists transactions_same_store on public.transactions;
create policy transactions_member_access on public.transactions for all to authenticated using((select private.has_store_access(store_id))) with check((select private.has_store_access(store_id)));
drop policy if exists items_same_store on public.transaction_items;
create policy items_member_access on public.transaction_items for all to authenticated using((select private.has_store_access(store_id))) with check((select private.has_store_access(store_id)));
grant delete on public.transaction_items to authenticated;
drop policy if exists rewards_same_store on public.membership_rewards;
create policy rewards_member_read on public.membership_rewards for select to authenticated using((select private.has_store_access(store_id)));
drop policy if exists kiloan_same_store on public.kiloan_orders;
create policy orders_member_access on public.kiloan_orders for all to authenticated using((select private.has_store_access(store_id))) with check((select private.has_store_access(store_id)));
drop policy if exists expenses_same_store on public.expenses;
create policy expenses_member_access on public.expenses for all to authenticated using((select private.has_store_access(store_id))) with check((select private.has_store_access(store_id)));
drop policy if exists inventory_read on public.inventory_items;
drop policy if exists inventory_owner_insert on public.inventory_items;
drop policy if exists inventory_owner_update on public.inventory_items;
drop policy if exists inventory_owner_delete on public.inventory_items;
create policy inventory_member_read on public.inventory_items for select to authenticated using((select private.has_store_access(store_id)));
create policy inventory_manager_insert on public.inventory_items for insert to authenticated with check((select private.has_store_role(store_id,array['master','outlet_manager','supervisor','admin'])));
create policy inventory_manager_update on public.inventory_items for update to authenticated using((select private.has_store_role(store_id,array['master','outlet_manager','supervisor','admin']))) with check((select private.has_store_role(store_id,array['master','outlet_manager','supervisor','admin'])));
create policy inventory_manager_delete on public.inventory_items for delete to authenticated using((select private.has_store_role(store_id,array['master','outlet_manager'])));
drop policy if exists closings_same_store on public.daily_closings;
create policy closings_manager_access on public.daily_closings for all to authenticated using((select private.has_store_role(store_id,array['master','outlet_manager','supervisor','admin']))) with check((select private.has_store_role(store_id,array['master','outlet_manager','supervisor','admin'])));
drop policy if exists membership_events_read on public.membership_events;
create policy membership_events_member_read on public.membership_events for select to authenticated using((select private.has_store_access(store_id)));

-- Memberships are visible to the same outlet; only master and outlet manager assign access.
alter table public.store_memberships enable row level security;
create policy store_memberships_member_read on public.store_memberships for select to authenticated using((select private.has_store_access(store_id)));
create policy store_memberships_manager_insert on public.store_memberships for insert to authenticated
  with check((select private.has_store_role(store_id,array['master','outlet_manager'])) and (role<>'master' or (select private.can_create_store())));
create policy store_memberships_manager_update on public.store_memberships for update to authenticated
  using((select private.has_store_role(store_id,array['master','outlet_manager'])))
  with check((select private.has_store_role(store_id,array['master','outlet_manager'])) and (role<>'master' or (select private.can_create_store())));
create policy store_memberships_manager_delete on public.store_memberships for delete to authenticated using((select private.has_store_role(store_id,array['master','outlet_manager'])));
grant select,insert,update,delete on public.store_memberships to authenticated;

-- Role-aware HR access; employees can submit their own attendance and leave request.
alter table public.attendance_records enable row level security;
create policy attendance_member_read on public.attendance_records for select to authenticated using((select private.has_store_access(store_id)));
create policy attendance_employee_insert on public.attendance_records for insert to authenticated with check(
  (user_id=(select auth.uid()) and (select private.has_store_access(store_id))) or (select private.has_store_role(store_id,array['master','outlet_manager','supervisor']))
);
create policy attendance_manager_update on public.attendance_records for update to authenticated using((select private.has_store_role(store_id,array['master','outlet_manager','supervisor']))) with check((select private.has_store_access(store_id)));
alter table public.leave_requests enable row level security;
create policy leave_employee_read on public.leave_requests for select to authenticated using(user_id=(select auth.uid()) or (select private.has_store_role(store_id,array['master','outlet_manager','supervisor'])));
create policy leave_employee_insert on public.leave_requests for insert to authenticated with check(user_id=(select auth.uid()) and (select private.has_store_access(store_id)));
create policy leave_manager_update on public.leave_requests for update to authenticated using((select private.has_store_role(store_id,array['master','outlet_manager','supervisor']))) with check((select private.has_store_access(store_id)));
alter table public.payroll_records enable row level security;
create policy payroll_manager_read on public.payroll_records for select to authenticated using((select private.has_store_role(store_id,array['master','outlet_manager','supervisor'])));
create policy payroll_self_read on public.payroll_records for select to authenticated using(user_id=(select auth.uid()) and (select private.has_store_access(store_id)));
create policy payroll_manager_manage on public.payroll_records for all to authenticated using((select private.has_store_role(store_id,array['master','outlet_manager']))) with check((select private.has_store_role(store_id,array['master','outlet_manager'])));
grant select,insert,update on public.attendance_records,public.leave_requests to authenticated;
grant select,insert,update on public.payroll_records to authenticated;

alter table public.transaction_payments enable row level security;
create policy payments_member_read on public.transaction_payments for select to authenticated using((select private.has_store_access(store_id)));
create policy payments_cashier_insert on public.transaction_payments for insert to authenticated with check((select private.has_store_role(store_id,array['master','outlet_manager','supervisor','admin'])));
grant select,insert on public.transaction_payments to authenticated;

alter table public.inventory_movements enable row level security;
create policy stock_movement_manager_read on public.inventory_movements for select to authenticated using((select private.has_store_access(store_id)));
create policy stock_movement_manager_insert on public.inventory_movements for insert to authenticated with check((select private.has_store_role(store_id,array['master','outlet_manager','supervisor','admin'])));
grant select,insert on public.inventory_movements to authenticated;

alter table public.production_steps enable row level security;
create policy production_member_read on public.production_steps for select to authenticated using((select private.has_store_access(store_id)));
create policy production_worker_update on public.production_steps for update to authenticated using((select private.has_store_role(store_id,array['master','outlet_manager','supervisor','production_wash','production_iron','packing']))) with check((select private.has_store_access(store_id)));
create policy production_manager_insert on public.production_steps for insert to authenticated with check((select private.has_store_role(store_id,array['master','outlet_manager','supervisor','admin'])));
grant select,insert,update on public.production_steps to authenticated;
