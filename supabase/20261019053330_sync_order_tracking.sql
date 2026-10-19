create or replace function public.sync_order_tracking_steps()
returns trigger language plpgsql security definer set search_path=''
as $$
declare step record; step_status text;
begin
  for step in select * from (values ('cuci',1),('pengeringan',2),('setrika',3),('packing',4),('siap_diambil',5)) as stages(name,rank) loop
    step_status:=case
      when new.status='Diambil' then 'selesai'
      when new.status='Selesai' and step.rank<5 then 'selesai'
      when new.status='Selesai' and step.rank=5 then 'proses'
      when new.status='Proses' and step.rank=1 then 'selesai'
      when new.status='Proses' and step.rank=2 then 'proses'
      when new.status='Masuk' and step.rank=1 then 'proses'
      else 'menunggu' end;
    insert into public.production_steps(store_id,order_id,stage,status,updated_by)
      values(new.store_id,new.id,step.name,step_status,(select auth.uid()))
      on conflict(order_id,stage) do update set status=excluded.status,updated_by=excluded.updated_by,updated_at=now();
  end loop;
  return new;
end $$;
revoke all on function public.sync_order_tracking_steps() from public,anon,authenticated;
drop trigger if exists kiloan_order_tracking_sync on public.kiloan_orders;
create trigger kiloan_order_tracking_sync after insert or update of status on public.kiloan_orders
for each row execute function public.sync_order_tracking_steps();
update public.kiloan_orders set status=status;
