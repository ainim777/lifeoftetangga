-- Preserve legacy service-specific customer IDs while keeping one customer
-- profile and one membership progress record per phone number.
alter table public.customers
  add column if not exists customer_id_lt text,
  add column if not exists customer_id_kl text,
  add column if not exists customer_id_b2b text;

create unique index if not exists customers_store_customer_id_lt_unique
  on public.customers(store_id,customer_id_lt) where customer_id_lt is not null;
create unique index if not exists customers_store_customer_id_kl_unique
  on public.customers(store_id,customer_id_kl) where customer_id_kl is not null;
create unique index if not exists customers_store_customer_id_b2b_unique
  on public.customers(store_id,customer_id_b2b) where customer_id_b2b is not null;

create table if not exists private.customer_code_counters(
  store_id uuid not null references public.stores(id) on delete cascade,
  service_code text not null check(service_code in ('LT','KL','B2B')),
  issue_date date not null,
  last_number bigint not null check(last_number>0),
  primary key(store_id,service_code,issue_date)
);
alter table private.customer_code_counters enable row level security;
revoke all on private.customer_code_counters from public,anon,authenticated;

create or replace function private.assign_customer_service_id(
  p_store_id uuid,p_customer_id uuid,p_service_code text
) returns text language plpgsql security definer set search_path=''
as $$
declare
  existing_id text;
  timezone_name text;
  today_local date;
  date_prefix text;
  existing_max bigint;
  next_number bigint;
  new_id text;
begin
  if p_service_code not in ('LT','KL','B2B') then raise exception 'Jenis ID Customer tidak dikenal.'; end if;
  select case p_service_code when 'LT' then c.customer_id_lt when 'KL' then c.customer_id_kl else c.customer_id_b2b end
    into existing_id
    from public.customers c
   where c.store_id=p_store_id and c.id=p_customer_id
   for update;
  if not found then raise exception 'Customer tidak ditemukan pada outlet ini.'; end if;
  if existing_id is not null then return existing_id; end if;

  select coalesce(nullif(s.timezone,''),'Asia/Jakarta') into timezone_name
    from public.stores s where s.id=p_store_id;
  if timezone_name is null then raise exception 'Outlet tidak ditemukan.'; end if;
  today_local:=(now() at time zone timezone_name)::date;
  date_prefix:=to_char(today_local,'DDMMYY');

  select coalesce(max(substring(v.customer_code from length(date_prefix||'-'||p_service_code||'-')+1)::bigint),0)
    into existing_max
    from (
      select c.customer_id_lt as customer_code from public.customers c where c.store_id=p_store_id
      union all select c.customer_id_kl from public.customers c where c.store_id=p_store_id
      union all select c.customer_id_b2b from public.customers c where c.store_id=p_store_id
    ) v
   where v.customer_code like date_prefix||'-'||p_service_code||'-%'
     and substring(v.customer_code from length(date_prefix||'-'||p_service_code||'-')+1) ~ '^[0-9]{4,}$';

  insert into private.customer_code_counters(store_id,service_code,issue_date,last_number)
    values(p_store_id,p_service_code,today_local,existing_max+1)
    on conflict(store_id,service_code,issue_date) do update
      set last_number=greatest(private.customer_code_counters.last_number,excluded.last_number-1)+1
    returning last_number into next_number;
  new_id:=date_prefix||'-'||p_service_code||'-'||lpad(next_number::text,4,'0');
  if p_service_code='LT' then
    update public.customers set customer_id_lt=new_id where id=p_customer_id and store_id=p_store_id;
  elsif p_service_code='KL' then
    update public.customers set customer_id_kl=new_id where id=p_customer_id and store_id=p_store_id;
  else
    update public.customers set customer_id_b2b=new_id where id=p_customer_id and store_id=p_store_id;
  end if;
  return new_id;
end $$;
revoke all on function private.assign_customer_service_id(uuid,uuid,text) from public,anon,authenticated;

create or replace function public.ensure_customer_service_id(
  p_store_id uuid,p_customer_id uuid,p_service_code text
) returns text language plpgsql security definer set search_path=''
as $$
begin
  if (select auth.uid()) is null or not private.has_store_access(p_store_id) then
    raise exception 'Akun tidak memiliki akses ke outlet ini.';
  end if;
  return private.assign_customer_service_id(p_store_id,p_customer_id,p_service_code);
end $$;
revoke all on function public.ensure_customer_service_id(uuid,uuid,text) from public,anon;
grant execute on function public.ensure_customer_service_id(uuid,uuid,text) to authenticated;

create or replace function private.assign_customer_service_id_after_transaction()
returns trigger language plpgsql security definer set search_path=''
as $$
begin
  if new.customer_id is null then return new; end if;
  if new.channel='self_service' then
    perform private.assign_customer_service_id(new.store_id,new.customer_id,'LT');
  elsif new.channel='kiloan_retail' then
    perform private.assign_customer_service_id(new.store_id,new.customer_id,'KL');
  elsif new.channel='b2b' then
    perform private.assign_customer_service_id(new.store_id,new.customer_id,'B2B');
  end if;
  return new;
end $$;
revoke all on function private.assign_customer_service_id_after_transaction() from public,anon,authenticated;
drop trigger if exists transactions_assign_customer_service_id on public.transactions;
create trigger transactions_assign_customer_service_id
  after insert on public.transactions
  for each row execute function private.assign_customer_service_id_after_transaction();

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
  imported_count integer:=0;
  updated_count integer:=0;
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
    id_lt:=nullif(btrim(r->>'customer_id_lt'),'');
    id_kl:=nullif(btrim(r->>'customer_id_kl'),'');
    id_b2b:=nullif(btrim(r->>'customer_id_b2b'),'');
    if name_value is null or phone is null or kind not in ('retail','b2b')
       or length(regexp_replace(phone,'[^0-9]','','g')) not between 8 and 15 then
      raise exception 'Nama, WhatsApp (8–15 digit), atau kategori pelanggan tidak valid.';
    end if;
    if (id_lt is not null and id_lt !~ '^[0-9]{6}-LT-[0-9]{4,}$')
       or (id_kl is not null and id_kl !~ '^[0-9]{6}-KL-[0-9]{4,}$')
       or (id_b2b is not null and id_b2b !~ '^[0-9]{6}-B2B-[0-9]{4,}$') then
      raise exception 'Format ID harus DDMMYY-LT-0001, DDMMYY-KL-0001, atau DDMMYY-B2B-0001.';
    end if;
    if exists(select 1 from public.customers c where c.store_id=p_store_id and c.whatsapp=phone) then
      update public.customers set name=name_value,customer_type=kind,
        customer_id_lt=coalesce(id_lt,customer_id_lt),
        customer_id_kl=coalesce(id_kl,customer_id_kl),
        customer_id_b2b=coalesce(id_b2b,customer_id_b2b)
       where store_id=p_store_id and whatsapp=phone;
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
