#!/usr/bin/env python3
"""Bounded discovery of official Mexican grocery catalogs; never publishes.

HTML/JSON and SHA256 receipts are retained. An explicit HTTP 206 opt-in is used
only for VTEX public search. A transport/access failure stops that source.
Stock is an online indication, never a reservation or verified physical count.
"""
import argparse
from datetime import datetime, timedelta, timezone
from decimal import Decimal, InvalidOperation
import hashlib
from html import unescape
from html.parser import HTMLParser
import json
from pathlib import Path
import re
import shutil
from urllib.parse import urljoin, urlsplit

from online_catalog import Page, objects, presentation, timestamp
from retail.domain import normalized_text, valid_gtin
from retail.transport import SafeHttpClient, HttpResponse

SOURCES = {
    'carnemart-mx': ('carnemart.com', 'carnemart-mexico-online', 'CarneMart México · online'),
    'merco-rosita-mx': ('merco4.tiendariqra.com', 'merco-nueva-rosita-online', 'Merco Nueva Rosita · online'),
    'gran-bodega-mx': ('www.lagranbodega.com.mx', 'gran-bodega-online', 'Gran Bodega · online'),
    'scorpion-mx': ('www.scorpion.com.mx', 'scorpion-mexico-online', 'Scorpion · online'),
    'justo-mx': ('justo.mx', 'justo-mexico-online', 'Jüsto · online'),
    'compro-super-mx': ('www.comprov.com.mx', 'compro-tepic-online', 'COMPRO Súper · online'),
    'chedraui-mx': ('www.chedraui.com.mx', 'chedraui-online', 'Chedraui'),
    'garis-mx': ('garis.mayoreoenlinea.mx', 'garis-mexico-online', 'Garís · online'),
    'mas-bodega-mx': ('masbodega.mayoreoenlinea.mx', 'mas-bodega-mexico-online', 'MAS Bodega · online'),
    'fenix-mx': ('superfenix.mx', 'fenix-mexico-online', 'Fénix El Super de Casa · online'),
    'smart-final-public-web': ('www.smartnfinal.com.mx', 'smart-final-mexico-online', 'Smart & Final México · online'),
    'superissste-mx': ('tusuperissste.com.mx', 'superissste-mexico-online', 'SUPERISSSTE · online'),
    'merkabastos-mx': ('merkabastos.com', 'merkabastos-mexico-online', 'Merkabastos · online'),
    'merco-mx': ('adomicilio.merco.mx', 'merco-monterrey-online', 'Merco Monterrey'),
}


class MainProductImage(HTMLParser):
    """Magento's main gallery image, never related cards or tracking images."""
    def __init__(self, html):
        super().__init__(convert_charrefs=True)
        self.images = []
        self.feed(html)

    def handle_starttag(self, tag, attributes):
        attrs = dict(attributes)
        if tag != 'img' or 'gallery-placeholder__image' not in attrs.get('class', '').split():
            return
        candidate = attrs.get('data-src') or attrs.get('src')
        if candidate:
            parsed = urlsplit(candidate)
            if (parsed.scheme == 'https' and parsed.netloc == 'www.scorpion.com.mx'
                    and parsed.path.startswith('/pub/media/catalog/product/')):
                self.images.append(candidate)


def catalog_projection(text):
    """Keep COMPRO's product data and currency; never retain admin settings."""
    data = json.loads(text)
    return {'settings': {'currencyCode': data.get('settings', {}).get('currencyCode')},
            'categories': data.get('categories', []), 'products': data.get('products', [])}


def money(value):
    if isinstance(value, bool):
        raise ValueError('Boolean price')
    try:
        result = Decimal(str(value))
    except (InvalidOperation, ValueError):
        raise ValueError('Missing or invalid price') from None
    if not result.is_finite() or not 0 < result < 1000000 or result != result.quantize(Decimal('.01')):
        raise ValueError('Invalid price precision or range')
    return float(result)


