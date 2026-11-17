-- Remove fact rows when a revised source changes generation to NULL
DELETE FROM project_dw.fact_hourly_generation f
USING (
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
    WHERE to_jsonb(s) ->> m.clean_column IS NULL
) withdrawn
WHERE f.authority_key = withdrawn.authority_key
  AND f.utc_hour_end = withdrawn.utc_hour_end
  AND f.energy_source_key = withdrawn.energy_source_key;

-- Record rows that contain generation but cannot resolve dimensions
INSERT INTO project_dw.etl_reject (
    run_id,
    step_name,
    source_file,
    source_row_number,
    authority_code,
    data_date,
    utc_hour_end,
    energy_source_column,
    rejection_reason
)
SELECT
    current_setting('powerpulse.run_id')::uuid,
    'fact_hourly_generation',
    s.source_file,
    s.source_row,
    s.authority_code,
    s.data_date,
    s.utc_hour_end,
    m.source_column,
    CONCAT_WS(
        '; ',
        CASE WHEN a.authority_key IS NULL
            THEN 'authority key not found' END,
        CASE WHEN d.date_key IS NULL
            THEN 'date key not found' END,
        CASE WHEN h.hour_key IS NULL
            THEN 'hour key not found' END,
        CASE WHEN e.energy_source_key IS NULL
            THEN 'energy source key not found' END,
        CASE WHEN ss.source_snapshot_key IS NULL
            THEN 'source snapshot key not found' END
    )
FROM project_staging.stg_eia930_balance_clean s
CROSS JOIN project_staging.stg_energy_source_mapping m
LEFT JOIN project_dw.dim_balancing_authority a
    ON a.authority_code = s.authority_code
LEFT JOIN project_dw.dim_date d
    ON d.calendar_date = s.data_date
LEFT JOIN project_dw.dim_hour h
    ON h.hour_ending =
       EXTRACT(HOUR FROM s.local_hour_end)::smallint
LEFT JOIN project_dw.dim_energy_source e
    ON e.source_column = m.source_column
LEFT JOIN project_dw.dim_source_snapshot ss
    ON ss.file_name = s.source_file
   AND ss.sha256 = s.source_sha256
WHERE to_jsonb(s) ->> m.clean_column IS NOT NULL
  AND (
      a.authority_key IS NULL
      OR d.date_key IS NULL
      OR h.hour_key IS NULL
      OR e.energy_source_key IS NULL
      OR ss.source_snapshot_key IS NULL
  );

-- Insert/update valid generation facts
INSERT INTO project_dw.fact_hourly_generation (
    authority_key,
    date_key,
    hour_key,
    energy_source_key,
    utc_hour_end,
    local_hour_end,
    utc_offset_minutes,
    generation_mw,
    source_snapshot_key,
    source_row_number
)
SELECT
    a.authority_key,
    d.date_key,
    h.hour_key,
    e.energy_source_key,
    s.utc_hour_end,
    s.local_hour_end,
    s.utc_offset_minutes,
    (to_jsonb(s) ->> m.clean_column)::numeric(18,4),
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
ON CONFLICT (
    authority_key,
    utc_hour_end,
    energy_source_key
)
DO UPDATE SET
    date_key = EXCLUDED.date_key,
    hour_key = EXCLUDED.hour_key,
    local_hour_end = EXCLUDED.local_hour_end,
    utc_offset_minutes = EXCLUDED.utc_offset_minutes,
    generation_mw = EXCLUDED.generation_mw,
    source_snapshot_key = EXCLUDED.source_snapshot_key,
    source_row_number = EXCLUDED.source_row_number;