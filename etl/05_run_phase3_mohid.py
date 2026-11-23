#!/usr/bin/env python3
"""Install and validate Mohid's reporting views; export selected results on request.

Does not rebuild Phase 2 or change warehouse data. Credentials stay in .env.
Example: python etl/05_run_phase3_mohid.py --export-dir reports/phase3/mohid/results
"""
import argparse
import base64
import csv
import hashlib
import json
import os
import re
import zlib
from datetime import date, datetime, timezone
from decimal import Decimal
from pathlib import Path

import psycopg
from dotenv import load_dotenv

ROOT = Path(__file__).resolve().parents[1]


def refresh_bi_snapshot(conn):
    """Embed validated reporting outputs for a portable, explicitly labeled BI mode.

    Always captures the full warehouse scope, independent of CLI export filters.
    The alternative Warehouse mode continues to use the PostgreSQL connector.
    """
    model_path = ROOT / 'bi/phase3/mohid/PowerPulse_Overview.SemanticModel/model.bim'
    definition = json.loads(model_path.read_text(encoding='utf-8'))
    tables = {t['name']: t for t in definition['model']['tables']}
    payload = {}
    sources = {
        'monthly': ('MonthlyDemand', 'project_reporting.vw_authority_analysis'),
        'months': ('Month', 'project_reporting.vw_q01_monthly_demand_energy'),
        'authorities': ('Authority', 'project_dw.dim_balancing_authority'),
    }
    for key, (table, view) in sources.items():
        columns = [c['sourceColumn'] for c in tables[table]['columns']]
        fields = psycopg.sql.SQL(', ').join(map(psycopg.sql.Identifier, columns))
        query = psycopg.sql.SQL('SELECT DISTINCT {} FROM {}.{} ORDER BY {}').format(
            fields, *map(psycopg.sql.Identifier, view.split('.')), fields)
        with conn.cursor() as cur:
            cur.execute(query)
            payload[key] = [dict(zip(columns, row)) for row in cur.fetchall()]
    with conn.cursor() as cur:
        cur.execute('SELECT file_name, sha256 FROM project_dw.dim_source_snapshot '
                    'ORDER BY file_name, sha256')
        snapshots = [dict(zip(('file_name', 'sha256'), row)) for row in cur.fetchall()]
    payload['metadata'] = {
        'generated_at_utc': datetime.now(timezone.utc).isoformat(),
        'basis': 'Validated project_reporting views; full warehouse selection',
        'view_sql_sha256': hashlib.sha256(
            (ROOT / 'sql/06_reporting/p1_demand_views.sql').read_bytes()).hexdigest(),
        'source_snapshots': snapshots,
    }

    def encode(value):
        if isinstance(value, (date, datetime)):
            return value.isoformat()
        if isinstance(value, Decimal):
            return int(value) if value == value.to_integral_value() else float(value)
        raise TypeError(type(value).__name__)

    packed = json.dumps(payload, default=encode, separators=(',', ':')).encode('utf-8')
    compressor = zlib.compressobj(level=9, wbits=-15)
    data = base64.b64encode(compressor.compress(packed) + compressor.flush()).decode('ascii')
    # Embed the verified data in the partitions, like Desktop's Enter Data
    # format. Shared expressions remain ordinary scalar connection parameters.
    for table in definition['model']['tables']:
        for partition in table['partitions']:
            source = partition['source']
            expression = '\n'.join(source['expression'])
            expression, replacements = re.subn(
                r'Binary\.FromText\("[^"]*", BinaryEncoding\.Base64\)',
                'Binary.FromText("' + data + '", BinaryEncoding.Base64)', expression)
            if replacements != 1:
                raise ValueError(f'Expected one snapshot literal in {table["name"]}')
            source['expression'] = expression.splitlines()
    model_path.write_text(json.dumps(definition, indent=2) + '\n', encoding='utf-8')
    print(f'Embedded verified BI snapshot: {len(payload["monthly"])} authority-months, '
          f'{len(payload["months"])} months, {len(payload["authorities"])} authorities')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--from-month', type=date.fromisoformat, default=date(2024, 1, 1))
    parser.add_argument('--to-month', type=date.fromisoformat, default=date(2026, 1, 1),
                        help='Exclusive end month')
    parser.add_argument('--authority', action='append', help='Repeat for multiple BA codes')
    parser.add_argument('--export-dir', type=Path, help='Optional CSV output; not required to install views')
    parser.add_argument('--refresh-bi-snapshot', action='store_true',
                        help='Embed full validated reporting outputs in the portable BI project')
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
                if args.refresh_bi_snapshot:
                    refresh_bi_snapshot(conn)
    except psycopg.Error as error:
        # Do not echo connection strings or configuration values.
        raise SystemExit(f'Phase 3 failed ({error.sqlstate or "connection"}): '
                         f'{error.diag.message_primary or "check local PostgreSQL settings"}') from None
    print('DONE: Mohid reporting package installed and reconciled.')


if __name__ == '__main__':
    main()
