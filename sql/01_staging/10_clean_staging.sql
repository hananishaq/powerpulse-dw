-- =====================================================================
-- PowerPulse | Phase 2 | Step 2 - Cleaning: raw (TEXT) -> typed clean table
-- Owner: Qasim Tanveer
-- Run against database: powerpulse_dw   (after etl/01_load_staging.py --load-only,
--                                        or simply run `python etl/01_load_staging.py`)
-- Re-runnable: yes. It rebuilds stg_eia930_balance_clean, stg_load_exception and
-- stg_cleaning_log from the raw table inside ONE transaction, so a failure leaves
-- the previous result untouched. (In pgAdmin: if it errors, run ROLLBACK; then retry.)
--
-- Cleaning rules (each one logs rows before / after / affected in stg_cleaning_log):
--   C01 Source import reconciliation  - raw rows per file vs source_manifest.json; unknown file/row rejected
--   C02 Text standardisation          - TRIM + UPPER on authority and region codes
--   C03 Reference validation          - authority must exist in stg_authority_reference, region must agree
--   C04 Date / timestamp conversion   - Data Date -> date; local label -> timestamp; UTC label -> timestamptz
--   C05 Hour and UTC offset checks    - Hour Number 1..25; offset = local - UTC must be -480..-240 minutes
--   C06 Numeric conversion            - text -> numeric(18,4); non-numeric text -> NULL + exception row
--   C07 NULL handling                 - blank measure -> NULL (never 0); the row is kept
--   C08 Negative generation           - negative values are real source data and are KEPT
--   C09 Duplicate removal             - one row per (authority_code, utc_hour_end); newest snapshot wins
--   C10 Fuel mapping reconciliation   - numeric cells per fuel column vs the supplied baseline
--   C11 Final result                  - raw rows -> clean rows + rejected rows, per file
-- =====================================================================

BEGIN;

TRUNCATE project_staging.stg_eia930_balance_clean,
         project_staging.stg_load_exception,
         project_staging.stg_cleaning_log
RESTART IDENTITY;

