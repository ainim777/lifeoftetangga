-- LifeofTetangga Business package: outlets, roles, payments, HR and tracking.
-- Existing records stay in their current outlet and existing paid transactions
-- receive one legacy payment row so reports remain consistent.

create table if not exists public.store_memberships (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  store_id uuid not null references public.stores(id) on delete cascade,
  role text not null check (role in ('master','outlet_manager','supervisor','admin','delivery','production_wash','production_iron','packing')),
  active boolean not null default true,
  created_at timestamptz not null default now(),
  unique(user_id,store_id)
);
insert into public.store_memberships(user_id,store_id,role,active)
select id,store_id,case when role='owner' then 'master' else 'admin' end,active
from public.profiles on conflict(user_id,store_id) do nothing;
create index if not exists store_memberships_store_role_idx on public.store_memberships(store_id,role) where active;
create index if not exists store_memberships_user_active_idx on public.store_memberships(user_id,store_id) where active;

alter table public.customers add column if not exists address text;
alter table public.customers add column if not exists first_transaction_at timestamptz;

-- Partial payments and a full payment ledger for cashflow, receivables and pay-later.
alter table public.transactions drop constraint if exists transactions_status_check;
alter table public.transactions add constraint transactions_status_check
  check(status in ('unpaid','partial','paid','refunded','void'));
create table if not exists public.transaction_payments (
  id uuid primary key default gen_random_uuid(),
  store_id uuid not null references public.stores(id),
  transaction_id uuid not null references public.transactions(id),
  amount numeric(12,2) not null check(amount > 0),
  payment_method text not null check(payment_method in ('Tunai','QR Mesin','QR Tetangga')),
  note text,
  paid_at timestamptz not null default now(),
  received_by uuid references auth.users(id),
  legacy_import boolean not null default false
);
create index if not exists transaction_payments_store_date_idx on public.transaction_payments(store_id,paid_at desc);
create index if not exists transaction_payments_transaction_idx on public.transaction_payments(transaction_id,paid_at);
insert into public.transaction_payments(store_id,transaction_id,amount,payment_method,paid_at,received_by,legacy_import)
select t.store_id,t.id,t.total,t.payment_method,coalesce(t.paid_at,t.created_at),t.created_by,true
from public.transactions t where t.status='paid'
  and not exists(select 1 from public.transaction_payments p where p.transaction_id=t.id);

create table if not exists public.attendance_records (
  id uuid primary key default gen_random_uuid(),
  store_id uuid not null references public.stores(id),
  user_id uuid not null references public.profiles(id),
  work_date date not null default current_date,
  check_in timestamptz not null default now(),
  check_out timestamptz,
  status text not null default 'hadir' check(status in ('hadir','terlambat','izin','cuti','alpa')),
  note text,
  created_by uuid references auth.users(id),
  unique(store_id,user_id,work_date),
  check(check_out is null or check_out>=check_in)
);
create index if not exists attendance_store_date_idx on public.attendance_records(store_id,work_date desc);

create table if not exists public.leave_requests (
  id uuid primary key default gen_random_uuid(),
  store_id uuid not null references public.stores(id),
  user_id uuid not null references public.profiles(id),
  starts_on date not null,
  ends_on date not null,
  reason text not null,
  status text not null default 'menunggu' check(status in ('menunggu','disetujui','ditolak')),
  reviewed_by uuid references auth.users(id),
  reviewed_at timestamptz,
  created_at timestamptz not null default now(),
  check(ends_on>=starts_on)
);
create index if not exists leave_requests_store_status_idx on public.leave_requests(store_id,status,starts_on);

create table if not exists public.payroll_records (
  id uuid primary key default gen_random_uuid(),
  store_id uuid not null references public.stores(id),
  user_id uuid not null references public.profiles(id),
  period_start date not null,
  period_end date not null,
  base_pay numeric(12,2) not null default 0 check(base_pay>=0),
  bonus numeric(12,2) not null default 0 check(bonus>=0),
  deductions numeric(12,2) not null default 0 check(deductions>=0),
  status text not null default 'draft' check(status in ('draft','paid')),
  payment_method text check(payment_method in ('Tunai','QR Mesin','QR Tetangga')),
  note text,
  paid_at timestamptz,
  created_by uuid references auth.users(id),
  created_at timestamptz not null default now(),
  check(period_end>=period_start),
  check(deductions<=base_pay+bonus),
  check(status<>'paid' or payment_method is not null)
);
create index if not exists payroll_store_period_idx on public.payroll_records(store_id,period_start desc);

create table if not exists public.inventory_movements (
  id uuid primary key default gen_random_uuid(),
  store_id uuid not null references public.stores(id),
  inventory_item_id uuid not null references public.inventory_items(id),
  direction text not null check(direction in ('masuk','keluar','penyesuaian')),
  quantity numeric(12,3) not null check(quantity>0),
  reason text not null,
  transaction_id uuid references public.transactions(id),
  created_by uuid references auth.users(id),
  created_at timestamptz not null default now()
);
create index if not exists inventory_movements_store_date_idx on public.inventory_movements(store_id,created_at desc);

alter table public.transactions add column if not exists stock_deducted_at timestamptz;
alter table public.transactions add column if not exists stock_reversed_at timestamptz;
alter table public.kiloan_orders add column if not exists tracking_token text not null default encode(gen_random_bytes(24),'hex');
create unique index if not exists kiloan_orders_tracking_token_idx on public.kiloan_orders(tracking_token);
create table if not exists public.production_steps (
  id uuid primary key default gen_random_uuid(),
  store_id uuid not null references public.stores(id),
  order_id uuid not null references public.kiloan_orders(id) on delete cascade,
  stage text not null check(stage in ('cuci','pengeringan','setrika','packing','siap_diambil')),
  status text not null default 'menunggu' check(status in ('menunggu','proses','selesai')),
  updated_by uuid references auth.users(id),
  updated_at timestamptz not null default now(),
  unique(order_id,stage)
);
create index if not exists production_steps_order_idx on public.production_steps(order_id,stage);
insert into public.production_steps(store_id,order_id,stage,status)
select o.store_id,o.id,step.stage,case when o.status='Diambil' then 'selesai' when o.status='Selesai' and step.stage='siap_diambil' then 'selesai' else 'menunggu' end
from public.kiloan_orders o cross join (values ('cuci'),('pengeringan'),('setrika'),('packing'),('siap_diambil')) as step(stage)
on conflict(order_id,stage) do nothing;

-- All production detail remains private. The public function returns only safe tracking fields.
create or replace function public.get_order_tracking(p_token text)
returns jsonb language sql stable security definer set search_path=''
as $$
  select jsonb_build_object(
    'order_no',o.order_no,
    'status',o.status,
    'created_at',t.created_at,
    'steps',coalesce((select jsonb_agg(jsonb_build_object('stage',p.stage,'status',p.status) order by case p.stage when 'cuci' then 1 when 'pengeringan' then 2 when 'setrika' then 3 when 'packing' then 4 else 5 end) from public.production_steps p where p.order_id=o.id),'[]'::jsonb)
  ) from public.kiloan_orders o join public.transactions t on t.id=o.transaction_id where o.tracking_token=p_token limit 1
$$;
revoke all on function public.get_order_tracking(text) from public;
grant execute on function public.get_order_tracking(text) to anon,authenticated;
