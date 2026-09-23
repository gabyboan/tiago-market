#!/usr/bin/env python3
"""Small, sequential public-page capture. No login, cookies, bypass or retries.

Reads JSON-LD offers from reviewed product URLs. Saves observation receipts and
NDJSON; --sql-out produces a server-side publish call, never uploads itself.
Replaying evidence preserves the original timestamp. Unit fixtures are not input.
"""
import argparse
from datetime import datetime, timedelta, timezone
import gzip
import hashlib
from html import unescape
from html.parser import HTMLParser
import json
from pathlib import Path
import re
import time
import unicodedata
from urllib.error import HTTPError
from urllib.parse import urlparse
from urllib.request import Request, urlopen
from urllib.robotparser import RobotFileParser

UA = 'TiagoMarketBot/0.1 (+https://github.com/gabyboan/tiago-market)'
SOURCES = {
    'arteli': ('www.arteli.com.mx', 'arteli-online', 'arteli-public-web'),
    'smart-final': ('www.smartnfinal.com.mx', 'smart-final-mexico-online', 'smart-final-public-web'),
}


def utcnow():
    return datetime.now(timezone.utc)


def timestamp(value):
    date = datetime.fromisoformat(value.replace('Z', '+00:00'))
    if date.tzinfo is None:
        raise ValueError('Timestamp requires timezone')
    return date


class Page(HTMLParser):
    def __init__(self, html):
        super().__init__()
        self.json_ld = []
        self.links = []
        self.text = []
        self.script = False
        self.script_text = ''
        self.feed(html)

    def handle_starttag(self, tag, attrs):
        attrs = dict(attrs)
        if tag == 'script' and attrs.get('type') == 'application/ld+json':
            self.script = True
            self.script_text = ''
        if tag == 'a' and attrs.get('href'):
            self.links.append(attrs['href'])

    def handle_endtag(self, tag):
        if tag == 'script' and self.script:
            self.script = False
            self.json_ld.append(json.loads(self.script_text))

    def handle_data(self, text):
        if self.script:
            self.script_text += text
        else:
            self.text.append(text)


def objects(value):
    if isinstance(value, dict):
        yield value
        for child in value.values():
            yield from objects(child)
    elif isinstance(value, list):
        for child in value:
            yield from objects(child)


def presentation(name, description):
    # Preserve multipacks before looking for a single unit; never invent 1 piece.
    for text in [name, description]:
        match = re.search(r'\b\d+\s*(?:x|de|piezas? de)\s*\d+(?:[.,]\d+)?\s*(?:kg|ml|g|l)\b', text, re.I)
        if not match:
            match = re.search(r'\b\d+(?:[.,]\d+)?\s*(?:kg|ml|g|l|piezas?|pzas?|rollos?)\b', text, re.I)
        if match:
            return match.group().strip()
        if re.search(r'\bpor kg\b', text, re.I):
            return 'por kg'
    raise ValueError('Missing presentation')


