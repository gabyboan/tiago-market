"""Offline orchestration checks; all staging, database and HTTP calls are mocked."""
from contextlib import redirect_stdout
import copy
import io
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import Mock, patch

import refresh_online_catalog as refresh


OBSERVED_AT = '2026-09-29T03:04:05+00:00'
URLS = {
    'chedraui-mx': 'https://www.chedraui.com.mx/arroz-fixture-1234567/p',
    'merco-mx': 'https://adomicilio.merco.mx/p/arroz-fixture-1234567',
}


def listing(source='chedraui-mx'):
    return {
        'source': source, 'store_product_url': URLS[source],
        'external_name': 'Arroz fixture 1 kg', 'normalized_name': 'arroz fixture',
        'presentation': '1 kg', 'category': 'Categoría revisada',
        'store_slug': source,
    }


def observation(source='chedraui-mx', **changes):
    result = dict(listing(source), source_product_name='Arroz fixture 1 kg',
                  source_url=URLS[source], category='Categoría capturada',
                  captured_at=OBSERVED_AT, observed_at=OBSERVED_AT,
                  content_hash='fixture12345678', price=30.0, available=True,
                  currency='MXN', price_scope='online', branch_id=None)
    result.pop('external_name')
    return result | changes


class KnownListingsTest(unittest.TestCase):
    def test_groups_only_existing_official_listings(self):
        entries = [listing(source) for source in refresh.SOURCES]
        groups = refresh.known_by_source(entries)
        for entry in entries:
            self.assertEqual(groups[entry['source']], {entry['store_product_url']: entry})

    def test_rejects_duplicate_persisted_listing(self):
        for source in refresh.SOURCES:
            with self.subTest(source=source), self.assertRaisesRegex(ValueError, 'Duplicate'):
                refresh.known_by_source([listing(source), listing(source)])

    def test_rejects_foreign_or_noncanonical_persisted_urls(self):
        for source in refresh.SOURCES:
            other = next(value for key, value in URLS.items() if key != source)
            for url in [other, 'https://example.invalid/product-123/p',
                        URLS[source].replace('https:', 'http:'),
                        URLS[source] + '?tracking=1', URLS[source] + '#offer']:
                with self.subTest(source=source, url=url), self.assertRaises(ValueError):
                    refresh.known_by_source([listing(source) | {'store_product_url': url}])


class PrepareRowsTest(unittest.TestCase):
    def test_rejects_changed_binding_identity_presentation_and_store(self):
        cases = [
            ({'source': 'merco-mx'}, 'unknown_listing'),
            ({'store_product_url': 'https://example.invalid/other'}, 'unknown_listing'),
            ({'store_product_url': URLS['chedraui-mx'].replace('1234567', '7654321')},
             'unknown_listing'),
            ({'source_url': 'https://example.invalid/evidence'}, 'changed_evidence_url'),
            ({'source_url': URLS['chedraui-mx'].replace('1234567', '7654321')},
             'changed_evidence_url'),
            ({'normalized_name': 'another product'}, 'changed_product_identity'),
            ({'source_product_name': 'Another product 1 kg'}, 'changed_product_identity'),
            ({'presentation': '2 kg'}, 'changed_presentation'),
            ({'store_slug': 'other-store'}, 'changed_store'),
        ]
        known = {URLS['chedraui-mx']: listing()}
        for changes, reason in cases:
            row = observation(**changes)
            with self.subTest(changes=changes):
                accepted, rejected = refresh.prepare_rows([row], 'chedraui-mx', known)
                self.assertEqual(accepted, [])
                self.assertEqual(rejected, [{'url': row['store_product_url'], 'reason': reason}])

    def test_retains_reviewed_category_and_original_observation_without_mutation(self):
        row = observation(raw_payload={'receipt': {'sku': '1234567'}})
        original = copy.deepcopy(row)
        accepted, rejected = refresh.prepare_rows(
            [row], 'chedraui-mx', {URLS['chedraui-mx']: listing()})
        self.assertEqual(rejected, [])
        self.assertEqual(accepted, [original | {'category': listing()['category']}])
        self.assertEqual(row, original)
        self.assertIsNot(accepted[0], row)

    def test_reuse_rejects_older_observations_and_keeps_equivalent_timestamp(self):
        known = {URLS['chedraui-mx']: listing() | {'latest_capture': OBSERVED_AT}}
        cases = [
            ('2026-09-28T03:04:05+00:00', 'older_than_current_observation'),
            ('invalid', 'invalid_captured_at'),
            (None, 'invalid_captured_at'),
            ('2026-09-29T00:04:05-03:00', None),
            ('2026-09-29T03:05:05+00:00', None),
        ]
        for captured_at, reason in cases:
            with self.subTest(captured_at=captured_at):
                row = observation(captured_at=captured_at)
                accepted, rejected = refresh.prepare_rows([row], 'chedraui-mx', known)
                if reason:
                    self.assertEqual(accepted, [])
                    self.assertEqual(rejected[0]['reason'], reason)
                else:
                    self.assertEqual(rejected, [])
                    self.assertEqual(accepted[0]['captured_at'], captured_at)