-- ---------------------------------------------------------------------
-- Step 1. Parse and standardise every raw row (C02, C04, C06 conversions)
-- ---------------------------------------------------------------------
DROP TABLE IF EXISTS tmp_parsed;
CREATE TEMP TABLE tmp_parsed AS
WITH base AS (
    SELECT
        r.raw_row_id,
        r.source_file,
        r.source_row                                            AS source_row_text,
        CASE WHEN BTRIM(r.source_row) ~ '^[0-9]{1,9}$'
             THEN BTRIM(r.source_row)::int END                  AS source_row,
        r.balancing_authority                                   AS authority_raw,
        r.region                                                AS region_raw,
        NULLIF(UPPER(BTRIM(r.balancing_authority)), '')         AS authority_code,   -- C02
        NULLIF(UPPER(BTRIM(r.region)), '')                      AS region_code,      -- C02
        r.data_date                                             AS data_date_text,
        r.utc_time_end                                          AS utc_text,
        project_staging.try_date_mdy(r.data_date)               AS data_date,        -- C04
        CASE WHEN BTRIM(r.hour_number) ~ '^[0-9]{1,2}$'
             THEN BTRIM(r.hour_number)::int END                 AS hour_number,      -- C05
        project_staging.try_timestamp_mdy12(r.local_time_end)   AS local_hour_end,   -- C04
        project_staging.try_timestamp_mdy12(r.utc_time_end)     AS utc_naive,        -- C04
        project_staging.try_numeric(r.demand_forecast_mw)       AS forecast_demand_mw,   -- C06
        project_staging.try_numeric(r.demand_mw)                AS actual_demand_mw,
        project_staging.try_numeric(r.net_generation_mw)        AS total_generation_mw,
    project_staging.try_numeric(r.gen_coal) AS gen_coal,
    project_staging.try_numeric(r.gen_natural_gas) AS gen_natural_gas,
    project_staging.try_numeric(r.gen_nuclear) AS gen_nuclear,
    project_staging.try_numeric(r.gen_all_petroleum_products) AS gen_all_petroleum_products,
    project_staging.try_numeric(r.gen_hydropower_and_pumped_storage) AS gen_hydropower_and_pumped_storage,
    project_staging.try_numeric(r.gen_solar) AS gen_solar,
    project_staging.try_numeric(r.gen_wind) AS gen_wind,
    project_staging.try_numeric(r.gen_other_fuel_sources) AS gen_other_fuel_sources,
    project_staging.try_numeric(r.gen_unknown_fuel_sources) AS gen_unknown_fuel_sources,
    project_staging.try_numeric(r.gen_hydropower_excluding_pumped_storage) AS gen_hydropower_excluding_pumped_storage,
    project_staging.try_numeric(r.gen_pumped_storage) AS gen_pumped_storage,
    project_staging.try_numeric(r.gen_solar_without_integrated_battery_storage) AS gen_solar_without_integrated_battery_storage,
    project_staging.try_numeric(r.gen_solar_with_integrated_battery_storage) AS gen_solar_with_integrated_battery_storage,
    project_staging.try_numeric(r.gen_wind_without_integrated_battery_storage) AS gen_wind_without_integrated_battery_storage,
    project_staging.try_numeric(r.gen_wind_with_integrated_battery_storage) AS gen_wind_with_integrated_battery_storage,
    project_staging.try_numeric(r.gen_battery_storage) AS gen_battery_storage,
    project_staging.try_numeric(r.gen_other_energy_storage) AS gen_other_energy_storage,
    project_staging.try_numeric(r.gen_unknown_energy_storage) AS gen_unknown_energy_storage,
    project_staging.try_numeric(r.gen_geothermal) AS gen_geothermal
    FROM project_staging.stg_eia930_balance_raw r
)
SELECT
    b.*,
    b.utc_naive AT TIME ZONE 'UTC'                              AS utc_hour_end,     -- explicit +00:00
    ROUND(EXTRACT(EPOCH FROM (b.local_hour_end - b.utc_naive)) / 60)::int
                                                                AS utc_offset_minutes,
    sf.sha256                                                   AS source_sha256,
    sf.retrieved_at_utc                                         AS retrieved_at_utc
FROM base b
LEFT JOIN project_staging.stg_source_file sf ON sf.file_name = b.source_file;

-- ---------------------------------------------------------------------
-- Step 2. Validate: the FIRST failing check decides the reject reason (C01, C03, C04, C05)
-- ---------------------------------------------------------------------
DROP TABLE IF EXISTS tmp_checked;
CREATE TEMP TABLE tmp_checked AS
SELECT p.*, v.rule_id AS reject_rule, v.reason AS reject_reason, v.bad_column, v.bad_value
FROM tmp_parsed p
LEFT JOIN project_staging.stg_authority_reference ref ON ref.authority_code = p.authority_code
LEFT JOIN LATERAL (
    SELECT t.rule_id, t.reason, t.bad_column, t.bad_value
    FROM (VALUES
        (1, 'C01', 'UNKNOWN_SOURCE_FILE',            'source_file',  p.source_file,       p.source_sha256 IS NULL),
        (2, 'C01', 'INVALID_SOURCE_ROW',             'source_row',   p.source_row_text,   p.source_row IS NULL),
        (3, 'C03', 'UNKNOWN_AUTHORITY_CODE',         'balancing_authority', p.authority_raw, ref.authority_code IS NULL),
        (4, 'C03', 'REGION_DOES_NOT_MATCH_AUTHORITY','region',       p.region_raw,        p.region_code IS DISTINCT FROM ref.region_code),
        (5, 'C04', 'INVALID_DATA_DATE',              'data_date',    p.data_date_text,    p.data_date IS NULL),
        (6, 'C04', 'INVALID_LOCAL_TIMESTAMP',        'local_time_end', NULL::text,        p.local_hour_end IS NULL),
        (7, 'C04', 'INVALID_UTC_TIMESTAMP',          'utc_time_end', p.utc_text,          p.utc_naive IS NULL),
        (8, 'C05', 'INVALID_HOUR_NUMBER',            'hour_number',  p.hour_number::text, p.hour_number IS NULL OR p.hour_number NOT BETWEEN 1 AND 25),
        (9, 'C05', 'INVALID_UTC_OFFSET',             'utc_offset_minutes', p.utc_offset_minutes::text,
                                                     p.utc_offset_minutes IS NULL OR p.utc_offset_minutes NOT IN (-480, -420, -360, -300, -240))
    ) AS t(ord, rule_id, reason, bad_column, bad_value, failed)
    WHERE t.failed
    ORDER BY t.ord
    LIMIT 1
) v ON TRUE;

