#!/usr/bin/env python3
from pathlib import Path
from datetime import datetime, timezone
import os
import uuid

import psycopg
from dotenv import load_dotenv

ROOT = Path(__file__).resolve().parents[1]
SQL_DIR = ROOT / "sql" / "04_fact_load"
SCRIPTS = [
    ("create_run_log", "00_create_etl_run_log.sql"),
    ("load_demand", "10_load_fact_hourly_demand.sql"),
    ("load_generation", "20_load_fact_hourly_generation.sql"),
    ("build_expected_grid", "30_build_expected_hour_grid.sql"),
    ("create_fk_indexes", "40_create_fk_indexes.sql"),
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

run_id = uuid.uuid4()

def scalar(cur, sql):
    cur.execute(sql)
    return cur.fetchone()[0]

with psycopg.connect(**connection) as conn:
    with conn.cursor() as cur:
        cur.execute((SQL_DIR / "00_create_etl_run_log.sql").read_text(encoding="utf-8"))
        conn.commit()

        for step_name, filename in SCRIPTS[1:]:
            started = datetime.now(timezone.utc)
            before = 0
            rows_read = 0
            target = None

            if step_name == "load_demand":
                target = "project_dw.fact_hourly_demand"
                before = scalar(cur, f"SELECT COUNT(*) FROM {target}")
                rows_read = scalar(cur, "SELECT COUNT(*) FROM project_staging.stg_eia930_balance_clean")
            elif step_name == "load_generation":
                target = "project_dw.fact_hourly_generation"
                before = scalar(cur, f"SELECT COUNT(*) FROM {target}")
                rows_read = scalar(cur, """
                    SELECT COUNT(*)
                    FROM project_staging.stg_eia930_balance_clean s
                    CROSS JOIN project_staging.stg_energy_source_mapping m
                    WHERE to_jsonb(s) ->> m.clean_column IS NOT NULL
                """)
            elif step_name == "build_expected_grid":
                target = "project_dw.expected_hour_grid"
                before = scalar(cur, "SELECT COUNT(*) FROM project_dw.expected_hour_grid") if scalar(cur, "SELECT to_regclass('project_dw.expected_hour_grid') IS NOT NULL") else 0
                rows_read = scalar(cur, "SELECT COUNT(*) FROM project_dw.fact_hourly_demand")

            try:
                print(f"Running sql\\04_fact_load\\{filename}")
                cur.execute((SQL_DIR / filename).read_text(encoding="utf-8"))
                after = scalar(cur, f"SELECT COUNT(*) FROM {target}") if target else 0
                inserted = max(after - before, 0)
                updated = max(rows_read - inserted, 0) if step_name in ("load_demand", "load_generation") else 0
                ended = datetime.now(timezone.utc)
                cur.execute("""
                    INSERT INTO project_dw.etl_run_log
                    (run_id, step_name, started_at, ended_at, rows_read,
                     rows_inserted, rows_updated, rows_rejected, status)
                    VALUES (%s,%s,%s,%s,%s,%s,%s,0,'SUCCESS')
                """, (run_id, step_name, started, ended, rows_read, inserted, updated))
                conn.commit()
            except Exception as exc:
                conn.rollback()
                ended = datetime.now(timezone.utc)
                cur.execute("""
                    INSERT INTO project_dw.etl_run_log
                    (run_id, step_name, started_at, ended_at, rows_read,
                     rows_inserted, rows_updated, rows_rejected, status, error_message)
                    VALUES (%s,%s,%s,%s,%s,0,0,0,'FAILED',%s)
                """, (run_id, step_name, started, ended, rows_read, str(exc)))
                conn.commit()
                raise

        demand = scalar(cur, "SELECT COUNT(*) FROM project_dw.fact_hourly_demand")
        generation = scalar(cur, "SELECT COUNT(*) FROM project_dw.fact_hourly_generation")
        grid = scalar(cur, "SELECT COUNT(*) FROM project_dw.expected_hour_grid")
        null_fks = scalar(cur, """
            SELECT
              (SELECT COUNT(*) FROM project_dw.fact_hourly_demand
               WHERE authority_key IS NULL OR date_key IS NULL OR hour_key IS NULL OR source_snapshot_key IS NULL)
              +
              (SELECT COUNT(*) FROM project_dw.fact_hourly_generation
               WHERE authority_key IS NULL OR date_key IS NULL OR hour_key IS NULL
                  OR energy_source_key IS NULL OR source_snapshot_key IS NULL)
        """)
        missing_hours = scalar(cur, """
            SELECT COUNT(*)
            FROM project_dw.expected_hour_grid g
            LEFT JOIN project_dw.fact_hourly_demand f
              ON f.authority_key = g.authority_key
             AND f.utc_hour_end = g.utc_hour_end
            WHERE f.demand_key IS NULL
        """)

print("\nFact validation")
print(f"fact_hourly_demand       {demand:>8}  {'OK' if demand == 87720 else 'EXPECTED 87720'}")
print(f"fact_hourly_generation   {generation:>8}  {'OK' if generation == 727720 else 'EXPECTED 727720'}")
print(f"expected_hour_grid        {grid:>8}  {'OK' if grid == 87720 else 'EXPECTED 87720'}")
print(f"NULL foreign keys         {null_fks:>8}  {'OK' if null_fks == 0 else 'FAIL'}")
print(f"Missing expected hours    {missing_hours:>8}  {'OK' if missing_hours == 0 else 'FAIL'}")

if (demand, generation, grid, null_fks, missing_hours) != (87720, 727720, 87720, 0, 0):
    raise SystemExit("Fact validation failed")
print("\nDONE - fact loads completed.")
