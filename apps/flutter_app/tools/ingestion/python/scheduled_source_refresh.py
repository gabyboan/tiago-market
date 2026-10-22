#!/usr/bin/env python3
"""Refresh one existing grocery source; store captures privately, report counts.

Uses the established capture, identity reconciliation and rollback-first staging
tools. A blocked store never prevents another matrix job from publishing.
"""
import argparse
from datetime import datetime, timezone
import json
import os
from pathlib import Path
import subprocess
import sys
from urllib.error import HTTPError
from urllib.request import Request, urlopen
from urllib.parse import urlsplit

from daily_basket_update import read_ndjson
from expand_grocery_sources import SOURCES
from online_catalog import timestamp
from prepare_grocery_batch import reconcile
from refresh_grocery_catalogs import BULK, capture_source, json_write
from refresh_online_catalog import Database, ROOT, literal


def known_sql(source):
    return """select sp.source, sp.store_product_url, sp.external_name, sp.presentation,
       p.normalized_name, p.category, s.slug as store_slug, sp.image_url,
       latest.captured_at as latest_capture, latest.source_product_id
from public.store_products sp
join public.products p on p.id=sp.product_id
join public.stores s on s.id=sp.store_id
join lateral (
  select ps.captured_at,
         coalesce(ps.raw_payload#>>'{raw_payload,evidence,productId}',
                  ps.raw_payload#>>'{raw_payload,product_id}',
                  ps.raw_payload#>>'{evidence,productId}',
                  ps.raw_payload->>'product_id') as source_product_id
  from public.price_snapshots ps
  where ps.store_product_id=sp.id and ps.price_scope='online' and ps.branch_id is null
  order by ps.captured_at desc limit 1
) latest on true
where sp.branch_id is null and s.enabled and s.country='MX'
  and sp.source=""" + literal(source) + """
order by sp.store_product_url, p.normalized_name
"""


def prepare_existing(rows, known):
    """Keep reviewed identities/categories and the HTTP observation's real date."""
    reconciled, held = reconcile(rows, known)
    saved = {}
    for item in known:
        key = (item['source'], item['store_product_url'], item['normalized_name'])
        saved.setdefault(key, []).append(item)
    accepted = []
    for item in reconciled:
        key = (item['source'], item['store_product_url'], item['normalized_name'])
        candidates = saved.get(key, [])
        reason = None
        if len(candidates) != 1:
            reason = 'New or ambiguous listing requires a separate review'
        else:
            previous = candidates[0]
            if (previous.get('latest_capture') and
                    timestamp(item['captured_at']) < timestamp(previous['latest_capture'])):
                reason = 'Observation is older than the saved price'
        if reason:
            held.append({'source': item['source'], 'url': item['store_product_url'],
                         'reason': reason})
        else:
            accepted.append(dict(item, category=previous['category']))
    return accepted, held


def publish(input_path, folder, run_source):
    """The commit command cannot run unless every rollback check passed."""
    command = [sys.executable, str(ROOT / 'tools/ingestion/python/publish_grocery_batch.py'),
               '--input', str(input_path), '--out-dir', str(folder),
               '--run-source', run_source]
    for phase, arguments in [('dry-run', []), ('publish', ['--publish'])]:
        with (input_path.parent / f'{phase}.log').open('w') as log:
            result = subprocess.run(command + arguments, cwd=ROOT, stdout=log,
                                    stderr=subprocess.STDOUT, timeout=1200)
        if result.returncode:
            raise RuntimeError(f'{phase} failed; inspect the private runner log')
    return json.loads((folder / 'publication-report.json').read_text())