-- ---------------------------------------------------------------------
-- Step 3. Duplicates on (authority_code, utc_hour_end) among valid rows (C09).
--         Newest snapshot wins; ties broken by file name then source row.
-- ---------------------------------------------------------------------
DROP TABLE IF EXISTS tmp_final;
CREATE TEMP TABLE tmp_final AS
SELECT c.*,
       ROW_NUMBER() OVER (
           PARTITION BY c.authority_code, c.utc_hour_end
           ORDER BY c.retrieved_at_utc DESC, c.source_file DESC, c.source_row DESC
       ) AS rn,
       COUNT(*) OVER (PARTITION BY c.authority_code, c.utc_hour_end) AS key_count
FROM tmp_checked c
WHERE c.reject_rule IS NULL;

-- ---------------------------------------------------------------------
-- Step 4. Every measure cell of every kept row, so C06/C07/C08 can be counted exactly.
--         Columns that do not exist in a file (raw value NULL) are structural absences, not blanks.
-- ---------------------------------------------------------------------
DROP TABLE IF EXISTS tmp_cells;
CREATE TEMP TABLE tmp_cells AS
SELECT r.raw_row_id,
       x.column_name,
       x.kind,
       x.raw_value,
       (x.raw_value IS NOT NULL AND BTRIM(x.raw_value) = '')                AS is_blank,
       project_staging.try_numeric(x.raw_value)                             AS num_value,
       r.source_file,
       r.source_row
FROM project_staging.stg_eia930_balance_raw r
JOIN tmp_final f ON f.raw_row_id = r.raw_row_id AND f.rn = 1
CROSS JOIN LATERAL (VALUES
    ('demand_forecast_mw', 'MEASURE', r.demand_forecast_mw),
    ('demand_mw',          'MEASURE', r.demand_mw),
    ('net_generation_mw',  'MEASURE', r.net_generation_mw),
    ('gen_coal', 'FUEL', r.gen_coal),
    ('gen_natural_gas', 'FUEL', r.gen_natural_gas),
    ('gen_nuclear', 'FUEL', r.gen_nuclear),
    ('gen_all_petroleum_products', 'FUEL', r.gen_all_petroleum_products),
    ('gen_hydropower_and_pumped_storage', 'FUEL', r.gen_hydropower_and_pumped_storage),
    ('gen_solar', 'FUEL', r.gen_solar),
    ('gen_wind', 'FUEL', r.gen_wind),
    ('gen_other_fuel_sources', 'FUEL', r.gen_other_fuel_sources),
    ('gen_unknown_fuel_sources', 'FUEL', r.gen_unknown_fuel_sources),
    ('gen_hydropower_excluding_pumped_storage', 'FUEL', r.gen_hydropower_excluding_pumped_storage),
    ('gen_pumped_storage', 'FUEL', r.gen_pumped_storage),
    ('gen_solar_without_integrated_battery_storage', 'FUEL', r.gen_solar_without_integrated_battery_storage),
    ('gen_solar_with_integrated_battery_storage', 'FUEL', r.gen_solar_with_integrated_battery_storage),
    ('gen_wind_without_integrated_battery_storage', 'FUEL', r.gen_wind_without_integrated_battery_storage),
    ('gen_wind_with_integrated_battery_storage', 'FUEL', r.gen_wind_with_integrated_battery_storage),
    ('gen_battery_storage', 'FUEL', r.gen_battery_storage),
    ('gen_other_energy_storage', 'FUEL', r.gen_other_energy_storage),
    ('gen_unknown_energy_storage', 'FUEL', r.gen_unknown_energy_storage),
    ('gen_geothermal', 'FUEL', r.gen_geothermal)
) AS x(column_name, kind, raw_value)
WHERE x.raw_value IS NOT NULL;

