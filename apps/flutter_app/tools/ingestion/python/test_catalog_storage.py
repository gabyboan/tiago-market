"""An archive failure must never authorize deleting its source observations."""
import json
import gzip
import hashlib
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import Mock, patch

import catalog_storage as storage
from restore_catalog_archive import restore_sql


class ArchiveSafetyTest(unittest.TestCase):
    def test_mutation_report_matches_on_both_transports(self):
        report = {'removed': 2, 'scanned': 3, 'cursor': 'fixture'}
        for url in ('postgresql://fixture', ''):
            db = Mock(url=url)
            db.execute.return_value = json.dumps(report if url else {'rows': [{'maintenance_report': report}]})
            self.assertEqual(storage.execute_report(db, 'with removed as (...) select ...', 'fixture'), report)

    def test_failed_remote_verification_never_deletes(self):
        db = Mock()
        rows = [{'row': {'id': 'fixture', 'price': 12, 'name': 'Leche ñ'}, 'fingerprint': 'digest'}]
        with tempfile.TemporaryDirectory() as folder, \
                patch.object(storage, 'upload_verified', side_effect=RuntimeError('failed')):
            with self.assertRaises(RuntimeError):
                storage.archive_batch(db, Path(folder), rows, '2026-07-01T00:00:00Z')
        db.query.assert_not_called()
        db.execute.assert_not_called()

    def test_manifest_must_also_be_verified_before_deletion(self):
        db = Mock()
        rows = [{'row': {'id': 'fixture'}, 'fingerprint': 'digest'}]
        with tempfile.TemporaryDirectory() as folder, \
                patch.object(storage, 'upload_verified', side_effect=[{'verified': True}, RuntimeError('failed')]):
            with self.assertRaises(RuntimeError):
                storage.archive_batch(db, Path(folder), rows, '2026-07-01T00:00:00Z')
        db.query.assert_not_called()
        db.execute.assert_not_called()

    def test_remote_receipt_with_wrong_checksum_is_rejected(self):
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / 'archive.gz'
            path.write_bytes(b'payload')
            result = subprocess.CompletedProcess([], 0, json.dumps({
                'verified': True, 'bucket': storage.BUCKET, 'object': 'test', 'sha256': 'wrong'}))
            with patch.object(storage.subprocess, 'run', return_value=result), self.assertRaises(RuntimeError):
                storage.upload_verified(path, 'test')

    def test_exact_postgres_numeric_text_survives_restore(self):
        text = '{"id":"fixture","price":12345678901234567890.123456789}'
        entry = {'row': json.loads(text), 'row_json': text,
                 'fingerprint': hashlib.md5(text.encode()).hexdigest()}
        with tempfile.TemporaryDirectory() as folder:
            archive = Path(folder) / 'snapshot.ndjson.gz'
            manifest = Path(folder) / 'snapshot.manifest.json'
            archive.write_bytes(gzip.compress((json.dumps(entry) + '\n').encode()))
            manifest.write_text(json.dumps({'format': 1, 'table': 'public.price_snapshots',
                                           'rows': 1, 'sha256': hashlib.sha256(archive.read_bytes()).hexdigest()}))
            self.assertIn('12345678901234567890.123456789', restore_sql(archive, manifest))

    def test_inconsistent_postgres_text_is_not_archived_or_deleted(self):
        db = Mock()
        entry = {'row': {'id': 'fixture', 'price': 10}, 'row_json': '{"id":"fixture","price":20}',
                 'fingerprint': 'wrong'}
        with tempfile.TemporaryDirectory() as folder, patch.object(storage, 'upload_verified') as upload:
            with self.assertRaises(RuntimeError):
                storage.archive_batch(db, Path(folder), [entry], None, reason='repeated')
        upload.assert_not_called()
        db.execute.assert_not_called()

    def test_preview_does_not_modify_database(self):
        db = Mock()
        db.query.side_effect = [[{'cutoff': '2026-07-01T00:00:00Z'}], [], []]
        result = storage.maintain(db, Path('/unused'))
        self.assertEqual(result['archived'], 0)
        db.execute.assert_not_called()
        self.assertTrue(all('delete ' not in call.args[0].lower() for call in db.query.call_args_list))


if __name__ == '__main__':
    unittest.main()
