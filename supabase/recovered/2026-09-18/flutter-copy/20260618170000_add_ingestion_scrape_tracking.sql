create schema if not exists ingestion;

create table if not exists ingestion.scrape_runs (
  id uuid primary key default gen_random_uuid(),
  source text not null,
  status text not null check (status in ('running', 'success', 'failed')),
  started_at timestamptz not null default now(),
  finished_at timestamptz,
  fetched_count integer not null default 0 check (fetched_count >= 0),
  inserted_snapshots integer not null default 0 check (inserted_snapshots >= 0),
  error_message text,
  metadata jsonb not null default '{}'::jsonb
);

create index if not exists scrape_runs_source_started_at_idx
  on ingestion.scrape_runs (source, started_at desc);

create table if not exists ingestion.source_price_staging (
  id uuid primary key default gen_random_uuid(),
  run_id uuid references ingestion.scrape_runs(id) on delete cascade,
  source text not null,
  payload jsonb not null,
  normalized_payload jsonb not null default '{}'::jsonb,
  validation_errors text[] not null default '{}',
  created_at timestamptz not null default now()
);

create index if not exists source_price_staging_run_id_idx
  on ingestion.source_price_staging (run_id);

revoke all on schema ingestion from anon, authenticated;
revoke all on all tables in schema ingestion from anon, authenticated;

grant usage on schema ingestion to service_role;
grant all on all tables in schema ingestion to service_role;