-- ---------------------------------------------------------------------
-- Step 5. Exceptions
-- ---------------------------------------------------------------------
INSERT INTO project_staging.stg_load_exception
    (raw_row_id, rule_id, reason, action_taken, column_name, bad_value, source_file, source_row)
SELECT raw_row_id, reject_rule, reject_reason, 'ROW_REJECTED', bad_column, bad_value, source_file, source_row_text
FROM tmp_checked
WHERE reject_rule IS NOT NULL;

INSERT INTO project_staging.stg_load_exception
    (raw_row_id, rule_id, reason, action_taken, column_name, bad_value, source_file, source_row)
SELECT raw_row_id, 'C09', 'DUPLICATE_AUTHORITY_UTC_HOUR', 'ROW_REJECTED', 'utc_time_end', utc_text, source_file, source_row_text
FROM tmp_final
WHERE rn > 1;

INSERT INTO project_staging.stg_load_exception
    (raw_row_id, rule_id, reason, action_taken, column_name, bad_value, source_file, source_row)
SELECT raw_row_id, 'C06', 'NON_NUMERIC_MEASURE_SET_TO_NULL', 'VALUE_SET_NULL', column_name, raw_value, source_file, source_row::text
FROM tmp_cells
WHERE NOT is_blank AND num_value IS NULL;

-- ---------------------------------------------------------------------
-- Step 6. Load the clean table
-- ---------------------------------------------------------------------
INSERT INTO project_staging.stg_eia930_balance_clean (
    authority_code, region_code, data_date, hour_number, local_hour_end, utc_hour_end, utc_offset_minutes,
    forecast_demand_mw, actual_demand_mw, total_generation_mw,
    gen_coal,
    gen_natural_gas,
    gen_nuclear,
    gen_all_petroleum_products,
    gen_hydropower_and_pumped_storage,
    gen_solar,
    gen_wind,
    gen_other_fuel_sources,
    gen_unknown_fuel_sources,
    gen_hydropower_excluding_pumped_storage,
    gen_pumped_storage,
    gen_solar_without_integrated_battery_storage,
    gen_solar_with_integrated_battery_storage,
    gen_wind_without_integrated_battery_storage,
    gen_wind_with_integrated_battery_storage,
    gen_battery_storage,
    gen_other_energy_storage,
    gen_unknown_energy_storage,
    gen_geothermal,
    source_file, source_sha256, source_row)
SELECT
    f.authority_code, f.region_code, f.data_date, f.hour_number, f.local_hour_end, f.utc_hour_end, f.utc_offset_minutes,
    f.forecast_demand_mw, f.actual_demand_mw, f.total_generation_mw,
    f.gen_coal,
    f.gen_natural_gas,
    f.gen_nuclear,
    f.gen_all_petroleum_products,
    f.gen_hydropower_and_pumped_storage,
    f.gen_solar,
    f.gen_wind,
    f.gen_other_fuel_sources,
    f.gen_unknown_fuel_sources,
    f.gen_hydropower_excluding_pumped_storage,
    f.gen_pumped_storage,
    f.gen_solar_without_integrated_battery_storage,
    f.gen_solar_with_integrated_battery_storage,
    f.gen_wind_without_integrated_battery_storage,
    f.gen_wind_with_integrated_battery_storage,
    f.gen_battery_storage,
    f.gen_other_energy_storage,
    f.gen_unknown_energy_storage,
    f.gen_geothermal,
    f.source_file, f.source_sha256, f.source_row