def observed_presentation(name, description=''):
    # Normalize only the observed unit spelling, without altering product identity.
    name, description = [re.sub(r'\bpzs\b', 'pzas', value, flags=re.I)
                         for value in (name, description)]
    name, description = [re.sub(r'\bpor kilo\b', 'por kg', value, flags=re.I)
                         for value in (name, description)]
    for pattern, unit in [(r'\b(?:grs?|gramos?)\b', 'g'),
                          (r'\b(?:lts?|ltos?|litros?)\b', 'l'),
                          (r'\bkilogramos?\b', 'kg')]:
        name, description = [re.sub(pattern, unit, value, flags=re.I)
                             for value in (name, description)]
    # "12 pack 355 ml" can mean per-container content or total pack content.
    # Require an explicit per-piece marker before multiplying those quantities.
    if re.search(r'\b\d+\s*pack\b', name, re.I):
        match = re.search(r'\b(\d+)\s*pack\s*(\d+(?:[.,]\d+)?)\s*(kg|ml|g|l)\s*(?:c/u|cada uno|por pieza)\b', name, re.I)
        if match:
            return f'{match[1]} x {match[2]} {match[3]}'
        raise ValueError('Multipack quantity requires per-piece or total-content review')
    return presentation(name, description)


def next_data(html):
    matches = re.findall(r'<script[^>]*id=["\']__NEXT_DATA__["\'][^>]*>(.*?)</script>', html, re.S)
    if len(matches) != 1:
        raise ValueError('Missing or ambiguous Next data')
    return json.loads(matches[0])


def source_home(source):
    path = '/tienda/' if source == 'fenix-mx' else '/'
    return f'https://{SOURCES[source][0]}{path}'


def product_links(html, source):
    host = SOURCES[source][0]
    if source in ('garis-mx', 'mas-bodega-mx'):
        return list(dict.fromkeys(urljoin(f'https://{host}/', href)
            for href in Page(html).links
            if re.fullmatch(r'/products/[a-z0-9-]+', href)))
    if source == 'scorpion-mx':
        # Magento navigation categories also end in .html: only product cards
        # are evidence of a product URL, never the entire navigation tree.
        return list(dict.fromkeys(re.findall(
            r'<a[^>]*class=["\'][^"\']*product-item-link[^"\']*["\'][^>]*href=["\'](https://www\.scorpion\.com\.mx/tienda/[a-z0-9-]+\.html)["\']', html)))
    if source == 'justo-mx':
        data = next_data(html)
        links = []
        for product in objects(data['props']['pageProps'].get('initialHome', {})):
            url = product.get('productDetailUrl')
            raw = [p for p in objects(product) if p.get('id') == product.get('id')
                   and 'isAvailable' in p and 'price' in p]
            if not raw or any(p.get('onSale') is not False or len(p.get('variants') or []) != 1
                              or p['variants'][0].get('isPiece') is not True for p in raw):
                continue
            if isinstance(url, str) and re.fullmatch(r'/product/[a-z0-9-]+-\d+/?', url):
                links.append('https://justo.mx' + url.rstrip('/'))
        return list(dict.fromkeys(links))
    pattern = (r'/product/[a-z0-9-]+/' if source == 'carnemart-mx' else
               r'/producto/[a-z0-9-]+/' if source == 'fenix-mx' else r'/p/[a-z0-9-]+')
    urls = {}
    for href in Page(html).links:
        url = urljoin(f'https://{host}/', href)
        parsed = urlsplit(url)
        if (parsed.scheme == 'https' and parsed.netloc == host and not parsed.query
                and not parsed.fragment and re.fullmatch(pattern, parsed.path)):
            urls.setdefault(url, None)
    if source in ('merco-rosita-mx', 'merco-mx'):
        # Discover only explicitly rendered products. Promotional prices without
        # verifiable validity and prices whose tax inclusion is unclear are held.
        data = next_data(html)
        eligible = {f'https://{host}/p/{p["slug"]}' for p in objects(data)
                    if p.get('__typename') == 'Product'
                    and isinstance(p.get('pricing'), dict)
                    and p['pricing'].get('isTaxExempt') is True
                    and p['pricing'].get('oldPrice') in (None, '')}
        urls = {url: None for url in urls if url in eligible}
    return list(urls)


