"""Non-destructive integration runner for the frozen Phase 2 baseline."""
import argparse
import hashlib
import importlib.util
import json
import subprocess
import sys
import uuid
from pathlib import Path

from psycopg import sql
from common import ROOT, EVIDENCE, connect, connection_settings, revision, run_sql, utc_now, write_json


def fingerprint(conn):
    """Ordered business-key/identity digests; sequence counters are not identity mappings."""
    queries = {
        "date": "SELECT calendar_date,date_key FROM project_dw.dim_date ORDER BY calendar_date",
        "hour": "SELECT hour_ending,hour_key FROM project_dw.dim_hour ORDER BY hour_ending",
        "authority": "SELECT authority_code,authority_key FROM project_dw.dim_balancing_authority ORDER BY authority_code",
        "fuel": "SELECT source_column,energy_source_key FROM project_dw.dim_energy_source ORDER BY source_column",
        "snapshot": "SELECT file_name,sha256,source_snapshot_key FROM project_dw.dim_source_snapshot ORDER BY file_name,sha256",
        "demand": "SELECT authority_key,utc_hour_end,demand_key FROM project_dw.fact_hourly_demand ORDER BY authority_key,utc_hour_end",
        "generation": "SELECT authority_key,utc_hour_end,energy_source_key,generation_key FROM project_dw.fact_hourly_generation ORDER BY authority_key,utc_hour_end,energy_source_key",
    }
    result = {}
    for label, query in queries.items():
        digest, count = hashlib.sha256(), 0
        with conn.cursor(name="fingerprint_" + label) as cur:
            cur.execute(query)
            for row in cur:
                digest.update((json.dumps(row, default=str, separators=(",", ":")) + "\n").encode())
                count += 1
        result[label] = dict(rows=count, sha256=digest.hexdigest())
    return result


def bootstrap():
    name = connection_settings()["dbname"]
    with connect(database="postgres", autocommit=True) as conn:
        if not conn.execute("SELECT 1 FROM pg_database WHERE datname=%s", (name,)).fetchone():
            conn.execute(sql.SQL("CREATE DATABASE {}").format(sql.Identifier(name)))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--bootstrap", action="store_true", help="create target database if absent (requires CREATEDB)")
    parser.add_argument("--report", action="store_true", help="build PDF from measured quality evidence")
    args = parser.parse_args()
    evidence = dict(run_id=str(uuid.uuid4()), started_at=utc_now(), source_commit=revision(),
                    status="RUNNING", steps=[])
    log_path = EVIDENCE / f"pipeline_{evidence['run_id']}.json"

    def step(name, action):
        record = dict(name=name, started_at=utc_now(), status="RUNNING")
        evidence["steps"].append(record)
        print(f"\n=== {name} ===", flush=True)
        try:
            value = action()
            record["status"] = "PASS"
            return value
        except BaseException:
            record["status"] = "FAIL"
            raise
        finally:
            record["completed_at"] = utc_now()
            write_json(log_path, evidence)

    def command(relative):
        result = subprocess.run([sys.executable, str(ROOT / relative)], cwd=ROOT,
                                text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
        print(result.stdout, flush=True)
        evidence["steps"][-1]["output"] = result.stdout
        if result.returncode:
            raise RuntimeError(f"{relative} exited {result.returncode}")

    try:
        if args.bootstrap:
            step("database_bootstrap", bootstrap)
        with connect() as conn:
            existing = conn.execute("SELECT to_regclass('project_dw.fact_hourly_generation')").fetchone()[0]
            before = fingerprint(conn) if existing else None
        def setup():
            with connect() as conn:
                for filename in ["sql/00_setup/01_create_schemas.sql",
                                 "sql/01_staging/00_create_staging_tables.sql",
                                 "sql/02_dw/00_create_dimensions.sql",
                                 "sql/02_dw/01_create_facts.sql",
                                 "sql/05_quality/00_create_dq_result_table.sql"]:
                    run_sql(conn, filename)
        step("physical_schema", setup)
        step("connection_test", lambda: command("etl/00_test_connection.py"))
        step("source_import_and_cleaning", lambda: command("etl/01_load_staging.py"))
        step("dimensions", lambda: command("etl/02_load_dimensions.py"))
        step("facts", lambda: command("etl/03_load_facts.py"))
        with connect() as conn:
            after = fingerprint(conn)
        evidence["identity_fingerprints_before"] = before
        evidence["identity_fingerprints_after"] = after
        extra = []
        if before and before["generation"]["rows"]:
            for label in after:
                extra.append(("rerun_identity_" + label,"Repeatability",1,int(before[label] == after[label]),
                              "Ordered business-key-to-surrogate-key digest unchanged on baseline rerun"))
        spec = importlib.util.spec_from_file_location("quality", ROOT / "etl/04_run_quality_checks.py")
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        result = step("quality_and_reporting", lambda: module.run_quality(extra_checks=extra))
        evidence["dq_run_id"] = str(result["run"]["run_id"])
        if result["run"]["status"] != "PASS":
            evidence["steps"][-1]["status"] = "FAIL"
            raise RuntimeError("Quality gate failed; inspect latest_dq.json")
        evidence["status"] = "PASS"
        if args.report:
            step("quality_report", lambda: command("reports/phase2/build_data_quality_report.py"))
    except (Exception, KeyboardInterrupt) as exc:
        evidence["status"] = "FAIL"
        evidence["error_message"] = str(exc)
        print("PIPELINE FAILED:", exc, file=sys.stderr)
    finally:
        evidence["completed_at"] = utc_now()
        write_json(log_path, evidence)
        write_json(EVIDENCE / "latest_pipeline.json", evidence)
    print(f"Pipeline {evidence['status']}: {log_path.relative_to(ROOT)}")
    return 0 if evidence["status"] == "PASS" else 1


if __name__ == "__main__":
    raise SystemExit(main())
