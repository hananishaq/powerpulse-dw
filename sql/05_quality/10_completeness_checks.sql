SELECT project_reporting.record_check('demand_count','Completeness',87720,COUNT(*),
 'Frozen source baseline; demand rows retained even when measures are NULL') FROM project_dw.fact_hourly_demand;
SELECT project_reporting.record_check('generation_count','Completeness',727720,COUNT(*),
 'One fact for each numeric reported fuel cell') FROM project_dw.fact_hourly_generation;
SELECT project_reporting.record_check('expected_grid_count','Completeness',87720,COUNT(*),
 'Independent authority-specific UTC coverage from frozen source profile') FROM project_reporting.vw_expected_hours;
SELECT project_reporting.record_check('missing_expected_hours','Completeness',0,COUNT(*),
 'Includes missing boundary hours and entirely absent authorities')
FROM project_reporting.vw_expected_hours e LEFT JOIN project_reporting.vw_demand_detail d
 USING(authority_code,utc_hour_end) WHERE d.demand_key IS NULL;
SELECT project_reporting.record_check('unexpected_demand_hours','Completeness',0,COUNT(*),
 'No authority/hour outside the frozen expected coverage')
FROM project_reporting.vw_demand_detail d LEFT JOIN project_reporting.vw_expected_hours e
 USING(authority_code,utc_hour_end) WHERE e.authority_code IS NULL;
SELECT project_reporting.record_check('null_actual','Completeness',218,COUNT(*),
 'Legitimate source blanks; not zero-filled') FROM project_dw.fact_hourly_demand WHERE actual_demand_mw IS NULL;
SELECT project_reporting.record_check('null_forecast','Completeness',218,COUNT(*),
 'Legitimate source blanks') FROM project_dw.fact_hourly_demand WHERE forecast_demand_mw IS NULL;
SELECT project_reporting.record_check('null_total_generation','Completeness',218,COUNT(*),
 'Legitimate source blanks') FROM project_dw.fact_hourly_demand WHERE total_generation_mw IS NULL;
SELECT project_reporting.record_check('any_core_null','Completeness',316,COUNT(*),
 'Authority-hours with at least one missing core measure') FROM project_dw.fact_hourly_demand
 WHERE actual_demand_mw IS NULL OR forecast_demand_mw IS NULL OR total_generation_mw IS NULL;
SELECT project_reporting.record_check('all_core_null','Completeness',120,COUNT(*),
 'Authority-hours with all three measures missing are retained') FROM project_dw.fact_hourly_demand
 WHERE actual_demand_mw IS NULL AND forecast_demand_mw IS NULL AND total_generation_mw IS NULL;
SELECT project_reporting.record_check('raw_manifest_rows','Completeness',
 (SELECT SUM(selected_row_count) FROM project_staging.stg_source_file),COUNT(*),
 'Raw landing count equals selected subset count, not full-source count') FROM project_staging.stg_eia930_balance_raw;
SELECT project_reporting.record_check('raw_per_file_mismatches','Completeness',0,COUNT(*),
 'Every manifest file reconciles separately') FROM (
 SELECT m.file_name FROM project_staging.stg_source_file m
 LEFT JOIN project_staging.stg_eia930_balance_raw r ON r.source_file=m.file_name
 GROUP BY m.file_name,m.selected_row_count HAVING COUNT(r.raw_row_id)<>m.selected_row_count
) x;
SELECT project_reporting.record_check('clean_count','Completeness',87720,COUNT(*),
 'Normal frozen baseline has no rejected rows') FROM project_staging.stg_eia930_balance_clean;
SELECT project_reporting.record_check('baseline_exceptions','Completeness',0,COUNT(*),
 'No bad numeric or identity rows in the frozen baseline; source blanks are not exceptions') FROM project_staging.stg_load_exception;
SELECT project_reporting.record_check('dimension_' || label,'Completeness',expected,actual,
 'Check EACH dimension count independently') FROM (
 SELECT 'date' AS label,731 AS expected,COUNT(*) AS actual FROM project_dw.dim_date
 UNION ALL SELECT 'hour',24,COUNT(*) FROM project_dw.dim_hour
 UNION ALL SELECT 'authority',5,COUNT(*) FROM project_dw.dim_balancing_authority
 UNION ALL SELECT 'energy_source',19,COUNT(*) FROM project_dw.dim_energy_source
 UNION ALL SELECT 'source_snapshot',4,COUNT(*) FROM project_dw.dim_source_snapshot
) c;