def row(source, response, *, name, amount, available, product_url,
        sku, description='', category='Alimentos', image=None, evidence=None,
        valid_until=None, evidence_kind='product_page', gtin=None):
    host, slug, brand = SOURCES[source]
    if any(urlsplit(u).hostname != host or urlsplit(u).scheme != 'https'
           for u in (response.url, product_url)):
        raise ValueError('Cross-origin product evidence')
    if type(available) is not bool or not isinstance(name, str) or not name.strip() or not sku:
        raise ValueError('Missing identity or availability')
    now = timestamp(response.observed_at)
    if now.tzinfo is None or not datetime.now(timezone.utc) - timedelta(days=7) < now <= datetime.now(timezone.utc) + timedelta(minutes=5):
        raise ValueError('Invalid observation date')
    if valid_until and timestamp(valid_until) <= now:
        raise ValueError('Expired offer')
    if image:
        image = unescape(image)
        if urlsplit(image).scheme != 'https' or not urlsplit(image).hostname:
            image = None
    result = {
        'source': source, 'store_slug': slug, 'store_brand': brand,
        'source_product_name': unescape(name).strip(), 'normalized_name': normalized_text(unescape(name)),
        'presentation': observed_presentation(name, description), 'category': category,
        'price': money(amount), 'currency': 'MXN', 'available': available,
        'price_scope': 'online', 'branch_id': None, 'branch_external_key': None,
        'branch_name': None, 'branch_address': None, 'branch_municipality': None,
        'branch_state': None, 'latitude': None, 'longitude': None,
        'observed_at': response.observed_at, 'captured_at': response.observed_at,
        'source_url': response.url, 'store_product_url': product_url,
        'external_reference': str(sku), 'image_url': image,
        'evidence_kind': evidence_kind, 'confidence_score': .90,
        'is_synthetic': False, 'review_status': 'accepted', 'validation_errors': [],
        'response_sha256': response.sha256,
        'raw_payload': {'evidence': evidence, 'response_sha256': response.sha256,
                        'scope_note': 'Online catalog observation; no verified branch, reservation or sales agreement'},
    }
    if gtin and valid_gtin(gtin):
        result['raw_payload']['validated_gtin'] = valid_gtin(gtin)
    if valid_until:
        result['valid_until'] = valid_until
        result['raw_payload']['offer_valid_until'] = valid_until
    result['content_hash'] = hashlib.sha256(json.dumps(result, sort_keys=True,
        ensure_ascii=False, allow_nan=False).encode()).hexdigest()
    return result


