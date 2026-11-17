#!/usr/bin/env python3
from pathlib import Path
from datetime import datetime, timezone
import os
import uuid

import psycopg
from dotenv import load_dotenv

ROOT = Path(__file__).resolve().parents[1]
SQL_DIR = ROOT / "sql" / "04_fact_load"

SETUP_SCRIPTS = [
    "00_create_etl_run_log.sql",
    "01_create_etl_reject.sql",
]

LOAD_SCRIPTS = [
    ("fact_hourly_demand", "10_load_fact_hourly_demand.sql"),
    ("fact_hourly_generation", "20_load_fact_hourly_generation.sql"),
    ("expected_hour_grid", "30_build_expected_hour_grid.sql"),
    ("fk_indexes", "40_create_fk_indexes.sql"),
]

EXPECTED_COUNTS = {
    "fact_hourly_demand": 87720,
    "fact_hourly_generation": 727720,
    "expected_hour_grid": 87720,
}

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


def now_utc():
    return datetime.now(timezone.utc)


def write_log(
    conn,
    step_name,
    started_at,
    ended_at,
    rows_read=0,
    rows_inserted=0,
    rows_updated=0,
    rows_rejected=0,
    status="SUCCESS",
    error_message=None,
):
    with conn.cursor() as cur:
        cur.execute(
            """
            INSERT INTO project_dw.etl_run_log (
                run_id,
                step_name,
                started_at,
                ended_at,
                rows_read,
                rows_inserted,
                rows_updated,
                rows_rejected,
                status,
                error_message
            )
            VALUES (
                %s, %s, %s, %s,
                %s, %s, %s, %s,
                %s, %s
            )
            """,
            (
                run_id,
                step_name,
                started_at,
                ended_at,
                rows_read,
                rows_inserted,
                rows_updated,
                rows_rejected,
                status,
                error_message,
            ),
        )
    conn.commit()


def get_reject_count(cur):
    cur.execute(
        """
        SELECT COUNT(*)
        FROM project_dw.etl_reject
        WHERE run_id = %s
        """,
        (run_id,),
    )
    return cur.fetchone()[0]


def demand_metrics(cur):
    cur.execute("""
        SELECT COUNT(*)
        FROM project_staging.stg_eia930_balance_clean
    """)
    rows_read = cur.fetchone()[0]

    cur.execute("""
        SELECT COUNT(*)
        FROM project_staging.stg_eia930_balance_clean s
        JOIN project_dw.dim_balancing_authority a
          ON a.authority_code = s.authority_code
        LEFT JOIN project_dw.fact_hourly_demand f
          ON f.authority_key = a.authority_key
         AND f.utc_hour_end = s.utc_hour_end
        WHERE f.demand_key IS NULL
    """)
    rows_inserted = cur.fetchone()[0]

    cur.execute("""
        SELECT COUNT(*)
        FROM project_staging.stg_eia930_balance_clean s
        JOIN project_dw.dim_balancing_authority a
          ON a.authority_code = s.authority_code
        JOIN project_dw.dim_date d
          ON d.calendar_date = s.data_date
        JOIN project_dw.dim_hour h
          ON h.hour_ending =
             EXTRACT(HOUR FROM s.local_hour_end)::smallint
        JOIN project_dw.dim_source_snapshot ss
          ON ss.file_name = s.source_file
         AND ss.sha256 = s.source_sha256
        JOIN project_dw.fact_hourly_demand f
          ON f.authority_key = a.authority_key
         AND f.utc_hour_end = s.utc_hour_end
        WHERE f.date_key IS DISTINCT FROM d.date_key
           OR f.hour_key IS DISTINCT FROM h.hour_key
           OR f.local_hour_end IS DISTINCT FROM s.local_hour_end
           OR f.utc_offset_minutes
                IS DISTINCT FROM s.utc_offset_minutes
           OR f.actual_demand_mw
                IS DISTINCT FROM s.actual_demand_mw
           OR f.forecast_demand_mw
                IS DISTINCT FROM s.forecast_demand_mw
           OR f.total_generation_mw
                IS DISTINCT FROM s.total_generation_mw
           OR f.source_snapshot_key
                IS DISTINCT FROM ss.source_snapshot_key
           OR f.source_row_number
                IS DISTINCT FROM s.source_row
    """)
    rows_updated = cur.fetchone()[0]

    return rows_read, rows_inserted, rows_updated


