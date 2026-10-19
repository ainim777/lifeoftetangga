create or replace function public.create_outlet(p_name text, p_timezone text default 'Asia/Jakarta')
returns uuid language plpgsql security definer set search_path=''
as $$
declare new_store uuid; base_store uuid;
begin
  if not exists(select 1 from public.store_memberships where user_id=(select auth.uid()) and active and role='master') then
    raise exception 'Hanya akun Master yang dapat menambah outlet.';
  end if;
  if trim(coalesce(p_name,''))='' then raise exception 'Nama outlet wajib diisi.'; end if;
  select store_id into base_store from public.store_memberships where user_id=(select auth.uid()) and active and role='master' order by created_at limit 1;
  insert into public.stores(name,timezone) values(trim(p_name),coalesce(nullif(p_timezone,''),'Asia/Jakarta')) returning id into new_store;
  insert into public.store_memberships(user_id,store_id,role) values((select auth.uid()),new_store,'master');
  insert into public.service_catalog(store_id,name,category,price,unit,active,estimated_unit_cost,price_is_demo)
    select new_store,name,category,price,unit,active,estimated_unit_cost,true
    from public.service_catalog where store_id=base_store on conflict(store_id,name,category) do nothing;
  insert into public.inventory_items(store_id,name,category,unit,quantity,minimum_quantity,unit_cost,is_demo)
    select new_store,name,category,unit,0,minimum_quantity,unit_cost,true
    from public.inventory_items where store_id=base_store on conflict(store_id,name,category) do nothing;
  return new_store;
end $$;
revoke all on function public.create_outlet(text,text) from public,anon;
grant execute on function public.create_outlet(text,text) to authenticated;
