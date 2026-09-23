#!/usr/bin/env python3
"""Capture only public robots/terms metadata; never authorize a product probe."""

import argparse
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
from urllib.error import HTTPError, URLError
from urllib.request import HTTPRedirectHandler, Request, build_opener


class NoRedirects(HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--out-dir', type=Path, required=True,
                        help='New directory; existing evidence is never overwritten')
    args = parser.parse_args()
    args.out_dir.mkdir(parents=True, exist_ok=False)
    opener = build_opener(NoRedirects())
    targets = [
        ('robots', 'https://www.chedraui.com.mx/robots.txt', 'text/plain'),
        ('terms', 'https://www.chedraui.com.mx/terminos-y-condiciones/plataformas-digitales', 'text/html'),
    ]
    for name, url, accept in targets:
        metadata = {
            'requested_url': url,
            'started_at': datetime.now(timezone.utc).isoformat(),
            'request_count': 1,
            'cookies_persisted': False,
            'credentials_used': False,
            'body_retained': name == 'robots',
        }
        request = Request(url, headers={
            'User-Agent': 'TiagoMarketBot/0.1 (+https://github.com/gabyboan/tiago-market)',
            'Accept': accept,
        })
        try:
            try:
                response = opener.open(request, timeout=20)
            except HTTPError as error:
                response = error
            with response:
                body = response.read()
                metadata.update({
                    'final_url': response.url,
                    'status_code': response.status,
                    'body_sha256': hashlib.sha256(body).hexdigest(),
                    'body_bytes': len(body),
                    'headers': {key: response.headers[key] for key in
                                ['Content-Type', 'Date', 'Retry-After', 'Cache-Control']
                                if key in response.headers},
                })
                if name == 'robots':
                    (args.out_dir / 'robots.txt').write_bytes(body)
        except (URLError, OSError, TimeoutError) as error:
            metadata['error'] = str(error)
        metadata['captured_at'] = datetime.now(timezone.utc).isoformat()
        (args.out_dir / f'{name}.metadata.json').write_text(
            json.dumps(metadata, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
        print(f"{name}: {metadata.get('status_code', 'network_error')}")
        if metadata.get('status_code') != 200:
            print('Stopped. No retries, product requests or sessions were attempted.')
            return 2
    print('Manual review required: HTTP 200 is not authorization to reuse data.')
    print('Read current robots/terms before considering any product or session probe.')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