class PublicationTest(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix='refresh-offline-')
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.capture = self.root / 'capture'
        self.output = self.root / 'output'
        self.capture.mkdir()
        self.output.mkdir()
        self.db = Mock()
        self.db.url = 'offline-fixture'
        self.db.query.return_value = [{'metadata': {
            'inserted_snapshots': 1, 'skipped_existing_snapshots': 0,
            'skipped_snapshot_conflicts': 0,
        }}]
        # Test transactions are never executed. Their dated payload proves that
        # the replay uses the exact staged observation rather than recapturing.
        self.sql = f'begin;\n-- original observation: {OBSERVED_AT}\nselect 1;\ncommit;\n'
        self.stage_calls = []
        self.http_guard = patch('urllib.request.OpenerDirector.open',
                                side_effect=AssertionError('Network forbidden in offline tests'))
        self.http_guard.start()
        self.addCleanup(self.http_guard.stop)
        self.process_guard = patch.object(refresh.subprocess, 'run',
                                           side_effect=AssertionError('External process forbidden'))
        self.process_guard.start()
        self.addCleanup(self.process_guard.stop)

    def captured(self, source='chedraui-mx', rows=None, **report):
        refresh.write_rows(self.capture / f'{source}.ndjson',
                           [observation(source)] if rows is None else rows)
        refresh.write_json(self.capture / f'{source}-capture.json',
                           {'attempted': 1, 'exit_code': 0, 'rejected': []} | report)

    def stage(self, valid_rows, rejected=None, duplicates=0):
        def fake(command, log):
            self.stage_calls.append(command)
            self.assertIn('--allow-partial', command)
            self.assertNotIn('--execute', command)
            self.assertEqual(command[2], 'tools/ingestion/bin/stage_ndjson.dart')
            sql = Path(command[command.index('--sql-out') + 1])
            report = Path(command[command.index('--json-report') + 1])
            refresh.write_json(report, {
                'publishable': len(valid_rows), 'publishable_records': valid_rows,
                'duplicate_input_records': duplicates, 'rejected_records': rejected or [],
            })
            if valid_rows:
                sql.write_text(self.sql)
            return 0 if valid_rows else 2
        return fake

    def publish(self, source='chedraui-mx'):
        return refresh.publish_source(source, {URLS[source]: listing(source)},
                                      self.capture, self.output, self.db, 'offline-test')

    def test_staging_rejects_only_invalid_rows_and_returns_its_validated_subset(self):
        valid = observation()
        invalid = observation(price=0, content_hash='invalid12345678')
        self.captured(rows=[valid, invalid, dict(valid)])
        published = valid | {'category': listing()['category']}
        rejection = {'line': 2, 'source': 'chedraui-mx',
                     'reasons': [{'code': 'invalid_price', 'message': 'Invalid price'}]}
        with patch.object(refresh, 'run_logged', side_effect=self.stage([published], [rejection], 1)):
            result, expected = self.publish()
        self.assertEqual(expected, [published])
        self.assertEqual(result['valid'], 1)
        self.assertEqual(result['inserted_snapshots'], 1)
        self.assertEqual(result['duplicates_avoided'], 1)
        self.assertEqual(result['rejections'], [rejection])
        self.assertEqual(result['errors'], [])
        self.assertEqual(len(refresh.read_ndjson(self.output / 'chedraui-mx-prepared.ndjson')), 3)

    def test_replay_uses_same_sql_with_rollback_and_preserves_observation_dates(self):
        self.captured()
        published = observation() | {'category': listing()['category']}
        with patch.object(refresh, 'run_logged', side_effect=self.stage([published])) as run:
            result, expected = self.publish()
        run.assert_called_once()
        self.assertEqual(self.db.execute.call_count, 2)
        self.assertEqual(self.db.execute.call_args_list[0].args,
                         (self.sql, 'chedraui-mx-publish'))
        replay, label = self.db.execute.call_args_list[1].args
        self.assertEqual(label, 'chedraui-mx-replay')
        self.assertTrue(replay.startswith(self.sql.rstrip()[:-len('commit;')]))
        self.assertTrue(replay.rstrip().endswith('rollback;'))
        self.assertNotIn('commit;', replay)
        self.assertIn('Replay inserted duplicate observations', replay)
        self.assertTrue(result['replay_verified'])
        self.assertEqual(result['replay_duplicates_avoided'], 1)
        self.assertEqual(expected[0]['captured_at'], OBSERVED_AT)
        self.assertEqual(expected[0]['observed_at'], OBSERVED_AT)

    def test_no_database_call_when_all_staging_rows_reject(self):
        self.captured(rows=[observation(price=0)])
        rejection = {'line': 1, 'reasons': [{'code': 'invalid_price'}]}
        with patch.object(refresh, 'run_logged', side_effect=self.stage([], [rejection])):
            result, expected = self.publish()
        self.assertEqual(expected, [])
        self.assertEqual(result['rejections'], [rejection])
        self.assertTrue(result['errors'])
        self.db.execute.assert_not_called()

    def test_replay_failure_preserves_committed_rows_for_rpc_verification(self):
        self.captured()
        published = observation() | {'category': listing()['category']}
        self.db.execute.side_effect = [None, RuntimeError('Replay failed')]
        with patch.object(refresh, 'run_logged', side_effect=self.stage([published])):
            result, expected = self.publish()
        self.assertEqual(result['inserted_snapshots'], 1)
        self.assertIn('Replay failed', result['errors'])
        self.assertFalse(result.get('replay_verified', False))
        self.assertEqual(expected, [published], 'Committed rows must remain visible to RPC verification')

    def test_publication_failure_in_one_source_leaves_other_source_publishable(self):
        for source in refresh.SOURCES:
            self.captured(source)
        self.db.execute.side_effect = [RuntimeError('Publication failed'), None, None]
        outcomes = {}
        for source in refresh.SOURCES:
            published = observation(source) | {'category': listing(source)['category']}
            with patch.object(refresh, 'run_logged', side_effect=self.stage([published])):
                outcomes[source] = self.publish(source)
        failed, failed_rows = outcomes['chedraui-mx']
        successful, successful_rows = outcomes['merco-mx']
        self.assertIn('Publication failed', failed['errors'])
        self.assertEqual(failed_rows, [])
        self.assertEqual(successful['errors'], [])
        self.assertEqual(successful['inserted_snapshots'], 1)
        self.assertEqual(successful_rows[0]['source'], 'merco-mx')

    def test_metadata_failure_also_preserves_already_committed_rows(self):
        self.captured()
        published = observation() | {'category': listing()['category']}
        self.db.query.side_effect = RuntimeError('Metadata unavailable')
        with patch.object(refresh, 'run_logged', side_effect=self.stage([published])):
            result, expected = self.publish()
        self.db.execute.assert_called_once_with(self.sql, 'chedraui-mx-publish')
        self.assertIn('Metadata unavailable', result['errors'])
        self.assertEqual(expected, [published])

    def test_main_reuse_is_offline_and_source_failure_does_not_block_other_source(self):
        self.captured('chedraui-mx', rows=[], attempted=0, exit_code=1, failure='Capture unavailable')
        self.captured('merco-mx')
        entries = [listing(source) for source in refresh.SOURCES]
        published = observation('merco-mx') | {'category': listing('merco-mx')['category']}
        self.db.query.side_effect = [entries, [{'metadata': {'inserted_snapshots': 1}}]]
        config = self.root / 'config.json'
        defines = {'SUPABASE_URL': 'https://fixture.invalid',
                   'SUPABASE_PUBLISHABLE_KEY': 'offline-fixture'}
        refresh.write_json(config, defines)
        work_dir = self.root / 'main-result'
        with patch.object(refresh, 'Database', return_value=self.db), \
             patch.object(refresh, 'database_summary', return_value=[]), \
             patch.object(refresh, 'run_logged', side_effect=self.stage([published])), \
             patch.object(refresh, 'capture_source') as capture, \
             patch.object(refresh, 'verify', return_value={'passed': True, 'errors': []}) as verify, \
             patch.object(refresh.shutil, 'which', return_value='/offline/executable'), \
             patch.object(refresh.os, 'chdir'), redirect_stdout(io.StringIO()):
            code = refresh.main(['--work-dir', str(work_dir), '--reuse', str(self.capture),
                                 '--defines', str(config)])
        capture.assert_not_called()
        self.assertEqual(code, 2)
        report = json.loads((work_dir / 'report.json').read_text())
        self.assertEqual(report['status'], 'PARCIAL')
        self.assertIn('Capture unavailable', report['sources']['chedraui-mx']['errors'])
        self.assertEqual(report['sources']['merco-mx']['inserted_snapshots'], 1)
        self.assertEqual(report['sources']['merco-mx']['errors'], [])
        self.assertEqual(refresh.read_ndjson(work_dir / 'published.ndjson'), [published])
        verify.assert_called_once_with(defines, [published])


if __name__ == '__main__':
    unittest.main()
