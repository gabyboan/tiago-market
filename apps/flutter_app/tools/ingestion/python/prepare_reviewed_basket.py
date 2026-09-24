#!/usr/bin/env python3
"""Prepare an explicitly reviewed, complete basket for the existing staging tool.

Exact URL/name/presentation bindings fail closed if a source changes. Produces
SQL only; never connects to Supabase. Original source names and receipts remain
intact. Reviewed comparison metadata is applied in the same load transaction.
"""
import argparse
import base64
from collections import Counter
import copy
import json
from pathlib import Path
import subprocess


def review_manifest(manifest, rows):
    """Return one fail-closed status for every expected source listing."""
    counts = Counter((r.get('source'), r.get('store_product_url')) for r in rows)
    by_url = {(r.get('source'), r.get('store_product_url')): r for r in rows}
    expected = set()
    report = []
    for item in manifest['items']:
        for listing in item['listings']:
            identity = (listing['source'], listing['url'])
            expected.add(identity)
            row = by_url.get(identity)
            reasons = []
            if counts[identity] > 1:
                reasons.append('duplicate_capture')
            if row is None:
                reasons.append('missing_capture_or_evidence')
            else:
                if row.get('source_product_name') != listing['observed_name']:
                    reasons.append('product_name_changed')
                if row.get('presentation') != listing['observed_presentation']:
                    reasons.append('presentation_or_unit_changed')
                if row.get('price_scope') != 'online':
                    reasons.append('price_scope_changed')
                if row.get('available') is not True:
                    reasons.append('availability_not_confirmed')
                if row.get('is_synthetic') is not False:
                    reasons.append('synthetic_or_unknown_evidence')
                if row.get('review_status') != 'accepted':
                    reasons.append('evidence_not_accepted')
                if not isinstance(row.get('raw_payload'), dict):
                    reasons.append('raw_evidence_missing')
            report.append({
                'canonical_variant_key': item['canonical_variant_key'],
                'label': item['label'], 'source': listing['source'],
                'url': listing['url'],
                'status': 'pending_review' if reasons else 'ready',
                'reasons': reasons,
                'observed_name': row.get('source_product_name') if row else None,
                'observed_presentation': row.get('presentation') if row else None,
            })
    for source, url in set(by_url) - expected:
        report.append({'canonical_variant_key': None, 'label': None,
                       'source': source, 'url': url,
                       'status': 'pending_review',
                       'reasons': ['unexpected_listing'],
                       'observed_name': by_url[(source, url)].get('source_product_name'),
                       'observed_presentation': by_url[(source, url)].get('presentation')})
    return report


def prepare(manifest, rows):
    review = review_manifest(manifest, rows)
    pending = [item for item in review if item['status'] == 'pending_review']
    if pending:
        summary = '; '.join(
            f"{item['source']} {item['url']}: {','.join(item['reasons'])}"
            for item in pending)
        raise ValueError('Review required: ' + summary)
    by_url = {(r['source'], r['store_product_url']): r for r in rows}
    if len(by_url) != len(rows):
        raise ValueError('Duplicate source URL in input')
    result, mappings, seen, keys = [], [], set(), set()
    for item in manifest['items']:
        key = item['canonical_variant_key']
        if not key.startswith('reviewed:') or key in keys:
            raise ValueError('Invalid or repeated reviewed identity')
        keys.add(key)
        if len(item['listings']) != 2 or {x['source'] for x in item['listings']} != {'merco-mx', 'chedraui-mx'}:
            raise ValueError('Each basket item requires both stores')
        for listing in item['listings']:
            identity = (listing['source'], listing['url'])
            if identity in seen or identity not in by_url:
                raise ValueError('Missing or repeated listing: ' + listing['url'])
            seen.add(identity)
            row = copy.deepcopy(by_url[identity])
            if (row['source_product_name'] != listing['observed_name'] or
                    row['presentation'] != listing['observed_presentation'] or
                    row['price_scope'] != 'online' or row['available'] is not True or
                    row['is_synthetic'] is not False or row['review_status'] != 'accepted'):
                raise ValueError('Listing changed or is not publishable: ' + listing['url'])
            row['category'] = item['category']
            row['raw_payload']['reviewed_comparison'] = {
                'canonical_variant_key': key,
                'basis': item['match_basis'],
                'reviewed_at': manifest['reviewed_at'],
            }
            # Preserve hash, source title, presentation and observation timestamp.
            result.append(row)
            mappings.append({
                'source': row['source'], 'url': row['store_product_url'],
                'name': row['source_product_name'], 'canonical_variant_key': key,
                'brand': item['brand'], 'variant_label': item['label'],
                'net_quantity': item['net_quantity'], 'unit': item['unit'],
                'pack_count': item['pack_count'],
            })
    if seen != set(by_url):
        raise ValueError('Input contains unreviewed extra listings')
    return result, mappings


