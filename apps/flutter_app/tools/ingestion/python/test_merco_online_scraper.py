"""Synthetic parser fixtures, never used as publication input."""
import json
from io import BytesIO
from pathlib import Path
from tempfile import TemporaryDirectory
import unittest
from unittest.mock import Mock, patch
from urllib.error import HTTPError, URLError

from merco_online_scraper import (
    Capture, DEFAULT_URLS, ORIGIN, main, parse_product, product_url, reviewed_urls,
)

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


class FixtureCapture:
    """No HTTP: an unexpected request fails instead of falling back to a site."""

    def __init__(self, pages):
        self.pages = pages
        self.requests = []
        self.count = 0
        self.delay = 5

    def get(self, url):
        self.requests.append(url)
        self.count += 1
        value = self.pages[url]
        if isinstance(value, Exception):
            raise value
        return value, {'content_type': 'text/html', 'observed_at': NOW,
                       'sha256': 'a' * 64}


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

    def test_explicit_unavailable_offer_refreshes_stock_and_hash(self):
        for prefix in ['', 'https://schema.org/', 'http://schema.org/']:
            with self.subTest(prefix=prefix):
                offer = {'@type': 'Offer', 'price': '31', 'priceCurrency': 'MXN',
                         'availability': prefix + 'OutOfStock'}
                unavailable = parse(page(offers=[offer]))
                self.assertIs(unavailable['available'], False)
                self.assertNotEqual(unavailable['content_hash'], parse()['content_hash'])
                self.assertEqual(unavailable['content_hash'], parse(page(offers=[offer]))['content_hash'])
                offer['availability'] = prefix + 'InStock'
                self.assertIs(parse(page(offers=[offer]))['available'], True)

    def test_identity_mismatch(self):
        for changes in [{'sku': 'other'}, {'url': URL + '-other'}]:
            with self.assertRaisesRegex(ValueError, 'mismatch'):
                parse(page(**changes))

    def test_reject_unverified_offers(self):
        base = {'@type': 'Offer', 'price': '31', 'priceCurrency': 'MXN', 'availability': 'InStock'}
        for change in [{'price': 'NaN'}, {'price': 'inf'}, {'price': 0}, {'price': True},
                       {'priceCurrency': 'USD'}, {'availability': 'PreOrder'},
                       {'availability': None}, {'availability': 'https://evil.test/InStock'},
                       {'availability': 'https://evil.test/OutOfStock'},
                       {'availability': 'https://schema.org/OutOfStock?fake=1'},
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

    def test_combined_presentations_are_not_reduced_to_first_quantity(self):
        for name in ['Fixture shampoo 1900 ml + 100 ml',
                     'Fixture leche 1 L + 250 ml',
                     'Fixture shampoo 1900 ml acondicionador 100 ml']:
            with self.subTest(name=name), self.assertRaisesRegex(
                    ValueError, 'Ambiguous combined presentation'):
                parse(page(name=name))

    def test_images_preserve_only_official_product_url(self):
        image = ('https://res.cloudinary.com/riqra/image/upload/v1/'
                 'merco-monterrey/products/fixture.jpg')
        self.assertEqual(parse(page(image=image))['image_url'], image)
        for unverified in [image + '?proxy=1', image + '#fragment',
                           image.replace('res.cloudinary.com', 'res.cloudinary.com.evil.test'),
                           image.replace('/merco-monterrey/', '/other-retailer/'),
                           image.replace('https:', 'http:'), [image], None]:
            with self.subTest(image=unverified):
                self.assertIsNone(parse(page(image=unverified))['image_url'])

    def test_url_allowlist(self):
        self.assertTrue(product_url(URL))
        for url in ['http://adomicilio.merco.mx/p/milk-123', URL + '?x=1',
                    'https://adomicilio.merco.mx.evil.test/p/milk-123',
                    'https://adomicilio.merco.mx/login', URL + '#other']:
            self.assertFalse(product_url(url))


class ReviewedCatalogTest(unittest.TestCase):
    def run_main(self, urls, pages, limit=300):
        with TemporaryDirectory() as folder:
            folder = Path(folder)
            inputs, output = folder / 'urls.json', folder / 'capture.ndjson'
            inputs.write_text(json.dumps(urls))
            capture = FixtureCapture(pages)
            argv = ['merco_online_scraper.py', '--urls', str(inputs),
                    '--out', str(output), '--limit', str(limit)]
            exit_code = 0
            with patch('merco_online_scraper.Capture', return_value=capture), \
                    patch('sys.argv', argv), patch('builtins.print'):
                try:
                    main()
                except SystemExit as error:
                    exit_code = error.code
            report = json.loads(Path(str(output) + '.evidence/report.json').read_text())
            rows = [json.loads(line) for line in output.read_text().splitlines()]
            return rows, report, capture.requests, exit_code

    def test_known_urls_deduplicate_by_sku_and_obey_limit(self):
        alias = URL.replace('leche-fresca-lala-entera', 'leche-alias')
        self.assertEqual(reviewed_urls([URL, URL, alias, DEFAULT_URLS[1]], 300),
                         [URL, DEFAULT_URLS[1]])
        self.assertEqual(reviewed_urls(DEFAULT_URLS, 1), DEFAULT_URLS[:1])
        many = [ORIGIN + f'/p/fixture-{sku}' for sku in range(301)]
        self.assertEqual(reviewed_urls(many, 300), many[:300])
        for limit in [0, 301]:
            with self.subTest(limit=limit), self.assertRaisesRegex(ValueError, '1..300'):
                reviewed_urls(DEFAULT_URLS, limit)
        for values in [[], {}, [URL, ORIGIN + '/login'], [None], 'https://evil.test/']:
            with self.subTest(values=values), self.assertRaises(ValueError):
                reviewed_urls(values, 300)

    def test_fetches_only_known_products_without_following_related_links(self):
        rows, report, requests, exit_code = self.run_main([URL, URL], {
            ORIGIN + '/robots.txt': 'User-agent: *\nDisallow:',
            URL: page() + '<a href="/p/new-product-101">Related product</a>',
        })
        self.assertEqual(requests, [ORIGIN + '/robots.txt', URL])
        self.assertEqual(len(rows), 1)
        self.assertEqual(report['accepted'], 1)
        self.assertEqual(report['attempted_product_pages'], 1)
        self.assertEqual(report['requested_product_pages'], 1)
        self.assertEqual(report['duplicate_rows'], 0)
        self.assertIsNone(report['failure'])
        self.assertEqual(exit_code, 0)

    def test_stop_retains_valid_rows_and_counts_failed_product_request(self):
        first, second, third = DEFAULT_URLS[:3]
        rows, report, requests, exit_code = self.run_main([first, second, third], {
            ORIGIN + '/robots.txt': 'User-agent: *\nDisallow:',
            first: page(), second: RuntimeError('Stopped: HTTP 429'),
        })
        self.assertEqual(requests, [ORIGIN + '/robots.txt', first, second])
        self.assertEqual(len(rows), 1)
        self.assertEqual(report['accepted'], 1)
        self.assertEqual(report['attempted_product_pages'], 2)
        self.assertEqual(report['requests'], 3)
        self.assertEqual(report['requested_product_pages'], 3)
        self.assertEqual(report['failure'], 'Stopped: HTTP 429')
        self.assertFalse(report['target_reached'])
        self.assertEqual(exit_code, 1)

    def test_robots_blocks_product_before_request(self):
        rows, report, requests, exit_code = self.run_main([URL], {
            ORIGIN + '/robots.txt': 'User-agent: *\nDisallow: /p/',
        })
        self.assertEqual(requests, [ORIGIN + '/robots.txt'])
        self.assertEqual(rows, [])
        self.assertEqual(report['attempted_product_pages'], 0)
        self.assertIn('robots.txt disallows', report['failure'])
        self.assertEqual(exit_code, 1)

    def test_invalid_product_is_rejected_and_valid_product_is_preserved(self):
        invalid = DEFAULT_URLS[1]
        rows, report, requests, exit_code = self.run_main([invalid, URL], {
            ORIGIN + '/robots.txt': 'User-agent: *\nDisallow:',
            invalid: '<html>Fixture without product evidence</html>', URL: page(),
        })
        self.assertEqual(requests, [ORIGIN + '/robots.txt', invalid, URL])
        self.assertEqual(len(rows), 1)
        self.assertEqual(report['accepted'], 1)
        self.assertEqual(report['attempted_product_pages'], 2)
        self.assertEqual(len(report['rejected']), 1)
        self.assertEqual(report['rejected'][0]['url'], invalid)
        self.assertIsNone(report['failure'])
        self.assertEqual(exit_code, 1)


class CaptureStopTest(unittest.TestCase):
    def test_network_failure_is_counted_without_retry(self):
        with TemporaryDirectory() as folder:
            capture = Capture(Path(folder), 0)
            capture.opener = Mock()
            capture.opener.open.side_effect = URLError('Fixture timeout')
            with patch('merco_online_scraper.time.sleep'), self.assertRaises(URLError):
                capture.get(URL)
            self.assertEqual(capture.opener.open.call_count, 1)
            self.assertEqual(capture.count, 1)
            receipt = json.loads((Path(folder) / 'request-001.json').read_text())
            self.assertEqual(receipt['url'], URL)
            self.assertIsNone(receipt['status'])
            self.assertIn('Fixture timeout', receipt['error'])

    def test_redirect_and_access_errors_stop_without_retry_and_keep_receipt(self):
        for status in [302, 403, 429, 503]:
            with self.subTest(status=status), TemporaryDirectory() as folder:
                body = b'Fixture blocked response'
                capture = Capture(Path(folder), 0)
                capture.opener = Mock()
                capture.opener.open.side_effect = HTTPError(
                    URL, status, 'Fixture HTTP error', {'Content-Type': 'text/html'},
                    BytesIO(body))
                with patch('merco_online_scraper.time.sleep'), self.assertRaisesRegex(
                        RuntimeError, f'HTTP {status}'):
                    capture.get(URL)
                self.assertEqual(capture.opener.open.call_count, 1)
                self.assertEqual(capture.count, 1)
                receipt = json.loads((Path(folder) / 'request-001.json').read_text())
                self.assertEqual(receipt['status'], status)
                self.assertEqual((Path(folder) / 'request-001.body').read_bytes(), body)
                self.assertGreaterEqual(capture.delay, 5)

    def test_successful_http_challenge_still_stops_without_retry(self):
        with TemporaryDirectory() as folder:
            response = BytesIO(b'<html>Fixture captcha challenge</html>')
            response.status = 200
            response.headers = {'Content-Type': 'text/html'}
            capture = Capture(Path(folder), 0)
            capture.opener = Mock()
            capture.opener.open.return_value = response
            with patch('merco_online_scraper.time.sleep'), self.assertRaisesRegex(
                    RuntimeError, 'access challenge'):
                capture.get(URL)
            self.assertEqual(capture.opener.open.call_count, 1)
            self.assertEqual(capture.count, 1)


if __name__ == '__main__':
    unittest.main()
