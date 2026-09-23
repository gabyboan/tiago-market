"""Synthetic parser fixtures, never used as publication input."""
import json
import unittest

from merco_online_scraper import DEFAULT_URLS, parse_product, product_url

URL = DEFAULT_URLS[0]
NOW = '2026-09-23T15:00:00+00:00'


def page(**changes):
    product = {
        '@type': 'Product', 'name': 'Fixture Leche Entera 1 Lto.',
        'url': URL, 'sku': '10248783',
        'offers': [{'@type': 'Offer', 'price': '31.00', 'priceCurrency': 'MXN',
                    'availability': 'InStock'}],
    }
    product.update(changes)
    return '<script type="application/ld+json">' + json.dumps([
        product, {'@type': 'BreadcrumbList', 'itemListElement': [
            {'name': 'Leche', 'item': 'https://adomicilio.merco.mx/c/leche'},
            {'name': product['name']},
        ]},
    ]) + '</script>'


def parse(html=None, observed=NOW):
    return parse_product(html or page(), URL, observed, 'a' * 64)


class MercoTest(unittest.TestCase):
    def test_online_contract_and_original_evidence(self):
        row = parse()
        self.assertEqual(row['price_scope'], 'online')
        self.assertEqual(row['presentation'], '1 l')
        self.assertEqual(row['category'], 'Leche')
        self.assertEqual(row['observed_at'], NOW)
        self.assertEqual(row['captured_at'], NOW)
        self.assertEqual(row['source_url'], URL)
        self.assertEqual(row['raw_payload']['json_ld_product']['offers'][0]['price'], '31.00')
        self.assertIsNone(row['latitude'])
        self.assertIsNone(row['branch_external_key'])

    def test_replay_deduplicates_but_new_capture_refreshes(self):
        self.assertEqual(parse()['content_hash'], parse()['content_hash'])
        self.assertNotEqual(parse()['content_hash'], parse(observed='2026-09-24T15:00:00+00:00')['content_hash'])

    def test_identity_mismatch(self):
        for changes in [{'sku': 'other'}, {'url': URL + '-other'}]:
            with self.assertRaisesRegex(ValueError, 'mismatch'):
                parse(page(**changes))

    def test_reject_unverified_offers(self):
        base = {'@type': 'Offer', 'price': '31', 'priceCurrency': 'MXN', 'availability': 'InStock'}
        for change in [{'price': 'NaN'}, {'price': 'inf'}, {'price': 0}, {'price': True},
                       {'priceCurrency': 'USD'}, {'availability': 'OutOfStock'},
                       {'availability': None}, {'availability': 'https://evil.test/InStock'},
                       {'priceValidUntil': '2026-06-01'}]:
            with self.subTest(change=change), self.assertRaises(ValueError):
                parse(page(offers=[base | change]))
        with self.assertRaises(ValueError):
            parse(page(offers=[base, base]))
        with self.assertRaises(ValueError):
            parse(page() + page())

    def test_no_invented_presentation_or_collapsed_pack(self):
        for name in ['Fixture milk', 'Fixture Leche 1 L C/6', 'Fixture Pack 6 Leches 1 L']:
            with self.assertRaises(ValueError):
                parse(page(name=name))
        self.assertEqual(parse(page(name='Fixture arroz 906 Gr'))['presentation'], '906 g')
        self.assertEqual(parse(page(name='Fixture leche 6 x 1 Lt'))['presentation'], '6 x 1 l')

    def test_url_allowlist(self):
        self.assertTrue(product_url(URL))
        for url in ['http://adomicilio.merco.mx/p/milk-123', URL + '?x=1',
                    'https://adomicilio.merco.mx.evil.test/p/milk-123',
                    'https://adomicilio.merco.mx/login', URL + '#other']:
            self.assertFalse(product_url(url))


if __name__ == '__main__':
    unittest.main()
