WITH unpivoted AS (
    SELECT
        s.authority_code,
        s.data_date,
        s.local_hour_end,
        s.utc_hour_end,
        s.utc_offset_minutes,
        s.source_file,
        s.source_sha256,
        s.source_row,
        m.source_column,
        (to_jsonb(s) ->> m.clean_column)::numeric(18,4) AS generation_mw
    FROM project_staging.stg_eia930_balance_clean s
    CROSS JOIN project_staging.stg_energy_source_mapping m
    WHERE to_jsonb(s) ->> m.clean_column IS NOT NULL
)
INSERT INTO project_dw.fact_hourly_generation (
    authority_key, date_key, hour_key, energy_source_key,
    utc_hour_end, local_hour_end, utc_offset_minutes,
    generation_mw, source_snapshot_key, source_row_number
)
SELECT
    a.authority_key,
    d.date_key,
    h.hour_key,
    e.energy_source_key,
    u.utc_hour_end,
    u.local_hour_end,
    u.utc_offset_minutes,
    u.generation_mw,
    ss.source_snapshot_key,
    u.source_row
FROM unpivoted u
JOIN project_dw.dim_balancing_authority a
  ON a.authority_code = u.authority_code
JOIN project_dw.dim_date d
  ON d.calendar_date = u.data_date
JOIN project_dw.dim_hour h
  ON h.hour_ending = EXTRACT(HOUR FROM u.local_hour_end)::smallint
JOIN project_dw.dim_energy_source e
  ON e.source_column = u.source_column
JOIN project_dw.dim_source_snapshot ss
  ON ss.file_name = u.source_file
 AND ss.sha256 = u.source_sha256
ON CONFLICT (authority_key, utc_hour_end, energy_source_key) DO UPDATE
SET date_key = EXCLUDED.date_key,
    hour_key = EXCLUDED.hour_key,
    local_hour_end = EXCLUDED.local_hour_end,
    utc_offset_minutes = EXCLUDED.utc_offset_minutes,
    generation_mw = EXCLUDED.generation_mw,
    source_snapshot_key = EXCLUDED.source_snapshot_key,
    source_row_number = EXCLUDED.source_row_number;
