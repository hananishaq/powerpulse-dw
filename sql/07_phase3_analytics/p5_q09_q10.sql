-- Q09: signed mix, retaining hours and coverage alongside the ratio.
SELECT * FROM project_reporting.vw_q09_high_demand_mix
ORDER BY authority_code, month_start, demand_cohort, source_group;

-- Q10: coverage and reconciliation diagnostics.
SELECT * FROM project_reporting.vw_q10_source_quality
ORDER BY residual_failure_hours DESC, authority_code, month_start;

-- Trace a failed residual to the balance publication and fuel lineage.
SELECT authority_code, month_start, utc_hour_end, file_name, sha256, source_row_number,
       generation_source_hashes, generation_source_rows, total_generation_mw,
       available_fuel_mw, residual_mw, tolerance_mw
FROM project_reporting.vw_generation_reconciliation_hour
WHERE abs(residual_mw) > tolerance_mw
ORDER BY abs(residual_mw) DESC, authority_code, utc_hour_end;
