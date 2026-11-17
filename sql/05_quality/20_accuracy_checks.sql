-- Direct source-vs-staging and source-vs-fact comparisons detect compensating errors.
SELECT project_reporting.record_check('source_to_staging_core','Accuracy',0,COUNT(*),
 'NULL-safe row comparison: measures, timestamps, operating date, offset and source locator')
FROM dq_source_core e FULL JOIN project_staging.stg_eia930_balance_clean s
 ON s.authority_code=e.authority_code AND s.utc_hour_end=e.utc_hour_end
WHERE e.authority_code IS NULL OR s.authority_code IS NULL OR
 ROW(e.calendar_date,e.local_hour_end,e.utc_offset_minutes,e.actual_demand_mw,e.forecast_demand_mw,
     e.total_generation_mw,e.file_name,e.sha256,e.source_row_number)
 IS DISTINCT FROM
 ROW(s.data_date,s.local_hour_end,s.utc_offset_minutes,s.actual_demand_mw,s.forecast_demand_mw,
     s.total_generation_mw,s.source_file,s.source_sha256::text,s.source_row);

SELECT project_reporting.record_check('source_to_demand_fact','Accuracy',0,COUNT(*),
 'Independent CSV parse versus loaded demand: every measure and dimension/time/lineage attribute')
FROM dq_source_core e FULL JOIN project_reporting.vw_demand_detail d USING(authority_code,utc_hour_end)
WHERE e.authority_code IS NULL OR d.authority_code IS NULL OR
 ROW(e.calendar_date,e.local_hour_end,e.hour_ending,e.utc_offset_minutes,e.actual_demand_mw,
     e.forecast_demand_mw,e.total_generation_mw,e.file_name,e.sha256,e.source_row_number)
 IS DISTINCT FROM
 ROW(d.calendar_date,d.local_hour_end,d.hour_ending,d.utc_offset_minutes,d.actual_demand_mw,
     d.forecast_demand_mw,d.total_generation_mw,d.file_name,d.sha256::text,d.source_row_number);

SELECT project_reporting.record_check('source_to_generation_fact','Accuracy',0,COUNT(*),
 'Independent numeric reported fuel cells versus facts; extra/withdrawn facts also detected')
FROM dq_source_fuel e FULL JOIN project_reporting.vw_generation_detail g
 USING(authority_code,utc_hour_end,source_column)
WHERE e.authority_code IS NULL OR g.authority_code IS NULL OR
 ROW(e.generation_mw,e.file_name,e.sha256,e.source_row_number)
 IS DISTINCT FROM ROW(g.generation_mw,g.file_name,g.sha256::text,g.source_row_number);

SELECT project_reporting.record_check('generation_time_dimension_mapping','Accuracy',0,COUNT(*),
 'Generation operating date and local hour come from source labels, not UTC date')
FROM project_reporting.vw_generation_detail g LEFT JOIN dq_source_core e USING(authority_code,utc_hour_end)
WHERE e.authority_code IS NULL OR ROW(e.calendar_date,e.local_hour_end,e.hour_ending,e.utc_offset_minutes)
 IS DISTINCT FROM ROW(g.calendar_date,g.local_hour_end,g.hour_ending,g.utc_offset_minutes);

SELECT project_reporting.record_check('demand_energy_difference_mwh','Accuracy',0,
 (SELECT SUM(actual_demand_mw) FROM project_dw.fact_hourly_demand WHERE actual_demand_mw >= 0)
 -(SELECT SUM(actual_demand_mw) FROM dq_source_core WHERE actual_demand_mw >= 0),
 'M01: nonnegative actual MW times one-hour intervals; source versus fact');
SELECT project_reporting.record_check('negative_fuel_retained','Accuracy',31007,COUNT(*),
 'Negative reported net generation is preserved') FROM project_dw.fact_hourly_generation WHERE generation_mw < 0;
SELECT project_reporting.record_check('forecast_eligible_pairs','Accuracy',87399,COUNT(*),
 'M04-M07 population: actual > 0 and forecast >= 0, both observed')
FROM project_reporting.vw_forecast_pairs WHERE eligible;
SELECT project_reporting.record_check('reconciliation_comparable','Accuracy',87471,COUNT(*),
 'M12 compares only total present and at least one reported fuel present')
FROM project_reporting.vw_hourly_comparison WHERE reconciliation_comparable;
SELECT project_reporting.record_check('reconciliation_flags','Accuracy',6958,COUNT(*),
 'Expected source diagnostic: abs(residual) > max(10 MW, 1% abs(total)); not corrected')
FROM project_reporting.vw_hourly_comparison WHERE reconciliation_flagged;
SELECT project_reporting.record_check('reconciliation_pjm_flags','Accuracy',6873,COUNT(*),
 'Expected frozen-source exceptions, not ETL failures')
FROM project_reporting.vw_hourly_comparison WHERE reconciliation_flagged AND authority_code='PJM';
SELECT project_reporting.record_check('reconciliation_erco_flags','Accuracy',85,COUNT(*),
 'Expected frozen-source exceptions, not ETL failures')
FROM project_reporting.vw_hourly_comparison WHERE reconciliation_flagged AND authority_code='ERCO';
SELECT project_reporting.record_check('safe_join_row_difference','Accuracy',0,
 (SELECT COUNT(*) FROM project_reporting.vw_hourly_comparison)
 -(SELECT COUNT(*) FROM project_dw.fact_hourly_demand),
 'Aggregate generation to authority/hour BEFORE joining demand');
SELECT project_reporting.record_check('safe_join_demand_difference','Accuracy',0,
 (SELECT SUM(actual_demand_mw) FROM project_reporting.vw_hourly_comparison)
 -(SELECT SUM(actual_demand_mw) FROM project_dw.fact_hourly_demand),
 'Adding fuel summary must not multiply demand totals');
SELECT project_reporting.record_check('q01_energy_difference','Reporting',0,
 (SELECT SUM(demand_energy_mwh) FROM project_reporting.vw_q01_monthly_demand_energy)
 -(SELECT SUM(actual_demand_mw) FROM dq_source_core WHERE actual_demand_mw >= 0),
 'Monthly reporting agrees with independently parsed source energy');
SELECT project_reporting.record_check('q10_coverage_difference','Reporting',0,
 (SELECT SUM(expected_hours) FROM project_reporting.vw_q10_monthly_source_quality)-87720,
 'Monthly completeness covers entire independent expected population');
