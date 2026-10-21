-- Outlet Admin inherits outlet-scoped operational management; global membership administration remains Master-only.

drop policy if exists stores_manager_update on public.stores;

create policy stores_manager_update on public.stores for update to authenticated using((select private.has_store_role(id,array['master','outlet_manager','admin']))) with check((select private.has_store_role(id,array['master','outlet_manager','admin'])));

drop policy if exists catalog_manager_insert on public.service_catalog;

drop policy if exists catalog_manager_update on public.service_catalog;

drop policy if exists catalog_manager_delete on public.service_catalog;

create policy catalog_manager_insert on public.service_catalog for insert to authenticated with check((select private.has_store_role(store_id,array['master','outlet_manager','supervisor','admin'])));

create policy catalog_manager_update on public.service_catalog for update to authenticated using((select private.has_store_role(store_id,array['master','outlet_manager','supervisor','admin']))) with check((select private.has_store_role(store_id,array['master','outlet_manager','supervisor','admin'])));

create policy catalog_manager_delete on public.service_catalog for delete to authenticated using((select private.has_store_role(store_id,array['master','outlet_manager','admin'])));

drop policy if exists inventory_manager_delete on public.inventory_items;

create policy inventory_manager_delete on public.inventory_items for delete to authenticated using((select private.has_store_role(store_id,array['master','outlet_manager','admin'])));

drop policy if exists employees_manager_manage on public.employees;

create policy employees_manager_manage on public.employees for all to authenticated using((select private.has_store_role(store_id,array['master','outlet_manager','admin']))) with check((select private.has_store_role(store_id,array['master','outlet_manager','admin'])));

drop policy if exists attendance_employee_insert on public.attendance_records;

create policy attendance_employee_insert on public.attendance_records for insert to authenticated with check((user_id=(select auth.uid()) and (select private.has_store_access(store_id))) or (select private.has_store_role(store_id,array['master','outlet_manager','supervisor','admin'])));

drop policy if exists attendance_manager_update on public.attendance_records;

create policy attendance_manager_update on public.attendance_records for update to authenticated using((select private.has_store_role(store_id,array['master','outlet_manager','supervisor','admin']))) with check((select private.has_store_role(store_id,array['master','outlet_manager','supervisor','admin'])));

drop policy if exists leave_employee_read on public.leave_requests;

create policy leave_employee_read on public.leave_requests for select to authenticated using(user_id=(select auth.uid()) or (select private.has_store_role(store_id,array['master','outlet_manager','supervisor','admin'])));

drop policy if exists leave_manager_update on public.leave_requests;

create policy leave_manager_update on public.leave_requests for update to authenticated using((select private.has_store_role(store_id,array['master','outlet_manager','supervisor','admin']))) with check((select private.has_store_role(store_id,array['master','outlet_manager','supervisor','admin'])));

drop policy if exists payroll_manager_read on public.payroll_records;

create policy payroll_manager_read on public.payroll_records for select to authenticated using((select private.has_store_role(store_id,array['master','outlet_manager','supervisor','admin'])));

drop policy if exists payroll_manager_manage on public.payroll_records;

create policy payroll_manager_manage on public.payroll_records for all to authenticated using((select private.has_store_role(store_id,array['master','outlet_manager','admin']))) with check((select private.has_store_role(store_id,array['master','outlet_manager','admin'])));

drop policy if exists production_worker_update on public.production_steps;

create policy production_worker_update on public.production_steps for update to authenticated using((select private.has_store_role(store_id,array['master','outlet_manager','supervisor','production_wash','production_iron','packing','admin']))) with check((select private.has_store_role(store_id,array['master','outlet_manager','supervisor','production_wash','production_iron','packing','admin'])));

