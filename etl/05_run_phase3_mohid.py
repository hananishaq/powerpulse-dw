#!/usr/bin/env python3
"""Install and validate Mohid's reporting views; export selected results on request.

Does not rebuild Phase 2 or change warehouse data. Credentials stay in .env.
Example: python etl/05_run_phase3_mohid.py --export-dir reports/phase3/mohid/results
"""
import argparse
import csv
import os
from datetime import date
from pathlib import Path

import psycopg
from dotenv import load_dotenv

ROOT = Path(__file__).resolve().parents[1]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--from-month', type=date.fromisoformat, default=date(2024, 1, 1))
    parser.add_argument('--to-month', type=date.fromisoformat, default=date(2026, 1, 1),
                        help='Exclusive end month')
    parser.add_argument('--authority', action='append', help='Repeat for multiple BA codes')
    parser.add_argument('--export-dir', type=Path, help='Optional CSV output; not required to install views')
    args = parser.parse_args()
    if args.from_month.day != 1 or args.to_month.day != 1 or args.from_month >= args.to_month:
        parser.error('Use first-of-month dates and from-month < to-month')
    authorities = args.authority or ['CISO', 'ERCO', 'ISNE', 'NYIS', 'PJM']
    if set(authorities) - {'CISO', 'ERCO', 'ISNE', 'NYIS', 'PJM'}:
        parser.error('Unknown authority; allowed: CISO, ERCO, ISNE, NYIS, PJM')

    load_dotenv(ROOT / '.env')
    config = {key: os.getenv(env, default) for key, env, default in [
        ('host', 'PGHOST', 'localhost'), ('port', 'PGPORT', '5432'),
        ('dbname', 'PGDATABASE', 'powerpulse_dw'), ('user', 'PGUSER', 'postgres')]}
    if os.getenv('PGPASSWORD'):
        config['password'] = os.environ['PGPASSWORD']

    try:
        with psycopg.connect(**config, connect_timeout=10) as conn:
            with conn.cursor() as cur:
                cur.execute("SET LOCAL statement_timeout = '120s'")
                for name in ['sql/06_reporting/p1_demand_views.sql',
                             'sql/07_phase3_analytics/p1_validate.sql']:
                    cur.execute((ROOT / name).read_text(encoding='utf-8'))
                    print(f'PASS: {name}')
                # Validate before committing: a failed check rolls back the view changes.
            conn.commit()
            with conn.transaction():
                conn.execute('SET TRANSACTION ISOLATION LEVEL REPEATABLE READ, READ ONLY')
                conn.execute("SET LOCAL statement_timeout = '120s'")
                for filename, view in [
                    ('q01_monthly_demand.csv', 'vw_q01_monthly_demand_energy'),
                    ('q02_hourly_profile.csv', 'vw_q02_hourly_profile'),
                    ('authority_analysis.csv', 'vw_authority_analysis')]:
                    # Identifiers are fixed in this source; only values are supplied by the CLI.
                    with conn.cursor() as cur:
                        cur.execute(f'SELECT * FROM project_reporting.{view} '
                                    'WHERE month_start >= %s AND month_start < %s '
                                    'AND authority_code = ANY(%s) '
                                    + ('ORDER BY authority_code, month_start, hour_ending'
                                       if filename.startswith('q02') else
                                       'ORDER BY authority_code, month_start'),
                                    (args.from_month, args.to_month, authorities))
                        rows = cur.fetchall()
                        print(f'{view}: {len(rows)} selected rows')
                        if args.export_dir:
                            args.export_dir.mkdir(parents=True, exist_ok=True)
                            target = args.export_dir / filename
                            with target.open('w', newline='', encoding='utf-8') as stream:
                                writer = csv.writer(stream)
                                writer.writerow([col.name for col in cur.description])
                                writer.writerows(rows)
                            print(f'Exported {target}')
    except psycopg.Error as error:
        # Do not echo connection strings or configuration values.
        raise SystemExit(f'Phase 3 failed ({error.sqlstate or "connection"}): '
                         f'{error.diag.message_primary or "check local PostgreSQL settings"}') from None
    print('DONE: Mohid reporting package installed and reconciled.')


if __name__ == '__main__':
    main()