def parse_product(html, url, source, observed_at, sha):
    host, slug, source_id = SOURCES[source]
    if urlparse(url).netloc != host:
        raise ValueError('Unexpected origin')
    page = Page(html)
    products = [x for x in objects(page.json_ld) if x.get('@type') == 'Product']
    if len(products) != 1:
        raise ValueError('Expected exactly one product')
    product = products[0]
    offers = [x for x in objects(product.get('offers', {})) if x.get('@type') == 'Offer']
    if len(offers) != 1:
        raise ValueError('Ambiguous or missing offer')
    offer = offers[0]
    name = unescape(unescape(product.get('name', ''))).strip()
    amount = float(offer['price'])
    if offer.get('priceCurrency') != 'MXN' or not (0 < amount < 1000000) or not name:
        raise ValueError('Invalid MXN price or name')
    if not str(offer.get('availability', '')).endswith('/InStock'):
        raise ValueError('Availability not confirmed')
    valid_until = offer.get('priceValidUntil')
    if valid_until:
        if re.fullmatch(r'\d{4}-\d{2}-\d{2}', valid_until):
            valid_until += 'T23:59:59-06:00'
        if timestamp(valid_until) <= timestamp(observed_at):
            raise ValueError('Expired offer')
    # Some WooCommerce pages expose a generic future JSON-LD expiry while their
    # visible promotion expired. Reject any sale on the main product summary.
    if source == 'smart-final':
        summary = re.search(r'<div class="summary entry-summary">(.*?)<div class="woocommerce-tabs', html, re.S)
        if summary and ('<del' in summary.group(1) or re.search(r'v[aá]lido hasta', summary.group(1), re.I)):
            raise ValueError('Promotion requires reliable current validity')
    image = product.get('image')
    if isinstance(image, list):
        image = image[0] if image else None
    if isinstance(image, dict):
        image = image.get('url')
    if image and (urlparse(image).scheme != 'https' or not urlparse(image).netloc):
        image = None
    category = product.get('category')
    if not isinstance(category, str) or not category:
        crumbs = [x for x in objects(page.json_ld) if x.get('@type') == 'BreadcrumbList']
        items = crumbs[-1].get('itemListElement', []) if crumbs else []
        cat_item = items[-2].get('item', {}) if len(items) > 2 else {}
        category = cat_item.get('name') if isinstance(cat_item, dict) else None
    if not category or category in ('Tienda', 'Inicio'):
        category = 'Otros'
    normalized = ''.join(c for c in unicodedata.normalize('NFD', name.lower()) if unicodedata.category(c) != 'Mn')
    return {
        'source': source_id, 'store_slug': slug, 'price_scope': 'online',
        'product_name': name, 'normalized_name': normalized,
        'presentation': presentation(name, product.get('description', '')),
        'category': category, 'price': amount, 'currency': 'MXN', 'available': True,
        'image_url': image, 'store_product_url': url, 'source_url': url,
        'observed_at': observed_at, 'valid_until': valid_until,
        'response_sha256': sha, 'is_synthetic': False, 'review_status': 'accepted',
        'evidence_kind': 'product_page', 'sku': product.get('sku'),
        'offer_evidence': {k: offer.get(k) for k in ['price', 'priceCurrency', 'availability', 'priceValidUntil']},
    }


class Capture:
    def __init__(self, folder, delay):
        self.folder = folder
        self.delay = max(5, delay)
        self.last = 0
        self.count = 0

    def get(self, url, image=False):
        time.sleep(max(0, self.last + self.delay - time.monotonic()))
        self.last = time.monotonic()
        started = utcnow().isoformat()
        try:
            response = urlopen(Request(url, headers={'User-Agent': UA, 'Accept-Encoding': 'gzip'}), timeout=25)
        except HTTPError as error:
            response = error
        with response:
            body = response.read(8 * 1024 * 1024)
            status = response.status
            final_url = response.url
            content_type = response.headers.get('Content-Type', '')
            if body[:2] == b'\x1f\x8b':
                body = gzip.decompress(body)
        observed = utcnow().isoformat()
        sha = hashlib.sha256(body).hexdigest()
        self.count += 1
        receipt = {'url': url, 'final_url': final_url, 'status': status,
                   'started_at': started, 'observed_at': observed,
                   'sha256': sha, 'bytes': len(body), 'content_type': content_type}
        (self.folder / f'request-{self.count:03}.json').write_text(json.dumps(receipt, indent=2))
        if status in (401, 403, 429) or status >= 500:
            raise RuntimeError(f'Stopped at HTTP {status}: {url}; no retries')
        if status != 200:
            raise ValueError(f'HTTP {status}: {url}')
        if urlparse(final_url).netloc != urlparse(url).netloc:
            raise RuntimeError('Stopped at cross-origin redirect')
        if image:
            if not content_type.startswith('image/'):
                raise ValueError('Image URL did not return an image')
        elif any(x in body[:100000].lower() for x in [b'cf-chl-', b'captcha challenge', b'px-captcha']):
            raise RuntimeError('Stopped at access challenge')
        return body, receipt


