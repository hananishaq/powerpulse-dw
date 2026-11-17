"""Exercise the real reporting views and quality detectors; roll back every mutation."""
from pathlib import Path
import sys
import uuid

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "etl"))
from common import EVIDENCE, connect, revision, run_sql, utc_now, write_json
from source_evidence import load_source_evidence


class Revert(Exception):
    pass


def main():
    tests = []
    with connect() as conn:
        load_source_evidence(conn)
        conn.commit()

        def test(name, action):
            observed = None
            try:
                with conn.transaction():
                    observed = action()
                    if not observed:
                        raise AssertionError("Expected detector/reporting behavior was not observed")
                    raise Revert()
            except Revert:
                tests.append(dict(name=name, passed=True, detail=str(observed)))
            except Exception as exc:
                tests.append(dict(name=name, passed=False, detail=str(exc)))
            print(tests[-1], flush=True)

        def prepare_check_run():
            ident = uuid.uuid4()
            conn.execute("""INSERT INTO project_reporting.dq_run
                (run_id,status,source_commit,server_version) VALUES (%s,'RUNNING','transactional-test',version())""",(ident,))
            conn.execute("SELECT set_config('powerpulse.dq_run_id',%s,true)",(str(ident),))
            return ident

        def detector_case(mutation, filename, expected_fail):
            ident = prepare_check_run()
            conn.execute(mutation)
            run_sql(conn, "sql/05_quality/" + filename)
            failed = {r[0] for r in conn.execute("""SELECT check_name FROM project_reporting.dq_check_result
                WHERE run_id=%s AND status='FAIL'""", (ident,))}
            return sorted(failed) if expected_fail <= failed else False

        test("Demand corruption fails row-level accuracy and reporting totals", lambda: detector_case(
            "UPDATE project_dw.fact_hourly_demand SET actual_demand_mw=actual_demand_mw+1 WHERE demand_key=(SELECT MIN(demand_key) FROM project_dw.fact_hourly_demand WHERE actual_demand_mw>0)",
            "20_accuracy_checks.sql", {"source_to_demand_fact", "q01_energy_difference"}))
        test("Missing reported fuel observation is detected", lambda: detector_case(
            "DELETE FROM project_dw.fact_hourly_generation WHERE generation_key=(SELECT MIN(generation_key) FROM project_dw.fact_hourly_generation)",
            "20_accuracy_checks.sql", {"source_to_generation_fact"}))
        test("Missing boundary demand hour fails completeness", lambda: detector_case(
            "DELETE FROM project_dw.fact_hourly_demand WHERE demand_key=(SELECT demand_key FROM project_reporting.vw_demand_detail WHERE authority_code='CISO' ORDER BY utc_hour_end LIMIT 1)",
            "10_completeness_checks.sql", {"missing_expected_hours", "demand_count"}))

        def ties():
            conn.execute("""UPDATE project_dw.fact_hourly_demand SET actual_demand_mw=999999999
                WHERE demand_key IN (SELECT demand_key FROM project_reporting.vw_demand_detail
                WHERE authority_code='CISO' AND calendar_year=2024 AND month_number=1 ORDER BY utc_hour_end LIMIT 2)""")
            return conn.execute("""SELECT COUNT(*) FROM project_reporting.vw_q03_monthly_peak_demand
                WHERE authority_code='CISO' AND calendar_year=2024 AND month_number=1""").fetchone()[0] == 2
        test("Monthly peak preserves every tied UTC hour", ties)

        def no_pairs():
            conn.execute("""UPDATE project_dw.fact_hourly_demand SET actual_demand_mw=0,forecast_demand_mw=0
              WHERE demand_key IN (SELECT demand_key FROM project_reporting.vw_demand_detail
              WHERE authority_code='CISO' AND calendar_year=2024 AND month_number=1)""")
            row=conn.execute("""SELECT eligible_pairs,mae_mw,wape_pct,bias_mw FROM project_reporting.vw_q05_monthly_forecast_accuracy
               WHERE authority_code='CISO' AND calendar_year=2024 AND month_number=1""").fetchone()
            return row == (0,None,None,None)
        test("No eligible forecast pairs yields NULL metrics", no_pairs)

        def no_share():
            conn.execute("""UPDATE project_dw.fact_hourly_demand SET total_generation_mw=0
              WHERE demand_key IN (SELECT demand_key FROM project_reporting.vw_demand_detail
              WHERE authority_code='CISO' AND calendar_year=2024 AND month_number=1)""")
            row=conn.execute("""SELECT eligible_hours,wind_solar_share_pct FROM project_reporting.vw_q08_wind_solar_share
               WHERE authority_code='CISO' AND calendar_year=2024 AND month_number=1""").fetchone()
            return row == (0,None)
        test("Zero total generation is excluded from wind/solar shares", no_share)

        def null_fuel():
            return conn.execute("""SELECT COUNT(*) FROM project_reporting.vw_q07_monthly_generation_by_fuel
                WHERE source_column='Net Generation (MW) from Other Energy Storage'
                AND reported_observations=0 AND generation_energy_mwh IS NULL""").fetchone()[0] == 120
        test("All-null fuel categories are visible without zero-fill", null_fuel)

        def restored():
            ident=prepare_check_run()
            for name in ["10_completeness_checks.sql","20_accuracy_checks.sql","30_integrity_checks.sql"]:
                run_sql(conn,"sql/05_quality/"+name)
            return conn.execute("SELECT COUNT(*) FROM project_reporting.dq_check_result WHERE run_id=%s AND status='FAIL'",(ident,)).fetchone()[0]==0
        test("All mutations rolled back; baseline passes again",restored)
    payload=dict(completed_at=utc_now(), source_commit=revision(),
                 status="PASS" if all(t["passed"] for t in tests) else "FAIL", tests=tests)
    write_json(EVIDENCE/"integration_tests.json",payload)
    raise SystemExit(0 if payload["status"]=="PASS" else 1)


if __name__=="__main__":
    main()
