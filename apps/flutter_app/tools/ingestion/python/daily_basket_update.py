#!/usr/bin/env python3
"""Capture, validate, and atomically publish the four reviewed basket pairs."""
import argparse
from datetime import datetime, timezone
import json
import os
from pathlib import Path
import subprocess
import sys

from prepare_reviewed_basket import review_manifest

SOURCES = ('chedraui-mx', 'merco-mx')


def run_logged(command, log_path, env=None):
    result = subprocess.run(command, text=True, stdout=subprocess.PIPE,
                            stderr=subprocess.STDOUT, env=env)
    log_path.write_text(result.stdout)
    return result.returncode


def publication_decision(source_codes, product_report):
    failed_sources = [source for source, code in source_codes.items() if code != 0]
    pending = [item for item in product_report if item['status'] == 'pending_review']
    return {
        'ready': not failed_sources and not pending and len(product_report) == 8,
        'failed_sources': failed_sources,
        'pending_review_count': len(pending),
    }


def read_ndjson(path):
    if not path.exists():
        return []
    return [json.loads(line) for line in path.read_text().splitlines() if line.strip()]


def read_json(path):
    if not path.exists():
        return None
    try:
        return json.loads(path.read_text())
    except (json.JSONDecodeError, OSError):
        return {'error': 'Report could not be read', 'path': str(path)}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--manifest', type=Path, required=True)
    parser.add_argument('--work-dir', type=Path, required=True)
    parser.add_argument('--publish', action='store_true')
    parser.add_argument('--delay-ms', type=int, default=5000)
    args = parser.parse_args()
    if args.work_dir.exists():
        parser.error('--work-dir must not exist')
    if args.delay_ms < 5000:
        parser.error('--delay-ms must be at least 5000')
    args.work_dir.mkdir(parents=True)
    manifest = json.loads(args.manifest.read_text())
    started = datetime.now(timezone.utc).isoformat()

    urls = {source: [listing['url'] for item in manifest['items']
                     for listing in item['listings'] if listing['source'] == source]
            for source in SOURCES}
    for source in SOURCES:
        (args.work_dir / f'{source}-urls.json').write_text(json.dumps(urls[source], indent=2) + '\n')

    chedraui_out = args.work_dir / 'chedraui.ndjson'
    merco_out = args.work_dir / 'merco.ndjson'
    source_codes = {}
    source_codes['chedraui-mx'] = run_logged([
        'dart', 'run', 'tools/ingestion/bin/chedraui_sitemap_scraper.dart',
        '--urls', str(args.work_dir / 'chedraui-mx-urls.json'), '--limit', '4',
        '--delay-ms', str(args.delay_ms), '--out', str(chedraui_out),
        '--evidence-dir', str(args.work_dir / 'chedraui-evidence')],
        args.work_dir / 'chedraui-mx.log')
    source_codes['merco-mx'] = run_logged([
        sys.executable, 'tools/ingestion/python/merco_online_scraper.py',
        '--urls', str(args.work_dir / 'merco-mx-urls.json'), '--limit', '4',
        '--delay-ms', str(args.delay_ms), '--out', str(merco_out)],
        args.work_dir / 'merco-mx.log')

    source_reports = {
        'chedraui-mx': {
            'exit_code': source_codes['chedraui-mx'],
            'details': read_json(args.work_dir / 'chedraui-evidence' / 'report.json'),
            'log': 'chedraui-mx.log',
        },
        'merco-mx': {
            'exit_code': source_codes['merco-mx'],
            'details': read_json(Path(str(merco_out) + '.evidence') / 'report.json'),
            'log': 'merco-mx.log',
        },
    }

    rows = read_ndjson(chedraui_out) + read_ndjson(merco_out)
    product_report = review_manifest(manifest, rows)
    decision = publication_decision(source_codes, product_report)
    report = {
        'started_at': started, 'finished_at': datetime.now(timezone.utc).isoformat(),
        'status': 'ready' if decision['ready'] else 'pending_review',
        'published': False, 'source_exit_codes': source_codes,
        'sources': source_reports,
        'failed_sources': decision['failed_sources'],
        'products': product_report,
    }
    report_path = args.work_dir / 'daily-report.json'

    if not decision['ready']:
        report_path.write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n')
        print(json.dumps(report, ensure_ascii=False, indent=2))
        return 2

    prepared = args.work_dir / 'prepared'
    prepare_code = run_logged([
        sys.executable, 'tools/ingestion/python/prepare_reviewed_basket.py',
        '--manifest', str(args.manifest), '--inputs', str(chedraui_out), str(merco_out),
        '--out-dir', str(prepared), '--review-report', str(args.work_dir / 'review-report.json')],
        args.work_dir / 'prepare.log')
    if prepare_code != 0:
        report['status'] = 'pending_review'
        report['preparation_error'] = 'See prepare.log'
        report_path.write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n')
        return 2

    if args.publish:
        database_url = os.environ.get('SUPABASE_DB_URL', '').strip()
        if not database_url:
            report['status'] = 'failed'
            report['publication_error'] = 'SUPABASE_DB_URL is missing'
            report_path.write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n')
            return 3
        publish_code = run_logged([
            'psql', database_url, '--set', 'ON_ERROR_STOP=1',
            '--file', str(prepared / 'publish.sql')], args.work_dir / 'publish.log')
        if publish_code != 0:
            report['status'] = 'failed'
            report['publication_error'] = 'Atomic SQL publication failed; see publish.log'
            report_path.write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n')
            return 3
        report['published'] = True
        report['status'] = 'published'
    report['finished_at'] = datetime.now(timezone.utc).isoformat()
    report_path.write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n')
    print(json.dumps({'status': report['status'], 'products': 4,
                      'observations': 8, 'report': str(report_path)}))
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
