#!/usr/bin/env python3
"""Build the standalone Flutter portfolio demo without any service defines."""

import argparse
from datetime import datetime, timezone
import json
from pathlib import Path
import re
import subprocess

ROOT = Path(__file__).resolve().parents[1]


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--base-href', default='/tiago-market/')
    args = parser.parse_args(argv)
    if not args.base_href.startswith('/') or not args.base_href.endswith('/'):
        parser.error('--base-href must start and end with /')
    match = re.search(r'^version:\s*(\S+)\s*$',
                      (ROOT / 'pubspec.yaml').read_text(encoding='utf-8'), re.MULTILINE)
    if match is None:
        parser.error('pubspec.yaml must declare an app version')
    version = match.group(1)
    revision = subprocess.run(
        ['git', 'rev-parse', 'HEAD'], cwd=ROOT, check=True,
        capture_output=True, text=True,
    ).stdout.strip()
    built_at = datetime.now(timezone.utc).isoformat(timespec='seconds')
    subprocess.run([
        'flutter', 'build', 'web', '--release', '--target=lib/main_demo.dart',
        '--output=build/portfolio-demo', '--no-web-resources-cdn',
        f'--base-href={args.base_href}',
        f'--dart-define=DEMO_APP_VERSION={version}',
        f'--dart-define=DEMO_BUILT_AT={built_at}',
    ], cwd=ROOT, check=True)
    index = ROOT / 'build/portfolio-demo/index.html'
    html = index.read_text(encoding='utf-8').replace('<title>Tiago Market</title>', '<title>Tiago Market · Demo</title>')
    html = html.replace(
        'Tiago Market: búsqueda, comparación de precios y listas de compras.',
        'Demo de Tiago Market con comercios y precios ficticios. Sin registro ni compras reales.',
    )
    index.write_text(html, encoding='utf-8')
    (index.parent / 'version.json').write_text(json.dumps({
        'version': version,
        'revision': revision,
        'built_at': built_at,
    }, indent=2) + '\n', encoding='utf-8')
    (index.parent / '.nojekyll').touch()
    print(f'Standalone demo built in {index.parent}; no service configuration used.')


if __name__ == '__main__':
    main()
