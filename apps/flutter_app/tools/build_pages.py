#!/usr/bin/env python3
"""Build the real Flutter application for GitHub Pages using public config only."""

import argparse
import base64
from datetime import datetime, timezone
import json
import os
from pathlib import Path
import re
import subprocess
from urllib.parse import urlparse

ROOT = Path(__file__).resolve().parents[1]


def public_config(environment):
    url = environment.get('SUPABASE_URL', '').strip()
    key = environment.get('SUPABASE_PUBLISHABLE_KEY', '').strip()
    parsed = urlparse(url)
    if parsed.scheme != 'https' or not parsed.hostname or parsed.username or parsed.password:
        raise ValueError('SUPABASE_URL must be a public HTTPS project URL')
    if not key.startswith('sb_publishable_'):
        try:
            payload = key.split('.')[1]
            claims = json.loads(base64.urlsafe_b64decode(payload + '=' * (-len(payload) % 4)))
        except (ValueError, IndexError, UnicodeDecodeError):
            raise ValueError('Use a publishable key or a legacy anon key') from None
        if claims.get('role') != 'anon':
            raise ValueError('Privileged Supabase keys must never enter the web build')
    return {'SUPABASE_URL': url, 'SUPABASE_PUBLISHABLE_KEY': key}


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--base-href', default='/tiago-market/')
    args = parser.parse_args(argv)
    if not args.base_href.startswith('/') or not args.base_href.endswith('/'):
        parser.error('--base-href must start and end with /')
    try:
        config = public_config(os.environ)
    except ValueError as error:
        parser.error(str(error))
    match = re.search(r'^version:\s*(\S+)\s*$',
                      (ROOT / 'pubspec.yaml').read_text(encoding='utf-8'), re.MULTILINE)
    if match is None:
        parser.error('pubspec.yaml must declare an app version')
    revision = subprocess.run(['git', 'rev-parse', 'HEAD'], cwd=ROOT, check=True,
                              capture_output=True, text=True).stdout.strip()
    subprocess.run([
        'flutter', 'build', 'web', '--release', '--target=lib/main.dart',
        '--output=build/pages', '--no-web-resources-cdn',
        f'--base-href={args.base_href}',
        *(f'--dart-define={name}={value}' for name, value in config.items()),
    ], cwd=ROOT, check=True)
    output = ROOT / 'build/pages'
    (output / 'version.json').write_text(json.dumps({
        'version': match.group(1), 'revision': revision,
        'built_at': datetime.now(timezone.utc).isoformat(timespec='seconds'),
        'catalog': 'supabase',
    }, indent=2) + '\n', encoding='utf-8')
    (output / '.nojekyll').touch()
    print(f'Live catalog application built in {output}.')


if __name__ == '__main__':
    main()