def parse_page(response, source):
    products = [p for p in objects(Page(response.text).json_ld) if p.get('@type') == 'Product']
    if len(products) != 1:
        raise ValueError('Expected exactly one JSON-LD product')
    product = products[0]
    if source == 'carnemart-mx':
        # Container weight in descriptive copy is not evidence that the quoted
        # price buys that container. Require a presentation in the actual title.
        observed_presentation(product.get('name') or '')
    offers = [o for o in objects(product.get('offers')) if o.get('@type') == 'Offer']
    if len(offers) != 1:
        raise ValueError('Ambiguous or missing offer')
    offer = offers[0]
    if offer.get('priceCurrency') != 'MXN':
        raise ValueError('MXN currency is not explicit')
    states = {'InStock': True, 'OutOfStock': False}
    available = states.get(str(offer.get('availability', '')).rsplit('/', 1)[-1])
    if available is None:
        raise ValueError('Unknown availability')
    for declared in (product.get('url'), offer.get('url')):
        if declared and declared != response.url:
            raise ValueError('Product or offer URL differs from captured URL')
    metadata = {'json_ld_product': product}
    if source == 'fenix-mx':
        specs = offer.get('priceSpecification') or []
        if isinstance(specs, dict):
            specs = [specs]
        if not specs or any(s.get('priceCurrency') != 'MXN'
                            or money(s.get('price')) != money(offer.get('price'))
                            or str(s.get('priceType', '')).endswith('StrikethroughPrice') for s in specs):
            raise ValueError('Uncorroborated unit price or promotion requires review')
    if source == 'justo-mx':
        payload = next_data(response.text)['props']['pageProps']['product']
        candidates = [p for p in objects(payload) if str(p.get('id')) == str(product.get('sku'))
                      and 'price' in p and 'isAvailable' in p]
        states = {json.dumps({k:p.get(k) for k in
            ('id','name','price','isAvailable','onSale','variants')},sort_keys=True):p for p in candidates}
        if len(states) != 1:
            raise ValueError('Missing or ambiguous matching storefront product')
        state = next(iter(states.values()))
        # JSON-LD availability alone can be optimistic; corroborate the actual
        # storefront state, package, price and identity before publishing.
        if str(state.get('id')) != str(product.get('sku')) or state.get('name') != product.get('name'):
            raise ValueError('Structured and storefront product identity conflict')
        if money(state.get('price')) != money(offer.get('price')):
            raise ValueError('Structured and storefront prices conflict')
        if type(state.get('isAvailable')) is not bool or state['isAvailable'] != available:
            raise ValueError('Structured and storefront availability conflict')
        if isinstance(payload, dict) and 'availability' in payload:
            if type(payload['availability']) is not bool or payload['availability'] != available:
                raise ValueError('Rendered storefront availability conflict')
            stock = payload.get('stockLevel')
            if stock is not None and (type(stock) not in (int, float) or stock < 0 or (stock > 0) != available):
                raise ValueError('Rendered stock level and availability conflict')
        if state.get('onSale') is not False:
            raise ValueError('Promotion requires independent validity review')
        variants = state.get('variants') or []
        if len(variants) != 1 or variants[0].get('isPiece') is not True:
            raise ValueError('Weighted or ambiguous sales unit requires review')
        observed_presentation(product.get('name') or '')
        metadata['storefront_product'] = {k: state.get(k) for k in
            ('id', 'name', 'sku', 'category', 'price', 'isAvailable', 'onSale', 'variants')}
        if isinstance(payload, dict) and type(payload.get('stockLevel')) in (int, float):
            metadata['stock_level'] = payload['stockLevel']
            metadata['stock_note'] = 'Declared ecommerce quantity; no physical branch or reservation verified'
    if source in ('merco-rosita-mx', 'merco-mx'):
        data = next_data(response.text)
        vendor = data['props']['vendor']
        if vendor.get('slug') != {'merco-rosita-mx': 'merco-nueva-rosita', 'merco-mx': 'merco-monterrey'}[source]:
            raise ValueError('Wrong Merco storefront')
        candidates = [p for p in objects(data) if p.get('__typename') == 'Product'
                      and p.get('sku') == product.get('sku')]
        states = {json.dumps({k: p.get(k) for k in ('id', 'sku', 'slug', 'stock', 'pricing')},
                             sort_keys=True): p for p in candidates}
        if len(states) != 1:
            raise ValueError('Missing or ambiguous matching SKU state')
        state = next(iter(states.values()))
        if state['pricing'].get('isTaxExempt') is not True:
            raise ValueError('Tax inclusion requires review')
        if state['pricing'].get('oldPrice') not in (None, ''):
            raise ValueError('Promotion lacks independently verified validity')
        if money(state['pricing']['price']) != money(offer['price']):
            raise ValueError('Structured and storefront prices conflict')
        stock = state.get('stock')
        if isinstance(stock, bool) or not isinstance(stock, (int, float)) or stock < 0 or (stock > 0) != available:
            raise ValueError('Stock and availability conflict')
        metadata['storefront_product'] = state
        metadata['vendor_slug'] = vendor['slug']
        metadata['stock_note'] = 'Declared ecommerce quantity; physical accuracy has not been independently checked'
        # Some Riqra JSON-LD omits the image although the matching SKU state
        # contains one. Only that exact product's image is eligible as fallback.
        if not product.get('image'):
            images = state.get('images') or []
            candidates = [i.get('url') if isinstance(i, dict) else i for i in images]
            candidates = [i for i in candidates if isinstance(i, str) and urlsplit(i).scheme == 'https']
            if candidates:
                product = dict(product, image=candidates[0])
                metadata['image_evidence'] = {'kind': 'matching SKU storefront image', 'url': candidates[0]}
    image = product.get('image')
    if isinstance(image, list):
        image = image[0] if image else None
    if isinstance(image, dict):
        image = image.get('url')
    if not image and source == 'scorpion-mx':
        candidates = list(dict.fromkeys(MainProductImage(response.text).images))
        if len(candidates) == 1:
            image = candidates[0]
            metadata['image_evidence'] = {'kind': 'main product gallery', 'url': image}
    expiry = offer.get('priceValidUntil')
    if expiry and re.fullmatch(r'\d{4}-\d{2}-\d{2}', expiry):
        expiry += 'T23:59:59-06:00'
    return row(source, response, name=product.get('name'), amount=offer.get('price'),
        available=available, product_url=response.url, sku=product.get('sku'),
        description=product.get('description') or '', image=image, evidence=metadata, valid_until=expiry)


