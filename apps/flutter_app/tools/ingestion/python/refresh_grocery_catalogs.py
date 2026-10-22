#!/usr/bin/env python3
"""Fresh, bounded public grocery capture with pagination and isolated failures.

No publication, authentication, cart, reservation, or challenge bypass. Every
source retains original HTTP timestamps and hashes; replay never refreshes them.
COMPRO evidence is a documented product-only projection of the original reply.
"""
import argparse
from collections import Counter
from concurrent.futures import ThreadPoolExecutor, as_completed
from datetime import datetime, timezone
from decimal import Decimal
import hashlib
from html import unescape
import json
from pathlib import Path
import re
from urllib.parse import urlsplit

from expand_grocery_sources import (SOURCES, catalog_projection, money,
    observed_presentation, parse_compro, parse_page, parse_garis, parse_vtex,
    product_links, row, source_home)
from online_catalog import Page
from retail.transport import SafeHttpClient, HttpResponse, FetchError

BULK = {'compro-super-mx': 'compro', 'smart-final-public-web': 'woo',
        'fenix-mx': 'woo', 'carnemart-mx': 'woo', 'garis-mx': 'shopify',
        'mas-bodega-mx': 'shopify', 'chedraui-mx': 'vtex', 'gran-bodega-mx': 'vtex',
        'superissste-mx': 'woo', 'merkabastos-mx': 'woo'}


def json_write(path, data):
    path.write_text(json.dumps(data, ensure_ascii=False, indent=2, allow_nan=False) + '\n')


def plain(html):
    return unescape(' '.join(Page(html or '').text)).strip()


def first_image(images, *, product_id=None, variant_id=None):
    for image in images or []:
        if not isinstance(image, dict):
            continue
        if product_id is not None and image.get('product_id') != product_id:
            continue
        variants = image.get('variant_ids') or []
        if variant_id is not None and variants and variant_id not in variants:
            continue
        url = image.get('src')
        if (isinstance(url, str) and urlsplit(url).scheme == 'https'
                and not re.search(r'placeholder|woocommerce-placeholder', url, re.I)):
            return url
    return None


def parse_woo_product(product, response, source):
    prices = product.get('prices') or {}
    if (prices.get('currency_code') != 'MXN' or type(prices.get('currency_minor_unit')) is not int
            or prices['currency_minor_unit'] != 2):
        raise ValueError('Explicit MXN and two minor units required')
    if (product.get('type') != 'simple' or product.get('has_options') is not False
            or product.get('variation') or product.get('variations') or prices.get('price_range')):
        raise ValueError('Variable or grouped sales unit requires review')
    if product.get('is_password_protected') is not False:
        raise ValueError('Protected product excluded')
    if type(product.get('is_in_stock')) is not bool or product.get('is_on_backorder') is not False:
        raise ValueError('Explicit stock required; backorders excluded')
    if product.get('on_sale') is not False or prices.get('price') != prices.get('regular_price'):
        raise ValueError('Promotion requires independently verified validity')
    raw_price = prices.get('price')
    if not isinstance(raw_price, str) or not re.fullmatch(r'\d+', raw_price):
        raise ValueError('Invalid minor-unit price')
    name = unescape(product.get('name') or '').strip()
    short = plain(product.get('short_description'))
    category_names = [c['name'] for c in product.get('categories') or [] if isinstance(c.get('name'), str)]
    categories = ' / '.join(category_names)
    # Wholesale meat storefronts can label a case while pricing by kilogram.
    # A container mentioned in copy is never used to infer its sales price.
    if source == 'carnemart-mx':
        if re.search(r'\bcaja\b|\b(?:kg|kilos?|kilogramos?)\b', name, re.I):
            raise ValueError('CarneMart case/weight price unit requires corroboration')
        pack = observed_presentation(name)
    else:
        if re.search(r'frutas|verduras|carnes|pescados|mariscos', categories, re.I):
            raise ValueError('Fresh weighted sales unit requires review')
        # Smart & Final renders the net quantity in its product summary. Other
        # stores must declare it in the title, never arbitrary descriptive copy.
        pack = observed_presentation(name, short if source == 'smart-final-public-web' else '')
    evidence = {'store_api_product': product, 'sales_presentation': pack,
                'stock_note': 'Explicit ecommerce is_in_stock; not physical inventory or reservation'}
    result = row(source, response, name=name, amount=Decimal(raw_price) / 100,
                 available=product['is_in_stock'], product_url=product.get('permalink'),
                 sku=product.get('sku') or product.get('id'),
                 description=short if source == 'smart-final-public-web' else '',
                 category=categories or 'Otros', image=first_image(product.get('images')),
                 evidence=evidence, evidence_kind='store_api')
    return result


