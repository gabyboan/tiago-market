"""Integrity tests for full public feeds, images, pagination and minor units."""
from copy import deepcopy
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

from expand_grocery_sources import parse_compro, parse_page, catalog_projection
from expand_grocery_sources import observed_presentation
from expand_grocery_sources import parse_vtex
from refresh_grocery_catalogs import parse_woo_product, parse_shopify_product, capture_source
from retail.transport import HttpResponse, FetchError


def response(data, url='https://superfenix.mx/wp-json/wc/store/v1/products'):
    body = data if isinstance(data,str) else json.dumps(data)
    return HttpResponse(url,200,body,datetime.now(timezone.utc).isoformat(),
                        hashlib.sha256(body.encode()).hexdigest(),'application/json')


def woo():
    return {'id':1,'sku':'fixture','name':'Arroz Fixture 500 g','type':'simple',
            'permalink':'https://superfenix.mx/producto/arroz-fixture/',
            'has_options':False,'is_in_stock':False,'is_on_backorder':False,
            'is_password_protected':False,'on_sale':False,
            'prices':{'currency_code':'MXN','currency_minor_unit':2,
                      'price':'1250','regular_price':'1250'},
            'images':[{'id':10,'src':'https://superfenix.mx/wp-content/uploads/arroz.jpg'}]}