def generation_metrics(cur):
    cur.execute("""
        SELECT COUNT(*)
        FROM project_staging.stg_eia930_balance_clean s
        CROSS JOIN project_staging.stg_energy_source_mapping m
        WHERE to_jsonb(s) ->> m.clean_column IS NOT NULL
    """)
    rows_read = cur.fetchone()[0]

    cur.execute("""
        WITH source_values AS (
            SELECT
                a.authority_key,
                s.utc_hour_end,
                e.energy_source_key
            FROM project_staging.stg_eia930_balance_clean s
            CROSS JOIN project_staging.stg_energy_source_mapping m
            JOIN project_dw.dim_balancing_authority a
              ON a.authority_code = s.authority_code
            JOIN project_dw.dim_energy_source e
              ON e.source_column = m.source_column
            WHERE to_jsonb(s) ->> m.clean_column IS NOT NULL
        )
        SELECT COUNT(*)
        FROM source_values s
        LEFT JOIN project_dw.fact_hourly_generation f
          ON f.authority_key = s.authority_key
         AND f.utc_hour_end = s.utc_hour_end
         AND f.energy_source_key = s.energy_source_key
        WHERE f.generation_key IS NULL
    """)
    rows_inserted = cur.fetchone()[0]

    cur.execute("""
        WITH source_values AS (
            SELECT
                a.authority_key,
                d.date_key,
                h.hour_key,
                e.energy_source_key,
                s.utc_hour_end,
                s.local_hour_end,
                s.utc_offset_minutes,
                (to_jsonb(s) ->> m.clean_column)::numeric(18,4)
                    AS generation_mw,
                ss.source_snapshot_key,
                s.source_row
            FROM project_staging.stg_eia930_balance_clean s
            CROSS JOIN project_staging.stg_energy_source_mapping m
            JOIN project_dw.dim_balancing_authority a
              ON a.authority_code = s.authority_code
            JOIN project_dw.dim_date d
              ON d.calendar_date = s.data_date
            JOIN project_dw.dim_hour h
              ON h.hour_ending =
                 EXTRACT(HOUR FROM s.local_hour_end)::smallint
            JOIN project_dw.dim_energy_source e
              ON e.source_column = m.source_column
            JOIN project_dw.dim_source_snapshot ss
              ON ss.file_name = s.source_file
             AND ss.sha256 = s.source_sha256
            WHERE to_jsonb(s) ->> m.clean_column IS NOT NULL
        )
        SELECT COUNT(*)
        FROM source_values s
        JOIN project_dw.fact_hourly_generation f
          ON f.authority_key = s.authority_key
         AND f.utc_hour_end = s.utc_hour_end
         AND f.energy_source_key = s.energy_source_key
        WHERE f.date_key IS DISTINCT FROM s.date_key
           OR f.hour_key IS DISTINCT FROM s.hour_key
           OR f.local_hour_end IS DISTINCT FROM s.local_hour_end
           OR f.utc_offset_minutes
                IS DISTINCT FROM s.utc_offset_minutes
           OR f.generation_mw IS DISTINCT FROM s.generation_mw
           OR f.source_snapshot_key
                IS DISTINCT FROM s.source_snapshot_key
           OR f.source_row_number
                IS DISTINCT FROM s.source_row
    """)
    changed = cur.fetchone()[0]

    cur.execute("""
        SELECT COUNT(*)
        FROM project_dw.fact_hourly_generation f
        JOIN project_dw.dim_balancing_authority a
          ON a.authority_key = f.authority_key
        JOIN project_dw.dim_energy_source e
          ON e.energy_source_key = f.energy_source_key
        JOIN project_staging.stg_eia930_balance_clean s
          ON s.authority_code = a.authority_code
         AND s.utc_hour_end = f.utc_hour_end
        JOIN project_staging.stg_energy_source_mapping m
          ON m.source_column = e.source_column
        WHERE to_jsonb(s) ->> m.clean_column IS NULL
    """)
    withdrawn = cur.fetchone()[0]

    return rows_read, rows_inserted, changed + withdrawn


pipeline_started = now_utc()

