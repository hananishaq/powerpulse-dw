-- =====================================================================
-- PowerPulse | Phase 2 | Step 2 - Staging verification (read-only)
-- Owner: Qasim Tanveer
-- Run in pgAdmin 4 Query Tool on database powerpulse_dw AFTER the staging load + cleaning.
-- Part A is one PASS / FAIL table: every row must say PASS.
-- Parts B-E are evidence queries (take screenshots of them for the Data Cleaning Report).
-- This script changes nothing.
-- =====================================================================

-- ---------------------------------------------------------------------
-- PART A - PASS / FAIL checks
-- ---------------------------------------------------------------------
WITH raw_per_file AS (
    SELECT source_file, COUNT(*) AS n FROM project_staging.stg_eia930_balance_raw GROUP BY source_file
),
checks AS (
    SELECT 1  AS n, 'stg_authority_reference rows'                      AS check_name, 5::numeric AS expected,
           (SELECT COUNT(*) FROM project_staging.stg_authority_reference)::numeric AS actual
    UNION ALL SELECT 2,  'stg_energy_source_mapping rows',                 19, (SELECT COUNT(*) FROM project_staging.stg_energy_source_mapping)
    UNION ALL SELECT 3,  'stg_source_file rows (manifest)',                 4, (SELECT COUNT(*) FROM project_staging.stg_source_file)
    UNION ALL SELECT 4,  'raw rows, all four files',                    87720, (SELECT COUNT(*) FROM project_staging.stg_eia930_balance_raw)
    UNION ALL SELECT 5,  'raw rows 2024 Jan-Jun',                       21835, (SELECT n FROM raw_per_file WHERE source_file = 'EIA930_BALANCE_2024_Jan_Jun.csv')
    UNION ALL SELECT 6,  'raw rows 2024 Jul-Dec',                       22085, (SELECT n FROM raw_per_file WHERE source_file = 'EIA930_BALANCE_2024_Jul_Dec.csv')
    UNION ALL SELECT 7,  'raw rows 2025 Jan-Jun',                       21715, (SELECT n FROM raw_per_file WHERE source_file = 'EIA930_BALANCE_2025_Jan_Jun.csv')
    UNION ALL SELECT 8,  'raw rows 2025 Jul-Dec',                       22085, (SELECT n FROM raw_per_file WHERE source_file = 'EIA930_BALANCE_2025_Jul_Dec.csv')
    UNION ALL SELECT 9,  'clean rows (stg_eia930_balance_clean)',       87720, (SELECT COUNT(*) FROM project_staging.stg_eia930_balance_clean)
    UNION ALL SELECT 10, 'rejected rows (stg_load_exception)',              0, (SELECT COUNT(*) FROM project_staging.stg_load_exception WHERE action_taken = 'ROW_REJECTED')
    UNION ALL SELECT 11, 'duplicate (authority, UTC hour) keys in clean',   0, (SELECT COUNT(*) FROM (SELECT 1 FROM project_staging.stg_eia930_balance_clean GROUP BY authority_code, utc_hour_end HAVING COUNT(*) > 1) d)
    UNION ALL SELECT 12, 'distinct authorities',                            5, (SELECT COUNT(DISTINCT authority_code) FROM project_staging.stg_eia930_balance_clean)
    UNION ALL SELECT 13, 'fewest UTC hours for any authority',          17544, (SELECT MIN(c) FROM (SELECT COUNT(*) c FROM project_staging.stg_eia930_balance_clean GROUP BY authority_code) t)
    UNION ALL SELECT 14, 'most UTC hours for any authority',            17544, (SELECT MAX(c) FROM (SELECT COUNT(*) c FROM project_staging.stg_eia930_balance_clean GROUP BY authority_code) t)
    UNION ALL SELECT 15, 'distinct operating dates',                      731, (SELECT COUNT(DISTINCT data_date) FROM project_staging.stg_eia930_balance_clean)
    UNION ALL SELECT 16, 'NULL actual demand (source blanks)',            218, (SELECT COUNT(*) FROM project_staging.stg_eia930_balance_clean WHERE actual_demand_mw IS NULL)
    UNION ALL SELECT 17, 'NULL forecast demand (source blanks)',          218, (SELECT COUNT(*) FROM project_staging.stg_eia930_balance_clean WHERE forecast_demand_mw IS NULL)
    UNION ALL SELECT 18, 'NULL total generation (source blanks)',         218, (SELECT COUNT(*) FROM project_staging.stg_eia930_balance_clean WHERE total_generation_mw IS NULL)
    UNION ALL SELECT 19, 'rows with at least one NULL measure',           316, (SELECT COUNT(*) FROM project_staging.stg_eia930_balance_clean WHERE actual_demand_mw IS NULL OR forecast_demand_mw IS NULL OR total_generation_mw IS NULL)
    UNION ALL SELECT 20, 'rows with all three measures NULL',             120, (SELECT COUNT(*) FROM project_staging.stg_eia930_balance_clean WHERE actual_demand_mw IS NULL AND forecast_demand_mw IS NULL AND total_generation_mw IS NULL)
    UNION ALL SELECT 21, 'blank never became 0 (zeros in clean = zeros in raw)',
           (SELECT COUNT(*) FROM project_staging.stg_eia930_balance_raw WHERE project_staging.try_numeric(demand_mw) = 0),
           (SELECT COUNT(*) FROM project_staging.stg_eia930_balance_clean WHERE actual_demand_mw = 0)
    UNION ALL SELECT 22, 'numeric fuel observations = baseline',        727720, (SELECT rows_after FROM project_staging.stg_cleaning_log WHERE rule_id = 'C10' AND scope = 'ALL')
    UNION ALL SELECT 23, 'fuel columns that differ from baseline',          0, (SELECT COUNT(*) FROM project_staging.stg_cleaning_log WHERE rule_id = 'C10' AND scope <> 'ALL' AND rows_affected <> 0)
    UNION ALL SELECT 24, 'negative fuel values kept (not removed)',     31007, (SELECT rows_affected FROM project_staging.stg_cleaning_log WHERE rule_id = 'C08' AND scope = 'ALL')
    UNION ALL SELECT 25, 'rows with Hour Number 25 (autumn clock change)',  10, (SELECT COUNT(*) FROM project_staging.stg_eia930_balance_clean WHERE hour_number = 25)
    UNION ALL SELECT 26, 'UTC offsets outside -480..-240',                  0, (SELECT COUNT(*) FROM project_staging.stg_eia930_balance_clean WHERE utc_offset_minutes NOT IN (-480,-420,-360,-300,-240))
    UNION ALL SELECT 27, 'clean rows without a matching source snapshot',  0, (SELECT COUNT(*) FROM project_staging.stg_eia930_balance_clean c LEFT JOIN project_staging.stg_source_file s ON s.file_name = c.source_file AND s.sha256 = c.source_sha256 WHERE s.file_name IS NULL)
    UNION ALL SELECT 28, 'columns absent from 2024 Jan-Jun are NULL (not 0)', 0, (SELECT COUNT(*) FROM project_staging.stg_eia930_balance_clean WHERE source_file = 'EIA930_BALANCE_2024_Jan_Jun.csv' AND (gen_hydropower_excluding_pumped_storage IS NOT NULL OR gen_battery_storage IS NOT NULL OR gen_geothermal IS NOT NULL))
    UNION ALL SELECT 29, 'raw data columns that are not TEXT',              0, (SELECT COUNT(*) FROM information_schema.columns WHERE table_schema = 'project_staging' AND table_name = 'stg_eia930_balance_raw' AND column_name NOT IN ('raw_row_id', 'subset_row_number', 'loaded_at') AND data_type <> 'text')
    UNION ALL SELECT 30, 'dirty self-test rows left behind in raw',         0, (SELECT COUNT(*) FROM project_staging.stg_eia930_balance_raw WHERE subset_row_number = 0)
)
SELECT n, check_name, expected, actual,
       CASE WHEN expected IS NOT DISTINCT FROM actual THEN 'PASS' ELSE 'FAIL' END AS status