def parse_vtex(response, currency, limit, source='gran-bodega-mx'):
    if currency != 'MXN':
        raise ValueError('Official storefront did not declare MXN')
    data = json.loads(response.text)
    if not isinstance(data, list) or len(data) > limit:
        raise ValueError('Unexpected or unbounded search result')
    accepted, rejected = [], []
    for product in data:
        try:
            if re.search(r'\b(?:mas|gratis|combo)\b|\+', normalized_text(product.get('productName') or '')):
                raise ValueError('Combined or promotional pack requires presentation review')
            items = product.get('items', [])
            if len(items) != 1:
                raise ValueError('Multiple SKU variants require review')
            item = items[0]
            if item.get('measurementUnit') not in (None, 'un') or item.get('unitMultiplier') not in (None, 1):
                raise ValueError('Weighted or multiplied price unit requires review')
            sellers = [s for s in item.get('sellers', []) if s.get('sellerId') == '1']
            if len(sellers) != 1:
                raise ValueError('Missing or ambiguous first-party offer')
            offer = sellers[0]['commertialOffer']
            price = money(offer.get('Price'))
            if offer.get('ListPrice') and money(offer['ListPrice']) != price:
                raise ValueError('Promotion requires independent validity review')
            quantity = offer.get('AvailableQuantity')
            if type(quantity) is not int or quantity < 0:
                raise ValueError('Quantity is not explicit')
            if offer.get('IsAvailable') is not None and (type(offer['IsAvailable']) is not bool or offer['IsAvailable'] != (quantity > 0)):
                raise ValueError('Availability contradicts quantity')
            images = item.get('images') or [{}]
            image = images[0].get('imageUrl')
            accepted.append(row(source, response,
                name=product.get('productName'), amount=price, available=quantity > 0,
                product_url=product.get('link'), sku=item.get('itemId'),
                description=product.get('description') or '', image=image,
                category=(product.get('categories') or ['/Alimentos/'])[0].strip('/').split('/')[0],
                evidence=product, evidence_kind='store_api', gtin=item.get('ean'),
                valid_until=offer.get('PriceValidUntil')))
        except (ValueError, KeyError, TypeError, IndexError) as error:
            rejected.append({'product_id': product.get('productId'), 'reason': str(error)})
    return accepted, rejected


