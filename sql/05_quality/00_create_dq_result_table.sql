CREATE SCHEMA IF NOT EXISTS project_reporting;

CREATE TABLE IF NOT EXISTS project_reporting.dq_run (
    run_id uuid PRIMARY KEY,
    started_at timestamptz NOT NULL DEFAULT clock_timestamp(),
    completed_at timestamptz,
    status text NOT NULL CHECK (status IN ('RUNNING','PASS','FAIL','ERROR')),
    source_commit text NOT NULL,
    server_version text NOT NULL,
    input_files jsonb NOT NULL DEFAULT '[]',
    error_message text
);

CREATE TABLE IF NOT EXISTS project_reporting.dq_check_result (
    result_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    run_id uuid NOT NULL REFERENCES project_reporting.dq_run(run_id),
    check_name text NOT NULL,
    category text NOT NULL,
    expected numeric NOT NULL,
    actual numeric,
    status text NOT NULL CHECK (status IN ('PASS','FAIL')),
    checked_at timestamptz NOT NULL DEFAULT clock_timestamp(),
    detail text NOT NULL,
    UNIQUE (run_id, check_name)
);

-- Frozen source-profile coverage, not inferred from potentially incomplete facts.
CREATE TABLE IF NOT EXISTS project_reporting.dq_expected_coverage (
    authority_code text PRIMARY KEY,
    first_utc timestamptz NOT NULL,
    last_utc timestamptz NOT NULL,
    time_zone text NOT NULL,
    CHECK (last_utc >= first_utc)
);

CREATE OR REPLACE FUNCTION project_reporting.record_check(
    p_name text, p_category text, p_expected numeric, p_actual numeric, p_detail text
) RETURNS void LANGUAGE sql AS $$
    INSERT INTO project_reporting.dq_check_result
      (run_id,check_name,category,expected,actual,status,detail)
    VALUES (current_setting('powerpulse.dq_run_id')::uuid,
      p_name,p_category,p_expected,p_actual,
      CASE WHEN p_expected IS NOT DISTINCT FROM p_actual THEN 'PASS' ELSE 'FAIL' END,
      p_detail);
$$;

CREATE OR REPLACE VIEW project_reporting.vw_latest_dq_results AS
SELECT r.* FROM project_reporting.dq_check_result r
WHERE run_id = (SELECT run_id FROM project_reporting.dq_run
                WHERE completed_at IS NOT NULL ORDER BY completed_at DESC LIMIT 1);
