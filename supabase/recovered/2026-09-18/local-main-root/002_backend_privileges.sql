revoke all on table public.stores from anon, authenticated;
revoke all on table public.products from anon, authenticated;
revoke all on table public.store_products from anon, authenticated;
revoke all on table public.price_snapshots from anon, authenticated;
revoke all on table public.latest_prices from anon, authenticated;
revoke all on table public.compare_prices from anon, authenticated;

grant usage on schema public to service_role;

grant select, insert, update
  on table public.stores, public.products, public.store_products
  to service_role;

grant select, insert
  on table public.price_snapshots
  to service_role;

grant select
  on table public.latest_prices, public.compare_prices
  to service_role;
