#!/usr/bin/env python3
"""Review every researched chain, keeping identities, blocks and samples distinct."""
import argparse
from concurrent.futures import ThreadPoolExecutor, as_completed
from datetime import datetime, timezone
import json
from pathlib import Path
from urllib.parse import urlsplit

from online_catalog import Page, objects
from refresh_grocery_catalogs import json_write
from retail.transport import SafeHttpClient

REGISTRY = Path(__file__).resolve().parents[1] / 'catalogs/grocery_retailers.json'


def probe(retailer, root, captures):
    name = retailer['chain']
    result = {'chain': name, 'formats': retailer['formats'], 'sources': retailer['sources'],
              'official_url': retailer['official_url'], 'identity_source': retailer['identity_source'],
              'prior_review_date': retailer['prior_review_date'], 'prior_detail': retailer['prior_detail']}
    captured = [captures[s] for s in retailer['sources'] if s in captures]
    if captured:
        result.update(status='captured' if any(c['accepted'] for c in captured) else 'capture_failed',
                      reviewed_at=max(c['finished_at'] for c in captured),
                      read=sum(c['catalog_items_read'] for c in captured),
                      accepted=sum(c['accepted'] for c in captured), images=sum(c['images'] for c in captured),
                      available=sum(c['available'] for c in captured), unavailable=sum(c['unavailable'] for c in captured),
                      full_catalog_traversed=all(c['full_catalog_traversed'] for c in captured),
                      failures=[c['failure'] for c in captured if c['failure']])
        return result
    if retailer['adapter_status'] == 'paused_after_429':
        result.update(status='paused_after_429', reviewed_at=None, read=0, accepted=0,
                      note='Historical adapter remains paused; no automatic recrawl or new stock claim')
        return result
    url = retailer['official_url']
    if not url or name in ('Dunosusa', 'Sumesa'):
        result.update(status='identity_pending' if not url else 'identity_only', reviewed_at=None,
                      read=0, accepted=0, note='No verified standalone commerce source')
        return result
    host = urlsplit(url).hostname
    directory = root / host
    directory.mkdir(parents=True, exist_ok=True)
    client = SafeHttpClient([host], max_requests=2, timeout=15, max_bytes=8*1024*1024)
    try:
        response = client.get(url)
        (directory/'home.html').write_text(response.text)
        metadata = dict(response.__dict__); metadata.pop('text')
        json_write(directory/'home.json', metadata)
        products = []
        try:
            products = [p for p in objects(Page(response.text).json_ld) if p.get('@type') == 'Product']
        except ValueError:
            result['structured_data_issue'] = 'Malformed JSON-LD; no offer accepted'
        result.update(status='public_site_stock_unvalidated', reviewed_at=response.observed_at,
                      read=len(products), accepted=0, note='Accessible site is not proof of stock')
    except (RuntimeError, OSError, ValueError) as error:
        result.update(status='access_pending', reviewed_at=datetime.now(timezone.utc).isoformat(),
                      read=0, accepted=0, failure=str(error))
    result['receipts'] = client.receipts
    json_write(directory/'report.json', result)
    return result


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--out-dir', type=Path, required=True)
    p.add_argument('--capture-dir', action='append', type=Path, default=[])
    args = p.parse_args()
    args.out_dir.mkdir(parents=True, exist_ok=False)
    captures = {}
    for root in args.capture_dir:
        for path in root.glob('*/report.json'):
            report = json.loads(path.read_text())
            if 'source' in report: captures[report['source']] = report
    retailers = json.loads(REGISTRY.read_text())['retailers']
    results = []
    with ThreadPoolExecutor(max_workers=4) as pool:
        jobs = [pool.submit(probe, retailer, args.out_dir, captures) for retailer in retailers]
        for job in as_completed(jobs):
            result = job.result(); results.append(result)
            print(json.dumps({k:result.get(k) for k in ('chain','status','read','accepted','failure')},ensure_ascii=False),flush=True)
    results.sort(key=lambda r:r['chain'])
    json_write(args.out_dir/'coverage.json', {'review_finished_at':datetime.now(timezone.utc).isoformat(),
                                            'retailers':results,'published':False})


if __name__ == '__main__': main()
