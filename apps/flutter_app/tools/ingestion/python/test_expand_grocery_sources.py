"""Data-integrity regressions for new catalogs. Fixtures are never publish inputs."""
from copy import deepcopy
from datetime import datetime, timedelta, timezone
import hashlib
import io
import json
from pathlib import Path
import tempfile
import unittest

from expand_grocery_sources import parse_page, parse_vtex, parse_compro, parse_garis, product_links, capture, replay, money, observed_presentation
from retail.transport import SafeHttpClient, HttpResponse, FetchError


def response(body, url='https://carnemart.com/product/alimento-8-pzs/', status=200):
    return HttpResponse(url, status, body, datetime.now(timezone.utc).isoformat(),
                        hashlib.sha256(body.encode()).hexdigest(), 'text/html')


def html(product=None, state=None):
    product = product or {
        '@type': 'Product', 'name': 'Alimento marca 8 Pzs', 'sku': 'demo-test',
        'offers': {'@type': 'Offer', 'price': '100.50', 'priceCurrency': 'MXN',
                   'availability': 'https://schema.org/InStock'},
    }
    text = '<script type="application/ld+json">' + json.dumps(product) + '</script>'
    if state:
        text += '<script id="__NEXT_DATA__" type="application/json">' + json.dumps(state) + '</script>'
    return text


def riqra():
    product = {'@type': 'Product', 'name': 'Aceitunas marca 175 g', 'sku': 'fixture',
               'offers': [{'@type': 'Offer', 'price': '31.99', 'priceCurrency': 'MXN', 'availability': 'InStock'}]}
    state = {'props': {'vendor': {'slug': 'merco-nueva-rosita'}, 'pageProps': {
        'product': {'__typename': 'Product', 'id': 'fixture-id', 'sku': 'fixture',
                    'slug': 'aceitunas-175-g', 'stock': 10,
                    'pricing': {'price': '31.99', 'oldPrice': None, 'isTaxExempt': True}}}}}
    return product, state


def vtex():
    return {'productId': 'fixture', 'productName': 'Leche marca 1000 ml',
            'link': 'https://www.lagranbodega.com.mx/leche-fixture/p',
            'items': [{'itemId': 'fixture', 'images': [], 'sellers': [
                {'sellerId': '1', 'commertialOffer': {'Price': 27, 'ListPrice': 27,
                  'AvailableQuantity': 99999, 'IsAvailable': True}}]}]}


