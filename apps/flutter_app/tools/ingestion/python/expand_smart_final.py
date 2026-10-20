#!/usr/bin/env python3
"""Discover bounded official category pages and capture online offers, without publishing."""
import argparse
from datetime import datetime, timezone
import json
from pathlib import Path
import re
from urllib.parse import urljoin, urlsplit

from online_catalog import Page, objects, parse_product, publish_sql, validate
from retail.transport import SafeHttpClient

ORIGIN = 'https://www.smartnfinal.com.mx'
CATEGORIES = ('abarrotes', 'desayuno-y-reposteria', 'salchichoneria-y-lacteos')


def product_links(html):
    """Ignore external, query, fragment and non-product links; preserve source order."""
    urls = {}
    for href in Page(html).links:
        url = urljoin(ORIGIN + '/', href)
        parsed = urlsplit(url)
        if (parsed.scheme == 'https' and parsed.netloc == 'www.smartnfinal.com.mx'
                and not parsed.query and not parsed.fragment
                and re.fullmatch(r'/tienda/[a-z0-9-]+/[a-z0-9-]+/', parsed.path)):
            urls.setdefault(url, None)
    return list(urls)


def observation(response):
    row = parse_product(response.text, response.url, 'smart-final',
                        response.observed_at, response.sha256)
    products = [p for p in objects(Page(response.text).json_ld) if p.get('@type') == 'Product']
    product = products[0]  # parse_product has already enforced exactly one Product.
    offer = [o for o in objects(product.get('offers')) if o.get('@type') == 'Offer'][0]
    if isinstance(offer.get('price'), bool):
        raise ValueError('Boolean price is not evidence')
    for declared in (product.get('url'), offer.get('url')):
        if declared and declared != response.url:
            raise ValueError('Offer/product evidence points to a different URL')
    row['raw_payload'] = {'json_ld_product': product, 'response_sha256': response.sha256,
                          'capture_context': 'Public online catalog; no selected physical branch'}
    validate(row)
    return row


def capture(folder, categories, limit, client=None):
    folder.mkdir(parents=True, exist_ok=False)
    client = client or SafeHttpClient(['www.smartnfinal.com.mx'], max_requests=limit + len(categories) + 1,
                                    max_bytes=8 * 1024 * 1024)
    rows, candidates, rejected, failure = [], {}, [], None
    report = {'started_at': datetime.now(timezone.utc).isoformat(), 'categories': list(categories)}

    def get(url):
        response = client.get(url)
        stem = f'page-{len(list(folder.glob("page-*.html"))) + 1:03}'
        (folder / (stem + '.html')).write_text(response.text, encoding='utf-8')
        (folder / (stem + '.json')).write_text(json.dumps({
            'url': response.url, 'observed_at': response.observed_at,
            'sha256': response.sha256, 'status': response.status,
            'content_type': response.content_type}, ensure_ascii=False, indent=2) + '\n')
        return response

    try:
        # Each category contributes a bounded portion, rather than filling the
        # entire run from the first category. No pagination or recursive crawl.
        for index, category in enumerate(categories):
            response = get(ORIGIN + '/categoria-producto/' + category + '/')
            quota = limit // len(categories) + (index < limit % len(categories))
            links = [url for url in product_links(response.text) if url not in candidates]
            candidates.update(dict.fromkeys(links[:quota], response.url))
        for url in candidates:
            response = get(url)
            try:
                row = observation(response)
                row['discovery_url'] = candidates[url]
                rows.append(row)
                print(json.dumps({'name': row['product_name'], 'price': row['price']}, ensure_ascii=False), flush=True)
            except (ValueError, KeyError, TypeError) as error:
                rejected.append({'url': url, 'reason': str(error)})
    except (RuntimeError, ValueError, KeyError, TypeError) as error:
        failure = str(error)
    finally:
        (folder / 'candidates.json').write_text(json.dumps(candidates, ensure_ascii=False, indent=2) + '\n')
        (folder / 'observations.ndjson').write_text(''.join(json.dumps(r, ensure_ascii=False) + '\n' for r in rows))
        if rows:
            (folder / 'publish.sql').write_text(publish_sql(rows))
        report.update(accepted=len(rows), rejected=rejected, failure=failure,
                      receipts=client.receipts, metrics=dict(client.metrics), published=False,
                      status='partial' if failure or rejected or not rows else 'ok')
        (folder / 'report.json').write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n')
    return report


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--out-dir', type=Path, required=True)
    parser.add_argument('--limit', type=int, default=18)
    parser.add_argument('--categories', default=','.join(CATEGORIES))
    args = parser.parse_args()
    categories = tuple(dict.fromkeys(args.categories.split(',')))
    if not categories or any(c not in CATEGORIES for c in categories):
        parser.error('Use only the supported supermarket categories: ' + ','.join(CATEGORIES))
    if not len(categories) <= args.limit <= 30:
        parser.error('--limit must be between the category count and 30')
    report = capture(args.out_dir, categories, args.limit)
    print(json.dumps({k: report[k] for k in ('accepted', 'rejected', 'failure', 'status')}, ensure_ascii=False))
    return 0 if report['status'] == 'ok' else 1


if __name__ == '__main__':
    raise SystemExit(main())
