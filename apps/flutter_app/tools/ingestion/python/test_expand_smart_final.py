"""Offline discovery and failure contracts; fixtures are never published."""
from collections import Counter
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import tempfile
import unittest

from expand_smart_final import ORIGIN, capture, observation, product_links
from retail.transport import FetchError, HttpResponse


def response(url, text):
    return HttpResponse(url, 200, text, datetime.now(timezone.utc).isoformat(),
                        hashlib.sha256(text.encode()).hexdigest(), 'text/html')


def fixture(product_url, **changes):
    product = {'@type': 'Product', 'name': 'Fixture arroz 1 kg', 'url': product_url,
               'offers': {'@type': 'Offer', 'price': 45, 'priceCurrency': 'MXN',
                          'availability': 'https://schema.org/InStock', 'url': product_url}}
    product['offers'].update(changes)
    return '<script type="application/ld+json">' + json.dumps(product) + '</script>'


class ExpansionTest(unittest.TestCase):
    def test_discovery_filters_external_and_unrelated_links(self):
        html = ''.join(f'<a href="{url}">rice</a>' for url in (
            '/tienda/abarrotes/arroz/', '/tienda/abarrotes/arroz/',
            'https://attacker.test/tienda/abarrotes/arroz/',
            '/tienda/abarrotes/arroz/?buy=1', '/tienda/abarrotes/arroz/#other',
            '/categoria-producto/abarrotes/', '/tienda/abarrotes/'))
        self.assertEqual(product_links(html), [ORIGIN + '/tienda/abarrotes/arroz/'])

    def test_wrong_product_offer_and_boolean_price_rejected(self):
        url = ORIGIN + '/tienda/abarrotes/arroz/'
        for changes in ({'url': ORIGIN + '/tienda/abarrotes/other/'}, {'price': True},
                        {'priceValidUntil': '2020-01-01'}):
            with self.assertRaises(ValueError):
                observation(response(url, fixture(url, **changes)))

    def test_keeps_timestamp_hash_and_original_evidence(self):
        url = ORIGIN + '/tienda/abarrotes/arroz/'
        receipt = response(url, fixture(url))
        row = observation(receipt)
        self.assertEqual(row['observed_at'], receipt.observed_at)
        self.assertEqual(row['raw_payload']['response_sha256'], receipt.sha256)
        self.assertEqual(row['raw_payload']['json_ld_product']['url'], url)
        self.assertEqual(row['price_scope'], 'online')

    def test_stop_retains_partial_evidence_without_publication(self):
        class Client:
            receipts = []
            metrics = Counter()
            def get(self, url):
                if '/categoria-producto/' in url:
                    return response(url, '<a href="/tienda/abarrotes/arroz/">rice</a>'
                                    '<a href="/tienda/abarrotes/other/">other</a>')
                if '/other/' in url:
                    raise FetchError('Origin stopped at HTTP 403', 403)
                return response(url, fixture(url))
        with tempfile.TemporaryDirectory() as root:
            folder = Path(root) / 'capture'
            report = capture(folder, ('abarrotes',), 2, Client())
            self.assertEqual(report['accepted'], 1)
            self.assertEqual(report['status'], 'partial')
            self.assertFalse(report['published'])
            self.assertIn('403', report['failure'])
            self.assertEqual(len(list(folder.glob('page-*.html'))), 2)
            self.assertTrue((folder / 'publish.sql').exists())
            with self.assertRaises(FileExistsError):
                capture(folder, ('abarrotes',), 2, Client())


if __name__ == '__main__':
    unittest.main()