class IntegrityTests(unittest.TestCase):
    def test_fenix_replay_recognizes_official_catalog_landing_page(self):
        p={'@type':'Product','name':'Pasta Fixture 200 g','sku':'fixture',
           'offers':{'@type':'Offer','price':9.3,'priceCurrency':'MXN','availability':'InStock',
             'priceSpecification':[{'price':9.3,'priceCurrency':'MXN'}]}}
        responses=[response('<html>Catalog</html>','https://superfenix.mx/tienda/'),
                   response(html(p),'https://superfenix.mx/producto/pasta-fixture/')]
        with tempfile.TemporaryDirectory() as tmp:
            original=Path(tmp)/'original/fenix-mx';original.mkdir(parents=True)
            for i,r in enumerate(responses):
                stem=original/f'response-{i:03}'
                stem.with_suffix('.txt').write_text(r.text)
                stem.with_suffix('.json').write_text(json.dumps(r.__dict__))
            report=replay(original.parent,Path(tmp)/'replayed',['fenix-mx'],3)
            self.assertEqual(report['sources']['fenix-mx']['accepted'],1)
            self.assertIsNone(report['sources']['fenix-mx']['failure'])

    def test_fenix_corroborates_regular_unit_price_and_holds_discount(self):
        p={'@type':'Product','name':'Pasta Fixture 200 g','sku':'fixture',
           'offers':{'@type':'Offer','price':9.3,'priceCurrency':'MXN','availability':'InStock',
             'priceSpecification':[{'price':9.3,'priceCurrency':'MXN','@type':'UnitPriceSpecification'}]}}
        url='https://superfenix.mx/producto/pasta-fixture/'
        self.assertEqual(parse_page(response(html(p),url),'fenix-mx')['price'],9.3)
        p['offers']['priceSpecification'].append({'price':10,'priceCurrency':'MXN','priceType':'https://schema.org/StrikethroughPrice'})
        with self.assertRaises(ValueError):parse_page(response(html(p),url),'fenix-mx')

    def test_mas_bodega_requires_piece_price_excludes_bulk_offer(self):
        p={'id':123,'handle':'arroz-227-gr','title':'Arroz Fixture 227 GR','available':True,
           'variants':[{'id':1,'title':'PZA/1','sku':'fixture','price':414,'available':True},
                       {'id':2,'title':'BLT/40','price':15185,'available':True}]}
        url='https://masbodega.mayoreoenlinea.mx/products/arroz-227-gr.js'
        row=parse_garis(response(json.dumps(p),url),'MXN',source='mas-bodega-mx')
        self.assertEqual(row['price'],4.14);self.assertEqual(row['source'],'mas-bodega-mx')
        self.assertEqual(row['raw_payload']['evidence']['sales_unit'],'one piece')

    def test_garis_uses_piece_variant_and_cents_without_case_quantity_or_discount(self):
        p = {'id':123,'handle':'fixture-20-500-gr','title':'Fixture 20/500 GR','available':True,
             'variants':[{'id':1,'title':'pieza 1 a 19','sku':'fixture','price':2256,
                          'compare_at_price':0,'available':True},
                         {'id':2,'title':'Caja con 20','price':39655,'available':True}]}
        url = 'https://garis.mayoreoenlinea.mx/products/fixture-20-500-gr.js'
        row = parse_garis(response(json.dumps(p),url),'MXN')
        self.assertEqual(row['price'],22.56);self.assertEqual(row['presentation'],'500 g')
        self.assertTrue(row['store_product_url'].endswith('?variant=1'))
        self.assertEqual(row['raw_payload']['evidence']['selected_variant_id'],1)
        for change in ('discount','case_only','availability','unknown_unit','currency'):
            q=deepcopy(p)
            if change=='discount':q['variants'][0]['compare_at_price']=3000
            elif change=='case_only':q['variants']=q['variants'][1:]
            elif change=='availability':q['available']=False
            elif change=='unknown_unit':q['title']='Fixture 20/500'
            with self.subTest(change=change), self.assertRaises(ValueError):
                parse_garis(response(json.dumps(q),url),'USD' if change=='currency' else 'MXN')

    def test_justo_discovery_follows_cacheable_product_inside_card_metadata(self):
        raw={'id':'123','isAvailable':True,'price':30,'onSale':False,'variants':[{'isPiece':True}]}
        card={'id':'123','productDetailUrl':'/product/leche-fixture-123/',
              'metadata':{'cacheable':raw}}
        state={'props':{'pageProps':{'initialHome':{'components':[card]}}}}
        text='<script id="__NEXT_DATA__">'+json.dumps(state)+'</script>'
        self.assertEqual(product_links(text,'justo-mx'),['https://justo.mx/product/leche-fixture-123'])
        raw['onSale']=True
        text='<script id="__NEXT_DATA__">'+json.dumps(state)+'</script>'
        self.assertEqual(product_links(text,'justo-mx'),[])

    def test_justo_rendered_stock_corroborates_cached_boolean(self):
        product={'@type':'Product','name':'Leche Fixture 1 l','sku':'123',
                 'offers':{'@type':'Offer','price':30,'priceCurrency':'MXN','availability':'InStock'}}
        raw={'id':'123','name':product['name'],'isAvailable':True,'price':30,'onSale':False,
             'variants':[{'isPiece':True}]}
        state={'props':{'pageProps':{'product':{'id':'123','availability':True,'stockLevel':5,
                                             'metadata':{'cacheable':raw}}}}}
        url='https://justo.mx/product/leche-fixture-123'
        row=parse_page(response(html(product,state),url),'justo-mx')
        self.assertEqual(row['raw_payload']['evidence']['stock_level'],5)
        for key,value in [('stockLevel',0),('stockLevel',True),('availability',False)]:
            changed=deepcopy(state);changed['props']['pageProps']['product'][key]=value
            with self.subTest(key=key),self.assertRaises(ValueError):
                parse_page(response(html(product,changed),url),'justo-mx')

    def test_vtex_chedraui_is_attributed_to_its_own_source(self):
        p=vtex();p['link']='https://www.chedraui.com.mx/leche-fixture/p'
        rows,errors=parse_vtex(response(json.dumps([p]),'https://www.chedraui.com.mx/api/catalog_system/pub/products/search/leche'),
                               'MXN',1,source='chedraui-mx')
        self.assertFalse(errors);self.assertEqual(rows[0]['store_slug'],'chedraui-online')

    def test_scorpion_discovery_requires_product_card_and_official_origin(self):
        text = ('<a href="https://www.scorpion.com.mx/tienda/categoria.html">category</a>'
            '<a class="product-item-link" href="https://www.scorpion.com.mx/tienda/leche-fixture.html">product</a>'
            '<a class="product-item-link" href="https://evil.test/tienda/leche.html">external</a>')
        self.assertEqual(product_links(text, 'scorpion-mx'),
                         ['https://www.scorpion.com.mx/tienda/leche-fixture.html'])

    def test_justo_corroborates_stock_price_and_unit_with_storefront(self):
        product = {'@type':'Product','name':'Leche Fixture 1 l','sku':'123',
            'offers':{'@type':'Offer','price':30,'priceCurrency':'MXN','availability':'InStock'}}
        state = {'props':{'pageProps':{'product':{'id':'123','name':'Leche Fixture 1 l',
            'price':30,'isAvailable':True,'onSale':False,'variants':[{'isPiece':True}]}}}}
        r = response(html(product,state),'https://justo.mx/product/leche-fixture-123')
        row = parse_page(r,'justo-mx')
        self.assertEqual(row['price'],30)
        for key,value in [('price',31),('isAvailable',False),('id','other'),
                          ('onSale',True),('variants',[{'isPiece':False}])]:
            changed = deepcopy(state); changed['props']['pageProps']['product'][key]=value
            with self.subTest(key=key), self.assertRaises(ValueError):
                parse_page(response(html(product,changed),r.url),'justo-mx')

    def test_shared_compro_feed_keeps_size_and_unavailable_items_without_admin_settings(self):
        data = {'settings':{'currencyCode':'MXN','adminPin':'never-ingest-fixture'},
            'categories':[{'id':'food','name':'Alimentos'}], 'products':[
                {'id':'a','name':'Leche Fixture','gramaje':'1 l','price':30,'available':True,'categoryId':'food'},
                {'id':'b','name':'Leche Fixture','gramaje':'500 ml','price':20,'available':False,'categoryId':'food'}]}
        r = response(json.dumps(data),'https://www.comprov.com.mx/productos-precios.json')
        rows, errors = parse_compro(r,15)
        self.assertFalse(errors); self.assertEqual(len(rows),2)
        self.assertNotEqual(rows[0]['normalized_name'],rows[1]['normalized_name'])
        self.assertEqual({row['available'] for row in rows},{True,False})
        self.assertEqual({row['store_product_url'] for row in rows},
                         {'https://www.comprov.com.mx/tienda.html'})
        self.assertNotIn('adminPin',json.dumps(rows))
        self.assertEqual(rows[0]['captured_at'],r.observed_at)
        for change in ('currency','duplicate_sku','sales_unit','promotion'):
            changed=deepcopy(data)
            if change=='currency': changed['settings']['currencyCode']='USD'
            elif change=='duplicate_sku': changed['products'][1]['id']='a'
            elif change=='sales_unit': changed['products'][0]['gramaje']='unknown'
            else: changed['products'][0]['salePrice']=10
            with self.subTest(change=change):
                if change in ('currency','duplicate_sku'):
                    with self.assertRaises(ValueError):parse_compro(response(json.dumps(changed),r.url),15)
                else:
                    rows, errors=parse_compro(response(json.dumps(changed),r.url),15)
                    self.assertEqual(len(rows),1);self.assertEqual(len(errors),1)

    def test_declared_spanish_units_preserve_quantity(self):
        for name, expected in [('Arroz 690 gr', '690 g'), ('Azúcar 907 grs', '907 g'),
                               ('Bebida 1 litro', '1 l'), ('Cloro 3.8 lts', '3.8 l'),
                               ('Carne 3.5 kilogramos', '3.5 kg')]:
            with self.subTest(name=name): self.assertEqual(observed_presentation(name), expected)
        with self.assertRaises(ValueError): observed_presentation('Arrachera 1.1')

    def test_piece_spelling_and_original_timestamp_preserved(self):
        r = response(html())
        row = parse_page(r, 'carnemart-mx')
        self.assertEqual(row['presentation'], '8 pzas')
        self.assertEqual(row['observed_at'], r.observed_at)
        self.assertEqual(row['response_sha256'], r.sha256)
        self.assertIsNone(row['branch_id'])

    def test_invalid_money_never_becomes_an_offer(self):
        for value in (True, None, 'NaN', 'Infinity', -1, 0, '1.001'):
            with self.subTest(value=value), self.assertRaises(ValueError):
                money(value)

    def test_unknown_currency_and_availability_are_rejected(self):
        p = json.loads(html().split('>', 1)[1].split('</script>')[0])
        for key, value in [('priceCurrency', 'USD'), ('availability', 'PreOrder'), ('price', True)]:
            q = deepcopy(p); q['offers'][key] = value
            with self.subTest(key=key), self.assertRaises(ValueError):
                parse_page(response(html(q)), 'carnemart-mx')

    def test_unrelated_offer_url_and_ambiguous_offers_are_rejected(self):
        p = json.loads(html().split('>', 1)[1].split('</script>')[0])
        p['offers']['url'] = 'https://carnemart.com/product/different/'
        with self.assertRaises(ValueError): parse_page(response(html(p)), 'carnemart-mx')
        p['offers'].pop('url'); p['offers'] = [p['offers'], deepcopy(p['offers'])]
        with self.assertRaises(ValueError): parse_page(response(html(p)), 'carnemart-mx')

    def test_expired_price_is_rejected(self):
        p = json.loads(html().split('>', 1)[1].split('</script>')[0])
        p['offers']['priceValidUntil'] = (datetime.now(timezone.utc) - timedelta(days=1)).isoformat()
        with self.assertRaises(ValueError): parse_page(response(html(p)), 'carnemart-mx')

    def test_container_weight_in_copy_does_not_define_price_unit(self):
        p = json.loads(html().split('>', 1)[1].split('</script>')[0])
        p['name'] = 'Molida especial en tubo de res'
        p['description'] = 'Viene en un tubo de 3.5 kg'
        with self.assertRaises(ValueError): parse_page(response(html(p)), 'carnemart-mx')

    def test_identical_riqra_cache_entries_are_not_ambiguous(self):
        p, state = riqra()
        state['props']['apolloState'] = deepcopy(state['props']['pageProps'])
        row = parse_page(response(html(p, state), 'https://merco4.tiendariqra.com/p/aceitunas-175-g'), 'merco-rosita-mx')
        self.assertEqual(row['price'], 31.99)
        self.assertNotIn('stock', row)
        self.assertEqual(row['raw_payload']['evidence']['storefront_product']['stock'], 10)

    def test_riqra_stock_conflict_promotion_tax_or_vendor_rejected(self):
        for field, value in [('stock', 0), ('oldPrice', '40.00'), ('price', '32.00'), ('isTaxExempt', False), ('vendor', 'other')]:
            p, state = riqra(); s = state['props']['pageProps']['product']
            if field == 'vendor': state['props']['vendor']['slug'] = value
            elif field == 'stock': s[field] = value
            else: s['pricing'][field] = value
            with self.subTest(field=field), self.assertRaises(ValueError):
                parse_page(response(html(p, state), 'https://merco4.tiendariqra.com/p/aceitunas-175-g'), 'merco-rosita-mx')

    def test_conflicting_cache_entries_require_review(self):
        p, state = riqra(); state['props']['other'] = deepcopy(state['props']['pageProps']['product'])
        state['props']['other']['stock'] = 20
        with self.assertRaises(ValueError):
            parse_page(response(html(p, state), 'https://merco4.tiendariqra.com/p/aceitunas-175-g'), 'merco-rosita-mx')

    def test_links_cannot_leave_approved_catalog(self):
        text = ''.join(f'<a href="{url}">x</a>' for url in [
            '/product/leche-1-l/', 'https://evil.test/product/leche/',
            '//evil.test/product/leche/', '/product/leche-1-l/?cart=1', '/login'])
        self.assertEqual(product_links(text, 'carnemart-mx'), ['https://carnemart.com/product/leche-1-l/'])

    def test_vtex_requires_explicit_mxn_and_bounded_results(self):
        r = response(json.dumps([vtex()]), 'https://www.lagranbodega.com.mx/api/catalog_system/pub/products/search/leche', 206)
        with self.assertRaises(ValueError): parse_vtex(r, None, 10)
        with self.assertRaises(ValueError): parse_vtex(r, 'MXN', 0)
        rows, errors = parse_vtex(r, 'MXN', 10)
        self.assertFalse(errors); self.assertEqual(rows[0]['price'], 27)
        self.assertNotIn('stock', rows[0])  # Sentinel quantity is never advertised as physical stock.

    def test_vtex_rejects_discount_third_party_and_inconsistent_stock(self):
        for kind in ('discount', 'third_party', 'quantity', 'availability', 'url', 'variants', 'expired', 'combined_pack'):
            p = vtex(); offer = p['items'][0]['sellers'][0]['commertialOffer']
            if kind == 'discount': offer['ListPrice'] = 50
            elif kind == 'third_party': p['items'][0]['sellers'][0]['sellerId'] = 'external'
            elif kind == 'quantity': offer['AvailableQuantity'] = True
            elif kind == 'availability': offer['IsAvailable'] = False
            elif kind == 'url': p['link'] = 'https://evil.test/product'
            elif kind == 'variants': p['items'].append(deepcopy(p['items'][0]))
            elif kind == 'expired': offer['PriceValidUntil'] = '2000-01-01T00:00:00Z'
            elif kind == 'combined_pack': p['productName'] = 'Leche 2 piezas 360 g más leche descremada'
            r = response(json.dumps([p]), 'https://www.lagranbodega.com.mx/api/catalog_system/pub/products/search/leche', 206)
            with self.subTest(kind=kind):
                rows, errors = parse_vtex(r, 'MXN', 10)
                self.assertFalse(rows); self.assertEqual(len(errors), 1)

    def test_access_failure_stops_source_and_retains_receipts(self):
        class FailedClient:
            receipts = [{'status': 403}]
            metrics = {'requests': 1}
            def __init__(self): self.requests = []
            def get(self, url):
                self.requests.append(url)
                raise FetchError('Origin stopped at HTTP 403', 403)
        client = FailedClient()
        with tempfile.TemporaryDirectory() as tmp:
            report = capture(Path(tmp) / 'new', ['carnemart-mx'], 8, client)
            self.assertEqual(len(client.requests), 1)
            self.assertEqual(report['sources']['carnemart-mx']['accepted'], 0)
            self.assertFalse(report['published'])
            self.assertTrue((Path(tmp) / 'new/report.json').exists())

    def test_replay_retains_capture_and_rejects_changed_bytes(self):
        home = response('<a href="/product/alimento-8-pzs/">x</a>', 'https://carnemart.com/')
        product = response(html())
        with tempfile.TemporaryDirectory() as tmp:
            original = Path(tmp) / 'original/carnemart-mx'; original.mkdir(parents=True)
            for index, r in enumerate([home, product]):
                stem = original / f'response-{index:03}'
                stem.with_suffix('.txt').write_text(r.text)
                stem.with_suffix('.json').write_text(json.dumps(r.__dict__))
            report = replay(original.parent, Path(tmp) / 'replayed', ['carnemart-mx'], 10)
            row = json.loads((Path(tmp) / 'replayed/carnemart-mx/observations.ndjson').read_text())
            self.assertEqual(row['captured_at'], product.observed_at)
            self.assertEqual(report['requests'], 0)
            (original / 'response-001.txt').write_text('tampered')
            report = replay(original.parent, Path(tmp) / 'changed', ['carnemart-mx'], 10)
            self.assertEqual(report['sources']['carnemart-mx']['accepted'], 0)
            self.assertIn('SHA256', report['sources']['carnemart-mx']['failure'])