FROM tmp_final f
WHERE f.rn = 1;

-- ---------------------------------------------------------------------
-- Step 7. Cleaning log (before / after / affected for every rule)
-- ---------------------------------------------------------------------

-- C01 source import reconciliation, per file and overall
INSERT INTO project_staging.stg_cleaning_log (rule_id, rule_name, scope, rows_before, rows_after, rows_affected, detail)
SELECT 'C01', 'Source import reconciliation', sf.file_name,
       sf.selected_row_count,
       COUNT(r.raw_row_id),
       ABS(sf.selected_row_count - COUNT(r.raw_row_id)),
       'rows_before = rows promised by source_manifest.json; rows_after = rows landed in stg_eia930_balance_raw'
FROM project_staging.stg_source_file sf
LEFT JOIN project_staging.stg_eia930_balance_raw r ON r.source_file = sf.file_name
GROUP BY sf.file_name, sf.selected_row_count
ORDER BY sf.file_name;

INSERT INTO project_staging.stg_cleaning_log (rule_id, rule_name, scope, rows_before, rows_after, rows_affected, detail)
SELECT 'C01', 'Source import reconciliation', 'ALL',
       (SELECT SUM(selected_row_count) FROM project_staging.stg_source_file),
       (SELECT COUNT(*) FROM project_staging.stg_eia930_balance_raw),
       ABS((SELECT SUM(selected_row_count) FROM project_staging.stg_source_file)
           - (SELECT COUNT(*) FROM project_staging.stg_eia930_balance_raw)),
       'rows with unknown source file or invalid source row are rejected under this rule: '
       || (SELECT COUNT(*) FROM tmp_checked WHERE reject_rule = 'C01');

-- C02 text standardisation
INSERT INTO project_staging.stg_cleaning_log (rule_id, rule_name, scope, rows_before, rows_after, rows_affected, detail)
SELECT 'C02', 'Text standardisation (TRIM + UPPER)', 'ALL',
       COUNT(*), COUNT(*),
       COUNT(*) FILTER (WHERE authority_raw IS DISTINCT FROM authority_code OR region_raw IS DISTINCT FROM region_code),
       'values changed in balancing_authority / region. Rule demo: '
       || quote_literal(' cISo ') || ' -> ' || quote_literal(UPPER(BTRIM(' cISo ')))
FROM tmp_parsed;

-- C03 / C04 / C05: rows entering and leaving each validation rule
INSERT INTO project_staging.stg_cleaning_log (rule_id, rule_name, scope, rows_before, rows_after, rows_affected, detail)
SELECT r.rule_id, r.rule_name, 'ALL',
       COUNT(*) FILTER (WHERE c.reject_rule IS NULL OR c.reject_rule >= r.rule_id),
       COUNT(*) FILTER (WHERE c.reject_rule IS NULL OR c.reject_rule >  r.rule_id),
       COUNT(*) FILTER (WHERE c.reject_rule = r.rule_id),
       r.detail
FROM (VALUES
    ('C03', 'Reference validation (authority + region)',     'rows rejected = authority not in stg_authority_reference, or region disagrees with the reference'),
    ('C04', 'Date and timestamp conversion',                 'Data Date -> date, local label -> timestamp, UTC label -> timestamptz (+00:00); rows rejected = unparseable'),
    ('C05', 'Hour number and UTC offset validation',         'Hour Number must be 1..25; utc_offset_minutes = local - UTC must be one of -480,-420,-360,-300,-240')
) AS r(rule_id, rule_name, detail)
CROSS JOIN tmp_checked c
GROUP BY r.rule_id, r.rule_name, r.detail
ORDER BY r.rule_id;

