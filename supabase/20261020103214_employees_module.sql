create table if not exists public.employees (
  id uuid primary key default gen_random_uuid(),
  store_id uuid not null references public.stores(id) on delete cascade,
  name text not null check (length(trim(name)) > 0),
  position text not null check (position in ('manager','cashier','iron','delivery')),
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (id, store_id)
);

create index if not exists employees_store_active_name_idx
  on public.employees(store_id, active, name);

alter table public.payroll_records alter column user_id drop not null;
alter table public.payroll_records
  add column if not exists employee_id uuid references public.employees(id);

alter table public.employees enable row level security;
drop policy if exists employees_member_read on public.employees;
create policy employees_member_read on public.employees
  for select to authenticated
  using ((select private.has_store_access(store_id)));

drop policy if exists employees_manager_manage on public.employees;
create policy employees_manager_manage on public.employees
  for all to authenticated
  using ((select private.has_store_role(store_id, array['master','outlet_manager'])))
  with check ((select private.has_store_role(store_id, array['master','outlet_manager'])));

grant select, insert, update, delete on public.employees to authenticated;
grant select, insert, update on public.payroll_records to authenticated;
