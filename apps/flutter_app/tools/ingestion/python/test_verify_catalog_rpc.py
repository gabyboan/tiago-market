"""Offline RPC contract tests: fixtures can never reach the network."""
import copy
from io import BytesIO, StringIO
import json
from pathlib import Path
from tempfile import TemporaryDirectory
import unittest
from unittest.mock import patch
from urllib.error import HTTPError

from verify_catalog_rpc import RPCError, main, verify

CONFIG = {'SUPABASE_URL': 'https://fixture.invalid',
          'SUPABASE_PUBLISHABLE_KEY': 'fixture-public-key'}
NOW = '2026-09-29T12:00:00Z'


def row(index=0, source='chedraui-mx', name='Leche Fixture 1 l', **changes):
    return {'source': source, 'store_product_url': f'https://fixture.invalid/p/{index}',
            'product_name': name, 'normalized_name': name.lower(),
            'branch_id': None, 'branch_name': None, 'branch_address': None,
            'branch_municipality': None, 'distance_km': None,
            'price': 20.5, 'currency': 'MXN', 'available': True,
            'captured_at': NOW} | changes


class FakeRPC:
    def __init__(self, rows, transform=None):
        self.rows = rows
        self.transform = transform
        self.requests = []

    def __call__(self, request, timeout):
        self.assert_request(request, timeout)
        params = json.loads(request.data)
        self.requests.append(params)
        query = params['search_query']
        filtered = [row for row in self.rows if any(
            query in str(row.get(field, '')).lower()
            for field in ('product_name', 'normalized_name'))]
        offset = (params['page_number'] - 1) * params['limit_count']
        rows = filtered[offset:offset + params['limit_count']]
        if self.transform:
            rows = self.transform(params, rows)
        return BytesIO(json.dumps(rows).encode())

    @staticmethod
    def assert_request(request, timeout):
        assert request.full_url == CONFIG['SUPABASE_URL'] + '/rest/v1/rpc/online_prices_v4'
        assert request.get_header('Apikey') == CONFIG['SUPABASE_PUBLISHABLE_KEY']
        assert timeout == 20
        params = json.loads(request.data)
        assert params['only_available'] is False
        assert params['limit_count'] == 100


