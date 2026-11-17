"""Check demo metadata and the service-free Flutter build command."""

import contextlib
import io
import json
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch

import build_portfolio_demo as demo


class PortfolioBuildTest(unittest.TestCase):
    def test_build_embeds_app_version_and_writes_matching_metadata(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / 'pubspec.yaml').write_text('name: app\nversion: 0.2.6+8\n', encoding='utf-8')
            output = root / 'build/portfolio-demo'
            output.mkdir(parents=True)
            (output / 'index.html').write_text(
                '<title>Tiago Market</title>Tiago Market: búsqueda, comparación de precios y listas de compras.',
                encoding='utf-8',
            )
            with patch.object(demo, 'ROOT', root), patch.object(
                demo.subprocess, 'run',
                return_value=subprocess.CompletedProcess([], 0, stdout='abc123\n'),
            ) as run, contextlib.redirect_stdout(io.StringIO()):
                demo.main(['--base-href=/tiago-market/'])

            metadata = json.loads((output / 'version.json').read_text(encoding='utf-8'))
            self.assertEqual(metadata['version'], '0.2.6+8')
            self.assertEqual(metadata['revision'], 'abc123')
            self.assertIsNotNone(demo.datetime.fromisoformat(metadata['built_at']).utcoffset())
            command = run.call_args_list[1].args[0]
            self.assertIn('--target=lib/main_demo.dart', command)
            self.assertIn('--base-href=/tiago-market/', command)
            self.assertEqual([arg for arg in command if arg.startswith('--dart-define')], [
                '--dart-define=DEMO_APP_VERSION=0.2.6+8',
                f"--dart-define=DEMO_BUILT_AT={metadata['built_at']}",
            ])
            html = (output / 'index.html').read_text(encoding='utf-8')
            self.assertIn('<title>Tiago Market · Demo</title>', html)
            self.assertIn('Sin registro ni compras reales.', html)
            self.assertTrue((output / '.nojekyll').exists())

    def test_invalid_base_href_stops_before_build(self):
        with patch.object(demo.subprocess, 'run') as run, contextlib.redirect_stderr(io.StringIO()):
            with self.assertRaises(SystemExit):
                demo.main(['--base-href=tiago-market'])
            run.assert_not_called()

    def test_missing_version_stops_before_build(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / 'pubspec.yaml').write_text('name: app\n', encoding='utf-8')
            with patch.object(demo, 'ROOT', root), patch.object(
                demo.subprocess, 'run',
            ) as run, contextlib.redirect_stderr(io.StringIO()):
                with self.assertRaises(SystemExit):
                    demo.main([])
                run.assert_not_called()


if __name__ == '__main__':
    unittest.main()