try:
    with psycopg.connect(**connection) as conn:
        with conn.cursor() as cur:
            for script in SETUP_SCRIPTS:
                path = SQL_DIR / script
                print(f"Running {path.relative_to(ROOT)}")
                cur.execute(path.read_text(encoding="utf-8"))

        conn.commit()

        write_log(
            conn,
            "fact_pipeline",
            pipeline_started,
            None,
            status="RUNNING",
        )

        for step_name, script in LOAD_SCRIPTS:
            step_started = now_utc()
            path = SQL_DIR / script
            print(f"Running {path.relative_to(ROOT)}")

            with conn.cursor() as cur:
                cur.execute(
                    "SELECT set_config('powerpulse.run_id', %s, true)",
                    (str(run_id),),
                )

                rejects_before = get_reject_count(cur)

                rows_read = 0
                rows_inserted = 0
                rows_updated = 0

                if step_name == "fact_hourly_demand":
                    (
                        rows_read,
                        rows_inserted,
                        rows_updated,
                    ) = demand_metrics(cur)

                elif step_name == "fact_hourly_generation":
                    (
                        rows_read,
                        rows_inserted,
                        rows_updated,
                    ) = generation_metrics(cur)

                cur.execute(path.read_text(encoding="utf-8"))

                rejects_after = get_reject_count(cur)
                rows_rejected = rejects_after - rejects_before

            conn.commit()

            write_log(
                conn,
                step_name,
                step_started,
                now_utc(),
                rows_read,
                rows_inserted,
                rows_updated,
                rows_rejected,
                "SUCCESS",
            )

        with conn.cursor() as cur:
            print("\nFinal validation")

            validation_failed = False

            for table, expected in EXPECTED_COUNTS.items():
                cur.execute(f"SELECT COUNT(*) FROM project_dw.{table}")
                actual = cur.fetchone()[0]

                status = "OK" if actual == expected else f"EXPECTED {expected}"
                print(f"{table:30} {actual:8}  {status}")

                if actual != expected:
                    validation_failed = True

            cur.execute("""
                SELECT COUNT(*)
                FROM project_dw.fact_hourly_demand
                WHERE authority_key IS NULL
                   OR date_key IS NULL
                   OR hour_key IS NULL
                   OR source_snapshot_key IS NULL
            """)
            null_demand_keys = cur.fetchone()[0]

            cur.execute("""
                SELECT COUNT(*)
                FROM project_dw.fact_hourly_generation
                WHERE authority_key IS NULL
                   OR date_key IS NULL
                   OR hour_key IS NULL
                   OR energy_source_key IS NULL
                   OR source_snapshot_key IS NULL
            """)
            null_generation_keys = cur.fetchone()[0]

            null_foreign_keys = null_demand_keys + null_generation_keys

            cur.execute("""
                SELECT COUNT(*)
                FROM project_dw.expected_hour_grid g
                LEFT JOIN project_dw.fact_hourly_demand f
                  ON f.authority_key = g.authority_key
                 AND f.utc_hour_end = g.utc_hour_end
                WHERE f.demand_key IS NULL
            """)
            missing_expected_hours = cur.fetchone()[0]

            cur.execute("""
                SELECT COUNT(DISTINCT authority_key)
                FROM project_dw.expected_hour_grid
            """)
            grid_authorities = cur.fetchone()[0]

            print(
                f"{'NULL foreign keys':30} "
                f"{null_foreign_keys:8}  "
                f"{'OK' if null_foreign_keys == 0 else 'FAILED'}"
            )

            print(
                f"{'Missing expected hours':30} "
                f"{missing_expected_hours:8}  "
                f"{'OK' if missing_expected_hours == 0 else 'FAILED'}"
            )

            print(
                f"{'Authorities in grid':30} "
                f"{grid_authorities:8}  "
                f"{'OK' if grid_authorities == 5 else 'EXPECTED 5'}"
            )

            if (
                null_foreign_keys != 0
                or missing_expected_hours != 0
                or grid_authorities != 5
            ):
                validation_failed = True

            if validation_failed:
                raise RuntimeError("Final fact validation failed")

        write_log(
            conn,
            "fact_pipeline",
            pipeline_started,
            now_utc(),
            status="SUCCESS",
        )

except Exception as exc:
    try:
        with psycopg.connect(**connection) as error_conn:
            write_log(
                error_conn,
                "fact_pipeline",
                pipeline_started,
                now_utc(),
                status="FAILED",
                error_message=str(exc),
            )
    except Exception:
        pass

    raise

print(f"\nRun ID: {run_id}")
print("DONE - fact loads completed.")