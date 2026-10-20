#!/usr/bin/env python3
"""Read-only v4 catalog verification with the local publishable configuration.

Optionally compare a published NDJSON batch against every current RPC page.
Original observation timestamps are compared as instants, never rewritten.
"""
import argparse
from datetime import datetime
from decimal import Decimal, InvalidOperation
import json
from pathlib import Path
import time
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen

RPC_NAME = 'online_prices_v4'
PAGE_SIZE = 100
SOURCES = ('chedraui-mx', 'merco-mx')
SEARCHES = ('', 'leche', 'arroz')


class RPCError(RuntimeError):
    """A bounded RPC request failed; callers can still save their batch summary."""


def _timestamp(value):
    if not isinstance(value, str):
        raise ValueError('missing timestamp')
    parsed = datetime.fromisoformat(value.replace('Z', '+00:00'))
    if parsed.tzinfo is None:
        raise ValueError('timestamp requires timezone')
    return parsed


def _price(value):
    if isinstance(value, bool) or value is None:
        raise ValueError('invalid price')
    try:
        price = Decimal(str(value))
    except InvalidOperation as error:
        raise ValueError('invalid price') from error
    if not price.is_finite() or price <= 0:
        raise ValueError('invalid price')
    return price


def _identity(row):
    values = (row.get('source'), row.get('store_product_url'), row.get('normalized_name'))
    return values if all(isinstance(value, str) and value for value in values) else None


def _matches(row, query):
    return any(query in str(row.get(field) or '').lower()
               for field in ('product_name', 'normalized_name'))


