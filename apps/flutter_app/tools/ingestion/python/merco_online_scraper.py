#!/usr/bin/env python3
"""Capture a bounded sample of Merco Monterrey's public online product pages.

Produces stage_ndjson.dart input and immutable HTTP evidence; never publishes.
No account, branch selection, cart, automatic retries or access challenges.
"""
import argparse
from datetime import datetime, timezone
import hashlib
from html import unescape
import json
import math
from pathlib import Path
import re
import time
import unicodedata
from urllib.error import HTTPError
from urllib.parse import urlparse
from urllib.request import HTTPRedirectHandler, Request, build_opener
from urllib.robotparser import RobotFileParser

from online_catalog import Page, objects, presentation, timestamp

ORIGIN = 'https://adomicilio.merco.mx'
SOURCE = 'merco-mx'
UA = 'TiagoMarketBot/0.1 (+https://github.com/gabyboan/tiago-market)'
DEFAULT_URLS = [ORIGIN + '/p/' + slug for slug in [
    'leche-fresca-lala-entera-1-lto-10248783',
    'leche-lala-chocolala-tetrapack-500-ml-10244586',
    'leche-lala-100-sin-lactosa-reducida-en-grasa-1-l-10244557',
    'arroz-mimarca-extra-906-gr-10263357',
    'aceite-vegetal-comestible-ave-cocina-850-ml-10250882',
    'pasta-barilla-para-sopa-de-fideo-n-0-200-g-10246078',
]]


def product_url(url):
    parsed = urlparse(url)
    return (parsed.scheme == 'https' and parsed.netloc == 'adomicilio.merco.mx'
            and not parsed.query and not parsed.fragment
            and re.fullmatch(r'/p/[a-z0-9-]+-\d+', parsed.path) is not None)


def parse_product(html, url, observed_at, response_sha256):
    if not product_url(url):
        raise ValueError('Unexpected product URL')
    if not re.fullmatch(r'[a-f0-9]{64}', response_sha256):
        raise ValueError('Missing response SHA256')
    timestamp(observed_at)
    page = Page(html)
    products = [p for p in objects(page.json_ld) if p.get('@type') == 'Product']
    if len(products) != 1:
        raise ValueError('Expected exactly one JSON-LD Product')
    product = products[0]
    sku = str(product.get('sku') or '')
    if product.get('url') != url or sku != url.rsplit('-', 1)[-1]:
        raise ValueError('Product URL/SKU mismatch')
    offers = [o for o in objects(product.get('offers')) if o.get('@type') == 'Offer']
    if len(offers) != 1:
        raise ValueError('Ambiguous or missing offer')
    offer = offers[0]
    if isinstance(offer.get('price'), bool):
        raise ValueError('Invalid price')
    price = float(offer['price'])
    if not math.isfinite(price) or not 0 < price < 1000000 or offer.get('priceCurrency') != 'MXN':
        raise ValueError('Invalid MXN price')
    availability = offer.get('availability')
    if availability not in ('InStock', 'https://schema.org/InStock', 'http://schema.org/InStock'):
        raise ValueError('Availability not confirmed')
    valid_until = offer.get('priceValidUntil')
    if valid_until:
        expiry = valid_until
        if re.fullmatch(r'\d{4}-\d{2}-\d{2}', expiry):
            expiry += 'T23:59:59-06:00'
        if timestamp(expiry) <= timestamp(observed_at):
            raise ValueError('Expired offer')
    name = unescape(str(product.get('name') or '')).strip()
    if not name:
        raise ValueError('Missing name')
    # Merco spells units as Lto., Lt, Gr and Grs. Preserve the pack text.
    unit_name = re.sub(r'\b(lto?s?|litros?)\b\.?', 'l', name, flags=re.I)
    unit_name = re.sub(r'\b(grs?|gramos?)\b\.?', 'g', unit_name, flags=re.I)
    pack = presentation(unit_name, '')
    if re.search(r'\b(?:pack|paquete|c/|\d+\s*(?:x|pzas?))', unit_name, re.I) and not re.search(r'\d+\s*(?:x|de)\s*\d+', pack, re.I):
        raise ValueError('Ambiguous multipack presentation')
    crumbs = [c for c in objects(page.json_ld) if c.get('@type') == 'BreadcrumbList']
    categories = [i.get('name') for c in crumbs for i in c.get('itemListElement', [])
                  if isinstance(i.get('item'), str) and i['item'].startswith(ORIGIN + '/c/')]
    if not categories or not isinstance(categories[-1], str):
        raise ValueError('Missing official category')
    image = product.get('image')
    if not (isinstance(image, str) and image.startswith('https://res.cloudinary.com/riqra/image/upload/')
            and '/merco-monterrey/products/' in image):
        image = None
    normalized = ''.join(c for c in unicodedata.normalize('NFD', name.lower())
                         if unicodedata.category(c) != 'Mn')
    row = {
        'source': SOURCE, 'store_brand': 'Merco Monterrey',
        'store_slug': 'merco-monterrey-online', 'price_scope': 'online',
        'source_product_name': name, 'normalized_name': normalized,
        'category': categories[-1], 'presentation': pack,
        'price': price, 'currency': 'MXN', 'available': True,
        'captured_at': observed_at, 'observed_at': observed_at,
        'source_url': url, 'store_product_url': url, 'external_reference': sku,
        'image_url': image, 'evidence_kind': 'product_page', 'confidence_score': 0.90,
        'is_synthetic': False, 'review_status': 'accepted', 'validation_errors': [],
        'branch_external_key': None, 'branch_name': None, 'branch_address': None,
        'branch_municipality': None, 'branch_state': None, 'latitude': None, 'longitude': None,
        'raw_payload': {'json_ld_product': product, 'response_sha256': response_sha256,
                        'capture_context': 'Public Merco Monterrey online catalog; no selected branch'},
    }
    # A replay is idempotent; a new observation refreshes unchanged prices.
    identity = [SOURCE, url, price, True, observed_at]
    row['content_hash'] = hashlib.sha256(json.dumps(identity).encode()).hexdigest()
    return row