def parse_shopify_product(product, response, currency, source):
    """Public products.json uses decimal prices, unlike product Ajax cents."""
    if currency != 'MXN':
        raise ValueError('Explicit storefront MXN required')
    if not isinstance(product.get('handle'), str) or not re.fullmatch(r'[a-z0-9-]+', product['handle']):
        raise ValueError('Invalid product handle')
    variants = product.get('variants') or []
    piece_label = r'pieza 1(?: a \d+)?' if source == 'garis-mx' else r'PZA/1'
    pieces = [v for v in variants if re.fullmatch(piece_label, v.get('title', ''), re.I)]
    if len(pieces) != 1:
        raise ValueError('Missing or ambiguous single-piece sales unit')
    variant = pieces[0]
    if type(variant.get('available')) is not bool or variant.get('product_id') != product.get('id'):
        raise ValueError('Variant identity or explicit availability missing')
    price = money(variant.get('price'))
    compare = variant.get('compare_at_price')
    if compare not in (None, '', '0.00', '0', 0) and money(compare) != price:
        raise ValueError('Discount requires independently verified validity')
    observed_presentation(product.get('title') or '')
    host = SOURCES[source][0]
    url = f'https://{host}/products/{product["handle"]}?variant={variant["id"]}'
    image = first_image(product.get('images'), product_id=product['id'], variant_id=variant['id'])
    return row(source, response, name=product['title'] + ' · ' + variant['title'],
               amount=price, available=variant['available'], product_url=url,
               sku=variant.get('sku') or variant.get('id'), category=product.get('product_type') or 'Otros',
               image=image, gtin=variant.get('sku'), evidence_kind='store_api',
               evidence={'catalog_product': product, 'currency': currency,
                         'selected_variant_id': variant['id'], 'sales_unit': 'one piece',
                         'price_unit_note': 'Decimal MXN piece price, case/bulk tiers excluded'})


def currency_from_home(html, adapter):
    pattern = (r'Shopify\.currency\s*=\s*\{[^}]*["\']active["\']\s*:\s*["\']MXN["\']'
               if adapter == 'shopify' else
               r'(?:ISOCurrencySymbol|CurrencyCode|currency)["\']?\s*:\s*["\']MXN["\']|<meta[^>]*name=["\']currency["\'][^>]*content=["\']MXN["\']')
    return 'MXN' if re.search(pattern, html, re.I) else None


