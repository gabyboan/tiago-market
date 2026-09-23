-- Align ingestion staging with the public online/local catalog split.
alter table ingestion.source_price_staging
  drop constraint if exists source_price_staging_accepted_real_evidence_check;

alter table ingestion.source_price_staging
  add constraint source_price_staging_accepted_real_evidence_check check (
    review_status <> 'accepted'
    or (
      is_synthetic = false
      and evidence_kind <> 'unknown'
      and observed_at is not null
      and source_url is not null
      and source_url ~* '^https?://'
      and confidence_score >= 0.70
      and coalesce(cardinality(validation_errors), 0) = 0
      and (
        (
          normalized_payload->>'price_scope' = 'online'
          and nullif(normalized_payload->>'branch_external_key', '') is null
          and nullif(normalized_payload->>'branch_name', '') is null
          and nullif(normalized_payload->>'branch_address', '') is null
          and nullif(normalized_payload->>'branch_municipality', '') is null
          and nullif(normalized_payload->>'branch_state', '') is null
          and nullif(normalized_payload->>'latitude', '') is null
          and nullif(normalized_payload->>'longitude', '') is null
        )
        or (
          coalesce(normalized_payload->>'price_scope', 'branch_local') = 'branch_local'
          and nullif(normalized_payload->>'branch_external_key', '') is not null
          and nullif(normalized_payload->>'branch_name', '') is not null
          and nullif(normalized_payload->>'branch_address', '') is not null
          and nullif(normalized_payload->>'branch_municipality', '') is not null
          and nullif(normalized_payload->>'branch_state', '') is not null
          and (normalized_payload->>'latitude') ~ '^-?[0-9]+(\\.[0-9]+)?$'
          and (normalized_payload->>'longitude') ~ '^-?[0-9]+(\\.[0-9]+)?$'
          and (normalized_payload->>'latitude')::numeric between 14 and 33.5
          and (normalized_payload->>'longitude')::numeric between -119 and -86
        )
      )
    )
  ) not valid;

create or replace view ingestion.publishable_source_prices as
select *
from ingestion.source_price_staging
where review_status = 'accepted'
  and is_synthetic = false
  and evidence_kind <> 'unknown'
  and observed_at is not null
  and source_url is not null
  and source_url ~* '^https?://'
  and confidence_score >= 0.70
  and coalesce(cardinality(validation_errors), 0) = 0
  and (
    (
      normalized_payload->>'price_scope' = 'online'
      and nullif(normalized_payload->>'branch_external_key', '') is null
      and nullif(normalized_payload->>'branch_name', '') is null
      and nullif(normalized_payload->>'branch_address', '') is null
      and nullif(normalized_payload->>'branch_municipality', '') is null
      and nullif(normalized_payload->>'branch_state', '') is null
      and nullif(normalized_payload->>'latitude', '') is null
      and nullif(normalized_payload->>'longitude', '') is null
    )
    or (
      coalesce(normalized_payload->>'price_scope', 'branch_local') = 'branch_local'
      and nullif(normalized_payload->>'branch_external_key', '') is not null
      and nullif(normalized_payload->>'branch_name', '') is not null
      and nullif(normalized_payload->>'branch_address', '') is not null
      and nullif(normalized_payload->>'branch_municipality', '') is not null
      and nullif(normalized_payload->>'branch_state', '') is not null
      and (normalized_payload->>'latitude') ~ '^-?[0-9]+(\\.[0-9]+)?$'
      and (normalized_payload->>'longitude') ~ '^-?[0-9]+(\\.[0-9]+)?$'
      and (normalized_payload->>'latitude')::numeric between 14 and 33.5
      and (normalized_payload->>'longitude')::numeric between -119 and -86
    )
  );