def metadata_sql(mappings):
    encoded = base64.b64encode(json.dumps(mappings, ensure_ascii=False).encode()).decode()
    # Base64 payload contains no SQL quote or dollar delimiter.
    return f"""
-- Apply reviewed identity only to the exact official source listings loaded above.
do $basket$
declare matched integer;
begin
  with mapping as (
    select * from jsonb_to_recordset(convert_from(decode('{encoded}', 'base64'), 'UTF8')::jsonb)
    as m(source text, url text, name text, canonical_variant_key text,
         brand text, variant_label text, net_quantity numeric, unit text, pack_count integer)
  ), bindings as (
    select sp.product_id, m.* from mapping m
    join public.store_products sp on sp.source = m.source
      and sp.store_product_url = m.url and sp.external_name = m.name
  ), updated as (
    update public.products p set canonical_variant_key = b.canonical_variant_key,
      brand = b.brand, variant_label = b.variant_label,
      net_quantity = b.net_quantity, unit = b.unit, pack_count = b.pack_count
    from bindings b where p.id = b.product_id returning p.id
  )
  select count(*) into matched from bindings;
  if matched <> {len(mappings)} then
    raise exception 'Reviewed basket binding mismatch: %', matched;
  end if;
end;
$basket$;
"""


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--manifest', type=Path, required=True)
    parser.add_argument('--inputs', type=Path, nargs='+', required=True)
    parser.add_argument('--out-dir', type=Path, required=True)
    parser.add_argument('--review-report', type=Path)
    args = parser.parse_args()
    rows = [json.loads(line) for p in args.inputs for line in p.read_text().splitlines() if line.strip()]
    manifest = json.loads(args.manifest.read_text())
    review = review_manifest(manifest, rows)
    if args.review_report:
        args.review_report.write_text(json.dumps(review, ensure_ascii=False, indent=2) + '\n')
    rows, mappings = prepare(manifest, rows)
    args.out_dir.mkdir(parents=True, exist_ok=False)
    ndjson = args.out_dir / 'basket.ndjson'
    sql = args.out_dir / 'publish.sql'
    ndjson.write_text(''.join(json.dumps(r, ensure_ascii=False) + '\n' for r in rows))
    subprocess.run(['dart', 'run', 'tools/ingestion/bin/stage_ndjson.dart',
                    '--input', str(ndjson), '--run-source', 'chedraui-merco-basket',
                    '--sql-out', str(sql), '--report-out', str(args.out_dir / 'preflight.txt')], check=True)
    statement = sql.read_text()
    if not statement.rstrip().endswith('commit;'):
        raise ValueError('Unexpected staging transaction')
    sql.write_text(statement.rstrip()[:-len('commit;')] + metadata_sql(mappings) + '\ncommit;\n')
    print(json.dumps({'observations': len(rows), 'by_source': dict(Counter(r['source'] for r in rows)),
                      'pairs': len(rows) // 2, 'sql': str(sql)}))


if __name__ == '__main__':
    main()