FROM checks
ORDER BY n;

-- ---------------------------------------------------------------------
-- PART B - Cleaning log: before / after for every rule (overall rows)
-- ---------------------------------------------------------------------
SELECT rule_id, rule_name, rows_before, rows_after, rows_affected, detail
FROM project_staging.stg_cleaning_log
WHERE scope = 'ALL'
ORDER BY log_id;

-- ---------------------------------------------------------------------
-- PART C - Missing values: NULL counts per measure and per authority
-- ---------------------------------------------------------------------
SELECT authority_code,
       COUNT(*)                                                  AS rows,
       COUNT(*) FILTER (WHERE actual_demand_mw    IS NULL)       AS null_demand,
       COUNT(*) FILTER (WHERE forecast_demand_mw  IS NULL)       AS null_forecast,
       COUNT(*) FILTER (WHERE total_generation_mw IS NULL)       AS null_total_generation
FROM project_staging.stg_eia930_balance_clean
GROUP BY authority_code
ORDER BY authority_code;

-- ---------------------------------------------------------------------
-- PART D - Before / after examples: raw text vs clean typed value
-- (1) a row with blank measures   (2) a row with negative generation   (3) a repeated autumn hour (Hour Number 25)
-- ---------------------------------------------------------------------
(SELECT '1 blank measures' AS example, r.source_file, r.source_row,
        r.balancing_authority AS raw_authority, r.demand_mw AS raw_demand, r.demand_forecast_mw AS raw_forecast, r.net_generation_mw AS raw_total_gen,
        c.authority_code, c.actual_demand_mw, c.forecast_demand_mw, c.total_generation_mw,
        c.hour_number, c.local_hour_end, c.utc_hour_end, c.utc_offset_minutes
 FROM project_staging.stg_eia930_balance_raw r
 JOIN project_staging.stg_eia930_balance_clean c ON c.source_file = r.source_file AND c.source_row = r.source_row::int
 WHERE BTRIM(r.demand_mw) = '' ORDER BY r.raw_row_id LIMIT 2)