def capture_source(source, folder, *, max_pages=60, page_size=None, product_limit=80, seeds=(), known_only=False, product_ids=()):
    folder.mkdir(parents=True, exist_ok=False)
    host = SOURCES[source][0]
    adapter = BULK.get(source, 'html')
    client = SafeHttpClient([host], max_requests=min(500, max_pages + product_limit + 6),
                            max_bytes=8 * 1024 * 1024, accepted_statuses=(200, 206))
    rows, rejected, seen, failure, complete, responses = [], [], set(), None, False, 0
    remaining_urls = set(seeds) if known_only else set()
    requested_urls = len(remaining_urls)
    targeted_complete = False
    report = {'source': source, 'adapter': adapter, 'started_at': datetime.now(timezone.utc).isoformat(),
              'limits': {'max_pages': max_pages, 'product_limit': product_limit}, 'published': False}

    def fetch(url):
        nonlocal responses
        response = client.get(url)
        responses += 1
        body, metadata = response.text, dict(response.__dict__)
        if source == 'compro-super-mx' and url.endswith('/productos-precios.json'):
            body = json.dumps(catalog_projection(body), ensure_ascii=False)
            metadata.update(redacted_projection=True, stored_projection_sha256=hashlib.sha256(body.encode()).hexdigest())
        metadata.pop('text')
        (folder / f'response-{responses:03}.txt').write_text(body)
        json_write(folder / f'response-{responses:03}.json', metadata)
        return response

    try:
        if adapter == 'compro':
            response = fetch(f'https://{host}/productos-precios.json')
            rows, rejected = parse_compro(response, 10000)
            seen.update(p['id'] for p in catalog_projection(response.text)['products'])
            complete = True
        elif adapter in ('woo', 'shopify', 'vtex'):
            currency = None
            if adapter != 'woo':
                currency = currency_from_home(fetch(source_home(source)).text, adapter)
                if currency != 'MXN':
                    raise ValueError('Official homepage did not declare MXN')
            size = page_size or (250 if adapter == 'shopify' else 50 if adapter == 'vtex' else 100)
            targeted = adapter == 'vtex' and known_only and bool(product_ids)
            batches = []
            if targeted:
                if size > 50 or any(not isinstance(value, str) or not re.fullmatch(r'[0-9]{1,20}', value)
                                    for value in product_ids):
                    raise ValueError('Invalid bounded VTEX product identifiers')
                unique_ids = list(dict.fromkeys(product_ids))
                batches = [unique_ids[i:i+size] for i in range(0, len(unique_ids), size)]
            for page in range(1, max_pages + 1):
                if adapter == 'woo':
                    url = f'https://{host}/wp-json/wc/store/v1/products?per_page={size}&page={page}&orderby=id&order=asc'
                elif adapter == 'shopify':
                    url = f'https://{host}/products.json?limit={size}&page={page}'
                else:
                    if targeted:
                        filters = '&'.join('fq=productId:' + value for value in batches[page-1])
                        url = f'https://{host}/api/catalog_system/pub/products/search?{filters}&_from=0&_to={size-1}'
                    else:
                        offset = (page-1)*size
                        url = f'https://{host}/api/catalog_system/pub/products/search?_from={offset}&_to={offset+size-1}&O=OrderByNameASC'
                response = fetch(url)
                data = json.loads(response.text)
                products = data.get('products') if adapter == 'shopify' and isinstance(data, dict) else data
                if not isinstance(products, list) or len(products) > size:
                    raise ValueError('Unexpected or unbounded catalog page')
                ids = [str(p.get('productId') if adapter == 'vtex' else p.get('id')) for p in products]
                if any(i in seen or i in ('None', '') for i in ids) or len(ids) != len(set(ids)):
                    raise ValueError('Repeated page or ambiguous product identity; pagination stopped')
                if targeted and not set(ids).issubset(batches[page-1]):
                    raise ValueError('VTEX response contains products outside the requested identifiers')
                seen.update(ids)
                if known_only:
                    for product in products:
                        if adapter == 'woo':
                            remaining_urls.discard(product.get('permalink'))
                        elif adapter == 'shopify':
                            for variant in product.get('variants') or []:
                                remaining_urls.discard(
                                    f'https://{host}/products/{product.get("handle")}?variant={variant.get("id")}')
                        else:
                            remaining_urls.discard(product.get('link'))
                if adapter == 'vtex':
                    accepted, issues = parse_vtex(response, currency, size, source=source)
                    rows.extend(accepted); rejected.extend(issues)
                else:
                    for product in products:
                        try:
                            result = (parse_woo_product(product, response, source) if adapter == 'woo'
                                      else parse_shopify_product(product, response, currency, source))
                            rows.append(result)
                        except (ValueError, KeyError, TypeError, IndexError) as error:
                            rejected.append({'product_id': product.get('id'), 'reason': str(error)})
                print(json.dumps({'source': source, 'page': page, 'read': len(seen), 'accepted': len(rows),
                                  'images': sum(bool(r['image_url']) for r in rows)}, ensure_ascii=False), flush=True)
                if targeted:
                    rejected.extend({'product_id': value, 'reason': 'Known product absent from current public catalog'}
                                    for value in set(batches[page-1]) - set(ids))
                    if page == len(batches):
                        targeted_complete = True
                        break
                    continue
                if len(products) < size:
                    complete = True
                    break
                if requested_urls and not remaining_urls:
                    break  # Every reviewed URL was seen; no discovery is needed.
        else:
            discovered = []
            if not known_only:
                home = fetch(source_home(source))
                discovered = product_links(home.text, source)
            # Previously validated links are fresh HTTP requests, never replays.
            candidates = list(dict.fromkeys(list(seeds) + discovered))[:product_limit]
            json_write(folder / 'candidates.json', candidates)
            for url in candidates:
                seen.add(url)
                try:
                    response = fetch(url)
                    if response.status != 200:
                        raise ValueError('Incomplete product page')
                    rows.append(parse_page(response, source))
                except (ValueError, KeyError, TypeError) as error:
                    rejected.append({'url': url, 'reason': str(error)})
                except FetchError as error:
                    if error.status == 404:
                        rejected.append({'url': url, 'reason': 'Product page removed (HTTP 404)'} )
                    else:
                        raise
            complete = False  # Homepage/seed sampling never proves full coverage.
    except (RuntimeError, ValueError, KeyError, TypeError, OSError) as error:
        failure = str(error)
    report.update(finished_at=datetime.now(timezone.utc).isoformat(), catalog_items_read=len(seen),
                  accepted=len(rows), images=sum(bool(r['image_url']) for r in rows),
                  available=sum(r['available'] for r in rows), unavailable=sum(not r['available'] for r in rows),
                  full_catalog_traversed=complete, failure=failure, rejected=rejected,
                  known_catalog_traversed=targeted_complete or (bool(requested_urls) and not remaining_urls),
                  known_urls_not_seen=len(remaining_urls),
                  rejection_counts=dict(Counter(r['reason'] for r in rejected)),
                  receipts=client.receipts, metrics=dict(client.metrics),
                  status='partial' if failure or rejected or not complete else 'ok')
    (folder / 'observations.ndjson').write_text(''.join(json.dumps(r, ensure_ascii=False, allow_nan=False)+'\n' for r in rows))
    json_write(folder / 'report.json', report)
    return report


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--out-dir', type=Path, required=True)
    parser.add_argument('--sources', default=','.join(SOURCES))
    parser.add_argument('--max-pages', type=int, default=60)
    parser.add_argument('--product-limit', type=int, default=80)
    parser.add_argument('--workers', type=int, default=3)
    parser.add_argument('--seed-file', type=Path, help='Verified source -> product URL list')
    args = parser.parse_args()
    sources = list(dict.fromkeys(args.sources.split(',')))
    if (any(s not in SOURCES for s in sources) or not 1 <= args.max_pages <= 100
            or not 1 <= args.workers <= 4 or not 1 <= args.product_limit <= 300):
        parser.error('Registered sources; 1..100 pages; 1..300 products; 1..4 workers')
    seeds = json.loads(args.seed_file.read_text()) if args.seed_file else {}
    args.out_dir.mkdir(parents=True, exist_ok=False)
    reports = {}
    with ThreadPoolExecutor(max_workers=args.workers) as pool:
        jobs = {pool.submit(capture_source, s, args.out_dir/s, max_pages=args.max_pages,
                            product_limit=args.product_limit, seeds=seeds.get(s, ())):s for s in sources}
        for job in as_completed(jobs):
            report = job.result(); reports[report['source']] = report
            print(json.dumps({k:report[k] for k in ('source','accepted','images','catalog_items_read',
                              'full_catalog_traversed','failure')}, ensure_ascii=False), flush=True)
    json_write(args.out_dir/'report.json', {'sources': reports, 'published': False})
    return 1 if any(r['failure'] for r in reports.values()) else 0


if __name__ == '__main__':
    raise SystemExit(main())
