#!/usr/bin/env python3
"""Install and reconcile Muaz forecast views. Requires Mohid reporting first.

Optional --export-dir writes two filterable CSVs using one read-only snapshot.
Local database credentials come from .env or the PG* environment variables.
"""
import argparse
import csv
from datetime import date
import os
from pathlib import Path

import psycopg
from dotenv import load_dotenv

ROOT = Path(__file__).resolve().parents[1]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--export-dir', type=Path)
    parser.add_argument('--from-month', type=date.fromisoformat, default=date(2024, 1, 1))
    parser.add_argument('--to-month', type=date.fromisoformat, default=date(2026, 1, 1))
    parser.add_argument('--authority', action='append', choices=['CISO', 'ERCO', 'ISNE', 'NYIS', 'PJM'])
    args = parser.parse_args()
    if args.from_month.day != 1 or args.to_month.day != 1 or args.from_month >= args.to_month:
        parser.error('Use first-of-month dates and from-month < to-month (end exclusive)')
    load_dotenv(ROOT / '.env')
    config = {k: os.getenv(env, default) for k, env, default in [
        ('host', 'PGHOST', 'localhost'), ('port', 'PGPORT', '5432'),
        ('dbname', 'PGDATABASE', 'powerpulse_dw'), ('user', 'PGUSER', 'postgres')]}
    if os.getenv('PGPASSWORD'):
        config['password'] = os.environ['PGPASSWORD']
    try:
        with psycopg.connect(**config, connect_timeout=10) as conn:
            conn.execute("SET LOCAL statement_timeout = '120s'")
            for file in ['sql/06_reporting/p3_forecast_views.sql',
                         'sql/07_phase3_analytics/p3_validate.sql']:
                conn.execute((ROOT / file).read_text(encoding='utf-8'))
                print(f'PASS: {file}')
            conn.commit()
            with conn.transaction():
                conn.execute('SET TRANSACTION ISOLATION LEVEL REPEATABLE READ, READ ONLY')
                for name, view, grain in [
                    ('q05_forecast_accuracy', 'vw_q05_forecast_accuracy', 'authority_code, month_start'),
                    ('q06_month_hour_components', 'vw_forecast_month_hour_components',
                     'authority_code, month_start, hour_ending')]:
                    cur = conn.execute(f'SELECT * FROM project_reporting.{view} '
                                       'WHERE month_start >= %s AND month_start < %s '
                                       f'AND authority_code = ANY(%s) ORDER BY {grain}',
                                       (args.from_month, args.to_month,
                                        args.authority or ['CISO', 'ERCO', 'ISNE', 'NYIS', 'PJM']))
                    rows = cur.fetchall()
                    print(f'{name}: {len(rows)} selected rows')
                    if args.export_dir:
                        args.export_dir.mkdir(parents=True, exist_ok=True)
                        with (args.export_dir / f'{name}.csv').open('w', newline='', encoding='utf-8') as f:
                            writer = csv.writer(f)
                            writer.writerow([col.name for col in cur.description])
                            writer.writerows(rows)
                # Filter Q06 monthly components before season/year aggregation.
                # The named Q06 analytical view covers full seasons; exports retain
                # month-grain components so partial-season filters remain honest.
    except psycopg.Error as error:
        raise SystemExit(f'Forecast reporting failed ({error.sqlstate or "connection"}): '
                         f'{error.diag.message_primary or "check local PostgreSQL settings"}') from None
    print('DONE: Muaz forecast views installed and reconciled.')


if __name__ == '__main__':
    main()