-- C06 numeric conversion
INSERT INTO project_staging.stg_cleaning_log (rule_id, rule_name, scope, rows_before, rows_after, rows_affected, detail)
SELECT 'C06', 'Numeric conversion (text -> numeric(18,4))', 'ALL',
       (SELECT COUNT(*) FROM tmp_final WHERE rn = 1),
       (SELECT COUNT(*) FROM project_staging.stg_eia930_balance_clean),
       COUNT(*) FILTER (WHERE NOT is_blank AND num_value IS NULL),
       'rows_affected = cells that were not numeric and became NULL. Numeric cells converted: '
       || COUNT(*) FILTER (WHERE num_value IS NOT NULL)
       || '; blank cells: ' || COUNT(*) FILTER (WHERE is_blank)
FROM tmp_cells;

-- C07 NULL handling: blank measures stay NULL, rows are kept
INSERT INTO project_staging.stg_cleaning_log (rule_id, rule_name, scope, rows_before, rows_after, rows_affected, detail)
SELECT 'C07', 'NULL handling (blank -> NULL, never 0)', m.scope,
       (SELECT COUNT(*) FROM project_staging.stg_eia930_balance_clean),
       (SELECT COUNT(*) FROM project_staging.stg_eia930_balance_clean),
       m.null_count,
       'blank source cells stored as NULL; rows retained'
FROM (
    SELECT 'forecast_demand_mw' AS scope,  COUNT(*) FILTER (WHERE forecast_demand_mw  IS NULL) AS null_count FROM project_staging.stg_eia930_balance_clean
    UNION ALL
    SELECT 'actual_demand_mw',             COUNT(*) FILTER (WHERE actual_demand_mw    IS NULL) FROM project_staging.stg_eia930_balance_clean
    UNION ALL
    SELECT 'total_generation_mw',          COUNT(*) FILTER (WHERE total_generation_mw IS NULL) FROM project_staging.stg_eia930_balance_clean
    UNION ALL
    SELECT 'ANY_OF_THE_THREE_MEASURES',    COUNT(*) FILTER (WHERE forecast_demand_mw IS NULL OR actual_demand_mw IS NULL OR total_generation_mw IS NULL) FROM project_staging.stg_eia930_balance_clean
    UNION ALL
    SELECT 'ALL_THREE_MEASURES',           COUNT(*) FILTER (WHERE forecast_demand_mw IS NULL AND actual_demand_mw IS NULL AND total_generation_mw IS NULL) FROM project_staging.stg_eia930_balance_clean
) m;

INSERT INTO project_staging.stg_cleaning_log (rule_id, rule_name, scope, rows_before, rows_after, rows_affected, detail)
SELECT 'C07', 'NULL handling (blank -> NULL, never 0)', 'ALL',
       (SELECT COUNT(*) FROM project_staging.stg_eia930_balance_clean),
       (SELECT COUNT(*) FROM project_staging.stg_eia930_balance_clean),
       COUNT(*) FILTER (WHERE is_blank),
       'blank cells (present in the file, empty) converted to NULL. Fuel cells not present in a file at all (structural absence, NULL in raw): '
       || ((SELECT COUNT(*) FROM tmp_final WHERE rn = 1) * 19 - COUNT(*) FILTER (WHERE kind = 'FUEL'))
FROM tmp_cells;

-- C08 negative generation is kept (counted per measure column, then overall)
INSERT INTO project_staging.stg_cleaning_log (rule_id, rule_name, scope, rows_before, rows_after, rows_affected, detail)
SELECT 'C08', 'Negative net generation retained', column_name,
       COUNT(num_value), COUNT(num_value), COUNT(*) FILTER (WHERE num_value < 0),
       'rows_affected = negative values. They are real source data (e.g. storage charging) and are NOT changed or dropped'
FROM tmp_cells
GROUP BY column_name
ORDER BY column_name;

INSERT INTO project_staging.stg_cleaning_log (rule_id, rule_name, scope, rows_before, rows_after, rows_affected, detail)
SELECT 'C08', 'Negative net generation retained', 'ALL',
       COUNT(num_value), COUNT(num_value), COUNT(*) FILTER (WHERE num_value < 0),
       'negative cells across total generation and all fuel columns; none removed, none set to 0'
