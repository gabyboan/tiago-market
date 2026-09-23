-- Only run against an isolated database. All fixtures roll back.
begin;
insert into stores(name,slug) values ('Fixture Smart','smart-final-mexico-online'),('Fixture Local','fixture-local');
insert into branches(store_id,name,address,municipality,latitude,longitude,geocoding_status)
select id,'Fixture Centro','Fixture address','CDMX',19.43,-99.13,'manual' from stores where slug='fixture-local';
insert into products(name,normalized_name,category)
select 'Fixture '||i,'fixture '||i,case when i<=101 then 'Food' else 'Other' end from generate_series(1,104) i;
insert into store_products(store_id,product_id,external_name,store_product_url,presentation)
select s.id,p.id,p.name,'https://www.smartnfinal.com.mx/fixture/'||p.normalized_name,'1 kg' from products p cross join stores s where s.slug='smart-final-mexico-online';
insert into price_snapshots(store_product_id,price,currency,available,source,captured_at,external_reference,raw_payload,price_scope)
select id,10,'MXN',true,'fixture',now()-interval '1 hour',store_product_url,'{}','online' from store_products;
-- Current local price linked to an actual fixture branch.
insert into store_products(store_id,product_id,external_name,store_product_url,presentation)
select s.id,p.id,p.name,'https://example.org/local','1 kg' from stores s cross join products p where s.slug='fixture-local' and p.normalized_name='fixture 1';
insert into price_snapshots(store_product_id,branch_id,price,currency,available,source,captured_at,external_reference,price_scope)
select sp.id,b.id,8,'MXN',true,'fixture',now(),'https://example.org/local','branch_local' from store_products sp join branches b on b.store_id=sp.store_id;
-- A latest unavailable snapshot must not resurrect a previous available price.
insert into price_snapshots(store_product_id,price,currency,available,source,captured_at,external_reference,price_scope)
select id,10,'MXN',false,'fixture',now(),store_product_url,'online' from store_products where external_name='Fixture 104';
-- Expired and synthetic observations are not current catalogue entries.
update price_snapshots set captured_at=now()-interval '8 days' where store_product_id in(select id from store_products where external_name='Fixture 103');
update price_snapshots set raw_payload='{"is_synthetic":true}' where store_product_id in(select id from store_products where external_name='Fixture 102');

do $$
declare a text[]; b text[]; count_rows integer; row jsonb; n integer;
begin
 select array_agg(product_name) into a from online_prices_v3('',100,1);
 select array_agg(product_name) into b from online_prices_v3('',100,2);
 assert cardinality(a)=100 and cardinality(b)=1, 'pagination sizes';
 assert not a && b, 'pagination overlap';
 assert (select count(*)=0 from online_prices_v3('',100,3)), 'end pagination';
 assert (select count(*)=1 from online_prices_v3('Fixture 101')), 'search';
 assert (select count(*)=0 from online_prices_v3('',100,1,'Other')), 'category/quality filter';
 assert (select bool_and(branch_id is null and distance_km is null) from online_prices_v3('')), 'online separation';
 assert (select count(*)=1 from nearby_prices_v3('',19.43,-99.13)), 'local coverage';
 assert (select bool_and(branch_id is not null and branch_address is not null) from nearby_prices_v3('',19.43,-99.13)), 'local trace';
 assert (select count(*)=0 from nearby_prices_v3('',0,0)), 'no local coverage';
 assert (select count(*)=0 from nearby_prices_v3('',19.43,-99.13,10,100,2)), 'local pagination';
 assert (select count(*)=0 from nearby_prices_v3('',19.43,-99.13,10,100,1,'Other')), 'local category';
 assert (select count(*)=0 from online_prices_v3('Fixture 104')), 'unavailable resurrection';
 assert not has_function_privilege('anon','public.publish_online_observations(jsonb)','execute'), 'public ingest denied';
 assert not has_table_privilege('anon','public.current_catalog_prices','select'), 'view private';
 begin
   perform online_prices_v3('',100,0);
   raise exception 'invalid page accepted';
 exception when raise_exception then
   assert sqlerrm='Invalid pagination';
 end;
 row := jsonb_build_object('source','smart-final-public-web','store_slug','smart-final-mexico-online','price_scope','online',
 'product_name','Publisher fixture','normalized_name','publisher fixture','category','Food','presentation','1 kg',
 'price',9,'currency','MXN','available',true,'is_synthetic',false,'review_status','accepted',
 'source_url','https://www.smartnfinal.com.mx/fixture/publisher','store_product_url','https://www.smartnfinal.com.mx/fixture/publisher',
 'observed_at',now(),'response_sha256',repeat('a',64));
 n := publish_online_observations(jsonb_build_array(row));
 assert n=1, 'first publish';
 n := publish_online_observations(jsonb_build_array(row));
 assert n=0, 'idempotent replay';
 assert (select captured_at=(row->>'observed_at')::timestamptz from online_prices_v3('Publisher fixture')), 'real observation date retained';
 begin
   perform publish_online_observations(jsonb_build_array(row || '{"branch_id":"00000000-0000-0000-0000-000000000001"}'));
   raise exception 'mixed mode accepted';
 exception when raise_exception then assert sqlerrm='Incomplete or invalid online observation'; end;
 begin
   perform publish_online_observations(jsonb_build_array(row || jsonb_build_object('observed_at',now()-interval '8 days')));
   raise exception 'expired accepted';
 exception when raise_exception then assert sqlerrm='Expired or future observation'; end;
end $$;
set local role anon;
select count(*) as anonymous_online_page from public.online_prices_v3('');
select count(*) as anonymous_local from public.nearby_prices_v3('',19.43,-99.13);
rollback;
