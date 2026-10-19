drop policy if exists transactions_member_access on public.transactions;
create policy transactions_member_read on public.transactions for select to authenticated
  using((select private.has_store_access(store_id)));
create policy transactions_operational_manage on public.transactions for all to authenticated
  using((select private.has_store_role(store_id,array['master','outlet_manager','supervisor','admin'])))
  with check((select private.has_store_role(store_id,array['master','outlet_manager','supervisor','admin'])));

drop policy if exists items_member_access on public.transaction_items;
create policy items_member_read on public.transaction_items for select to authenticated
  using((select private.has_store_access(store_id)));
create policy items_operational_manage on public.transaction_items for all to authenticated
  using((select private.has_store_role(store_id,array['master','outlet_manager','supervisor','admin'])))
  with check((select private.has_store_role(store_id,array['master','outlet_manager','supervisor','admin'])));

drop policy if exists orders_member_access on public.kiloan_orders;
create policy orders_member_read on public.kiloan_orders for select to authenticated
  using((select private.has_store_access(store_id)));
create policy orders_operational_insert on public.kiloan_orders for insert to authenticated
  with check((select private.has_store_role(store_id,array['master','outlet_manager','supervisor','admin'])));
create policy orders_staff_update on public.kiloan_orders for update to authenticated
  using((select private.has_store_role(store_id,array['master','outlet_manager','supervisor','admin','delivery','production_wash','production_iron','packing'])))
  with check((select private.has_store_access(store_id)));

drop policy if exists expenses_member_access on public.expenses;
create policy expenses_member_read on public.expenses for select to authenticated
  using((select private.has_store_access(store_id)));
create policy expenses_finance_manage on public.expenses for all to authenticated
  using((select private.has_store_role(store_id,array['master','outlet_manager','supervisor','admin'])))
  with check((select private.has_store_role(store_id,array['master','outlet_manager','supervisor','admin'])));
