DROP TABLE IF EXISTS temp_demand_resolved;

CREATE TEMP TABLE temp_demand_resolved
ON COMMIT DROP
AS
SELECT
    s.authority_code,
    s.data_date,
    s.local_hour_end,
    s.utc_hour_end,
    s.utc_offset_minutes,
    s.actual_demand_mw,
    s.forecast_demand_mw,
    s.total_generation_mw,
    s.source_file,
    s.source_sha256,
    s.source_row,
    a.authority_key,
    d.date_key,
    h.hour_key,
    ss.source_snapshot_key,
    to_jsonb(s) AS source_record
FROM project_staging.stg_eia930_balance_clean s
LEFT JOIN project_dw.dim_balancing_authority a
    ON a.authority_code = s.authority_code
LEFT JOIN project_dw.dim_date d
    ON d.calendar_date = s.data_date
LEFT JOIN project_dw.dim_hour h
    ON h.hour_ending =
       EXTRACT(HOUR FROM s.local_hour_end)::smallint
LEFT JOIN project_dw.dim_source_snapshot ss
    ON ss.file_name = s.source_file
   AND ss.sha256 = s.source_sha256;

-- Record unresolved dimension keys
INSERT INTO project_dw.etl_reject (
    run_id,
    step_name,
    source_file,
    source_row_number,
    authority_code,
    data_date,
    utc_hour_end,
    rejection_reason,
    source_record
)
SELECT
    current_setting('powerpulse.run_id')::uuid,
    'fact_hourly_demand',
    source_file,
    source_row,
    authority_code,
    data_date,
    utc_hour_end,
    CONCAT_WS(
        '; ',
        CASE
            WHEN authority_key IS NULL
            THEN 'authority key not found'
        END,
        CASE
            WHEN date_key IS NULL
            THEN 'date key not found'
        END,
        CASE
            WHEN hour_key IS NULL
            THEN 'hour key not found'
        END,
        CASE
            WHEN source_snapshot_key IS NULL
            THEN 'source snapshot key not found'
        END
    ),
    source_record
FROM temp_demand_resolved
WHERE authority_key IS NULL
   OR date_key IS NULL
   OR hour_key IS NULL
   OR source_snapshot_key IS NULL;

-- Load only correctly resolved rows
INSERT INTO project_dw.fact_hourly_demand (
    authority_key,
    date_key,
    hour_key,
    utc_hour_end,
    local_hour_end,
    utc_offset_minutes,
    actual_demand_mw,
    forecast_demand_mw,
    total_generation_mw,
    source_snapshot_key,
    source_row_number
)
SELECT
    authority_key,
    date_key,
    hour_key,
    utc_hour_end,
    local_hour_end,
    utc_offset_minutes,
    actual_demand_mw,
    forecast_demand_mw,
    total_generation_mw,
    source_snapshot_key,
    source_row
FROM temp_demand_resolved
WHERE authority_key IS NOT NULL
  AND date_key IS NOT NULL
  AND hour_key IS NOT NULL
  AND source_snapshot_key IS NOT NULL
ON CONFLICT (
    authority_key,
    utc_hour_end
)
DO UPDATE SET
    date_key = EXCLUDED.date_key,
    hour_key = EXCLUDED.hour_key,
    local_hour_end = EXCLUDED.local_hour_end,
    utc_offset_minutes = EXCLUDED.utc_offset_minutes,
    actual_demand_mw = EXCLUDED.actual_demand_mw,
    forecast_demand_mw = EXCLUDED.forecast_demand_mw,
    total_generation_mw = EXCLUDED.total_generation_mw,
    source_snapshot_key = EXCLUDED.source_snapshot_key,
    source_row_number = EXCLUDED.source_row_number;