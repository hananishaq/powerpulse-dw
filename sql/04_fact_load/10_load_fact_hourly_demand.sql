INSERT INTO project_dw.fact_hourly_demand (
    authority_key, date_key, hour_key,
    utc_hour_end, local_hour_end, utc_offset_minutes,
    actual_demand_mw, forecast_demand_mw, total_generation_mw,
    source_snapshot_key, source_row_number
)
SELECT
    a.authority_key,
    d.date_key,
    h.hour_key,
    s.utc_hour_end,
    s.local_hour_end,
    s.utc_offset_minutes,
    s.actual_demand_mw,
    s.forecast_demand_mw,
    s.total_generation_mw,
    ss.source_snapshot_key,
    s.source_row
FROM project_staging.stg_eia930_balance_clean s
JOIN project_dw.dim_balancing_authority a
  ON a.authority_code = s.authority_code
JOIN project_dw.dim_date d
  ON d.calendar_date = s.data_date
JOIN project_dw.dim_hour h
  ON h.hour_ending = EXTRACT(HOUR FROM s.local_hour_end)::smallint
JOIN project_dw.dim_source_snapshot ss
  ON ss.file_name = s.source_file
 AND ss.sha256 = s.source_sha256
ON CONFLICT (authority_key, utc_hour_end) DO UPDATE
SET date_key = EXCLUDED.date_key,
    hour_key = EXCLUDED.hour_key,
    local_hour_end = EXCLUDED.local_hour_end,
    utc_offset_minutes = EXCLUDED.utc_offset_minutes,
    actual_demand_mw = EXCLUDED.actual_demand_mw,
    forecast_demand_mw = EXCLUDED.forecast_demand_mw,
    total_generation_mw = EXCLUDED.total_generation_mw,
    source_snapshot_key = EXCLUDED.source_snapshot_key,
    source_row_number = EXCLUDED.source_row_number;
