#!/usr/bin/env python3
"""Build the standalone Flutter portfolio demo without any service defines."""

import argparse
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[1]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--base-href', default='/tiago-market/')
    args = parser.parse_args()
    if not args.base_href.startswith('/') or not args.base_href.endswith('/'):
        parser.error('--base-href must start and end with /')
    subprocess.run([
        'flutter', 'build', 'web', '--release', '--target=lib/main_demo.dart',
        '--output=build/portfolio-demo', '--no-web-resources-cdn',
        f'--base-href={args.base_href}',
    ], cwd=ROOT, check=True)
    index = ROOT / 'build/portfolio-demo/index.html'
    html = index.read_text().replace('<title>Tiago Market</title>', '<title>Tiago Market · Demo</title>')
    html = html.replace(
        'Tiago Market: búsqueda, comparación de precios y listas de compras.',
        'Demo de Tiago Market con comercios y precios ficticios. Sin registro ni compras reales.',
    )
    index.write_text(html)
    (index.parent / '.nojekyll').touch()
    print(f'Standalone demo built in {index.parent}; no service configuration used.')


if __name__ == '__main__':
    main()
