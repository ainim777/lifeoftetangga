-- Import customer directories securely and remove unnecessary anonymous
-- table grants. Customer access remains scoped by the existing RLS policy.
revoke all on table public.customers from anon;

create or replace function public.import_customers(p_store_id uuid,p_customers jsonb)
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare
  r jsonb;
  phone text;
  name_value text;
  kind text;
  imported_count integer:=0;
  skipped_count integer:=0;
begin
  if (select auth.uid()) is null or not private.has_store_role(p_store_id,array['master','outlet_manager']) then
    raise exception 'Hanya Master atau Manajer Outlet yang dapat mengimpor pelanggan.';
  end if;
  if jsonb_typeof(p_customers)<>'array' or jsonb_array_length(p_customers)>500 then
    raise exception 'Format tidak sesuai atau jumlah pelanggan melebihi 500.';
  end if;
  for r in select value from jsonb_array_elements(p_customers) loop
    name_value:=nullif(btrim(r->>'name'),'');
    phone:=nullif(btrim(r->>'whatsapp'),'');
    kind:=coalesce(nullif(r->>'customer_type',''),'retail');
    if name_value is null or phone is null or kind not in ('retail','b2b')
       or length(regexp_replace(phone,'[^0-9]','','g')) not between 8 and 15 then
      raise exception 'Nama, WhatsApp (8–15 digit), atau kategori pelanggan tidak valid.';
    end if;
    if exists(select 1 from public.customers c where c.store_id=p_store_id and c.whatsapp=phone) then
      update public.customers set name=name_value,customer_type=kind
       where store_id=p_store_id and whatsapp=phone;
      skipped_count:=skipped_count+1;
    else
      insert into public.customers(store_id,name,whatsapp,customer_type)
       values(p_store_id,name_value,phone,kind);
      imported_count:=imported_count+1;
    end if;
  end loop;
  return jsonb_build_object('imported_customers',imported_count,'updated_customers',skipped_count);
end $$;
revoke all on function public.import_customers(uuid,jsonb) from public,anon;
grant execute on function public.import_customers(uuid,jsonb) to authenticated;

create or replace function public.import_historical_bundle(
  p_store_id uuid,p_customers jsonb,p_transactions jsonb,p_expenses jsonb
) returns jsonb language plpgsql security definer set search_path=''
as $$
declare customer_result jsonb; history_result jsonb;
begin
  if (select auth.uid()) is null or not private.has_store_role(p_store_id,array['master','outlet_manager']) then
    raise exception 'Hanya Master atau Manajer Outlet yang dapat mengimpor data.';
  end if;
  if jsonb_typeof(p_customers)<>'array' or jsonb_typeof(p_transactions)<>'array'
     or jsonb_typeof(p_expenses)<>'array'
     or jsonb_array_length(p_customers)+jsonb_array_length(p_transactions)+jsonb_array_length(p_expenses)>500 then
    raise exception 'Format tidak sesuai atau jumlah baris melebihi 500.';
  end if;
  customer_result:=public.import_customers(p_store_id,p_customers);
  history_result:=public.import_historical_data(p_store_id,p_transactions,p_expenses);
  return history_result || customer_result;
end $$;
revoke all on function public.import_historical_bundle(uuid,jsonb,jsonb,jsonb) from public,anon;
grant execute on function public.import_historical_bundle(uuid,jsonb,jsonb,jsonb) to authenticated;
