-- Master customer visibility/edit support uses the existing cross-outlet RLS
-- memberships. This migration changes the milestone 10 reward to a free main
-- Self Service service, while preserving the milestone 5 discount.

alter table public.membership_rewards
  drop constraint if exists membership_rewards_percent_off_check;
-- Only unused rewards change meaning; historical redeemed rewards remain intact.
update public.membership_rewards
   set percent_off = 100
 where milestone = 10 and used_at is null and percent_off <> 100;
alter table public.membership_rewards
  add constraint membership_rewards_percent_off_check
  check ((milestone = 5 and percent_off = 25) or (milestone = 10 and percent_off = 100));

alter table public.transaction_payments
  drop constraint if exists transaction_payments_amount_check;
alter table public.transaction_payments
  add constraint transaction_payments_amount_check check (amount >= 0);

create or replace function public.apply_transaction_payment()
returns trigger language plpgsql security definer set search_path=''
as $$
declare
  t public.transactions%rowtype;
  already_paid numeric(12,2);
  main_total numeric(12,2);
  effective_total numeric(12,2);
  reward_percent numeric(5,2);
begin
  select * into t
    from public.transactions
   where id=new.transaction_id and store_id=new.store_id
   for update;
  if not found or t.status not in ('unpaid','partial') then
    raise exception 'Tagihan ini tidak lagi dapat menerima pembayaran.';
  end if;

  select coalesce(sum(p.amount),0) into already_paid
    from public.transaction_payments p
   where p.transaction_id=new.transaction_id and p.id<>new.id;
  effective_total:=t.total;

  if t.channel='self_service' and t.customer_id is not null then
    select coalesce(sum(i.line_total),0) into main_total
      from public.transaction_items i
     where i.transaction_id=t.id and i.store_id=t.store_id and i.scope='self_service_main';
    select r.percent_off into reward_percent
      from public.membership_rewards r
     where r.store_id=t.store_id and r.customer_id=t.customer_id
       and r.used_at is null and r.revoked_at is null and r.expires_at>now()
     order by r.expires_at,r.milestone limit 1;
    if reward_percent is not null and main_total>0 then
      effective_total:=greatest(t.subtotal-round(main_total*reward_percent/100,2),0);
    end if;
  end if;

  if already_paid+new.amount>effective_total then
    raise exception 'Jumlah pembayaran melebihi sisa tagihan setelah reward.';
  end if;
  if new.amount=0 and effective_total>already_paid then
    raise exception 'Pembayaran nol hanya berlaku jika seluruh tagihan sudah ditutup reward.';
  end if;
  update public.transactions
     set status=case when already_paid+new.amount>=effective_total then 'paid' else 'partial' end,
         payment_method=new.payment_method
   where id=t.id;
  return new;
end $$;
revoke all on function public.apply_transaction_payment() from public,anon,authenticated;

create or replace function public.count_membership_use()
returns trigger language plpgsql security definer set search_path=''
as $$
declare
  n integer;
  main_total numeric(12,2);
  reward_id uuid;
  chosen_reward public.membership_rewards%rowtype;
  is_legacy boolean;
  earned_at timestamptz;
  milestone_percent numeric(5,2);
begin
  select exists(select 1 from private.historical_import_transactions h where h.transaction_id=new.id) into is_legacy;
  if tg_op='INSERT' and new.status='paid' then
    raise exception 'Create the transaction as unpaid, add its items, then mark it paid.';
  end if;

  if tg_op='UPDATE' and old.status<>'paid' and new.status='paid' then
    select coalesce(sum(i.line_total),0),
           coalesce(sum(i.line_total) filter (where i.scope='self_service_main'),0)
      into new.subtotal,main_total
      from public.transaction_items i where i.transaction_id=new.id and i.store_id=new.store_id;
    if new.subtotal<=0 then raise exception 'A paid transaction must have at least one item with a positive total.'; end if;

    if not is_legacy then
      new.membership_discount:=0;
      if new.channel='self_service' and new.customer_id is not null and main_total>0 then
        select * into chosen_reward from public.membership_rewards r
         where r.store_id=new.store_id and r.customer_id=new.customer_id
           and r.used_at is null and r.revoked_at is null and r.expires_at>now()
         order by r.expires_at,r.milestone limit 1 for update;
        if found then
          new.membership_discount:=round(main_total*chosen_reward.percent_off/100,2);
          update public.membership_rewards set used_transaction_id=new.id,used_at=now() where id=chosen_reward.id;
          insert into public.membership_events(store_id,customer_id,transaction_id,event_type,use_number,details)
          values(new.store_id,new.customer_id,new.id,'reward_used',chosen_reward.milestone,
                 jsonb_build_object('percent_off',chosen_reward.percent_off,'discount',new.membership_discount));
        end if;
      end if;
      new.total:=greatest(new.subtotal-new.membership_discount,0);
    end if;
    new.paid_at:=coalesce(new.paid_at,now());
  end if;

  if tg_op='UPDATE' and old.status='paid' and new.status in ('refunded','void')
     and old.membership_counted_at is not null and old.membership_reversed_at is null and old.customer_id is not null then
    update public.customers set membership_uses=greatest(membership_uses-1,0)
      where id=old.customer_id and store_id=old.store_id;
    new.membership_reversed_at:=now();
    insert into public.membership_events(store_id,customer_id,transaction_id,event_type,use_number,details)
      values(old.store_id,old.customer_id,old.id,'transaction_reversed',old.membership_use_number,jsonb_build_object('reason',new.status));
    if old.membership_use_number in (5,10) then
      update public.membership_rewards set revoked_at=now(),revoked_reason='Transaksi pemicu progres dibatalkan atau direfund.'
       where store_id=old.store_id and customer_id=old.customer_id and milestone=old.membership_use_number and used_at is null and revoked_at is null;
    end if;
  end if;

  if new.status='paid' and new.channel in ('self_service','kiloan_retail') and new.customer_id is not null
     and (new.membership_counted_at is null or new.membership_reversed_at is not null) then
    update public.customers set membership_uses=membership_uses+1 where id=new.customer_id and store_id=new.store_id returning membership_uses into n;
    if n is not null then
      earned_at:=case when is_legacy then coalesce(new.paid_at,new.created_at,now()) else now() end;
      new.membership_counted_at:=earned_at;
      new.membership_reversed_at:=null;
      new.membership_use_number:=n;
      insert into public.membership_events(store_id,customer_id,transaction_id,event_type,use_number)
        values(new.store_id,new.customer_id,new.id,'use_counted',n);
      if n in (5,10) then
        milestone_percent:=case when n=5 then 25 else 100 end;
        insert into public.membership_rewards(store_id,customer_id,milestone,percent_off,earned_at,expires_at)
          values(new.store_id,new.customer_id,n,milestone_percent,earned_at,earned_at+interval '30 days')
          on conflict(customer_id,milestone) do update
            set percent_off=excluded.percent_off,earned_at=excluded.earned_at,expires_at=excluded.expires_at,revoked_at=null,revoked_reason=null
            where membership_rewards.used_at is null
          returning id into reward_id;
        if found then
          insert into public.membership_events(store_id,customer_id,transaction_id,event_type,use_number,details)
          values(new.store_id,new.customer_id,new.id,'reward_earned',n,
                 jsonb_build_object('percent_off',milestone_percent,'valid_days',30,'scope','self_service_main','label',case when n=5 then 'Diskon 25%' else 'Gratis jasa utama' end));
        end if;
      end if;
    end if;
  end if;
  return new;
end $$;
revoke all on function public.count_membership_use() from public,anon,authenticated;