def parse_compro(response, limit):
    """Public catalog feed, including unavailable items; not a branch inventory.

    This retailer has a shared catalog link, not individual product pages.
    SKU/name/presentation distinguish listings. Only product and currency fields
    are preserved; unrelated site/admin settings never enter ingestion payloads.
    """
    if response.url != 'https://www.comprov.com.mx/productos-precios.json' or response.status != 200:
        raise ValueError('Unexpected COMPRO feed URL/status')
    data = json.loads(response.text)
    if data.get('settings', {}).get('currencyCode') != 'MXN':
        raise ValueError('Explicit MXN currency required')
    products = data.get('products')
    if not isinstance(products, list) or len(products) > 10000 or not 1 <= limit <= 10000:
        raise ValueError('Unexpected catalog or observation limit')
    ids = [p.get('id') for p in products]
    if any(not isinstance(sku, str) or not sku for sku in ids) or len(set(ids)) != len(ids):
        raise ValueError('Missing or duplicate catalog SKU')
    categories = {p['id']: p['name'] for p in data.get('categories', [])}
    # Reserve out-of-stock examples in small samples, while a complete capture
    # visits EVERY product, including malformed records that must be reported.
    if limit >= len(products):
        selected = products
    else:
        unavailable = [p for p in products if p.get('available') is False][:min(2, limit)]
        selected = [p for p in products if p.get('available') is not False][:limit-len(unavailable)] + unavailable
    accepted, rejected = [], []
    for p in selected:
        try:
            if type(p.get('available')) is not bool or not isinstance(p.get('name'), str):
                raise ValueError('Missing product name or explicit availability')
            if p.get('salePrice') is not None or p.get('promotion') is not None:
                raise ValueError('Promotion requires independent validity review')
            quantity = observed_presentation(p.get('gramaje') or '')
            if not p['name'].strip() or not p.get('categoryId') in categories:
                raise ValueError('Missing catalog name/category')
            # The public UI displays name and gramaje separately. Keep both
            # together to avoid merging differently sized catalog entries.
            name = p['name'].strip() + ' ' + quantity
            evidence = {'catalog_product': {k: p.get(k) for k in
                ('id', 'name', 'gramaje', 'image', 'categoryId', 'price', 'available', 'salePrice', 'promotion')},
                'currency': 'MXN', 'link_scope': 'shared catalog, no individual product page'}
            image = urljoin('https://www.comprov.com.mx/', p.get('image') or '')
            if not p.get('image') or urlsplit(image).hostname != 'www.comprov.com.mx':
                image = None
            accepted.append(row('compro-super-mx', response, name=name, amount=p.get('price'),
                available=p['available'], product_url='https://www.comprov.com.mx/tienda.html',
                sku=p['id'], category=categories[p['categoryId']], image=image,
                evidence=evidence, evidence_kind='store_api'))
        except (ValueError, KeyError, TypeError) as error:
            rejected.append({'sku': p.get('id'), 'reason': str(error)})
    # Shared catalog URLs must not silently merge distinct SKUs with the same
    # normalized name/pack. Hold the entire ambiguous group for identity review.
    counts = {}
    for item in accepted:
        counts[item['normalized_name']] = counts.get(item['normalized_name'], 0) + 1
    ambiguous = [item for item in accepted if counts[item['normalized_name']] > 1]
    rejected.extend({'sku': item['external_reference'], 'reason': 'Ambiguous shared-link product identity'} for item in ambiguous)
    return [item for item in accepted if counts[item['normalized_name']] == 1], rejected


def parse_garis(response, currency, source='garis-mx'):
    """One explicitly priced piece variant; cases and discounts require review."""
    if currency != 'MXN' or response.status != 200:
        raise ValueError('Explicit storefront currency and complete response required')
    product = json.loads(response.text)
    host = SOURCES[source][0]
    expected = f'https://{host}/products/{product.get("handle")}.js'
    if response.url != expected or not isinstance(product.get('title'), str):
        raise ValueError('Catalog product identity or URL conflict')
    variants = product.get('variants') or []
    if (type(product.get('available')) is not bool
            or any(type(v.get('available')) is not bool for v in variants)
            or product['available'] != any(v['available'] for v in variants)):
        raise ValueError('Conflicting product and variant availability')
    piece_label = r'pieza 1(?: a \d+)?' if source == 'garis-mx' else r'PZA/1'
    pieces = [v for v in variants if re.fullmatch(piece_label, v.get('title', ''), re.I)]
    if len(pieces) != 1:
        raise ValueError('Missing or ambiguous single-piece sales unit')
    variant = pieces[0]
    cents = variant.get('price')
    if type(cents) is not int or variant.get('compare_at_price') not in (None, 0, cents):
        raise ValueError('Discount or unverified cents price requires review')
    # A wholesale title can describe pieces per case; only an explicit net
    # quantity and the selected one-piece price define this published offer.
    observed_presentation(product['title'])
    return row(source, response,
        name=product['title'] + ' · ' + variant['title'], amount=Decimal(cents) / 100,
        available=variant['available'],
        product_url=expected[:-3] + '?variant=' + str(variant['id']),
        sku=variant.get('sku') or variant.get('id'), category=product.get('type') or 'Alimentos',
        image=urljoin(f'https://{host}/', product.get('featured_image') or '') if product.get('featured_image') else None,
        evidence={'catalog_product': product, 'currency': currency,
                  'selected_variant_id': variant['id'], 'sales_unit': 'one piece',
                  'price_unit_note': 'Piece price in the explicitly selected tier; case price excluded'},
        evidence_kind='store_api', gtin=variant.get('sku'))


