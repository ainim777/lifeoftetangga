-- Reporting, stock cost snapshots, fully-counted cash closing, and server-side
-- membership reward application for LifeofTetangga.

alter table public.customers
  add column customer_type text not null default 'retail'
    check (customer_type in ('retail','b2b'));

alter table public.service_catalog
  add column estimated_unit_cost numeric(12,2) not null default 0
    check (estimated_unit_cost >= 0);

alter table public.transaction_items
  add column unit_cost numeric(12,2) not null default 0
    check (unit_cost >= 0),
  add column line_cost numeric(12,2)
    generated always as (quantity * unit_cost) stored;

alter table public.transactions
  add column membership_use_number integer,
  add column membership_reversed_at timestamptz;

alter table public.membership_rewards
  add column revoked_at timestamptz,
  add column revoked_reason text;

alter table public.inventory_items
  add column unit_cost numeric(12,2) not null default 0
    check (unit_cost >= 0);

alter table public.daily_closings
  add column qr_machine_counted numeric(12,2) not null default 0,
  add column qr_neighbor_counted numeric(12,2) not null default 0;

create table public.daily_traffic (
  id uuid primary key default gen_random_uuid(),
  store_id uuid not null references public.stores(id),
  business_date date not null,
  visitors integer not null default 0 check (visitors >= 0),
  note text,
  created_by uuid references auth.users(id),
  created_at timestamptz not null default now(),
  unique (store_id, business_date)
);
alter table public.daily_traffic enable row level security;
create policy daily_traffic_same_store on public.daily_traffic
  for all to authenticated
  using (store_id = (select public.current_store_id()))
  with check (store_id = (select public.current_store_id()));
grant select, insert, update on public.daily_traffic to authenticated;

create index if not exists profiles_store_id_idx on public.profiles(store_id);
create index if not exists transactions_customer_id_idx on public.transactions(customer_id);
create index if not exists transactions_created_by_idx on public.transactions(created_by);
create index if not exists transaction_items_transaction_id_idx on public.transaction_items(transaction_id);
create index if not exists transaction_items_service_id_idx on public.transaction_items(service_id);
create index if not exists membership_rewards_store_id_idx on public.membership_rewards(store_id);
create index if not exists membership_rewards_used_transaction_id_idx on public.membership_rewards(used_transaction_id);
create index if not exists kiloan_orders_transaction_id_idx on public.kiloan_orders(transaction_id);
create index if not exists expenses_created_by_idx on public.expenses(created_by);
create index if not exists daily_closings_closed_by_idx on public.daily_closings(closed_by);
create index if not exists membership_events_customer_id_idx on public.membership_events(customer_id);
create index if not exists membership_events_transaction_id_idx on public.membership_events(transaction_id);
create index if not exists daily_traffic_store_date_idx on public.daily_traffic(store_id,business_date desc);
create index if not exists membership_rewards_available_idx
  on public.membership_rewards(store_id,customer_id,expires_at)
  where used_at is null and revoked_at is null;

-- Trigger-only function: do not expose it as an RPC to browser roles.
revoke all on function public.count_membership_use() from public, anon, authenticated;
-- The policy helpers are needed by RLS for signed-in users, never anonymous users.
revoke all on function public.current_store_id() from public, anon;
revoke all on function public.current_role() from public, anon;
grant execute on function public.current_store_id() to authenticated;
grant execute on function public.current_role() to authenticated;

create or replace function public.count_membership_use()
returns trigger language plpgsql security definer set search_path=''
as $$
declare
  n integer;
  main_total numeric(12,2);
  reward_id uuid;
  chosen_reward public.membership_rewards%rowtype;
begin
  if tg_op = 'INSERT' and new.status = 'paid' then
    raise exception 'Create the transaction as unpaid, add its items, then mark it paid.';
  end if;

  if tg_op = 'UPDATE' and old.status <> 'paid' and new.status = 'paid' then
    select coalesce(sum(i.line_total),0),
           coalesce(sum(i.line_total) filter (where i.scope='self_service_main'),0)
      into new.subtotal, main_total
      from public.transaction_items i
     where i.transaction_id=new.id and i.store_id=new.store_id;
    if new.subtotal <= 0 then
      raise exception 'A paid transaction must have at least one item with a positive total.';
    end if;

    new.membership_discount := 0;
    if new.channel='self_service' and new.customer_id is not null and main_total > 0 then
      select * into chosen_reward
        from public.membership_rewards r
       where r.store_id=new.store_id and r.customer_id=new.customer_id
         and r.used_at is null and r.revoked_at is null and r.expires_at > now()
       order by r.expires_at, r.milestone
       limit 1 for update;
      if found then
        new.membership_discount := round(main_total * chosen_reward.percent_off / 100,2);
        update public.membership_rewards
           set used_transaction_id=new.id, used_at=now()
         where id=chosen_reward.id;
        insert into public.membership_events(store_id,customer_id,transaction_id,event_type,use_number,details)
        values(new.store_id,new.customer_id,new.id,'reward_used',chosen_reward.milestone,
               jsonb_build_object('percent_off',chosen_reward.percent_off,'discount',new.membership_discount));
      end if;
    end if;
    new.total := greatest(new.subtotal-new.membership_discount,0);
    new.paid_at := coalesce(new.paid_at,now());
  end if;

  if tg_op = 'UPDATE'
     and old.status='paid' and new.status in ('refunded','void')
     and old.membership_counted_at is not null
     and old.membership_reversed_at is null
     and old.customer_id is not null then
    update public.customers
       set membership_uses=greatest(membership_uses-1,0)
     where id=old.customer_id and store_id=old.store_id;
    new.membership_reversed_at := now();
    insert into public.membership_events(store_id,customer_id,transaction_id,event_type,use_number,details)
    values(old.store_id,old.customer_id,old.id,'transaction_reversed',old.membership_use_number,
           jsonb_build_object('reason',new.status));
    if old.membership_use_number in (5,10) then
      update public.membership_rewards
         set revoked_at=now(), revoked_reason='Transaksi pemicu progres dibatalkan atau direfund.'
       where store_id=old.store_id and customer_id=old.customer_id
         and milestone=old.membership_use_number and used_at is null and revoked_at is null;
    end if;
  end if;

  if new.status='paid' and new.channel in ('self_service','kiloan_retail')
     and new.customer_id is not null
     and (new.membership_counted_at is null or new.membership_reversed_at is not null) then
    update public.customers
       set membership_uses=membership_uses+1
     where id=new.customer_id and store_id=new.store_id
     returning membership_uses into n;
    if n is not null then
      new.membership_counted_at := now();
      new.membership_reversed_at := null;
      new.membership_use_number := n;
      insert into public.membership_events(store_id,customer_id,transaction_id,event_type,use_number)
      values(new.store_id,new.customer_id,new.id,'use_counted',n);
      if n in (5,10) then
        insert into public.membership_rewards(store_id,customer_id,milestone)
        values(new.store_id,new.customer_id,n)
        on conflict(customer_id,milestone) do update
          set earned_at=now(), expires_at=now()+interval '30 days', revoked_at=null, revoked_reason=null
          where membership_rewards.used_at is null
        returning id into reward_id;
        if found then
          insert into public.membership_events(store_id,customer_id,transaction_id,event_type,use_number,details)
          values(new.store_id,new.customer_id,new.id,'reward_earned',n,
                 jsonb_build_object('percent_off',25,'valid_days',30,'scope','self_service_main'));
        end if;
      end if;
    end if;
  end if;
  return new;
end $$;

-- Existing trigger already calls this function before insert/update of status.
