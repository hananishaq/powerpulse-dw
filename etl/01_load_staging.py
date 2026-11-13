#!/usr/bin/env python3
"""
PowerPulse | Phase 2 | Step 2 - Source import and staging cleaning
Owner: Qasim Tanveer

What it does (safe to run any number of times):
  1. Creates project_staging objects        -> sql/01_staging/00_create_staging_tables.sql
  2. Loads reference data                   -> authority_reference.csv, energy_source_mapping.csv,
                                               source_manifest.json
  3. Loads the 4 EIA-930 CSVs into the raw  -> project_staging.stg_eia930_balance_raw  (all TEXT, via COPY)
  4. Checks raw row counts against the manifest
  5. Cleans raw -> typed clean table        -> sql/01_staging/10_clean_staging.sql

Usage (from the repo root, with .env filled in):
    python etl/01_load_staging.py                 # load + clean
    python etl/01_load_staging.py --load-only     # steps 1-4
    python etl/01_load_staging.py --clean-only    # step 5 only (raw table must already be loaded)
    python etl/01_load_staging.py --self-test     # proves the cleaning rules catch bad data (LOCAL db only)

Exit code 0 = everything reconciled, 1 = a count did not match the manifest or an error occurred.
"""
import argparse
import csv
import json
import os
import re
import sys
from pathlib import Path
from urllib.parse import urlparse

import psycopg
from dotenv import load_dotenv

ROOT = Path(__file__).resolve().parents[1]
DATA_DIR = ROOT / "data_acquisition" / "data"
SQL_DIR = ROOT / "sql" / "01_staging"
SCHEMA = "project_staging"

# CSV header (exact spelling) -> raw table column, in raw table order.
BASE_COLUMNS = [
    ("_SourceFile", "source_file"),
    ("_SourceRow", "source_row"),
    ("Balancing Authority", "balancing_authority"),
    ("Region", "region"),
    ("Data Date", "data_date"),
    ("Hour Number", "hour_number"),
    ("Local Time at End of Hour", "local_time_end"),
    ("UTC Time at End of Hour", "utc_time_end"),
    ("Demand Forecast (MW)", "demand_forecast_mw"),
    ("Demand (MW)", "demand_mw"),
    ("Net Generation (MW)", "net_generation_mw"),
]
RAW_COLUMNS = (
    ["source_file", "source_row", "subset_row_number", "balancing_authority", "region",
     "data_date", "hour_number", "local_time_end", "utc_time_end",
     "demand_forecast_mw", "demand_mw", "net_generation_mw"]
)


def snake(label: str) -> str:
    """'Hydropower and Pumped Storage' -> 'hydropower_and_pumped_storage'"""
    return re.sub(r"[^a-z0-9]+", "_", label.lower()).strip("_")


def connect() -> psycopg.Connection:
    load_dotenv(ROOT / ".env")
    conn = psycopg.connect(
        host=os.getenv("PGHOST", "localhost"),
        port=os.getenv("PGPORT", "5432"),
        dbname=os.getenv("PGDATABASE", "powerpulse_dw"),
        user=os.getenv("PGUSER", "postgres"),
        password=os.getenv("PGPASSWORD", ""),
        autocommit=True,          # the SQL scripts manage their own BEGIN/COMMIT
    )
    return conn


def run_sql_file(conn: psycopg.Connection, path: Path) -> None:
    print(f"  running {path.relative_to(ROOT)}")
    conn.execute(path.read_text(encoding="utf-8"))


