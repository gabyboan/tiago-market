-- Bounded cleanup can prove that staging payloads were published without
-- repeatedly scanning/decompressing the complete price history.
create index if not exists price_snapshots_source_content_hash_idx
on public.price_snapshots (source, (raw_payload->>'content_hash'))
where raw_payload ? 'content_hash';
