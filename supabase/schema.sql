-- LifeofTetangga: Supabase / PostgreSQL starter schema.
-- No customer data is included. Apply only in a new Supabase project.
create extension if not exists pgcrypto;

create table public.stores (
 id uuid primary key default gen_random_uuid(),
 name text not null,
 timezone text not null default 'Asia/Jakarta',
 created_at timestamptz not null default now()
);
create table public.profiles (
 id uuid primary key references auth.users(id) on delete cascade,
 store_id uuid not null references public.stores(id),
 name text not null,
 role text not null check (role in ('owner','cashier')),
 active boolean not null default true
);
create table public.customers (
 id uuid primary key default gen_random_uuid(),
 store_id uuid not null references public.stores(id),
 name text not null,
 whatsapp text not null,
 membership_uses integer not null default 0 check (membership_uses >= 0),
 created_at timestamptz not null default now(),
 unique(store_id,whatsapp)
);
create table public.service_catalog (
 id uuid primary key default gen_random_uuid(),
 store_id uuid not null references public.stores(id),
 name text not null,
 category text not null check(category in ('self_service_main','addon','product','kiloan_service')),
 price numeric(12,2) not null default 0 check(price >= 0),
 unit text not null default 'item',
 active boolean not null default true,
 unique(store_id,name,category)
);
create table public.transactions (
 id uuid primary key default gen_random_uuid(),
 store_id uuid not null references public.stores(id),
 invoice_no text not null,
 customer_id uuid references public.customers(id),
 channel text not null check(channel in ('self_service','kiloan_retail','b2b')),
 status text not null default 'unpaid' check(status in ('unpaid','paid','refunded','void')),
 payment_method text check(payment_method in ('Tunai','QR Mesin','QR Tetangga')),
 subtotal numeric(12,2) not null default 0 check(subtotal >= 0),
 membership_discount numeric(12,2) not null default 0 check(membership_discount >= 0),
 total numeric(12,2) not null default 0 check(total >= 0),
 paid_at timestamptz,
 membership_counted_at timestamptz,
 created_by uuid references auth.users(id),
 created_at timestamptz not null default now(),
 unique(store_id,invoice_no),
 check(status <> 'paid' or payment_method is not null),
 check(channel = 'self_service' or membership_discount = 0)
);
create table public.transaction_items (
 id uuid primary key default gen_random_uuid(),
 store_id uuid not null references public.stores(id),
 transaction_id uuid not null references public.transactions(id) on delete cascade,
 service_id uuid references public.service_catalog(id),
 name text not null,
 scope text not null check(scope in ('self_service_main','addon','product','kiloan_service')),
 quantity numeric(12,3) not null default 1 check(quantity > 0),
 unit_price numeric(12,2) not null check(unit_price >= 0),
 line_total numeric(12,2) not null check(line_total >= 0)
);
create table public.membership_rewards (
 id uuid primary key default gen_random_uuid(),
 store_id uuid not null references public.stores(id),
 customer_id uuid not null references public.customers(id),
 milestone integer not null check(milestone in (5,10)),
 percent_off numeric(5,2) not null default 25 check(percent_off = 25),
 earned_at timestamptz not null default now(),
 expires_at timestamptz not null default(now() + interval '30 days'),
 used_transaction_id uuid references public.transactions(id),
 used_at timestamptz,
 unique(customer_id,milestone),
 check((used_transaction_id is null) = (used_at is null))
);
create table public.kiloan_orders (
 id uuid primary key default gen_random_uuid(),
 store_id uuid not null references public.stores(id),
 transaction_id uuid not null unique references public.transactions(id) on delete cascade,
 order_no text not null,
 weight_kg numeric(10,3) not null check(weight_kg > 0),
 status text not null default 'Masuk' check(status in ('Masuk','Proses','Selesai','Diambil')),
 due_at timestamptz,
 picked_up_at timestamptz,
 unique(store_id,order_no)
);
create table public.expenses (
 id uuid primary key default gen_random_uuid(),
 store_id uuid not null references public.stores(id),
 category text not null,
 note text not null,
 amount numeric(12,2) not null check(amount > 0),
 payment_method text not null check(payment_method in ('Tunai','QR Mesin','QR Tetangga')),
 spent_at timestamptz not null default now(),
 created_by uuid references auth.users(id)
);
create table public.inventory_items (
 id uuid primary key default gen_random_uuid(),
 store_id uuid not null references public.stores(id),
 name text not null,
 category text not null check(category in ('product','operational_supply')),
 unit text not null,
 quantity numeric(12,3) not null default 0 check(quantity >= 0),
 minimum_quantity numeric(12,3) not null default 0 check(minimum_quantity >= 0),
 unique(store_id,name,category)
);
create table public.daily_closings (
 id uuid primary key default gen_random_uuid(),
 store_id uuid not null references public.stores(id),
 business_date date not null,
 cash_expected numeric(12,2) not null default 0,
 cash_counted numeric(12,2) not null default 0,
 qr_machine_expected numeric(12,2) not null default 0,
 qr_neighbor_expected numeric(12,2) not null default 0,
 note text,
 closed_by uuid references auth.users(id),
 closed_at timestamptz not null default now(),
 unique(store_id,business_date)
);
create table public.membership_events (
 id uuid primary key default gen_random_uuid(),
 store_id uuid not null references public.stores(id),
 customer_id uuid not null references public.customers(id),
 transaction_id uuid not null references public.transactions(id),
 event_type text not null check(event_type in ('use_counted','reward_earned','reward_used','transaction_reversed')),
 use_number integer,
 details jsonb not null default '{}'::jsonb,
 created_at timestamptz not null default now()
);

