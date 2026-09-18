alter table ingestion.scrape_runs enable row level security;
alter table ingestion.source_price_staging enable row level security;
alter table ingestion.source_catalog enable row level security;

revoke all on schema ingestion from anon, authenticated;
revoke all on all tables in schema ingestion from anon, authenticated;
revoke all on all sequences in schema ingestion from anon, authenticated;
revoke all on all functions in schema ingestion from anon, authenticated;

grant usage on schema ingestion to service_role;
grant all on all tables in schema ingestion to service_role;
grant all on all sequences in schema ingestion to service_role;
grant all on all functions in schema ingestion to service_role;

revoke execute on function public.rls_auto_enable() from public;
revoke execute on function public.rls_auto_enable() from anon;
revoke execute on function public.rls_auto_enable() from authenticated;