class NoRedirect(HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None


class Capture:
    def __init__(self, folder, delay):
        self.folder, self.delay = folder, max(5, delay)
        self.last, self.count = 0, 0
        self.opener = build_opener(NoRedirect())

    def get(self, url):
        time.sleep(max(0, self.last + self.delay - time.monotonic()))
        self.last = time.monotonic()
        try:
            response = self.opener.open(Request(url, headers={'User-Agent': UA}), timeout=25)
        except HTTPError as error:
            response = error
        with response:
            body = response.read(4 * 1024 * 1024 + 1)
            status = response.status
            content_type = response.headers.get('Content-Type', '')
        self.count += 1
        receipt = {'url': url, 'status': status, 'content_type': content_type,
                   'observed_at': datetime.now(timezone.utc).isoformat(),
                   'sha256': hashlib.sha256(body).hexdigest(), 'bytes': len(body)}
        prefix = self.folder / f'request-{self.count:03}'
        prefix.with_suffix('.json').write_text(json.dumps(receipt, indent=2))
        prefix.with_suffix('.body').write_bytes(body)
        if status != 200 or len(body) > 4 * 1024 * 1024:
            raise RuntimeError(f'Stopped: HTTP {status} or oversized response at {url}')
        if any(c in body.lower() for c in [b'cf-chl-', b'px-captcha', b'captcha challenge']):
            raise RuntimeError('Stopped at access challenge')
        return body.decode('utf-8'), receipt


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--urls', type=Path, help='JSON array of official product URLs; defaults to six reviewed URLs')
    parser.add_argument('--out', type=Path, required=True)
    parser.add_argument('--limit', type=int, default=6)
    parser.add_argument('--delay-ms', type=int, default=5000)
    args = parser.parse_args()
    if not 1 <= args.limit <= 20 or args.delay_ms < 0:
        parser.error('limit must be 1..20; delay must be nonnegative')
    urls = json.loads(args.urls.read_text()) if args.urls else DEFAULT_URLS
    if not isinstance(urls, list) or not urls or any(not isinstance(u, str) or not product_url(u) for u in urls):
        parser.error('Expected a nonempty JSON array of official Merco product URLs')
    urls = list(dict.fromkeys(urls))[:args.limit]
    folder = Path(str(args.out) + '.evidence')
    if args.out.exists() or folder.exists():
        parser.error('Output or evidence already exists; use a new path')
    folder.mkdir(parents=True)
    capture = Capture(folder, args.delay_ms / 1000)
    rows, rejected, failure = [], [], None
    try:
        robots, _ = capture.get(ORIGIN + '/robots.txt')
        if '<html' in robots.lower() or 'user-agent:' not in robots.lower():
            raise RuntimeError('Invalid robots.txt response')
        rules = RobotFileParser(ORIGIN + '/robots.txt')
        rules.parse(robots.splitlines())
        capture.delay = max(capture.delay, rules.crawl_delay(UA) or 0)
        for url in urls:
            if not rules.can_fetch(UA, url):
                raise RuntimeError('robots.txt disallows ' + url)
            html, receipt = capture.get(url)
            try:
                if 'text/html' not in receipt['content_type']:
                    raise ValueError('Expected HTML product page')
                row = parse_product(html, url, receipt['observed_at'], receipt['sha256'])
                rows.append(row)
                print(f"{row['external_reference']}: {row['source_product_name']} — {row['price']:.2f} MXN", flush=True)
            except (ValueError, KeyError, TypeError) as error:
                rejected.append({'url': url, 'reason': str(error)})
    except Exception as error:
        failure = str(error)
    finally:
        args.out.write_text(''.join(json.dumps(r, ensure_ascii=False) + '\n' for r in rows))
        report = {'source': SOURCE, 'accepted': len(rows), 'rejected': rejected,
                  'failure': failure, 'requests': capture.count, 'price_scope': 'online'}
        (folder / 'report.json').write_text(json.dumps(report, ensure_ascii=False, indent=2))
        print(json.dumps(report, ensure_ascii=False), flush=True)
    if failure or rejected or not rows:
        raise SystemExit(1)


if __name__ == '__main__':
    main()