class TransportTests(unittest.TestCase):
    def retry_client(self, statuses, body=b'[]'):
        class FakeResponse(io.BytesIO):
            headers={'Content-Type':'application/json'}
            def __init__(self,status):
                super().__init__(body);self.status=status
            def geturl(self):return 'https://test.example/products'
        class Opener:
            calls=0
            def open(self,request,timeout):
                status=statuses[self.calls];self.calls+=1
                if isinstance(status,Exception):raise status
                return FakeResponse(status)
        opener=Opener();sleeps=[]
        client=SafeHttpClient(['test.example'],opener=opener,server_retries=2,
            sleep=sleeps.append,resolver=lambda *a,**kw:[(None,None,None,None,('93.184.216.34',443))])
        return client,opener,sleeps

    def test_transient_server_error_retries_with_delay_and_counts_every_attempt(self):
        client,opener,sleeps=self.retry_client([500,200])
        result=client._request('https://test.example/products')
        self.assertEqual(result.status,200)
        self.assertEqual(opener.calls,2)
        self.assertIn(10,sleeps)
        self.assertEqual(client.metrics['requests'],2)
        self.assertEqual(client.metrics['server_retries'],1)
        self.assertEqual([r['status'] for r in client.receipts],[500,200])

    def test_exhausted_server_retries_keep_the_origin_circuit_open(self):
        client,opener,_=self.retry_client([503,503,503])
        with self.assertRaises(FetchError):client._request('https://test.example/products')
        with self.assertRaises(FetchError):client._request('https://test.example/products')
        self.assertEqual(opener.calls,3)
        self.assertEqual(client.metrics['server_retries'],2)

    def test_access_blocks_rate_limits_and_challenges_never_retry(self):
        for status,body in [(403,b'blocked'),(429,b'slow down'),(500,b'captcha challenge')]:
            with self.subTest(status=status,body=body):
                client,opener,sleeps=self.retry_client([status],body)
                with self.assertRaises(FetchError):client._request('https://test.example/products')
                self.assertEqual(opener.calls,1)
                self.assertFalse(sleeps)
                self.assertEqual(client.metrics['server_retries'],0)

    def test_read_timeouts_retry_then_recover_with_request_accounting(self):
        from urllib.error import URLError
        for error in (TimeoutError(), URLError(TimeoutError())):
            with self.subTest(error=type(error).__name__):
                client,opener,sleeps=self.retry_client([error,200])
                self.assertEqual(client._request('https://test.example/products').status,200)
                self.assertEqual(opener.calls,2)
                self.assertEqual(client.metrics['requests'],2)
                self.assertEqual(client.metrics['timeouts'],1)
                self.assertIn(10,sleeps)

    def test_repeated_timeouts_stop_after_two_retries(self):
        client,opener,_=self.retry_client([TimeoutError(),TimeoutError(),TimeoutError()])
        with self.assertRaises(FetchError):client._request('https://test.example/products')
        with self.assertRaises(FetchError):client._request('https://test.example/products')
        self.assertEqual(opener.calls,3)

    def test_timeouts_do_not_retry_posts_or_exceed_request_budget(self):
        client,opener,_=self.retry_client([TimeoutError()])
        with self.assertRaises(FetchError):client._request('https://test.example/products',b'{}')
        self.assertEqual(opener.calls,1)
        client,opener,_=self.retry_client([TimeoutError()])
        client.max_requests=1
        with self.assertRaises(FetchError):client._request('https://test.example/products')
        self.assertEqual(opener.calls,1)

    def client(self, status, allowed=(200,)):
        class FakeResponse(io.BytesIO):
            headers = {'Content-Type': 'application/json', 'Content-Range': 'products 0-0/1'}
            def __init__(self): super().__init__(b'[]'); self.status = status
            def geturl(self): return 'https://test.example/products'
        class Opener:
            def open(self, request, timeout): return FakeResponse()
        client = SafeHttpClient(['test.example'], accepted_statuses=allowed, opener=Opener(),
            resolver=lambda *a, **kw: [(None, None, None, None, ('93.184.216.34', 443))])
        return client

    def test_partial_response_requires_explicit_opt_in(self):
        with self.assertRaises(FetchError): self.client(206)._request('https://test.example/products')
        response = self.client(206, (200, 206))._request('https://test.example/products')
        self.assertEqual(response.status, 206)
        self.assertEqual(response.content_range, 'products 0-0/1')

    def test_auth_or_rate_limit_cannot_be_whitelisted(self):
        for status in (401, 403, 429, 500):
            with self.subTest(status=status), self.assertRaises(ValueError):
                self.client(status, (200, status))

    def test_partial_robots_cannot_authorize_a_product_request(self):
        class Opener:
            calls = 0
            def open(self, request, timeout):
                self.calls += 1
                class PartialRobots(io.BytesIO):
                    status = 206
                    headers = {'Content-Type': 'text/plain'}
                    def geturl(self): return request.full_url
                return PartialRobots(b'User-agent: *\nAllow: /\n')
        opener = Opener()
        client = SafeHttpClient(['test.example'], accepted_statuses=(200, 206), opener=opener,
            resolver=lambda *a, **kw: [(None, None, None, None, ('93.184.216.34', 443))])
        with self.assertRaises(FetchError): client.get('https://test.example/products')
        self.assertEqual(opener.calls, 1)


if __name__ == '__main__': unittest.main()