def load_reference(conn: psycopg.Connection) -> list[tuple[str, str]]:
    """Load authority reference, fuel mapping and manifest. Returns [(source_column, clean_column), ...]."""
    with conn.transaction():
        conn.execute(
            f"TRUNCATE {SCHEMA}.stg_authority_reference, {SCHEMA}.stg_energy_source_mapping, "
            f"{SCHEMA}.stg_source_file"
        )

        with open(DATA_DIR / "authority_reference.csv", newline="", encoding="utf-8-sig") as fh:
            rows = [
                (r["AuthorityCode"].strip(), r["AuthorityName"].strip(), r["ReportingTimeZone"].strip(),
                 r["RegionCode"].strip(), r["RegionName"].strip())
                for r in csv.DictReader(fh)
            ]
        with conn.cursor() as cur:
            cur.executemany(
                f"INSERT INTO {SCHEMA}.stg_authority_reference "
                "(authority_code, authority_name, reporting_time_zone, region_code, region_name) "
                "VALUES (%s,%s,%s,%s,%s)", rows)
        print(f"  stg_authority_reference : {len(rows)} rows")

        with open(DATA_DIR / "energy_source_mapping.csv", newline="", encoding="utf-8-sig") as fh:
            mapping = [
                (r["SourceColumn"], r["SourceLabel"], r["SourceGroup"],
                 int(r["NumericCellsInBaseline"]), "gen_" + snake(r["SourceLabel"]))
                for r in csv.DictReader(fh)
            ]
        with conn.cursor() as cur:
            cur.executemany(
                f"INSERT INTO {SCHEMA}.stg_energy_source_mapping "
                "(source_column, source_label, source_group, numeric_cells_in_baseline, clean_column) "
                "VALUES (%s,%s,%s,%s,%s)", mapping)
        print(f"  stg_energy_source_mapping: {len(mapping)} rows")

        manifest = json.loads((DATA_DIR / "source_manifest.json").read_text(encoding="utf-8"))
        files = [
            (Path(urlparse(f["url"]).path).name, f["url"], f["retrieved_at_utc"], f["sha256"],
             f["source_rows"], f["selected_rows"], f["subset_file"], f["subset_sha256"])
            for f in manifest["files"]
        ]
        with conn.cursor() as cur:
            cur.executemany(
                f"INSERT INTO {SCHEMA}.stg_source_file "
                "(file_name, source_url, retrieved_at_utc, sha256, source_row_count, "
                " selected_row_count, subset_file_name, subset_sha256) "
                "VALUES (%s,%s,%s,%s,%s,%s,%s,%s)", files)
        print(f"  stg_source_file         : {len(files)} rows")
    return [(m[0], m[4]) for m in mapping]


def load_raw_csvs(conn: psycopg.Connection, fuel_map: list[tuple[str, str]]) -> None:
    """COPY the 4 CSVs into the raw table. Per file, only the columns that exist are read."""
    fuel_headers = [h for h, _ in fuel_map]
    fuel_cols = [c for _, c in fuel_map]
    all_cols = RAW_COLUMNS + fuel_cols
    manifest = json.loads((DATA_DIR / "source_manifest.json").read_text(encoding="utf-8"))

    with conn.transaction():
        conn.execute(f"TRUNCATE {SCHEMA}.stg_eia930_balance_raw RESTART IDENTITY")
        for f in manifest["files"]:
            path = DATA_DIR / f["subset_file"]
            with open(path, newline="", encoding="utf-8-sig") as fh:
                reader = csv.reader(fh)
                header = next(reader)
                pos = {}
                for i, h in enumerate(header):        # first occurrence wins
                    pos.setdefault(h, i)
                missing_base = [h for h, _ in BASE_COLUMNS if h not in pos]
                if missing_base:
                    raise SystemExit(f"{path.name}: missing required columns {missing_base}")
                present_fuel = [h for h in fuel_headers if h in pos]
                absent_fuel = [h for h in fuel_headers if h not in pos]
                print(f"  {path.name}: {len(header)} columns, "
                      f"{len(present_fuel)} reported fuel columns, {len(absent_fuel)} absent -> NULL")

                n = 0
                copy_sql = f"COPY {SCHEMA}.stg_eia930_balance_raw ({', '.join(all_cols)}) FROM STDIN"
                with conn.cursor() as cur, cur.copy(copy_sql) as copy:
                    for line_no, row in enumerate(reader, start=1):
                        if not row:
                            continue
                        values = [row[pos[h]] for h, _ in BASE_COLUMNS[:2]]      # source_file, source_row
                        values.append(line_no)                                   # subset_row_number
                        values += [row[pos[h]] for h, _ in BASE_COLUMNS[2:]]
                        # absent column -> None (SQL NULL); present blank cell stays ''
                        values += [row[pos[h]] if h in pos else None for h in fuel_headers]
                        copy.write_row(values)
                        n += 1
            print(f"    loaded {n:,} rows")


