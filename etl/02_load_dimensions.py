#!/usr/bin/env python3
from pathlib import Path
import os

import psycopg
from dotenv import load_dotenv

ROOT = Path(__file__).resolve().parents[1]
SQL_DIR = ROOT / "sql" / "03_dimension_load"
SCRIPTS = [
    "10_load_dim_hour.sql",
    "11_load_dim_date.sql",
    "12_load_dim_balancing_authority.sql",
    "13_load_dim_energy_source.sql",
    "14_load_dim_source_snapshot.sql",
]
COUNTS = [
    ("dim_hour", 24),
    ("dim_date", 731),
    ("dim_balancing_authority", 5),
    ("dim_energy_source", 19),
    ("dim_source_snapshot", 4),
]

load_dotenv(ROOT / ".env")

connection = {
    "host": os.getenv("PGHOST", "localhost"),
    "port": os.getenv("PGPORT", "5432"),
    "dbname": os.getenv("PGDATABASE", "powerpulse_dw"),
    "user": os.getenv("PGUSER", "postgres"),
    "password": os.getenv("PGPASSWORD"),
}

if not connection["password"]:
    raise SystemExit("PGPASSWORD is missing from .env")

with psycopg.connect(**connection) as conn:
    with conn.cursor() as cur:
        for script in SCRIPTS:
            path = SQL_DIR / script
            print(f"Running {path.relative_to(ROOT)}")
            cur.execute(path.read_text(encoding="utf-8"))
        conn.commit()

        total = 0
        print("\nDimension counts")
        for table, expected in COUNTS:
            cur.execute(f"SELECT COUNT(*) FROM project_dw.{table}")
            actual = cur.fetchone()[0]
            total += actual
            status = "OK" if actual == expected else f"EXPECTED {expected}"
            print(f"{table:28} {actual:4}  {status}")

        print(f"{'TOTAL':28} {total:4}  {'OK' if total == 783 else 'EXPECTED 783'}")

        cur.execute("""
            SELECT authority_code, authority_key
            FROM project_dw.dim_balancing_authority
            WHERE authority_code = 'CISO'
        """)
        row = cur.fetchone()
        print(f"\nCISO lookup: {row if row else 'not found'}")

if total != 783:
    raise SystemExit("Dimension validation failed")

print("\nDONE - dimension loads completed.")