def capture(folder, sources, limit, client=None):
    folder.mkdir(parents=True, exist_ok=False)
    client = client or SafeHttpClient([SOURCES[s][0] for s in sources],
        max_requests=60, max_bytes=8 * 1024 * 1024, accepted_statuses=(200, 206))
    report = {'started_at': datetime.now(timezone.utc).isoformat(), 'published': False, 'sources': {}}

    def fetch(url, directory):
        response = client.get(url)
        stem = f'response-{len(list(directory.glob("response-*.txt"))) + 1:03}'
        body = response.text
        metadata = {
            'url': response.url, 'status': response.status, 'observed_at': response.observed_at,
            'sha256': response.sha256, 'content_type': response.content_type,
            'content_range': response.content_range}
        if url == 'https://www.comprov.com.mx/productos-precios.json':
            body = json.dumps(catalog_projection(body), ensure_ascii=False)
            metadata.update(redacted_projection=True, stored_projection_sha256=hashlib.sha256(body.encode()).hexdigest())
        (directory / (stem + '.txt')).write_text(body, encoding='utf-8')
        (directory / (stem + '.json')).write_text(json.dumps(metadata, ensure_ascii=False, indent=2) + '\n')
        return response

    for source in sources:
        directory = folder / source
        directory.mkdir()
        accepted, rejected, failure, candidates = [], [], None, []
        try:
            home = fetch(source_home(source), directory)
            if home.status != 200:
                raise ValueError('Homepage must return a complete response')
            if source == 'compro-super-mx':
                response = fetch('https://www.comprov.com.mx/productos-precios.json', directory)
                accepted, rejected = parse_compro(response, limit)
            elif source in ('gran-bodega-mx', 'chedraui-mx'):
                # Currency comes from the official HTML, not country inference.
                currency = 'MXN' if (re.search(r'(?:ISOCurrencySymbol|CurrencyCode|currency)["\']?\s*:\s*["\']MXN["\']', home.text, re.I)
                    or re.search(r'<meta[^>]*name=["\']currency["\'][^>]*content=["\']MXN["\']', home.text, re.I)) else None
                response = fetch(f'https://{SOURCES[source][0]}/api/catalog_system/pub/products/search/leche?_from=0&_to={limit-1}', directory)
                accepted, rejected = parse_vtex(response, currency, limit, source=source)
            elif source in ('garis-mx', 'mas-bodega-mx'):
                currency = 'MXN' if re.search(r'Shopify\.currency\s*=\s*\{[^}]*["\']active["\']\s*:\s*["\']MXN["\']', home.text) else None
                candidates = product_links(home.text, source)[:limit]
                for url in candidates:
                    response = fetch(url + '.js', directory)
                    try:
                        accepted.append(parse_garis(response, currency, source=source))
                    except (ValueError, KeyError, TypeError) as error:
                        rejected.append({'url': url, 'reason': str(error)})
            else:
                candidates = product_links(home.text, source)[:limit]
                for url in candidates:
                    response = fetch(url, directory)
                    if response.status != 200:
                        raise ValueError('Product HTML must return a complete response')
                    try:
                        accepted.append(parse_page(response, source))
                    except (ValueError, KeyError, TypeError) as error:
                        rejected.append({'url': url, 'reason': str(error)})
        except (RuntimeError, ValueError, KeyError, TypeError) as error:
            failure = str(error)
        (directory / 'observations.ndjson').write_text(''.join(json.dumps(r, ensure_ascii=False, allow_nan=False) + '\n' for r in accepted))
        (directory / 'candidates.json').write_text(json.dumps(candidates, indent=2) + '\n')
        report['sources'][source] = {'accepted': len(accepted), 'rejected': rejected,
            'failure': failure, 'status': 'partial' if failure or rejected or not accepted else 'ok'}
        print(json.dumps({'source': source, **report['sources'][source]}, ensure_ascii=False), flush=True)
    report['receipts'], report['metrics'] = client.receipts, dict(client.metrics)
    (folder / 'report.json').write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n')
    return report


