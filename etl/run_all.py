#!/usr/bin/env python3
"""Run the warehouse load and optionally Mohid's Phase 3 reporting.

Create the database and configure .env first. No credentials are committed.
"""
import argparse
import os
from pathlib import Path
import subprocess
import sys

import psycopg
from dotenv import load_dotenv

ROOT = Path(__file__).resolve().parents[1]


def initialize_warehouse():
    config = {key: os.getenv(env, default) for key, env, default in [
        ('host', 'PGHOST', 'localhost'), ('port', 'PGPORT', '5432'),
        ('dbname', 'PGDATABASE', 'powerpulse_dw'), ('user', 'PGUSER', 'postgres')]}
    if os.getenv('PGPASSWORD'):
        config['password'] = os.environ['PGPASSWORD']
    with psycopg.connect(**config, connect_timeout=10) as conn:
        for script in ['00_create_dimensions.sql', '01_create_facts.sql']:
            conn.execute((ROOT / 'sql/02_dw' / script).read_text(encoding='utf-8'))
    print('SUCCESS: warehouse schema initialized', flush=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--phase3', action='store_true',
                        help="Install and validate Mohid's demand reporting views after ETL")
    parser.add_argument('--refresh-bi-snapshot', action='store_true',
                        help='With --phase3, embed validated full results into the BI source project')
    args = parser.parse_args()
    if args.refresh_bi_snapshot and not args.phase3:
        parser.error('--refresh-bi-snapshot requires --phase3')
    load_dotenv(ROOT / '.env')
    steps = [('Staging load', '01_load_staging.py'),
             ('Dimension load', '02_load_dimensions.py'),
             ('Fact load', '03_load_facts.py')]
    if args.phase3:
        steps.append(('Mohid Phase 3 reporting and reconciliation', '05_run_phase3_mohid.py'))
    print('PowerPulse warehouse pipeline', flush=True)
    for name, script in steps:
        if script == '02_load_dimensions.py':
            initialize_warehouse()
        print(f'Starting: {name}', flush=True)
        command = [sys.executable, str(ROOT / 'etl' / script)]
        if script == '05_run_phase3_mohid.py' and args.refresh_bi_snapshot:
            command.append('--refresh-bi-snapshot')
        result = subprocess.run(command, cwd=ROOT)
        if result.returncode:
            raise SystemExit(f'FAILED: {name} (exit {result.returncode})')
        print(f'SUCCESS: {name}', flush=True)
    print('DONE: selected ETL/reporting stages completed. See the team checklist '
          'for warehouse-wide quality and final submission sign-off.', flush=True)


if __name__ == '__main__':
    main()
