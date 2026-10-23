"""Restore a downloaded private snapshot archive. Defaults to a rollback check.

Download the .ndjson.gz and its .manifest.json from catalog-private-archives
using the Supabase dashboard or an authenticated Storage client first.
"""
import argparse
import gzip
import hashlib
import json
import os
from pathlib import Path

from refresh_online_catalog import Database, literal


def restore_sql(path, manifest, *, apply=False):
    metadata = json.loads(manifest.read_text())
    if (metadata.get('table') != 'public.price_snapshots' or metadata.get('format') != 1
            or metadata.get('sha256') != hashlib.sha256(path.read_bytes()).hexdigest()):
        raise ValueError('Archive manifest/checksum mismatch')
    rows = [json.loads(line)['row'] for line in gzip.decompress(path.read_bytes()).splitlines()]
    if len(rows) != metadata['rows'] or len({row['id'] for row in rows}) != len(rows):
        raise ValueError('Archive row count/identity mismatch')
    return "begin;\nwith restored as (insert into public.price_snapshots select * from " + \
        "jsonb_populate_recordset(null::public.price_snapshots," + literal(json.dumps(rows)) + \
        "::jsonb) on conflict do nothing returning id) select count(*) as restored from restored;\n" + \
        ('commit;' if apply else 'rollback;')


def main():
    os.umask(0o077)
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--archive', type=Path, required=True)
    parser.add_argument('--manifest', type=Path, required=True)
    parser.add_argument('--work-dir', type=Path, required=True)
    parser.add_argument('--apply', action='store_true')
    args = parser.parse_args()
    args.work_dir.mkdir(parents=True, exist_ok=True, mode=0o700)
    sql = restore_sql(args.archive, args.manifest, apply=args.apply)
    Database(args.work_dir).execute(sql, 'restore-commit' if args.apply else 'restore-rollback')
    print('Restore committed.' if args.apply else 'Restore rollback check passed; no rows changed.')


if __name__ == '__main__':
    main()
