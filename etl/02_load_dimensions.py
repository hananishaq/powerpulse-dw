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

        # Save existing surrogate-key mappings
        cur.execute("""
            SELECT authority_code, authority_key
            FROM project_dw.dim_balancing_authority
            ORDER BY authority_code
        """)
        before_authorities = dict(cur.fetchall())

        cur.execute("""
            SELECT source_column, energy_source_key
            FROM project_dw.dim_energy_source
            ORDER BY source_column
        """)
        before_sources = dict(cur.fetchall())

        # Run dimension loaders
        for script in SCRIPTS:
            path = SQL_DIR / script
            print(f"Running {path.relative_to(ROOT)}")
            cur.execute(path.read_text(encoding="utf-8"))

        conn.commit()

        # Validate every dimension independently
        print("\nDimension counts")
        validation_failed = False
        total = 0

        for table, expected in COUNTS:
            cur.execute(f"SELECT COUNT(*) FROM project_dw.{table}")
            actual = cur.fetchone()[0]
            total += actual

            if actual == expected:
                print(f"{table:28} {actual:4}  OK")
            else:
                print(f"{table:28} {actual:4}  EXPECTED {expected}")
                validation_failed = True

        print(f"{'TOTAL':28} {total:4}")

        if validation_failed:
            raise SystemExit("Dimension validation failed")

        # Check surrogate keys after rerun
        cur.execute("""
            SELECT authority_code, authority_key
            FROM project_dw.dim_balancing_authority
            ORDER BY authority_code
        """)
        after_authorities = dict(cur.fetchall())

        cur.execute("""
            SELECT source_column, energy_source_key
            FROM project_dw.dim_energy_source
            ORDER BY source_column
        """)
        after_sources = dict(cur.fetchall())

        # First loads add members; previously assigned keys must stay stable.
        if any(after_authorities.get(code) != key
               for code, key in before_authorities.items()):
            raise SystemExit("Authority surrogate keys changed")

        if any(after_sources.get(source) != key
               for source, key in before_sources.items()):
            raise SystemExit("Energy-source surrogate keys changed")

        print("\nSurrogate-key stability: OK")

        # Business-key lookup evidence
        cur.execute("""
            SELECT authority_code, authority_key
            FROM project_dw.dim_balancing_authority
            WHERE authority_code = 'CISO'
        """)
        row = cur.fetchone()

        print(f"CISO lookup: {row if row else 'not found'}")

print("\nDONE - dimension loads completed.")