UNION ALL
(SELECT '2 negative generation', r.source_file, r.source_row,
        r.balancing_authority, r.demand_mw, r.demand_forecast_mw, r.gen_unknown_energy_storage,
        c.authority_code, c.actual_demand_mw, c.forecast_demand_mw, c.gen_unknown_energy_storage,
        c.hour_number, c.local_hour_end, c.utc_hour_end, c.utc_offset_minutes
 FROM project_staging.stg_eia930_balance_raw r
 JOIN project_staging.stg_eia930_balance_clean c ON c.source_file = r.source_file AND c.source_row = r.source_row::int
 WHERE c.gen_unknown_energy_storage < 0 ORDER BY r.raw_row_id LIMIT 2)
UNION ALL
(SELECT '3 repeated hour (25)', r.source_file, r.source_row,
        r.balancing_authority, r.demand_mw, r.demand_forecast_mw, r.net_generation_mw,
        c.authority_code, c.actual_demand_mw, c.forecast_demand_mw, c.total_generation_mw,
        c.hour_number, c.local_hour_end, c.utc_hour_end, c.utc_offset_minutes
 FROM project_staging.stg_eia930_balance_raw r
 JOIN project_staging.stg_eia930_balance_clean c ON c.source_file = r.source_file AND c.source_row = r.source_row::int
 WHERE c.hour_number = 25 ORDER BY r.raw_row_id LIMIT 2);

-- ---------------------------------------------------------------------
-- PART E - Column mapping handed to the fact-load owner (Step 4)
-- source_column keeps the ORIGINAL header spelling; clean_column is the column to unpivot.
-- ---------------------------------------------------------------------
SELECT source_column, clean_column, source_label, source_group, numeric_cells_in_baseline
FROM project_staging.stg_energy_source_mapping
ORDER BY clean_column;
