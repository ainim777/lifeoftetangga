-- Run once in Supabase SQL Editor after creating the first Auth user.
-- Replace OWNER_EMAIL with the exact email used for that Supabase Auth user.
insert into public.profiles(id,store_id,name,role,active)
select u.id,s.id,'Pemilik LifeofTetangga','owner',true
from auth.users u
cross join public.stores s
where lower(u.email)=lower('OWNER_EMAIL')
  and s.name='LifeofTetangga'
  and s.id=(select id from public.stores where name='LifeofTetangga' order by created_at desc limit 1)
on conflict (id) do nothing;