def validate(row, now=None):
    now = now or utcnow()
    if row.get('price_scope') != 'online' or any(row.get(k) is not None for k in ['branch_id', 'branch_name', 'branch_external_key', 'latitude', 'longitude']):
        raise ValueError('Mixed mode')
    if row.get('is_synthetic') is not False or row.get('review_status') != 'accepted':
        raise ValueError('Unreviewed/synthetic record')
    for field in ['source', 'store_slug', 'product_name', 'presentation', 'category', 'source_url', 'store_product_url', 'observed_at', 'response_sha256']:
        if not row.get(field):
            raise ValueError('Missing ' + field)
    if row['currency'] != 'MXN' or not 0 < row['price'] < 1000000:
        raise ValueError('Invalid price')
    observed = timestamp(row['observed_at'])
    if observed <= now - timedelta(days=7) or observed > now + timedelta(minutes=5):
        raise ValueError('Expired/future observation')
    if row.get('valid_until') and timestamp(row['valid_until']) <= now:
        raise ValueError('Expired offer')


def publish_sql(rows):
    for row in rows:
        validate(row)
    # Dollar delimiter does not occur in serialized data; no shell interpolation.
    payload = json.dumps(rows, ensure_ascii=False)
    delimiter = '$tiago_observations$'
    if delimiter in payload:
        raise ValueError('Unexpected SQL delimiter')
    return 'begin;\nselect public.publish_online_observations(' + delimiter + payload + delimiter + '::jsonb);\ncommit;\n'


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source', choices=SOURCES, required=True)
    parser.add_argument('--urls', type=Path, required=True, help='JSON array of reviewed product page URLs')
    parser.add_argument('--out-dir', type=Path, required=True, help='New directory, never overwrite evidence')
    parser.add_argument('--limit', type=int, default=8)
    parser.add_argument('--delay', type=float, default=5)
    args = parser.parse_args()
    if args.source == 'arteli':
        parser.error('Arteli capture paused after CDN HTTP 429 on 2026-09-23. Review access before enabling; no retries or alternate CDN.')
    if not 1 <= args.limit <= 20:
        parser.error('limit must be 1..20')
    args.out_dir.mkdir(parents=True, exist_ok=False)
    capture = Capture(args.out_dir, args.delay)
    host = SOURCES[args.source][0]
    robots_url = f'https://{host}/robots.txt'
    robots_body, _ = capture.get(robots_url)
    (args.out_dir / 'robots.txt').write_bytes(robots_body)
    rules = RobotFileParser(robots_url)
    rules.parse(robots_body.decode().splitlines())
    rows, rejected = [], []
    urls = list(dict.fromkeys(json.loads(args.urls.read_text())))[:args.limit]
    try:
        for url in urls:
            if urlparse(url).netloc != host or not rules.can_fetch(UA, url):
                raise RuntimeError('Unapproved host or robots disallow: ' + url)
            body, receipt = capture.get(url)
            try:
                row = parse_product(body.decode(), url, args.source, receipt['observed_at'], receipt['sha256'])
                if row['image_url']:
                    # Only known public CDN paths; do not follow arbitrary JSON-LD URLs.
                    image_host = urlparse(row['image_url']).netloc
                    allowed_images = {host, 'arteli.vtexassets.com', 'arteli.vteximg.com.br'}
                    if image_host not in allowed_images:
                        row['image_url'] = None
                    else:
                        try:
                            _, image_receipt = capture.get(row['image_url'], image=True)
                            row['image_checked_at'] = image_receipt['observed_at']
                        except ValueError:
                            row['image_url'] = None
                validate(row)
                rows.append(row)
                print(json.dumps({'name': row['product_name'], 'price': row['price'], 'image': bool(row['image_url'])}, ensure_ascii=False), flush=True)
            except (ValueError, KeyError) as error:
                rejected.append({'url': url, 'reason': str(error)})
    finally:
        (args.out_dir / 'observations.ndjson').write_text(''.join(json.dumps(r, ensure_ascii=False)+'\n' for r in rows))
        (args.out_dir / 'report.json').write_text(json.dumps({'accepted': len(rows), 'rejected': rejected, 'requests': capture.count}, indent=2))
    if rows:
        (args.out_dir / 'publish.sql').write_text(publish_sql(rows))


if __name__ == '__main__':
    main()
