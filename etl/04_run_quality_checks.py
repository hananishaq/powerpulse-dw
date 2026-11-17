"""Persist independent source-to-warehouse checks and export reviewable evidence."""
import argparse
import json
import uuid

from psycopg.rows import dict_row
from psycopg.types.json import Jsonb
from common import ROOT, EVIDENCE, connect, revision, run_sql, write_json
from source_evidence import load_source_evidence

CHECK_FILES = ["10_completeness_checks.sql", "20_accuracy_checks.sql", "30_integrity_checks.sql"]
REPORTING_FILES = ["00_base_views.sql", "10_business_question_views.sql"]


def run_quality(negative_tests=True, extra_checks=()):
    run_id = uuid.uuid4()
    error = None
    with connect(autocommit=True, row_factory=dict_row) as conn:
        run_sql(conn, "sql/05_quality/00_create_dq_result_table.sql")
        version = conn.execute("SELECT version() AS version").fetchone()["version"]
        conn.execute("""INSERT INTO project_reporting.dq_run
            (run_id,status,source_commit,server_version) VALUES (%s,'RUNNING',%s,%s)""",
            (run_id, revision(), version))
        conn.execute("SELECT set_config('powerpulse.dq_run_id',%s,false)", (str(run_id),))
        try:
            # Freshly created dimensions otherwise have default cardinality estimates,
            # which can turn hour-grain joins into very expensive partial merge joins.
            for table in ["dim_date","dim_hour","dim_balancing_authority","dim_energy_source",
                          "dim_source_snapshot","fact_hourly_demand","fact_hourly_generation"]:
                from psycopg import sql
                conn.execute(sql.SQL("ANALYZE project_dw.{}").format(sql.Identifier(table)))
            # Source evidence uses a tuple cursor for COPY and does not fetch rows.
            with conn.transaction():
                inputs = load_source_evidence(conn)
                conn.execute("UPDATE project_reporting.dq_run SET input_files=%s WHERE run_id=%s",
                             (Jsonb(inputs), run_id))
                for filename in REPORTING_FILES:
                    run_sql(conn, "sql/06_reporting/" + filename)
            files = CHECK_FILES + (["40_negative_tests.sql"] if negative_tests else [])
            for filename in files:
                print("Quality:", filename, flush=True)
                with conn.transaction():
                    run_sql(conn, "sql/05_quality/" + filename)
            for check in extra_checks:
                conn.execute("SELECT project_reporting.record_check(%s,%s,%s,%s,%s)", check)
            views = conn.execute("""SELECT table_name FROM information_schema.views
                WHERE table_schema='project_reporting' AND table_name ~ '^vw_q[0-9]{2}_'
                ORDER BY table_name""").fetchall()
            for view in views:
                name = view["table_name"]
                # Identifiers originate in information_schema, still quote explicitly.
                from psycopg import sql
                count = conn.execute(sql.SQL("SELECT COUNT(*) AS n FROM project_reporting.{}")
                                     .format(sql.Identifier(name))).fetchone()["n"]
                conn.execute("SELECT project_reporting.record_check(%s,'Reporting',1,%s,%s)",
                             (name, int(count > 0), f"View executes; {count} result rows"))
            conn.execute("SELECT project_reporting.record_check('business_view_count','Reporting',10,%s,%s)",
                         (len(views), "All ten business question views exist"))
            failed = conn.execute("""SELECT COUNT(*) AS n FROM project_reporting.dq_check_result
                WHERE run_id=%s AND status='FAIL'""", (run_id,)).fetchone()["n"]
            status = "FAIL" if failed else "PASS"
        except (Exception, KeyboardInterrupt) as exc:
            status, error = "ERROR", str(exc)
        conn.execute("""UPDATE project_reporting.dq_run SET completed_at=clock_timestamp(),
            status=%s,error_message=%s WHERE run_id=%s""", (status, error, run_id))
        metadata = conn.execute("SELECT * FROM project_reporting.dq_run WHERE run_id=%s", (run_id,)).fetchone()
        results = conn.execute("""SELECT check_name,category,expected,actual,status,detail,checked_at
            FROM project_reporting.dq_check_result WHERE run_id=%s ORDER BY result_id""", (run_id,)).fetchall()
        coverage = conn.execute("SELECT * FROM project_reporting.vw_q10_monthly_source_quality ORDER BY authority_code,calendar_year,month_number").fetchall() if not error else []
        metrics = conn.execute("""SELECT SUM(demand_energy_mwh) AS observed_demand_energy_mwh,
            SUM(eligible_hours) AS eligible_demand_hours FROM project_reporting.vw_q01_monthly_demand_energy""").fetchone() if not error else {}
    payload = dict(run=metadata, checks=results, monthly_coverage=coverage, metrics=metrics,
                   negative_tests_requested=negative_tests)
    write_json(EVIDENCE / f"dq_{run_id}.json", payload)
    write_json(EVIDENCE / "latest_dq.json", payload)
    passed = sum(r["status"] == "PASS" for r in results)
    print(f"Quality {status}: {passed}/{len(results)} checks; run {run_id}", flush=True)
    for result in results:
        if result["status"] == "FAIL":
            print(f"FAIL {result['check_name']}: expected={result['expected']} actual={result['actual']}")
    if error:
        print("Quality error:", error)
    return payload


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--skip-negative-tests", action="store_true")
    args = parser.parse_args()
    result = run_quality(not args.skip_negative_tests)
    raise SystemExit(0 if result["run"]["status"] == "PASS" else 1)


if __name__ == "__main__":
    main()