CREATE OR REPLACE FUNCTION public.import_customers(p_store_id uuid, p_customers jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
  if (select auth.uid()) is null or not private.has_store_role(p_store_id,array['master','outlet_manager','admin']) then
    raise exception 'Hanya Master, Manajer Outlet, atau Admin Outlet yang dapat mengimpor pelanggan.';
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
end $function$
;

CREATE OR REPLACE FUNCTION public.import_historical_bundle(p_store_id uuid, p_customers jsonb, p_transactions jsonb, p_expenses jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare customer_result jsonb; history_result jsonb;
begin
  if (select auth.uid()) is null or not private.has_store_role(p_store_id,array['master','outlet_manager','admin']) then raise exception 'Hanya Master, Manajer Outlet, atau Admin Outlet yang dapat mengimpor data.'; end if;
  if jsonb_typeof(p_customers)<>'array' or jsonb_typeof(p_transactions)<>'array' or jsonb_typeof(p_expenses)<>'array' or jsonb_array_length(p_customers)+jsonb_array_length(p_transactions)+jsonb_array_length(p_expenses)>500 then raise exception 'Format tidak sesuai atau jumlah baris melebihi 500.'; end if;
  customer_result:=public.import_customers(p_store_id,p_customers);
  history_result:=public.import_historical_data(p_store_id,p_transactions,p_expenses);
  return history_result || customer_result;
end $function$
;

CREATE OR REPLACE FUNCTION public.import_historical_data(p_store_id uuid, p_transactions jsonb, p_expenses jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  r jsonb; tx_id uuid; customer_id uuid; service_id uuid; invoice text; phone text;
  channel text; scope text; service_name text; q numeric; price numeric; subtotal numeric;
  discount numeric; total numeric; paid numeric; qty_weight numeric; order_status text;
  method text; imported_tx integer:=0; imported_exp integer:=0; skipped_tx integer:=0; skipped_exp integer:=0;
  created_on timestamptz; paid_on timestamptz; spent_on timestamptz; exp_key text;
begin
  if (select auth.uid()) is null or not private.has_store_role(p_store_id,array['master','outlet_manager','admin']) then
    raise exception 'Hanya Master, Manajer Outlet, atau Admin Outlet yang dapat mengimpor data.';
  end if;
  if jsonb_typeof(p_transactions)<>'array' or jsonb_typeof(p_expenses)<>'array'
     or jsonb_array_length(p_transactions)+jsonb_array_length(p_expenses)>500 then
    raise exception 'Format tidak sesuai atau jumlah baris melebihi 500.';
  end if;

  for r in select value from jsonb_array_elements(p_transactions) order by value->>'created_at' loop
    invoice:=nullif(btrim(r->>'invoice_no'),'');
    if invoice is null then raise exception 'Nomor nota wajib diisi.'; end if;
    if exists(select 1 from public.transactions t where t.store_id=p_store_id and t.invoice_no=invoice) then
      skipped_tx:=skipped_tx+1; continue;
    end if;
    channel:=r->>'channel'; scope:=r->>'scope'; service_name:=nullif(btrim(r->>'service_name'),'');
    created_on:=(r->>'created_at')::timestamptz;
    paid_on:=coalesce(nullif(r->>'paid_at','')::timestamptz,created_on);
    if created_on is null or channel not in ('self_service','kiloan_retail','b2b','shoe_service') or service_name is null then raise exception 'Tanggal, jenis layanan, atau nama layanan tidak valid pada nota %.',invoice; end if;
    if (channel='self_service' and scope not in ('self_service_main','addon','product'))
       or (channel in ('kiloan_retail','b2b') and scope<>'kiloan_service')
       or (channel='shoe_service' and scope<>'shoe_service') then raise exception 'Kategori layanan tidak sesuai dengan jenis layanan pada nota %.',invoice; end if;
    q:=nullif(r->>'quantity','')::numeric; price:=nullif(r->>'unit_price','')::numeric;
    subtotal:=coalesce(nullif(r->>'subtotal','')::numeric,q*price);
    discount:=coalesce(nullif(r->>'discount','')::numeric,0);
    total:=coalesce(nullif(r->>'total','')::numeric,subtotal-discount);
    paid:=coalesce(nullif(r->>'paid_amount','')::numeric,0);
    if q is null or q<=0 or price is null or price<0 or subtotal<=0 or discount<0 or total<0 or paid<0 or paid>total then raise exception 'Jumlah atau nominal tidak valid pada nota %.',invoice; end if;
    method:=coalesce(nullif(r->>'payment_method',''),'Tunai');
    if paid>0 and method not in ('Tunai','QR Mesin','QR Tetangga') then raise exception 'Metode pembayaran tidak valid pada nota %.',invoice; end if;
    phone:=nullif(btrim(r->>'whatsapp'),''); customer_id:=null;
    if phone is not null then
      insert into public.customers(store_id,name,whatsapp,customer_type)
        values(p_store_id,btrim(r->>'customer_name'),phone,case when channel='b2b' then 'b2b' else 'retail' end)
        on conflict(store_id,whatsapp) do update set name=excluded.name
        returning id into customer_id;
    end if;
    select s.id into service_id from public.service_catalog s where s.store_id=p_store_id and s.name=service_name and s.category=scope limit 1;
    insert into public.transactions(store_id,invoice_no,customer_id,channel,status,subtotal,membership_discount,total,payment_method,created_by,created_at,paid_at)
      values(p_store_id,invoice,customer_id,channel,'unpaid',subtotal,discount,total,nullif(method,''),auth.uid(),created_on,case when paid>=total and paid>0 then paid_on else null end)
      returning id into tx_id;
    insert into private.historical_import_transactions(transaction_id) values(tx_id);
    insert into public.transaction_items(store_id,transaction_id,service_id,name,scope,quantity,unit_price,unit_cost,line_total)
      values(p_store_id,tx_id,service_id,service_name,scope,q,price,coalesce(nullif(r->>'unit_cost','')::numeric,0),subtotal);
    if paid>0 then
      insert into public.transaction_payments(store_id,transaction_id,amount,payment_method,paid_at,received_by,legacy_import)
        values(p_store_id,tx_id,paid,method,paid_on,auth.uid(),true);
    end if;
    qty_weight:=coalesce(nullif(r->>'weight_kg','')::numeric,0);
    if channel='kiloan_retail' and qty_weight>0 then
      order_status:=coalesce(nullif(r->>'order_status',''),'Diambil');
      if order_status not in ('Masuk','Proses','Selesai','Diambil') then raise exception 'Status pesanan tidak dikenal pada nota %.',invoice; end if;
      insert into public.kiloan_orders(store_id,transaction_id,order_no,weight_kg,status)
        values(p_store_id,tx_id,invoice,qty_weight,order_status);
    end if;
    imported_tx:=imported_tx+1;
  end loop;

  for r in select value from jsonb_array_elements(p_expenses) loop
    exp_key:=nullif(r->>'import_key',''); spent_on:=(r->>'spent_at')::timestamptz;
    if exp_key is null or spent_on is null or coalesce(nullif(r->>'category',''),'')='' or coalesce(nullif(r->>'note',''),'')=''
       or coalesce(nullif(r->>'amount','')::numeric,0)<=0 or r->>'payment_method' not in ('Tunai','QR Mesin','QR Tetangga') then raise exception 'Tanggal, kategori, catatan, jumlah, atau metode pada data pengeluaran tidak valid.'; end if;
    if exists(select 1 from public.expenses e where e.store_id=p_store_id and e.import_key=exp_key) then skipped_exp:=skipped_exp+1; continue; end if;
    insert into public.expenses(store_id,category,note,amount,payment_method,spent_at,created_by,import_key)
      values(p_store_id,btrim(r->>'category'),btrim(r->>'note'),(r->>'amount')::numeric,r->>'payment_method',spent_on,auth.uid(),exp_key);
    imported_exp:=imported_exp+1;
  end loop;
  return jsonb_build_object('imported_transactions',imported_tx,'imported_expenses',imported_exp,'skipped_transactions',skipped_tx,'skipped_expenses',skipped_exp);
end $function$
;