"""Automatic refresh must preserve identities, dates and publication gates."""
from contextlib import redirect_stdout
from copy import deepcopy
import io
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import Mock, patch
from urllib.error import HTTPError

import scheduled_source_refresh as refresh
from refresh_grocery_catalogs import parse_woo_product
from test_refresh_grocery_catalogs import response, woo
from refresh_online_catalog import Database


def fixture():
    row = parse_woo_product(woo(), response([woo()]), 'fenix-mx')
    known = {key: row[key] for key in ('source', 'store_product_url', 'presentation',
                                     'normalized_name', 'store_slug', 'image_url')}
    known.update(external_name=row['source_product_name'], category='Categoría revisada',
                 latest_capture='2026-01-01T00:00:00Z')
    return row, known


class IdentityTest(unittest.TestCase):
    def test_exclusion_summary_counts_reasons_without_exposing_raw_input(self):
        private = 'raw body or credential must remain private'
        capture = {'rejected': [
            {'reason': 'Promotion lacks independently verified validity', 'url': private},
            {'reason': 'Promotion lacks independently verified validity'},
            {'reason': 'Product page removed (HTTP 404)'}, {'reason': private},
        ]}
        summary = refresh.exclusion_counts(capture, [
            {'reason': 'Existing URL has a different or ambiguous product identity'}])
        self.assertEqual(summary, {'capture': {
            'promotion_without_verified_validity': 2, 'removed_product_page': 1,
            'other_validation': 1}, 'identity': {'changed_or_ambiguous_identity': 1}})
        self.assertNotIn(private, json.dumps(summary))

    def test_refresh_preserves_http_date_and_reviewed_identity_and_category(self):
        row, known = fixture()
        original = deepcopy(row)
        rows, held = refresh.prepare_existing([row], [known])
        self.assertFalse(held)
        self.assertEqual(rows[0]['captured_at'], original['captured_at'])
        self.assertEqual(rows[0]['category'], 'Categoría revisada')
        self.assertEqual(row, original)

    def test_new_product_and_changed_package_are_not_automatically_published(self):
        row, known = fixture()
        for saved in ([], [known | {'presentation': '1 kg'}]):
            rows, held = refresh.prepare_existing([row], saved)
            self.assertFalse(rows)
            self.assertTrue(held)

    def test_old_capture_cannot_replace_a_newer_saved_observation(self):
        row, known = fixture()
        known['latest_capture'] = '2099-01-01T00:00:00Z'
        rows, held = refresh.prepare_existing([row], [known])
        self.assertFalse(rows)
        self.assertIn('older', held[0]['reason'])


