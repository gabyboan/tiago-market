"""Check that the published app uses real data and excludes privileged config."""

import base64
import contextlib
import io
import json
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch

import build_pages as pages


class PagesBuildTest(unittest.TestCase):
    def test_public_configuration_rejects_missing_or_privileged_keys(self):
        for key in ['', 'sb_secret_fixture', self.jwt('service_role')]:
            with self.subTest(key=key), self.assertRaises(ValueError):
                pages.public_config({'SUPABASE_URL': 'https://fixture.supabase.co',
                                     'SUPABASE_PUBLISHABLE_KEY': key})
        for key in ['sb_publishable_fixture', self.jwt('anon')]:
            self.assertEqual(pages.public_config({
                'SUPABASE_URL': 'https://fixture.supabase.co',
                'SUPABASE_PUBLISHABLE_KEY': key,
                'SUPABASE_SERVICE_ROLE_KEY': 'must-not-be-forwarded',
            }), {'SUPABASE_URL': 'https://fixture.supabase.co',
                 'SUPABASE_PUBLISHABLE_KEY': key})

    @staticmethod
    def jwt(role):
        payload = base64.urlsafe_b64encode(json.dumps({'role': role}).encode()).decode().rstrip('=')
        return f'header.{payload}.signature'

    def test_build_targets_real_app_and_records_catalog_revision(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / 'pubspec.yaml').write_text('name: app\nversion: 0.2.6+8\n', encoding='utf-8')
            output = root / 'build/pages'
            output.mkdir(parents=True)
            with patch.object(pages, 'ROOT', root), patch.dict(pages.os.environ, {
                'SUPABASE_URL': 'https://fixture.supabase.co',
                'SUPABASE_PUBLISHABLE_KEY': 'sb_publishable_fixture',
                'SUPABASE_SERVICE_ROLE_KEY': 'must-not-be-forwarded',
            }), patch.object(pages.subprocess, 'run',
                             return_value=subprocess.CompletedProcess([], 0, stdout='abc123\n')) as run, \
                    contextlib.redirect_stdout(io.StringIO()):
                pages.main([])
            command = run.call_args_list[1].args[0]
            self.assertIn('--target=lib/main.dart', command)
            self.assertIn('--dart-define=SUPABASE_PUBLISHABLE_KEY=sb_publishable_fixture', command)
            self.assertNotIn('must-not-be-forwarded', ' '.join(command))
            metadata = json.loads((output / 'version.json').read_text())
            self.assertEqual(metadata['catalog'], 'supabase')
            self.assertEqual(metadata['revision'], 'abc123')
            self.assertTrue((output / '.nojekyll').exists())


if __name__ == '__main__':
    unittest.main()