FROM tmp_cells
WHERE kind = 'FUEL' OR column_name = 'net_generation_mw';

-- C09 duplicate removal
INSERT INTO project_staging.stg_cleaning_log (rule_id, rule_name, scope, rows_before, rows_after, rows_affected, detail)
SELECT 'C09', 'Duplicate removal on (authority_code, utc_hour_end)', 'ALL',
       COUNT(*),
       COUNT(*) FILTER (WHERE rn = 1),
       COUNT(*) FILTER (WHERE rn > 1),
       'duplicate keys found: ' || COUNT(DISTINCT (authority_code, utc_hour_end)) FILTER (WHERE key_count > 1)
       || '. Kept row = newest snapshot, then highest file name, then highest source row'
FROM tmp_final;

-- C10 fuel column reconciliation against the supplied baseline (energy_source_mapping.csv)
INSERT INTO project_staging.stg_cleaning_log (rule_id, rule_name, scope, rows_before, rows_after, rows_affected, detail)
SELECT 'C10', 'Fuel mapping reconciliation', m.source_column,
       m.numeric_cells_in_baseline,
       COALESCE(c.numeric_cells, 0),
       ABS(m.numeric_cells_in_baseline - COALESCE(c.numeric_cells, 0)),
       'rows_before = numeric cells in the supplied baseline; rows_after = numeric cells in the clean table (' || m.clean_column || ')'
FROM project_staging.stg_energy_source_mapping m
LEFT JOIN (
    SELECT column_name, COUNT(num_value) AS numeric_cells
    FROM tmp_cells WHERE kind = 'FUEL' GROUP BY column_name
) c ON c.column_name = m.clean_column
ORDER BY m.clean_column;

INSERT INTO project_staging.stg_cleaning_log (rule_id, rule_name, scope, rows_before, rows_after, rows_affected, detail)
SELECT 'C10', 'Fuel mapping reconciliation', 'ALL',
       SUM(rows_before), SUM(rows_after), SUM(rows_affected),
       'total numeric fuel observations: baseline vs clean (this is the expected row count of fact_hourly_generation)'
FROM project_staging.stg_cleaning_log
WHERE rule_id = 'C10' AND scope <> 'ALL';

-- C11 final result per file and overall
INSERT INTO project_staging.stg_cleaning_log (rule_id, rule_name, scope, rows_before, rows_after, rows_affected, detail)
SELECT 'C11', 'Final result (raw rows -> clean rows)', r.source_file,
       COUNT(*),
       COUNT(*) FILTER (WHERE f.rn = 1),
       COUNT(*) FILTER (WHERE f.rn IS NULL OR f.rn > 1),
       'rows_affected = rows rejected or removed as duplicates'
FROM project_staging.stg_eia930_balance_raw r
LEFT JOIN tmp_final f ON f.raw_row_id = r.raw_row_id
GROUP BY r.source_file
ORDER BY r.source_file;

INSERT INTO project_staging.stg_cleaning_log (rule_id, rule_name, scope, rows_before, rows_after, rows_affected, detail)
SELECT 'C11', 'Final result (raw rows -> clean rows)', 'ALL',
       (SELECT COUNT(*) FROM project_staging.stg_eia930_balance_raw),
       (SELECT COUNT(*) FROM project_staging.stg_eia930_balance_clean),
       (SELECT COUNT(*) FROM project_staging.stg_load_exception WHERE action_taken = 'ROW_REJECTED'),
       'clean rows = 5 authorities x 17,544 UTC hours when nothing is rejected';

COMMIT;

-- Quick look (pgAdmin shows the last result set)
SELECT rule_id, rule_name, scope, rows_before, rows_after, rows_affected
FROM project_staging.stg_cleaning_log
WHERE scope = 'ALL'
ORDER BY log_id;