class BulkIntegrityTests(unittest.TestCase):
    def test_vtex_weight_multiplier_is_held_before_pricing_it_as_a_piece(self):
        from test_expand_grocery_sources import vtex
        p=vtex();p['items'][0].update(measurementUnit='kg',unitMultiplier=.5)
        rows,issues=parse_vtex(response([p],'https://www.lagranbodega.com.mx/api/catalog_system/pub/products/search'),'MXN',50)
        self.assertFalse(rows);self.assertIn('price unit',issues[0]['reason'])

    def test_pack_does_not_silently_become_one_container(self):
        self.assertEqual(observed_presentation('Leche Marca 6 pack 1 l c/u'),'6 x 1 l')
        for name in ('Cerveza Marca 12 pack 355 ml','Yakult 40 Lt 5 pack 80 ml',
                     'Doritos 10 pack 500 g','8PACK RAZOR REGALO 1PZ DE 100G'):
            with self.subTest(name=name),self.assertRaises(ValueError):observed_presentation(name)

    def test_full_compro_includes_all_unavailable_and_reports_invalid_entries(self):
        data={'settings':{'currencyCode':'MXN','adminPin':'never-store'},
              'categories':[{'id':'food','name':'Alimentos'}],
              'products':[{'id':str(i),'name':f'Arroz Marca {i}','gramaje':'500 g','price':12.5,
                           'available':i%2==0,'categoryId':'food'} for i in range(40)]}
        rows,issues=parse_compro(response(data,'https://www.comprov.com.mx/productos-precios.json'),10000)
        self.assertEqual(len(rows),40);self.assertEqual(sum(not r['available'] for r in rows),20)
        self.assertFalse(issues)
        data['products'][0]['available']='true'
        rows,issues=parse_compro(response(data,'https://www.comprov.com.mx/productos-precios.json'),10000)
        self.assertEqual(len(rows),39);self.assertEqual(len(issues),1)
        self.assertNotIn('adminPin',json.dumps(catalog_projection(json.dumps(data))))

    def test_compro_shared_link_never_merges_two_skus_with_identical_name_pack(self):
        data={'settings':{'currencyCode':'MXN'},'categories':[{'id':'food','name':'Alimentos'}],
              'products':[{'id':sku,'name':'Arroz Marca','gramaje':'500 g','price':12.5,
                           'available':True,'categoryId':'food'} for sku in ['a','b']]}
        rows,issues=parse_compro(response(data,'https://www.comprov.com.mx/productos-precios.json'),10000)
        self.assertFalse(rows);self.assertEqual(len(issues),2)

    def test_woo_minor_unit_price_and_explicit_out_of_stock_are_preserved(self):
        p=woo();r=response([p]);item=parse_woo_product(p,r,'fenix-mx')
        self.assertEqual(item['price'],12.5);self.assertFalse(item['available'])
        self.assertEqual(item['captured_at'],r.observed_at)
        for path,value in [('currency_minor_unit',0),('price','12.50'),('currency_code','USD')]:
            q=deepcopy(p);q['prices'][path]=value
            with self.subTest(path=path),self.assertRaises(ValueError):parse_woo_product(q,r,'fenix-mx')
        for path,value in [('on_sale',True),('is_in_stock',None),('is_on_backorder',True),
                           ('type','variable'),('has_options',True),('is_password_protected',True)]:
            q=deepcopy(p);q[path]=value
            with self.subTest(path=path),self.assertRaises(ValueError):parse_woo_product(q,r,'fenix-mx')

    def test_meat_case_price_cannot_be_assumed_to_buy_the_full_case(self):
        p=woo();p.update(name='Molida de res Caja 16 kg',permalink='https://carnemart.com/product/molida/')
        with self.assertRaises(ValueError):parse_woo_product(p,response([p],'https://carnemart.com/wp-json/wc/store/v1/products'),'carnemart-mx')

    def test_shopify_decimal_price_and_matching_product_photo(self):
        p={'id':2,'handle':'arroz-fixture','title':'ARROZ 20/500 GR',
           'variants':[{'id':10,'product_id':2,'title':'pieza 1 a 19','price':'12.50','available':False}],
           'images':[{'product_id':999,'src':'https://cdn.shopify.com/wrong.jpg'},
                     {'product_id':2,'variant_ids':[99],'src':'https://cdn.shopify.com/wrong-variant.jpg'},
                     {'product_id':2,'variant_ids':[],'src':'https://cdn.shopify.com/correct.jpg'}]}
        r=response({'products':[p]},'https://garis.mayoreoenlinea.mx/products.json?limit=250&page=1')
        item=parse_shopify_product(p,r,'MXN','garis-mx')
        self.assertEqual(item['price'],12.5);self.assertFalse(item['available'])
        self.assertEqual(item['image_url'],'https://cdn.shopify.com/correct.jpg')
        p['variants'][0]['product_id']=3
        with self.assertRaises(ValueError):parse_shopify_product(p,r,'MXN','garis-mx')

    def test_scorpion_gallery_fallback_ignores_related_cards_and_placeholder(self):
        p={'@type':'Product','name':'Arroz Fixture 500 g','sku':'fixture',
           'offers':{'@type':'Offer','price':'12.5','priceCurrency':'MXN','availability':'InStock'}}
        body='<script type="application/ld+json">'+json.dumps(p)+'</script>'
        body+='<img class="product-card" src="https://www.scorpion.com.mx/pub/media/catalog/product/wrong.jpg">'
        body+='<img class="lazyload gallery-placeholder__image" src="data:image/svg+xml,placeholder" data-src="https://www.scorpion.com.mx/pub/media/catalog/product/correct.jpg">'
        item=parse_page(response(body,'https://www.scorpion.com.mx/tienda/arroz-fixture.html'),'scorpion-mx')
        self.assertEqual(item['image_url'],'https://www.scorpion.com.mx/pub/media/catalog/product/correct.jpg')
        body+='<img class="gallery-placeholder__image" data-src="https://www.scorpion.com.mx/pub/media/catalog/product/ambiguous.jpg">'
        self.assertIsNone(parse_page(response(body,'https://www.scorpion.com.mx/tienda/arroz-fixture.html'),'scorpion-mx')['image_url'])

    def test_pagination_stops_at_a_repeated_page_without_duplicate_offers(self):
        class Client:
            receipts=[];metrics={}
            def get(self,url):return response([woo()],url)
        with tempfile.TemporaryDirectory() as tmp,patch('refresh_grocery_catalogs.SafeHttpClient',return_value=Client()):
            report=capture_source('fenix-mx',Path(tmp)/'capture',max_pages=3,page_size=1)
        self.assertEqual(report['accepted'],1)
        self.assertIn('Repeated page',report['failure'])
        self.assertFalse(report['full_catalog_traversed'])

    def test_removed_product_does_not_stop_remaining_html_products(self):
        from test_expand_grocery_sources import html
        class Client:
            receipts=[];metrics={}
            def get(self,url):
                if url.endswith('/'):return response('<html></html>',url)
                if url.endswith('removed.html'):raise FetchError('Unexpected HTTP 404',404)
                return response(html({'@type':'Product','name':'Arroz Fixture 500 g','sku':'fixture',
                    'offers':{'@type':'Offer','price':12.5,'priceCurrency':'MXN','availability':'InStock'}}),url)
        seeds=['https://www.scorpion.com.mx/tienda/removed.html','https://www.scorpion.com.mx/tienda/valid.html']
        with tempfile.TemporaryDirectory() as tmp,patch('refresh_grocery_catalogs.SafeHttpClient',return_value=Client()):
            report=capture_source('scorpion-mx',Path(tmp)/'capture',seeds=seeds)
        self.assertEqual(report['accepted'],1);self.assertEqual(len(report['rejected']),1)
        self.assertIsNone(report['failure'])

    def test_scheduled_html_refresh_requests_only_previously_reviewed_urls(self):
        from test_expand_grocery_sources import html
        url='https://www.scorpion.com.mx/tienda/valid.html'
        requested=[]
        class Client:
            receipts=[];metrics={}
            def get(self,target):
                requested.append(target)
                if target != url:raise AssertionError('Unexpected discovery request')
                return response(html({'@type':'Product','name':'Arroz Fixture 500 g','sku':'fixture',
                    'offers':{'@type':'Offer','price':12.5,'priceCurrency':'MXN','availability':'InStock'}}),target)
        with tempfile.TemporaryDirectory() as tmp,patch('refresh_grocery_catalogs.SafeHttpClient',return_value=Client()):
            report=capture_source('scorpion-mx',Path(tmp)/'capture',seeds=[url],known_only=True)
        self.assertEqual(requested,[url])
        self.assertEqual(report['accepted'],1)
        self.assertIsNone(report['failure'])


if __name__=='__main__':unittest.main()