class PublicationTest(unittest.TestCase):
    def test_psql_uses_remote_host_and_database_name_without_uri_in_arguments(self):
        connection = 'postgresql://postgres.fixture:p%40ss%25word@aws-0-region.pooler.supabase.com:5432/postgres?sslmode=require'
        with tempfile.TemporaryDirectory() as tmp, \
                patch.dict(refresh.os.environ, {'SUPABASE_DB_URL': connection}), \
                patch('refresh_online_catalog.shutil.which', return_value='/usr/bin/psql'), \
                patch('refresh_online_catalog.subprocess.run', return_value=Mock(
                    returncode=0, stdout='[]', stderr='')) as run:
            db = Database(Path(tmp))
            db.execute('select 1', 'fixture')
            command = run.call_args.args[0]
            env = run.call_args.kwargs['env']
            self.assertEqual(env['PGHOST'], 'aws-0-region.pooler.supabase.com')
            self.assertEqual(env['PGDATABASE'], 'postgres')
            self.assertEqual(env['PGUSER'], 'postgres.fixture')
            self.assertEqual(env['PGPASSWORD'], 'p@ss%word')
            self.assertEqual(env['PGSSLMODE'], 'require')
            self.assertNotIn(connection, str(command))
            self.assertNotIn('p@ss%word', str(command))

    def test_diagnostics_report_only_categories_without_raw_credentials(self):
        with tempfile.TemporaryDirectory() as tmp:
            secret = 'postgresql://postgres:private-password@db.invalid/postgres'
            (Path(tmp) / 'db.log').write_text(secret + '\nFATAL: password authentication failed')
            result = refresh.failure_diagnostics(Path(tmp))
            self.assertEqual(len(result), 1)
            self.assertIn('password rejected', result[0])
            self.assertNotIn(secret, str(result))

    def test_failed_rollback_never_runs_commit(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / 'accepted.ndjson'
            with patch.object(refresh.subprocess, 'run', return_value=Mock(returncode=1)) as run:
                with self.assertRaisesRegex(RuntimeError, 'dry-run failed'):
                    refresh.publish(path, Path(tmp) / 'staging', 'fixture')
            self.assertEqual(run.call_count, 1)
            self.assertNotIn('--publish', run.call_args.args[0])

    def test_catalog_must_contain_every_original_published_value(self):
        row, _ = fixture()
        db = Mock()
        db.query.return_value = [{'expected': 1, 'matched': 0}]
        with self.assertRaisesRegex(RuntimeError, 'do not match'):
            refresh.verify_database(db, [row])
        self.assertIn(row['captured_at'], db.query.call_args.args[0])

    def test_empty_public_rpc_is_an_error(self):
        with patch.object(refresh, 'urlopen', side_effect=lambda *a, **k: io.StringIO('[]')):
            with self.assertRaisesRegex(RuntimeError, 'no available products'):
                refresh.public_smoke({'SUPABASE_URL': 'https://fixture.supabase.co',
                                      'SUPABASE_PUBLISHABLE_KEY': 'public-fixture'})

    def test_public_rpc_retries_transient_server_errors_then_validates_every_search(self):
        row={'currency':'MXN','available':True,'branch_id':None,'distance_km':None}
        replies=[HTTPError('https://fixture.supabase.co',500,'fixture',{},None)]
        replies += [io.StringIO(json.dumps([row])) for _ in range(3)]
        with patch.object(refresh,'urlopen',side_effect=replies) as request, \
                patch.object(refresh.time,'sleep') as sleep:
            counts=refresh.public_smoke({'SUPABASE_URL':'https://fixture.supabase.co',
                                        'SUPABASE_PUBLISHABLE_KEY':'public-fixture'})
        self.assertEqual(counts,{'all':1,'leche':1,'arroz':1})
        self.assertEqual(request.call_count,4)
        sleep.assert_called_once_with(5)

    def test_persistent_server_error_or_access_error_still_fails_public_verification(self):
        for status,attempts in [(500,3),(403,1)]:
            with self.subTest(status=status), \
                    patch.object(refresh,'urlopen',side_effect=HTTPError(
                        'https://fixture.supabase.co',status,'fixture',{},None)) as request, \
                    patch.object(refresh.time,'sleep'):
                with self.assertRaisesRegex(RuntimeError,f'HTTP {status}'):
                    refresh.public_smoke({'SUPABASE_URL':'https://fixture.supabase.co',
                                         'SUPABASE_PUBLISHABLE_KEY':'public-fixture'})
                self.assertEqual(request.call_count,attempts)


class OrchestrationTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.folder = Path(self.tmp.name) / 'run'
        self.row, self.known = fixture()
        self.config = {'SUPABASE_URL': 'https://fixture.supabase.co',
                       'SUPABASE_PUBLISHABLE_KEY': 'public-fixture'}
        self.connection = 'postgresql://postgres.fixture:fixture-password@aws-0-region.pooler.supabase.com/postgres'

    def execute(self, capture_failure=None, rows=None, verify_error=None,
                catalog_complete=True, known_catalog_complete=False, source='fenix-mx'):
        db = Mock()
        db.query.return_value = [self.known]
        with patch.dict(refresh.os.environ, {'SUPABASE_DB_URL': self.connection}), \
                patch.object(refresh, 'Database', return_value=db), \
                patch.object(refresh, 'capture_source', return_value={
                    'failure': capture_failure, 'full_catalog_traversed': catalog_complete,
                    'known_catalog_traversed': known_catalog_complete}), \
                patch.object(refresh, 'read_ndjson', return_value=[self.row] if rows is None else rows), \
                patch.object(refresh, 'publish', return_value={'inserted_snapshots': 1}) as publish, \
                patch.object(refresh, 'verify_database', side_effect=verify_error,
                             return_value={'expected': 1, 'matched': 1}), \
                patch.object(refresh, 'public_smoke', return_value={'all': 1, 'leche': 0, 'arroz': 1}), \
                redirect_stdout(io.StringIO()):
            report = refresh.refresh(source, self.folder, self.config)
        return report, publish

    def test_healthy_source_publishes_and_verifies(self):
        report, publish = self.execute()
        self.assertEqual(report['status'], 'ok')
        self.assertEqual(report['inserted'], 1)
        self.assertEqual(publish.call_count, 1)
        self.assertEqual(json.loads((self.folder / 'report.json').read_text()), report)
        self.assertNotIn(self.connection, (self.folder / 'report.json').read_text())

    def test_blocked_capture_with_no_observations_never_publishes(self):
        report, publish = self.execute('Origin stopped at HTTP 403', [])
        self.assertEqual(report['status'], 'failed')
        publish.assert_not_called()

    def test_partial_capture_publishes_only_valid_observations_and_reports_failure(self):
        report, publish = self.execute('Origin stopped at HTTP 503')
        self.assertEqual(report['status'], 'partial')
        publish.assert_called_once()

    def test_complete_known_catalog_does_not_require_discovering_new_products(self):
        report, publish = self.execute(catalog_complete=False, known_catalog_complete=True)
        self.assertEqual(report['status'], 'ok')
        self.assertFalse(report['catalog_complete'])
        self.assertTrue(report['known_catalog_complete'])
        publish.assert_called_once()

    def test_incomplete_html_target_is_partial_even_without_a_transport_error(self):
        report, publish = self.execute(catalog_complete=False, source='merco-mx')
        self.assertEqual(report['status'], 'partial')
        publish.assert_called_once()

    def test_failed_post_publication_verification_cannot_report_success(self):
        report, _ = self.execute(verify_error=RuntimeError('Verification failed'))
        self.assertEqual(report['status'], 'failed')

    def test_error_report_does_not_expose_connection_or_public_key(self):
        report, _ = self.execute(verify_error=RuntimeError(
            self.connection + ' ' + self.config['SUPABASE_PUBLISHABLE_KEY']))
        serialized = json.dumps(report)
        self.assertNotIn(self.connection, serialized)
        self.assertNotIn(self.config['SUPABASE_PUBLISHABLE_KEY'], serialized)

    def test_wrong_project_fails_before_database_or_capture(self):
        with patch.dict(refresh.os.environ, {'SUPABASE_DB_URL': self.connection}), \
                patch.object(refresh, 'Database') as db, redirect_stdout(io.StringIO()):
            report = refresh.refresh('fenix-mx', self.folder,
                                     self.config | {'SUPABASE_URL': 'https://other.supabase.co'})
        self.assertEqual(report['status'], 'failed')
        db.assert_not_called()

    def test_preflight_checks_real_database_and_public_rpc(self):
        with patch.dict(refresh.os.environ, {'SUPABASE_DB_URL': self.connection}), \
                patch.object(refresh, 'Database') as db, \
                patch.object(refresh, 'public_smoke') as smoke, redirect_stdout(io.StringIO()):
            self.assertEqual(refresh.check_config(self.folder, self.config), 0)
        db.return_value.query.assert_called_once()
        smoke.assert_called_once_with(self.config)

    def test_preflight_rejects_wrong_project_before_connecting(self):
        with patch.dict(refresh.os.environ, {'SUPABASE_DB_URL': self.connection}), \
                patch.object(refresh, 'Database') as db, redirect_stdout(io.StringIO()):
            self.assertEqual(refresh.check_config(
                self.folder, self.config | {'SUPABASE_URL': 'https://other.supabase.co'}), 1)
        db.assert_not_called()


if __name__ == '__main__':
    unittest.main()
