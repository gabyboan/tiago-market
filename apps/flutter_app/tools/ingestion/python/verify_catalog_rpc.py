#!/usr/bin/env python3
"""Read-only smoke test using local Flutter publishable configuration."""
import argparse
import json
from pathlib import Path
from urllib.request import Request, urlopen


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--defines', type=Path, default=Path('dart_defines.local.json'))
    parser.add_argument('--out', type=Path, required=True)
    args = parser.parse_args()
    config = json.loads(args.defines.read_text())
    key = config.get('SUPABASE_PUBLISHABLE_KEY') or config['SUPABASE_ANON_KEY']
    base = config['SUPABASE_URL']+'/rest/v1/rpc/'
    calls = []

    def rpc(name, params):
        req = Request(base+name, data=json.dumps(params).encode(), headers={
            'apikey': key, 'Content-Type': 'application/json'})
        with urlopen(req, timeout=20) as response:
            data = json.load(response)
        calls.append({'rpc': name, 'params': params, 'count': len(data)})
        return data

    online = rpc('online_prices_v3', {'search_query': ''})
    assert online, 'No current online observations'
    assert all(r['branch_id'] is None and r['distance_km'] is None for r in online)
    pages = [rpc('online_prices_v3', {'search_query': '', 'limit_count': 2, 'page_number': n}) for n in range(1, len(online)//2+3)]
    urls = [r['store_product_url'] for p in pages for r in p]
    assert len(urls) == len(set(urls)) == len(online)
    assert pages[-1] == []
    search = rpc('online_prices_v3', {'search_query': 'mayonesa'})
    assert search and all('mayonesa' in r['product_name'].lower() for r in search)
    categories = rpc('catalog_categories_v3', {})
    for category in categories:
        filtered = rpc('online_prices_v3', {'search_query': '', 'category_filter': category['name']})
        assert filtered and all(r['category'] == category['name'] for r in filtered)
    local = rpc('nearby_prices_v3', {'search_query': '', 'user_latitude': 19.432608, 'user_longitude': -99.133209})
    assert all(r['branch_id'] and r['branch_name'] and r['branch_address'] and r['observation_url'].startswith('https://') for r in local)
    empty = rpc('nearby_prices_v3', {'search_query': '', 'user_latitude': 0, 'user_longitude': 0})
    assert empty == []
    assert not {r['store_product_url'] for r in online} & {r['store_product_url'] for r in local}
    args.out.write_text(json.dumps({'calls': calls, 'online': online, 'local': local, 'passed': True}, ensure_ascii=False, indent=2))
    print(f'RPC smoke passed: {len(online)} online; {len(local)} local; {len(calls)} public calls')


if __name__ == '__main__':
    main()