class CatalogRPCVerificationTest(unittest.TestCase):
    def verify_rows(self, rows, expected=None, transform=None):
        rpc = FakeRPC(rows, transform)
        with patch('verify_catalog_rpc.urlopen', side_effect=rpc):
            return verify(CONFIG, expected), rpc

    def test_all_pages_and_both_sources_include_out_of_stock(self):
        rows = [row(i, source='chedraui-mx' if i < 201 else 'merco-mx',
                    name='Leche Fixture 1 l' if i % 2 else 'Arroz Fixture 1 kg',
                    available=i not in (200, 270)) for i in range(271)]
        report, rpc = self.verify_rows(rows, rows)
        self.assertTrue(report['passed'], report['errors'])
        self.assertEqual(report['expected_matched'], 271)
        self.assertEqual(len(report['online']), 271)
        self.assertEqual([c['count'] for c in report['calls'] if not c['params']['search_query']],
                         [100, 100, 71, 0])
        self.assertEqual(report['by_source']['chedraui-mx']['current'], 201)
        self.assertEqual(report['by_source']['merco-mx']['current'], 70)
        for source in ('chedraui-mx', 'merco-mx'):
            summary = report['by_source'][source]
            self.assertEqual(summary['unavailable'], 1)
            self.assertEqual(summary['latest_captured_at'], NOW)
            self.assertGreater(summary['searches']['leche'], 0)
            self.assertGreater(summary['searches']['arroz'], 0)
        for query in ('', 'leche', 'arroz'):
            calls = [c for c in report['calls'] if c['params']['search_query'] == query]
            self.assertEqual(calls[-1]['count'], 0)
        self.assertEqual(len(rpc.requests), len(report['calls']))

    def test_exact_match_uses_source_and_url_and_preserves_timestamp(self):
        rows = [row(source='chedraui-mx'), row(source='merco-mx', price=30)]
        expected = copy.deepcopy(rows)
        expected[0]['price'] = '20.50'
        expected[0]['captured_at'] = '2026-09-29T09:00:00-03:00'
        expected[1]['observed_at'] = expected[1].pop('captured_at')
        before = copy.deepcopy(expected)
        report, _ = self.verify_rows(rows, expected)
        self.assertTrue(report['passed'], report['errors'])
        self.assertEqual(report['expected_matched'], 2)
        self.assertEqual(expected, before)
        self.assertEqual(report['online'][0]['captured_at'], NOW)
        json.dumps(report)  # Report is directly writable to the execution evidence.

    def test_image_backfill_is_verified_and_wrong_product_photo_fails(self):
        actual=row(image_url='https://fixture.invalid/correct.jpg')
        expected=row(image_url='https://fixture.invalid/wrong.jpg')
        report,_=self.verify_rows([actual],[expected])
        self.assertFalse(report['passed'])
        self.assertIn('image_url',str(report['errors']))
        report,_=self.verify_rows([actual],[actual])
        self.assertTrue(report['passed'])
        self.assertEqual(report['by_source']['chedraui-mx']['images'],1)

    def test_mismatch_price_currency_availability_and_time_fail(self):
        for field, value in [('price', 31), ('currency', 'USD'), ('available', False),
                             ('captured_at', '2026-09-29T12:00:01Z')]:
            with self.subTest(field=field):
                report, _ = self.verify_rows([row()], [row(**{field: value})])
                self.assertFalse(report['passed'])
                self.assertIn(field, '\n'.join(report['errors']))
                self.assertEqual(report['expected_matched'], 0)

    def test_missing_expected_listing_fails(self):
        report, _ = self.verify_rows([row()], [row(1)])
        self.assertFalse(report['passed'])
        self.assertIn('absent from RPC', '\n'.join(report['errors']))

    def test_shared_catalog_url_preserves_distinct_product_identities(self):
        rows = [row(source='catalog-feed', name='Arroz Fixture 1 kg'),
                row(source='catalog-feed', name='Leche Fixture 1 l', available=False)]
        report, _ = self.verify_rows(rows, copy.deepcopy(rows))
        self.assertTrue(report['passed'], report['errors'])
        self.assertEqual(report['expected_matched'], 2)
        self.assertEqual(report['by_source']['catalog-feed']['unavailable'], 1)

    def test_expected_product_name_change_cannot_match_shared_url(self):
        report, _ = self.verify_rows([row()], [row(name='Arroz Fixture 1 kg')])
        self.assertFalse(report['passed'])
        self.assertEqual(report['expected_matched'], 0)

    def test_duplicate_expected_listing_fails(self):
        report, _ = self.verify_rows([row()], [row(), row()])
        self.assertFalse(report['passed'])
        self.assertIn('duplicate source URL', '\n'.join(report['errors']))

    def test_search_must_preserve_matches_in_each_source(self):
        rows = [row(0), row(1, source='merco-mx')]
        report, _ = self.verify_rows(rows, transform=lambda params, page: (
            [item for item in page if item['source'] != 'merco-mx']
            if params['search_query'] == 'leche' else page))
        self.assertFalse(report['passed'])
        self.assertIn('missing matching source URLs', '\n'.join(report['errors']))
        self.assertIn('merco-mx', '\n'.join(report['errors']))

    def test_search_rejects_unrelated_rows(self):
        report, _ = self.verify_rows([row()], transform=lambda params, page: (
            [row()] if params['search_query'] == 'arroz' and params['page_number'] == 1 else page))
        self.assertFalse(report['passed'])
        self.assertIn('unexpected source URLs', '\n'.join(report['errors']))

    def test_online_rows_require_null_branch_and_distance(self):
        for change in [{'branch_id': 'fixture-branch'}, {'distance_km': 1},
                       {'branch_name': 'Invented branch'}]:
            with self.subTest(change=change):
                report, _ = self.verify_rows([row(**change)])
                self.assertFalse(report['passed'])
                self.assertIn('non-null online', '\n'.join(report['errors']))

    def test_empty_expected_is_smoke_without_false_missing_search_failures(self):
        for rows in ([], [row(name='Pasta Fixture 200 g')]):
            with self.subTest(count=len(rows)):
                report, _ = self.verify_rows(rows, [])
                self.assertTrue(report['passed'], report['errors'])
                self.assertEqual(report['mode'], 'smoke')
                self.assertEqual(report['expected_checked'], 0)
                self.assertEqual(set(report['searches']), {'', 'leche', 'arroz'})

    def test_repeated_page_fails_without_unbounded_requests(self):
        report, rpc = self.verify_rows([row()], transform=lambda params, page: (
            [row()] if not params['search_query'] else page))
        self.assertFalse(report['passed'])
        self.assertIn('duplicate source URL', '\n'.join(report['errors']))
        self.assertEqual(len([r for r in rpc.requests if not r['search_query']]), 2)

    def test_http_failure_propagates_once_with_context(self):
        error = HTTPError(CONFIG['SUPABASE_URL'], 503, 'unavailable', {}, None)
        with patch('verify_catalog_rpc.urlopen', side_effect=error) as call:
            with self.assertRaisesRegex(RPCError, 'online_prices_v4.*page=1: HTTP 503'):
                verify(CONFIG, [])
        call.assert_called_once()

    def test_malformed_response_is_a_handled_rpc_failure(self):
        for body in (b'{"error":"fixture"}', b'not json'):
            with self.subTest(body=body), patch('verify_catalog_rpc.urlopen', return_value=BytesIO(body)):
                with self.assertRaises(RPCError):
                    verify(CONFIG)

    def test_cli_writes_failure_report_and_nonzero_exit(self):
        with TemporaryDirectory() as folder:
            defines = Path(folder) / 'defines.json'
            defines.write_text(json.dumps(CONFIG))
            out = Path(folder) / 'evidence' / 'rpc.json'
            with patch('verify_catalog_rpc.urlopen', side_effect=RPCError('HTTP fixture')), \
                    patch('sys.stdout', new_callable=StringIO):
                status = main(['--defines', str(defines), '--out', str(out)])
            self.assertEqual(status, 1)
            report = json.loads(out.read_text())
            self.assertFalse(report['passed'])
            self.assertNotIn(CONFIG['SUPABASE_PUBLISHABLE_KEY'], out.read_text())


if __name__ == '__main__':
    unittest.main()