def verify(config, expected_rows=None, *, progress=None):
    """Return a JSON-safe report; transport errors raise RPCError, never retry.

    Empty or omitted expected rows select smoke mode. Search results must equal
    the matching rows of the full catalog, including unavailable products and
    both stores wherever those stores have matching current rows.
    """
    key = config.get('SUPABASE_PUBLISHABLE_KEY') or config.get('SUPABASE_ANON_KEY')
    base = config.get('SUPABASE_URL')
    if not isinstance(base, str) or not base or not isinstance(key, str) or not key:
        raise ValueError('SUPABASE_URL and a publishable/anon key are required')
    endpoint = base.rstrip('/') + '/rest/v1/rpc/' + RPC_NAME
    calls, errors = [], []

    def pages(query):
        result, seen = [], set()
        for page in range(1, 10001):
            params = {'search_query': query, 'limit_count': PAGE_SIZE,
                      'page_number': page, 'only_available': False}
            request = Request(endpoint, data=json.dumps(params).encode(), headers={
                'apikey': key, 'Content-Type': 'application/json'})
            context = f'{RPC_NAME} query={query!r} page={page}'
            started = time.monotonic()
            try:
                with urlopen(request, timeout=20) as response:
                    rows = json.load(response)
            except HTTPError as error:
                raise RPCError(f'{context}: HTTP {error.code}') from error
            except (URLError, OSError, ValueError) as error:
                raise RPCError(f'{context}: {type(error).__name__}') from error
            if not isinstance(rows, list) or any(not isinstance(row, dict) for row in rows):
                raise RPCError(f'{context}: expected a JSON array of objects')
            call = {'rpc': RPC_NAME, 'params': params, 'count': len(rows),
                    'elapsed_seconds': round(time.monotonic() - started, 3)}
            calls.append(call)
            if progress:
                progress(call)
            if not rows:
                return result
            if len(rows) > PAGE_SIZE:
                errors.append(f'{context}: page exceeds {PAGE_SIZE} rows')
            duplicate = False
            for row in rows:
                identity = _identity(row)
                if identity is None:
                    errors.append(f'{context}: missing source/store_product_url')
                elif identity in seen:
                    errors.append(f'{context}: duplicate source URL {identity!r}')
                    duplicate = True
                else:
                    seen.add(identity)
                for field in ('branch_id', 'branch_name', 'branch_address',
                              'branch_municipality', 'distance_km'):
                    if field in ('branch_id', 'distance_km') and field not in row:
                        errors.append(f'{context}: missing {field} for {identity!r}')
                    elif row.get(field) is not None:
                        errors.append(f'{context}: non-null online {field} for {identity!r}')
                if row.get('currency') != 'MXN':
                    errors.append(f'{context}: non-MXN currency for {identity!r}')
                if not isinstance(row.get('available'), bool):
                    errors.append(f'{context}: invalid availability for {identity!r}')
                try:
                    _price(row.get('price'))
                    _timestamp(row.get('captured_at'))
                except ValueError as error:
                    errors.append(f'{context}: {error} for {identity!r}')
                result.append(row)
            # Repeated pages or duplicate identities are a contract failure; do
            # not loop until the server's maximum page when pagination is broken.
            if duplicate or len(rows) > PAGE_SIZE:
                return result
        errors.append(f'{RPC_NAME} query={query!r}: pagination did not reach an empty page')
        return result

    online = pages('')
    by_identity = {_identity(row): row for row in online if _identity(row)}
    searches = {'': online}
    for query in SEARCHES[1:]:
        found = pages(query)
        searches[query] = found
        expected_ids = {identity for identity, row in by_identity.items() if _matches(row, query)}
        found_ids = {_identity(row) for row in found if _identity(row)}
        missing, unexpected = expected_ids - found_ids, found_ids - expected_ids
        if missing:
            errors.append(f'{query!r}: missing matching source URLs {sorted(missing)!r}')
        if unexpected:
            errors.append(f'{query!r}: unexpected source URLs {sorted(unexpected)!r}')

    expected_rows = list(expected_rows or [])
    expected_seen, matched = set(), 0
    for expected in expected_rows:
        identity = _identity(expected)
        if identity is None or identity in expected_seen:
            errors.append(f'Expected batch has missing or duplicate source URL {identity!r}')
            continue
        expected_seen.add(identity)
        actual = by_identity.get(identity)
        if actual is None:
            errors.append(f'Expected source URL absent from RPC: {identity!r}')
            continue
        mismatches = []
        try:
            if _price(actual.get('price')) != _price(expected.get('price')):
                mismatches.append('price')
        except ValueError:
            mismatches.append('price')
        for field in ('currency', 'available'):
            if type(actual.get(field)) is not type(expected.get(field)) or actual.get(field) != expected.get(field):
                mismatches.append(field)
        if 'image_url' in expected and actual.get('image_url') != expected.get('image_url'):
            mismatches.append('image_url')
        try:
            expected_at = expected.get('captured_at') or expected.get('observed_at')
            if _timestamp(actual.get('captured_at')) != _timestamp(expected_at):
                mismatches.append('captured_at')
        except ValueError:
            mismatches.append('captured_at')
        if mismatches:
            errors.append(f'Published values differ for {identity!r}: {", ".join(mismatches)}')
        else:
            matched += 1

    by_source = {}
    source_names = set(SOURCES) | {row['source'] for row in online if _identity(row)}
    for source in sorted(source_names):
        rows = [row for row in online if row.get('source') == source]
        timestamps = []
        for row in rows:
            try:
                timestamps.append((_timestamp(row.get('captured_at')), row['captured_at']))
            except ValueError:
                pass  # The contract error is already recorded above.
        by_source[source] = {
            'current': len(rows),
            'available': sum(row.get('available') is True for row in rows),
            'unavailable': sum(row.get('available') is False for row in rows),
            'images': sum(bool(row.get('image_url')) for row in rows),
            'latest_captured_at': max(timestamps)[1] if timestamps else None,
            'searches': {query: sum(row.get('source') == source for row in found)
                         for query, found in searches.items()},
        }
    return {'rpc': RPC_NAME, 'passed': not errors, 'errors': errors,
            'calls': calls, 'online': online, 'searches': searches,
            'by_source': by_source, 'expected_checked': len(expected_rows),
            'expected_matched': matched, 'mode': 'expected' if expected_rows else 'smoke'}


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--defines', type=Path, default=Path('dart_defines.local.json'))
    parser.add_argument('--expected', type=Path, help='Published NDJSON to compare exactly')
    parser.add_argument('--out', type=Path, help='Write the complete JSON verification report')
    args = parser.parse_args(argv)

    def progress(call):
        params = call['params']
        if params['page_number'] == 1 or params['page_number'] % 10 == 0 or not call['count']:
            print(f"{RPC_NAME}: query={params['search_query']!r} "
                  f"page={params['page_number']} rows={call['count']} "
                  f"seconds={call['elapsed_seconds']}", flush=True)

    try:
        config = json.loads(args.defines.read_text())
        expected = ([json.loads(line) for line in args.expected.read_text().splitlines() if line.strip()]
                    if args.expected else None)
        report = verify(config, expected, progress=progress)
    except (RPCError, OSError, ValueError) as error:
        report = {'rpc': RPC_NAME, 'passed': False, 'errors': [str(error)]}
    if args.out:
        args.out.parent.mkdir(parents=True, exist_ok=True)
        args.out.write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n')
    print(f'{RPC_NAME}: {"OK" if report["passed"] else "ERROR"}')
    for source, summary in report.get('by_source', {}).items():
        print(f'{source}: {summary["current"]} actuales; '
              f'{summary["available"]} disponibles; {summary["unavailable"]} sin stock; '
              f'captura {summary["latest_captured_at"]}')
    for error in report['errors']:
        print(error)
    return 0 if report['passed'] else 1


if __name__ == '__main__':
    raise SystemExit(main())