def verify_counts(conn: psycopg.Connection) -> bool:
    rows = conn.execute(f"""
        SELECT s.file_name, s.selected_row_count, COUNT(r.raw_row_id)
        FROM {SCHEMA}.stg_source_file s
        LEFT JOIN {SCHEMA}.stg_eia930_balance_raw r ON r.source_file = s.file_name
        GROUP BY s.file_name, s.selected_row_count ORDER BY s.file_name""").fetchall()
    ok = True
    print("\n  Raw rows per file vs manifest")
    print(f"  {'file':36} {'manifest':>9} {'loaded':>9}  status")
    for name, expected, loaded in rows:
        good = expected == loaded
        ok &= good
        print(f"  {name:36} {expected:>9,} {loaded:>9,}  {'OK' if good else 'MISMATCH'}")
    total_expected = sum(r[1] for r in rows)
    total_loaded = sum(r[2] for r in rows)
    stray = conn.execute(
        f"SELECT COUNT(*) FROM {SCHEMA}.stg_eia930_balance_raw r WHERE NOT EXISTS "
        f"(SELECT 1 FROM {SCHEMA}.stg_source_file s WHERE s.file_name = r.source_file)").fetchone()[0]
    ok &= (total_expected == total_loaded) and stray == 0
    print(f"  {'TOTAL':36} {total_expected:>9,} {total_loaded:>9,}  {'OK' if ok else 'MISMATCH'}"
          f"   (rows with unknown source file: {stray})")
    return ok


def print_clean_summary(conn: psycopg.Connection) -> None:
    clean = conn.execute(f"SELECT COUNT(*) FROM {SCHEMA}.stg_eia930_balance_clean").fetchone()[0]
    rejected = conn.execute(
        f"SELECT COUNT(*) FROM {SCHEMA}.stg_load_exception WHERE action_taken = 'ROW_REJECTED'").fetchone()[0]
    nulled = conn.execute(
        f"SELECT COUNT(*) FROM {SCHEMA}.stg_load_exception WHERE action_taken = 'VALUE_SET_NULL'").fetchone()[0]
    print("\n  Cleaning result")
    print(f"  stg_eia930_balance_clean : {clean:,} rows")
    print(f"  rows rejected            : {rejected:,}")
    print(f"  cell values set to NULL  : {nulled:,}")
    print("\n  Cleaning log (rule, scope, before -> after, affected)")
    for rule, scope, before, after, affected in conn.execute(
        f"SELECT rule_id, scope, rows_before, rows_after, rows_affected "
        f"FROM {SCHEMA}.stg_cleaning_log WHERE scope IN ('ALL') OR rule_id IN ('C01') ORDER BY log_id"):
        print(f"  {rule:4} {scope[:38]:38} {str(before):>9} -> {str(after):>9}   affected {affected}")


# Expected outcome of the 9 dirty rows in 95_selftest_insert_dirty_rows.sql: source_row -> (rule, reason)
SELFTEST_EXPECTED = {
    "1":      ("C09", "DUPLICATE_AUTHORITY_UTC_HOUR"),
    "900003": ("C03", "UNKNOWN_AUTHORITY_CODE"),
    "900004": ("C04", "INVALID_DATA_DATE"),
    "900005": ("C05", "INVALID_HOUR_NUMBER"),
    "900006": ("C03", "REGION_DOES_NOT_MATCH_AUTHORITY"),
    "900007": ("C05", "INVALID_UTC_OFFSET"),
    "900008": ("C01", "UNKNOWN_SOURCE_FILE"),
}


