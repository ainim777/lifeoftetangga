-- Legacy customer lists can omit phone numbers. A service membership ID still
-- gives the record a stable identity; an ID can later be matched and enriched
-- with a phone number during another import.
alter table public.customers alter column whatsapp drop not null;

create or replace function public.import_customers(p_store_id uuid,p_customers jsonb)
returns jsonb language plpgsql security definer set search_path=''
as $$
declare
  r jsonb;
  phone text;
  name_value text;
  kind text;
  id_lt text;
  id_kl text;
  id_b2b text;
  existing_customer_id uuid;
  imported_count integer:=0;
  updated_count integer:=0;
begin
  if (select auth.uid()) is null or not private.has_store_role(p_store_id,array['master','outlet_manager']) then
    raise exception 'Hanya Master atau Manajer Outlet yang dapat mengimpor pelanggan.';
  end if;
  if jsonb_typeof(p_customers)<>'array' or jsonb_array_length(p_customers)>2000 then
    raise exception 'Format tidak sesuai atau jumlah pelanggan melebihi 2.000.';
  end if;
  for r in select value from jsonb_array_elements(p_customers) loop
    name_value:=nullif(btrim(r->>'name'),'');
    phone:=nullif(btrim(r->>'whatsapp'),'');
    if phone='0' then phone:=null; end if;
    kind:=coalesce(nullif(r->>'customer_type',''),'retail');
    id_lt:=nullif(btrim(r->>'customer_id_lt'),'');
    id_kl:=nullif(btrim(r->>'customer_id_kl'),'');
    id_b2b:=nullif(btrim(r->>'customer_id_b2b'),'');
    if name_value is null or kind not in ('retail','b2b')
       or (phone is null and id_lt is null and id_kl is null and id_b2b is null)
       or (phone is not null and length(regexp_replace(phone,'[^0-9]','','g')) not between 8 and 15) then
      raise exception 'Nama wajib diisi. Lengkapi WhatsApp atau setidaknya satu ID layanan.';
    end if;
    if (id_lt is not null and id_lt !~ '^[0-9]{6}-LT-[0-9]{4,}$')
       or (id_kl is not null and id_kl !~ '^[0-9]{6}-KL-[0-9]{4,}$')
       or (id_b2b is not null and id_b2b !~ '^[0-9]{6}-B2B-[0-9]{4,}$') then
      raise exception 'Format ID harus DDMMYY-LT-0001, DDMMYY-KL-0001, atau DDMMYY-B2B-0001.';
    end if;
    existing_customer_id:=null;
    select c.id into existing_customer_id from public.customers c
     where c.store_id=p_store_id and (
       (phone is not null and c.whatsapp=phone)
       or (id_lt is not null and c.customer_id_lt=id_lt)
       or (id_kl is not null and c.customer_id_kl=id_kl)
       or (id_b2b is not null and c.customer_id_b2b=id_b2b)
     ) order by (phone is not null and c.whatsapp=phone) desc limit 1 for update;
    if existing_customer_id is not null then
      update public.customers set
        name=name_value,customer_type=kind,whatsapp=coalesce(phone,whatsapp),
        customer_id_lt=coalesce(id_lt,customer_id_lt),
        customer_id_kl=coalesce(id_kl,customer_id_kl),
        customer_id_b2b=coalesce(id_b2b,customer_id_b2b)
       where id=existing_customer_id and store_id=p_store_id;
      updated_count:=updated_count+1;
    else
      insert into public.customers(store_id,name,whatsapp,customer_type,customer_id_lt,customer_id_kl,customer_id_b2b)
       values(p_store_id,name_value,phone,kind,id_lt,id_kl,id_b2b);
      imported_count:=imported_count+1;
    end if;
  end loop;
  return jsonb_build_object('imported_customers',imported_count,'updated_customers',updated_count);
end $$;
revoke all on function public.import_customers(uuid,jsonb) from public,anon;
grant execute on function public.import_customers(uuid,jsonb) to authenticated;