def replay(original, folder, sources, limit):
    """Reparse verified saved responses without a request or a new timestamp."""
    folder.mkdir(parents=True, exist_ok=False)
    report = {'replay_from': str(original), 'published': False, 'requests': 0, 'sources': {}}
    for source in sources:
        directory = folder / source
        directory.mkdir()
        accepted, rejected, failure, responses = [], [], None, []
        try:
            for metadata_file in sorted((original / source).glob('response-*.json')):
                metadata = json.loads(metadata_file.read_text())
                text_file = metadata_file.with_suffix('.txt')
                body = text_file.read_bytes()
                expected_sha = metadata.get('stored_projection_sha256') if metadata.get('redacted_projection') else metadata['sha256']
                if metadata.get('redacted_projection') and (source != 'compro-super-mx' or metadata['url'] != 'https://www.comprov.com.mx/productos-precios.json'):
                    raise ValueError('Unexpected redacted evidence')
                if hashlib.sha256(body).hexdigest() != expected_sha:
                    raise ValueError('Saved evidence SHA256 mismatch')
                response = HttpResponse(metadata['url'], metadata['status'], body.decode('utf-8'),
                    metadata['observed_at'], metadata['sha256'], metadata['content_type'], metadata.get('content_range'))
                if urlsplit(response.url).hostname != SOURCES[source][0]:
                    raise ValueError('Saved response outside source origin')
                shutil.copyfile(metadata_file, directory / metadata_file.name)
                shutil.copyfile(text_file, directory / text_file.name)
                responses.append(response)
            homes = [r for r in responses if r.url == source_home(source)]
            if len(homes) != 1 or homes[0].status != 200:
                raise ValueError('Missing verified homepage')
            for response in responses:
                if response is homes[0]:
                    continue
                try:
                    if source == 'compro-super-mx':
                        rows, issues = parse_compro(response, limit)
                        accepted.extend(rows); rejected.extend(issues)
                    elif source in ('gran-bodega-mx', 'chedraui-mx'):
                        currency = 'MXN' if (re.search(r'(?:ISOCurrencySymbol|CurrencyCode|currency)["\']?\s*:\s*["\']MXN["\']', homes[0].text, re.I)
                            or re.search(r'<meta[^>]*name=["\']currency["\'][^>]*content=["\']MXN["\']', homes[0].text, re.I)) else None
                        rows, issues = parse_vtex(response, currency, limit, source=source)
                        accepted.extend(rows); rejected.extend(issues)
                    elif source in ('garis-mx', 'mas-bodega-mx'):
                        currency = 'MXN' if re.search(r'Shopify\.currency\s*=\s*\{[^}]*["\']active["\']\s*:\s*["\']MXN["\']', homes[0].text) else None
                        accepted.append(parse_garis(response, currency, source=source))
                    else:
                        if response.status != 200:
                            raise ValueError('Saved product response is incomplete')
                        accepted.append(parse_page(response, source))
                except (ValueError, KeyError, TypeError) as error:
                    rejected.append({'url': response.url, 'reason': str(error)})
        except (OSError, ValueError, KeyError, TypeError) as error:
            failure = str(error)
        (directory / 'observations.ndjson').write_text(''.join(json.dumps(r, ensure_ascii=False, allow_nan=False) + '\n' for r in accepted))
        report['sources'][source] = {'accepted': len(accepted), 'rejected': rejected,
            'failure': failure, 'status': 'partial' if failure or rejected or not accepted else 'ok'}
        print(json.dumps({'source': source, **report['sources'][source]}, ensure_ascii=False), flush=True)
    (folder / 'report.json').write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n')
    return report


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--out-dir', type=Path, required=True)
    parser.add_argument('--sources', default=','.join(SOURCES))
    parser.add_argument('--limit-per-source', type=int, default=10)
    parser.add_argument('--replay-from', type=Path, help='Verified saved capture; no network requests')
    args = parser.parse_args()
    sources = list(dict.fromkeys(args.sources.split(',')))
    if not sources or any(s not in SOURCES for s in sources) or not 1 <= args.limit_per_source <= 15:
        parser.error('Use registered sources and a limit of 1..15')
    report = (replay(args.replay_from, args.out_dir, sources, args.limit_per_source)
              if args.replay_from else capture(args.out_dir, sources, args.limit_per_source))
    return 1 if any(s['status'] != 'ok' for s in report['sources'].values()) else 0


if __name__ == '__main__':
    raise SystemExit(main())