create or replace function public.current_store_id()
returns uuid language sql stable security definer set search_path=''
as $$ select p.store_id from public.profiles p where p.id=(select auth.uid()) and p.active $$;
create or replace function public.current_role()
returns text language sql stable security definer set search_path=''
as $$ select p.role from public.profiles p where p.id=(select auth.uid()) and p.active $$;
revoke all on function public.current_store_id() from public;
revoke all on function public.current_role() from public;
grant execute on function public.current_store_id() to authenticated;
grant execute on function public.current_role() to authenticated;

-- Membership increments once when an eligible transaction first becomes paid.
-- B2B is excluded; reward milestones are only 5 and 10.
create or replace function public.count_membership_use()
returns trigger language plpgsql security definer set search_path=''
as $$
declare n integer;
begin
 if new.status='paid' and new.channel in ('self_service','kiloan_retail')
    and new.customer_id is not null and new.membership_counted_at is null then
   update public.customers set membership_uses=membership_uses+1
    where id=new.customer_id and store_id=new.store_id returning membership_uses into n;
   if n is not null then
    new.membership_counted_at:=coalesce(new.paid_at,now());
     insert into public.membership_events(store_id,customer_id,transaction_id,event_type,use_number)
      values(new.store_id,new.customer_id,new.id,'use_counted',n);
    if n in (5,10) then
     insert into public.membership_rewards(store_id,customer_id,milestone)
     values(new.store_id,new.customer_id,n) on conflict(customer_id,milestone) do nothing;
      insert into public.membership_events(store_id,customer_id,transaction_id,event_type,use_number,details)
       values(new.store_id,new.customer_id,new.id,'reward_earned',n,jsonb_build_object('percent_off',25,'valid_days',30,'scope','self_service_main'));
    end if;
   end if;
 end if;
 return new;
end $$;
revoke all on function public.count_membership_use() from public;
create trigger transaction_membership_count
before insert or update of status on public.transactions
for each row execute function public.count_membership_use();

create index customers_store_name_idx on public.customers(store_id,name);
create index transactions_store_created_idx on public.transactions(store_id,created_at desc);
create index expenses_store_date_idx on public.expenses(store_id,spent_at desc);
create index orders_store_status_idx on public.kiloan_orders(store_id,status);
create index rewards_available_idx on public.membership_rewards(customer_id,expires_at) where used_at is null;

-- RLS: private to signed-in users with an active profile in the same store.
do $$
declare t text;
begin
 foreach t in array array['stores','profiles','customers','service_catalog','transactions','transaction_items','membership_rewards','kiloan_orders','expenses','inventory_items','daily_closings','membership_events'] loop
  execute format('alter table public.%I enable row level security',t);
 end loop;
end $$;
create policy store_read on public.stores for select to authenticated using(id=(select public.current_store_id()));
create policy store_owner_update on public.stores for update to authenticated using(id=(select public.current_store_id()) and (select public.current_role())='owner') with check(id=(select public.current_store_id()) and (select public.current_role())='owner');
create policy profiles_same_store on public.profiles for select to authenticated using(store_id=(select public.current_store_id()));
create policy profiles_owner_manage on public.profiles for all to authenticated using(store_id=(select public.current_store_id()) and (select public.current_role())='owner') with check(store_id=(select public.current_store_id()) and (select public.current_role())='owner');
create policy customers_same_store on public.customers for all to authenticated using(store_id=(select public.current_store_id())) with check(store_id=(select public.current_store_id()));
create policy catalog_read on public.service_catalog for select to authenticated using(store_id=(select public.current_store_id()));
create policy catalog_owner_manage on public.service_catalog for all to authenticated using(store_id=(select public.current_store_id()) and (select public.current_role())='owner') with check(store_id=(select public.current_store_id()) and (select public.current_role())='owner');
create policy transactions_same_store on public.transactions for all to authenticated using(store_id=(select public.current_store_id())) with check(store_id=(select public.current_store_id()));
create policy items_same_store on public.transaction_items for all to authenticated using(store_id=(select public.current_store_id())) with check(store_id=(select public.current_store_id()));
create policy rewards_same_store on public.membership_rewards for all to authenticated using(store_id=(select public.current_store_id())) with check(store_id=(select public.current_store_id()));
create policy kiloan_same_store on public.kiloan_orders for all to authenticated using(store_id=(select public.current_store_id())) with check(store_id=(select public.current_store_id()));
create policy expenses_same_store on public.expenses for all to authenticated using(store_id=(select public.current_store_id())) with check(store_id=(select public.current_store_id()));
create policy inventory_read on public.inventory_items for select to authenticated using(store_id=(select public.current_store_id()));
create policy inventory_owner_manage on public.inventory_items for all to authenticated using(store_id=(select public.current_store_id()) and (select public.current_role())='owner') with check(store_id=(select public.current_store_id()) and (select public.current_role())='owner');
create policy closings_same_store on public.daily_closings for all to authenticated using(store_id=(select public.current_store_id())) with check(store_id=(select public.current_store_id()));
create policy membership_events_read on public.membership_events for select to authenticated using(store_id=(select public.current_store_id()));

grant select,insert,update,delete on public.customers,public.transactions,public.transaction_items,public.membership_rewards,public.kiloan_orders,public.expenses,public.daily_closings to authenticated;
grant select on public.stores,public.profiles,public.service_catalog,public.inventory_items,public.membership_events to authenticated;
grant insert,update,delete on public.service_catalog,public.inventory_items to authenticated;
grant update on public.stores,public.profiles to authenticated;
-- Do not grant anon access. Never expose a Supabase service_role key in frontend code.