def run_self_test(conn: psycopg.Connection) -> dict:
    """Insert 9 dirty rows, run the cleaning SQL, check every rule fired, then restore the real data.
    Returns the evidence (used by the Data Cleaning Report). Raises AssertionError if a rule failed."""
    baseline = conn.execute(f"SELECT COUNT(*) FROM {SCHEMA}.stg_eia930_balance_clean").fetchone()[0]
    if baseline != 87720:
        raise SystemExit("Self-test needs the normal baseline first: run  python etl/01_load_staging.py")
    evidence: dict = {}
    try:
        run_sql_file(conn, SQL_DIR / "95_selftest_insert_dirty_rows.sql")
        run_sql_file(conn, SQL_DIR / "10_clean_staging.sql")
        evidence["clean_rows"] = conn.execute(f"SELECT COUNT(*) FROM {SCHEMA}.stg_eia930_balance_clean").fetchone()[0]
        evidence["exceptions"] = conn.execute(
            f"SELECT rule_id, reason, action_taken, column_name, bad_value, source_file, source_row "
            f"FROM {SCHEMA}.stg_load_exception ORDER BY rule_id, source_row").fetchall()
        evidence["standardised"] = conn.execute(
            f"SELECT authority_code, region_code, source_row FROM {SCHEMA}.stg_eia930_balance_clean "
            f"WHERE source_row = 900001").fetchall()
        evidence["nulled_demand"] = conn.execute(
            f"SELECT authority_code, actual_demand_mw, total_generation_mw FROM {SCHEMA}.stg_eia930_balance_clean "
            f"WHERE source_row = 900009").fetchall()
        evidence["log"] = conn.execute(
            f"SELECT rule_id, rule_name, rows_before, rows_after, rows_affected FROM {SCHEMA}.stg_cleaning_log "
            f"WHERE scope = 'ALL' ORDER BY log_id").fetchall()
    finally:                                     # always put the real data back
        run_sql_file(conn, SQL_DIR / "96_selftest_remove_dirty_rows.sql")
        run_sql_file(conn, SQL_DIR / "10_clean_staging.sql")

    rejected = {r[6]: (r[0], r[1]) for r in evidence["exceptions"] if r[2] == "ROW_REJECTED"}
    nulled = [r for r in evidence["exceptions"] if r[2] == "VALUE_SET_NULL"]
    checks = [
        ("clean table = 87,720 real rows + 2 kept dirty rows", evidence["clean_rows"] == 87722),
        ("7 dirty rows rejected, each with the expected rule and reason", rejected == SELFTEST_EXPECTED),
        ("1 non-numeric cell set to NULL (rule C06)", len(nulled) == 1 and nulled[0][4] == "N/A"),
        ("' pjm ' / 'mida ' standardised to PJM / MIDA (rule C02)", evidence["standardised"] == [("PJM", "MIDA", 900001)]),
        ("blank / non-numeric demand stays NULL, row kept", evidence["nulled_demand"] == [("CISO", None, 450)]),
    ]
    restored = conn.execute(f"SELECT COUNT(*) FROM {SCHEMA}.stg_eia930_balance_clean").fetchone()[0]
    leftover = conn.execute(f"SELECT COUNT(*) FROM {SCHEMA}.stg_load_exception").fetchone()[0]
    checks.append(("real data restored: 87,720 clean rows, 0 exceptions", restored == 87720 and leftover == 0))
    evidence["checks"] = checks
    print("\n  Self-test results")
    for name, ok in checks:
        print(f"  [{'PASS' if ok else 'FAIL'}] {name}")
    if not all(ok for _, ok in checks):
        raise AssertionError("cleaning self-test failed")
    return evidence


def main() -> int:
    ap = argparse.ArgumentParser(description="Load and clean the PowerPulse staging layer.")
    mode = ap.add_mutually_exclusive_group()
    mode.add_argument("--load-only", action="store_true", help="create tables and load raw data, skip cleaning")
    mode.add_argument("--clean-only", action="store_true", help="only run the cleaning SQL on the existing raw table")
    mode.add_argument("--self-test", action="store_true",
                      help="add 9 dirty rows, prove the cleaning rules catch them, then restore (LOCAL db only)")
    args = ap.parse_args()

    try:
        conn = connect()
    except psycopg.Error as exc:
        print(f"Could not connect to PostgreSQL: {exc}\nCheck .env (PGHOST, PGPORT, PGDATABASE, PGUSER, PGPASSWORD).")
        return 1

    with conn:
        ok = True
        if args.self_test:
            try:
                run_self_test(conn)
            except AssertionError as exc:
                print(f"\nSELF-TEST FAILED: {exc}")
                return 1
            print("\nDONE - every cleaning rule caught its bad row and the real data is restored.")
            return 0
        if not args.clean_only:
            print("1) Creating staging objects")
            run_sql_file(conn, SQL_DIR / "00_create_staging_tables.sql")
            print("2) Loading reference data and manifest")
            fuel_map = load_reference(conn)
            print("3) Loading the four EIA-930 CSVs into the raw table")
            load_raw_csvs(conn, fuel_map)
            print("4) Reconciling against the manifest")
            ok = verify_counts(conn)
        if not args.load_only:
            print("5) Cleaning raw -> typed clean table")
            run_sql_file(conn, SQL_DIR / "10_clean_staging.sql")
            print_clean_summary(conn)

    print("\nDONE - all counts reconciled." if ok else "\nFINISHED WITH MISMATCHES - see above.")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