def verify_database(db, rows):
    expected = [{k: r[k] for k in ('source', 'store_product_url', 'normalized_name',
                                  'captured_at', 'price', 'available')} for r in rows]
    sql = """
with expected as (
  select * from jsonb_to_recordset(""" + literal(json.dumps(expected)) + """::jsonb)
  as x(source text, store_product_url text, normalized_name text,
       captured_at timestamptz, price numeric, available boolean)
)
select count(*) as expected,
       count(c.store_product_id) as matched
from expected e
left join public.current_catalog_prices c
  on c.source=e.source and c.store_product_url=e.store_product_url
 and c.normalized_name=e.normalized_name and c.captured_at=e.captured_at
 and c.price=e.price and c.available=e.available and c.branch_id is null
"""
    result = db.query(sql, 'verify-published')[0]
    if result['expected'] != len(rows) or result['matched'] != len(rows):
        raise RuntimeError('Published observations do not match the current catalog')
    return result


def public_smoke(config):
    """Check the public app endpoint, including availability and search routes."""
    counts = {}
    for query in ('', 'leche', 'arroz'):
        request = Request(config['SUPABASE_URL'].rstrip('/') + '/rest/v1/rpc/online_prices_v4',
                          data=json.dumps({'search_query': query, 'limit_count': 100,
                                           'page_number': 1, 'only_available': True}).encode(),
                          headers={'apikey': config['SUPABASE_PUBLISHABLE_KEY'],
                                   'Content-Type': 'application/json'})
        try:
            with urlopen(request, timeout=30) as response:
                found = json.load(response)
        except HTTPError as error:
            raise RuntimeError(f'Public catalog returned HTTP {error.code}') from None
        if not isinstance(found, list) or len(found) > 100:
            raise RuntimeError('Invalid public catalog response')
        for row in found:
            if (row.get('currency') != 'MXN' or row.get('available') is not True
                    or row.get('branch_id') is not None or row.get('distance_km') is not None):
                raise RuntimeError('Public online catalog contract failed')
        counts[query or 'all'] = len(found)
    if not counts['all']:
        raise RuntimeError('The public app still has no available products')
    return counts


def failure_diagnostics(folder):
    """Expose controlled error categories, never raw SQL, replies or credentials."""
    signatures = {
        'password authentication failed': 'Database password rejected: update the Actions SUPABASE_DB_URL secret.',
        'tenant or user not found': 'Pooler project/user not found: check the Actions SUPABASE_DB_URL secret.',
        'network is unreachable': 'Database network unreachable: use the IPv4-compatible Session pooler URI.',
        'could not translate host name': 'Database hostname could not be resolved.',
        'connection timed out': 'Database connection timed out.',
        'permission denied': 'Database role lacks the required permission.',
        'syntax error': 'Database query syntax failed.',
        'does not exist': 'Database schema does not match the ingestion contract.',
        'read-only transaction': 'Database is read-only; check project storage and configuration.',
    }
    found = set()
    for path in folder.rglob('*.log'):
        content = path.read_text(errors='replace').lower()
        found.update(message for signature, message in signatures.items() if signature in content)
    return sorted(found)


def validate_config(config):
    if not config.get('SUPABASE_URL') or not config.get('SUPABASE_PUBLISHABLE_KEY'):
        raise RuntimeError('Missing SUPABASE_URL or SUPABASE_PUBLISHABLE_KEY in Actions configuration')
    connection = urlsplit(os.environ.get('SUPABASE_DB_URL', ''))
    project = urlsplit(config['SUPABASE_URL']).hostname
    project_ref = project.removesuffix('.supabase.co') if project else ''
    if (connection.scheme not in ('postgres', 'postgresql') or not connection.password
            or not connection.path.lstrip('/') or not project_ref or
            not (connection.hostname == 'db.' + project
                 or ((connection.hostname or '').endswith('.pooler.supabase.com')
                     and connection.username == 'postgres.' + project_ref))):
        raise RuntimeError('SUPABASE_DB_URL must be a complete PostgreSQL URI for the configured Supabase project')


def check_config(folder, config):
    """One real read and a public RPC check before starting the store matrix."""
    folder.mkdir(parents=True, exist_ok=True)
    try:
        validate_config(config)
        db = Database(folder)
        db.query(known_sql('compro-super-mx') + ' limit 1', 'preflight')
        public_smoke(config)
    except Exception:
        diagnostics = failure_diagnostics(folder)
        print('::error::Refresh preflight failed. Check database and public RPC configuration.')
        for diagnostic in diagnostics:
            print('::error::' + diagnostic)
        return 1
    print('Database connection, catalog schema and public RPC checks passed.')
    return 0


