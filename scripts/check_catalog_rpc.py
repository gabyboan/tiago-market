"""Compare RPC results and privileges in the isolated PostgreSQL CI database."""
from pathlib import Path
import subprocess


def main():
    root = Path(__file__).resolve().parents[1] / 'apps/flutter_app/supabase'
    old = (root / 'migrations/20260923143000_catalog_variant_rpc_v4.sql').read_text()
    baseline = old.split('create or replace function public.nearby_prices_v4', 1)[0]
    sql = '\n'.join([
        'begin;',
        (root / 'tests/catalog_rpc_fixture_schema.sql').read_text(),
        (root / 'migrations/20261013124052_optimize_current_catalog_metadata.sql').read_text(),
        baseline.replace('online_prices_v4', 'online_prices_v4_baseline'),
        (root / 'migrations/20261022161501_optimize_online_catalog_lookup.sql').read_text(),
        (root / 'tests/catalog_rpc_equivalence.sql').read_text(),
        'rollback;',
    ])
    subprocess.run(['psql', '-X', '--set', 'ON_ERROR_STOP=1'], input=sql, text=True, check=True)


if __name__ == '__main__':
    main()
