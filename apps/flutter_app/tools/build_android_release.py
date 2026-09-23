#!/usr/bin/env python3
"""Build a locally signed APK using client-only compile-time configuration."""
import argparse
import base64
import json
from pathlib import Path
import subprocess
from urllib.parse import urlparse

ROOT = Path(__file__).resolve().parents[1]
ALLOWED = {
    'SUPABASE_URL', 'SUPABASE_PUBLISHABLE_KEY', 'SUPABASE_ANON_KEY',
    'API_BASE_URL', 'GOOGLE_WEB_CLIENT_ID', 'GOOGLE_IOS_CLIENT_ID',
    'APP_ENV', 'CRASHLYTICS_ENABLED', 'SENTRY_DSN',
}


def validate(values):
    if not isinstance(values, dict) or set(values) - ALLOWED:
        raise ValueError('Only documented client dart-defines are allowed.')
    if any(not isinstance(v, (str, bool)) for v in values.values()):
        raise ValueError('Dart-define values must be strings or booleans.')
    for name in ('SUPABASE_URL', 'API_BASE_URL'):
        url = urlparse(str(values.get(name, '')))
        if url.scheme != 'https' or not url.hostname or url.username or url.password:
            raise ValueError(f'{name} must be an HTTPS URL without credentials.')
    keys = [values[name] for name in ('SUPABASE_PUBLISHABLE_KEY', 'SUPABASE_ANON_KEY')
            if values.get(name)]
    if not keys:
        raise ValueError('A public Supabase client key is required.')
    for key in keys:
        if not isinstance(key, str):
            raise ValueError('Invalid public client key.')
        if key.startswith('sb_publishable_') and len(key) > 20:
            continue
        try:
            payload = key.split('.')[1]
            role = json.loads(base64.urlsafe_b64decode(payload + '=' * (-len(payload) % 4)))['role']
        except (IndexError, ValueError, KeyError):
            raise ValueError('Only publishable or legacy anon client keys are allowed.') from None
        if role != 'anon':
            raise ValueError('Privileged Supabase keys must never be compiled into an APK.')
    for value in values.values():
        if isinstance(value, str) and any(marker in value for marker in
                ('sb_secret_', 'PRIVATE KEY', 'service_role', 'ghp_', 'gho_')):
            raise ValueError('Private credential detected in client configuration.')
    if str(values.get('CRASHLYTICS_ENABLED', '')).lower() != 'true':
        raise ValueError('This release requires CRASHLYTICS_ENABLED=true.')
    if not values.get('APP_ENV'):
        raise ValueError('APP_ENV is required.')
    if not str(values.get('GOOGLE_WEB_CLIENT_ID', '')).endswith('.apps.googleusercontent.com'):
        raise ValueError('The Google Web OAuth client ID is required for native sign-in.')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--defines', type=Path, default=ROOT / 'dart_defines.release.local.json')
    parser.add_argument('--check-only', action='store_true')
    args = parser.parse_args()
    defines = args.defines.resolve()
    try:
        values = json.loads(defines.read_text())
        validate(values)
        for name in ('android/key.properties', 'android/app/google-services.json'):
            if not (ROOT / name).is_file():
                raise ValueError(f'Missing local file: {name}')
        firebase = json.loads((ROOT / 'android/app/google-services.json').read_text())
        if not any(client['client_info'].get('android_client_info', {}).get('package_name')
                   == 'com.tiagomarket.tiago_market_app' for client in firebase['client']):
            raise ValueError('Firebase Android package does not match Tiago Market.')
        web_clients = {oauth.get('client_id') for client in firebase['client']
                       for oauth in client.get('oauth_client', []) if oauth.get('client_type') == 3}
        if values['GOOGLE_WEB_CLIENT_ID'] not in web_clients:
            raise ValueError('Google Web OAuth client does not match Firebase configuration.')
    except (OSError, ValueError, KeyError) as error:
        # Never dump configuration contents or JSON parser excerpts.
        parser.exit(1, f'Release validation failed: {type(error).__name__}. Check local configuration.\n')
    print('Release configuration validated; no private credentials printed.', flush=True)
    if not args.check_only:
        subprocess.run(['flutter', 'build', 'apk', '--release',
                        f'--dart-define-from-file={defines}'], cwd=ROOT, check=True)


if __name__ == '__main__':
    main()