def refresh(source, folder, config, *, max_pages=100):
    folder.mkdir(parents=True, exist_ok=False)
    report = {'source': source, 'status': 'failed', 'started_at': datetime.now(timezone.utc).isoformat(),
              'known': 0, 'captured': 0, 'accepted': 0, 'held': 0, 'inserted': 0, 'errors': []}
    try:
        validate_config(config)
        db = Database(folder)
        known = db.query(known_sql(source), 'known-listings')
        report['known'] = len(known)
        if not known:
            raise RuntimeError('No previously published listings for this source')
        json_write(folder / 'known.json', known)
        product_ids = []
        if source in ('chedraui-mx', 'gran-bodega-mx'):
            product_ids = [row.get('source_product_id') for row in known]
            if any(not isinstance(value, str) or not value.isdecimal() for value in product_ids):
                raise RuntimeError('Missing reviewed VTEX product identifiers; catalog review required')
        capture = capture_source(source, folder / 'capture', max_pages=max_pages,
                                 product_limit=300, seeds=[r['store_product_url'] for r in known],
                                 known_only=True, product_ids=product_ids)
        raw = read_ndjson(folder / 'capture/observations.ndjson')
        report['captured'] = len(raw)
        rows, held = prepare_existing(raw, known)
        report.update(accepted=len(rows), held=len(held),
                      not_refreshed=max(0, len(known) - len(rows)),
                      capture_failure=capture.get('failure'),
                      catalog_complete=capture.get('full_catalog_traversed', False),
                      known_catalog_complete=capture.get('known_catalog_traversed', False))
        json_write(folder / 'held-private.json', held)
        if not rows:
            raise RuntimeError('No valid observations of existing products; nothing was published')
        input_path = folder / 'accepted.ndjson'
        input_path.write_text(''.join(json.dumps(r, ensure_ascii=False) + '\n' for r in rows))
        result = publish(input_path, folder / 'staging',
                         'scheduled:' + source + ':' + datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%S%f'))
        report['inserted'] = result['inserted_snapshots']
        report['verification'] = verify_database(db, rows)
        report['public_search_counts'] = public_smoke(config)
        if capture.get('failure') or (source in BULK and not report['catalog_complete']
                                      and not report['known_catalog_complete']):
            report['status'] = 'partial'
            report['errors'].append('Capture stopped early; only validated observations were published')
        else:
            report['status'] = 'ok'
    except Exception as error:
        # DB helpers redact connection strings. Do not copy raw scraper bodies,
        # database credentials, SQL or subprocess output into public artifacts.
        message = str(error)
        for value in (os.environ.get('SUPABASE_DB_URL'), config.get('SUPABASE_PUBLISHABLE_KEY')):
            if value:
                message = message.replace(value, '[REDACTED]')
        report['errors'].append(message)
        report['diagnostics'] = failure_diagnostics(folder)
    finally:
        report['finished_at'] = datetime.now(timezone.utc).isoformat()
        json_write(folder / 'report.json', report)
        print(json.dumps(report, ensure_ascii=False), flush=True)
    return report


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source', choices=tuple(SOURCES))
    parser.add_argument('--check-config', action='store_true')
    parser.add_argument('--work-dir', type=Path, required=True)
    parser.add_argument('--max-pages', type=int, default=100)
    args = parser.parse_args()
    if not 1 <= args.max_pages <= 100:
        parser.error('--max-pages must be between 1 and 100')
    config = {key: os.environ.get(key, '') for key in
              ('SUPABASE_URL', 'SUPABASE_PUBLISHABLE_KEY')}
    if args.check_config:
        return check_config(args.work_dir.resolve(), config)
    if not args.source:
        parser.error('--source is required unless --check-config is used')
    report = refresh(args.source, args.work_dir.resolve(), config, max_pages=args.max_pages)
    return 0 if report['status'] == 'ok' else 1


if __name__ == '__main__':
    raise SystemExit(main())
