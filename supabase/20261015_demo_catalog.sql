-- Seed configurable catalog and inventory with visible demo markers.
alter table public.service_catalog
  add column price_is_demo boolean not null default true;
alter table public.inventory_items
  add column is_demo boolean not null default true;

insert into public.service_catalog(store_id,name,category,price,unit,active,estimated_unit_cost,price_is_demo)
select s.id,v.name,v.category,v.price,v.unit,true,0,true
from public.stores s
cross join (values
 ('Cuci Kering 5 KG','self_service_main',10000::numeric,'siklus'),
 ('Cuci Kering 7 KG','self_service_main',20000::numeric,'siklus'),
 ('Cuci Saja 5 KG','self_service_main',30000::numeric,'siklus'),
 ('Cuci Saja 7 KG','self_service_main',40000::numeric,'siklus'),
 ('Kering Saja 5 KG','self_service_main',50000::numeric,'siklus'),
 ('Kering Saja 7 KG','self_service_main',60000::numeric,'siklus'),
 ('Drop Off','addon',5000::numeric,'layanan'),
 ('Lipat','addon',10000::numeric,'layanan'),
 ('Sewa Setrika','addon',15000::numeric,'layanan'),
 ('Antar Jemput','addon',20000::numeric,'layanan'),
 ('Detergen Scoop Additional','addon',25000::numeric,'scoop'),
 ('Detergen Kemasan','product',12000::numeric,'pcs'),
 ('Pewangi Kemasan','product',24000::numeric,'pcs'),
 ('Plastik Merah','product',36000::numeric,'pak'),
 ('Cuci Kering','kiloan_service',10000::numeric,'kg'),
 ('Cuci Kering + Setrika','kiloan_service',20000::numeric,'kg'),
 ('Setrika Saja','kiloan_service',30000::numeric,'kg')
) as v(name,category,price,unit)
where s.id=(select id from public.stores where name='LifeofTetangga' order by created_at desc limit 1);

insert into public.inventory_items(store_id,name,category,unit,quantity,minimum_quantity,unit_cost,is_demo)
select s.id,v.name,v.category,v.unit,v.quantity,v.minimum_quantity,0,true
from public.stores s
cross join (values
 ('Detergen Kemasan','product','pcs',12::numeric,10::numeric),
 ('Pewangi Kemasan','product','pcs',8::numeric,10::numeric),
 ('Plastik Merah','product','pak',6::numeric,8::numeric),
 ('Detergen curah','operational_supply','kg',4::numeric,5::numeric),
 ('Pewangi laundry','operational_supply','liter',2::numeric,3::numeric),
 ('Kantong laundry','operational_supply','pcs',45::numeric,20::numeric)
) as v(name,category,unit,quantity,minimum_quantity)
where s.id=(select id from public.stores where name='LifeofTetangga' order by created_at desc limit 1);
