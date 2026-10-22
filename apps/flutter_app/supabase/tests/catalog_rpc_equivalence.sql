-- Both RPC definitions run against exactly the same snapshot and roll back.
insert into public.stores(name,slug) values ('Fixture Alpha','fixture-alpha'),('Fixture Beta','fixture-beta');
insert into public.products(name,normalized_name,category,brand,net_quantity,unit,pack_count)
select 'Fixture '||i,'fixture '||i,case when i%2=0 then 'Food' else 'Other' end,'Fixture',1,'kg',1 from generate_series(1,230) i;
insert into public.store_products(store_id,product_id,external_name,store_product_url,image_url,presentation)
select s.id,p.id,p.name,'https://example.org/'||s.slug||'/'||replace(p.normalized_name,' ','-'),'https://example.org/image.jpg','1 kg' from public.products p cross join public.stores s;
insert into public.price_snapshots(store_product_id,price_scope,price,currency,available,source,captured_at,external_reference,raw_payload)
select sp.id,'online',split_part(p.normalized_name,' ',2)::numeric,'MXN',true,'fixture',now()-interval '2 hours',sp.store_product_url,'{}' from public.store_products sp join public.products p on p.id=sp.product_id;
insert into public.product_images(store_product_id,image_url)
select sp.id,'https://example.org/'||i||'.jpg' from public.store_products sp cross join generate_series(1,2) i;

-- Newer unavailable, expired, rejected and synthetic prices never resurrect history.
insert into public.price_snapshots(store_product_id,price_scope,price,currency,available,source,captured_at,external_reference,raw_payload)
select sp.id,'online',5,'MXN',false,'fixture',now(),sp.store_product_url,'{}' from public.store_products sp join public.products p on p.id=sp.product_id where p.normalized_name='fixture 104';
update public.price_snapshots ps set captured_at=now()-interval '8 days' from public.store_products sp join public.products p on p.id=sp.product_id where ps.store_product_id=sp.id and p.normalized_name='fixture 103';
update public.price_snapshots ps set raw_payload=case p.normalized_name
  when 'fixture 102' then '{"is_synthetic":true}'::jsonb
  when 'fixture 105' then '{"review_status":"rejected"}'::jsonb
  when 'fixture 106' then jsonb_build_object('valid_until',now()-interval '1 hour')
  when 'fixture 113' then '{"source_url":"https://example.org/evidence"}'::jsonb
  else '{}'::jsonb end
from public.store_products sp join public.products p on p.id=sp.product_id where ps.store_product_id=sp.id;
insert into public.price_snapshots(store_product_id,price_scope,price,currency,available,source,captured_at,external_reference,raw_payload)
select sp.id,'online',1,case when p.normalized_name='fixture 108' then 'USD' else 'MXN' end,true,'fixture',
  case when p.normalized_name='fixture 107' then now()+interval '10 minutes' else now() end,sp.store_product_url,'{}'
from public.store_products sp join public.products p on p.id=sp.product_id where p.normalized_name in('fixture 107','fixture 108');
update public.price_snapshots ps set price=0 from public.store_products sp join public.products p on p.id=sp.product_id where ps.store_product_id=sp.id and p.normalized_name='fixture 109';
update public.products set name='' where normalized_name='fixture 110';
update public.store_products sp set presentation='' from public.products p where p.id=sp.product_id and p.normalized_name='fixture 111';
update public.price_snapshots ps set source='' from public.store_products sp join public.products p on p.id=sp.product_id where ps.store_product_id=sp.id and p.normalized_name='fixture 112';
update public.store_products sp set store_product_url='invalid',image_url='invalid' from public.products p where p.id=sp.product_id and p.normalized_name='fixture 113';

-- A price from a real branch must not replace the separate online observation.
insert into public.branches(store_id,name,address,municipality,latitude,longitude,geocoding_status)
select id,'Fixture branch','Fixture address','Fixture municipality',19.43,-99.13,'manual' from public.stores where slug='fixture-alpha';
insert into public.price_snapshots(store_product_id,branch_id,price_scope,price,currency,available,source,captured_at,external_reference,raw_payload)
select sp.id,b.id,'branch_local',0.5,'MXN',true,'fixture',now(),'https://example.org/local','{}' from public.store_products sp join public.products p on p.id=sp.product_id join public.branches b on b.store_id=sp.store_id where p.normalized_name='fixture 1';

do $$
declare item record; previous jsonb; optimized jsonb;
begin
  for item in select * from (values
    ('',100,1,null::text,true,'price_asc'),('',100,2,null,true,'price_asc'),
    ('',20,3,null,true,'price_asc'),('Fixture 1',100,1,null,true,'price_asc'),
    ('fixture',10,1,'Food',true,'price_asc'),('missing',100,1,null,true,'price_asc'),
    ('',100,1,null,false,'price_asc'),('',100,1,null,null,'price_asc'),
    ('',100,1,null,true,'price_desc'),('',100,1,null,true,'fresh_desc'),
    ('',100,1,null,true,'name'),('',100,1,null,true,'unknown'),
    ('',100,1,null,true,null),('',100,1,'missing',true,'price_asc'),
    ('',100,10000,null,true,'price_asc')
  ) as args(search_query,limit_count,page_number,category_filter,only_available,sort_order)
  loop
    select coalesce(jsonb_agg(to_jsonb(x)-'ordinality' order by x.ordinality),'[]') into previous
    from public.online_prices_v4_baseline(item.search_query,item.limit_count,item.page_number,item.category_filter,item.only_available,item.sort_order) with ordinality x;
    select coalesce(jsonb_agg(to_jsonb(x)-'ordinality' order by x.ordinality),'[]') into optimized
    from public.online_prices_v4(item.search_query,item.limit_count,item.page_number,item.category_filter,item.only_available,item.sort_order) with ordinality x;
    assert previous=optimized, format('RPC changed results or ordering: %s',row_to_json(item));
  end loop;
  for item in select * from (values(0,1),(101,1),(null::integer,1),(10,0),(10,10001),(10,null::integer)) args(limit_count,page_number)
  loop
    begin
      perform public.online_prices_v4('',item.limit_count,item.page_number);
      raise exception 'Invalid pagination accepted';
    exception when raise_exception then assert sqlerrm='Invalid pagination'; end;
  end loop;
  assert not has_table_privilege('anon','public.price_snapshots','select'), 'No anonymous table access';
  assert not has_table_privilege('anon','public.current_catalog_prices','select'), 'Catalog view remains private';
  assert not exists(select 1 from pg_proc p cross join lateral aclexplode(p.proacl) a where p.oid='public.online_prices_v4(text,integer,integer,text,boolean,text)'::regprocedure and a.grantee=0 and a.privilege_type='EXECUTE'), 'No PUBLIC execution grant';
end $$;
set local role anon;
select count(*) as anonymous_catalog_page from public.online_prices_v4('');
reset role;
