-- Let authenticated outlet members receive customer changes immediately.
-- Realtime payload visibility still follows the customers table's RLS policies.
do $$
begin
  if exists(select 1 from pg_publication where pubname='supabase_realtime')
     and not exists(select 1 from pg_publication_tables where pubname='supabase_realtime' and schemaname='public' and tablename='customers') then
    execute 'alter publication supabase_realtime add table public.customers';
  end if;
end $$;
