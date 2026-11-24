-- Q09 grain: authority, operating month, demand cohort and approved source group.
-- Calculate demand percentiles before joining generation. Group fuel by
-- authority, UTC hour and approved group before the single demand lookup.
CREATE OR REPLACE VIEW project_reporting.vw_q09_high_demand_mix AS
WITH thresholds AS (
    SELECT authority_key, month_start,
           percentile_cont(0.9) WITHIN GROUP (ORDER BY actual_demand_mw) AS p90_demand_mw
    FROM project_reporting.vw_demand_observation
    WHERE actual_demand_mw > 0 GROUP BY authority_key, month_start
), demand_cohorts AS MATERIALIZED (
    SELECT d.authority_key, d.authority_code, d.month_start, d.utc_hour_end,
           t.p90_demand_mw, CASE WHEN d.actual_demand_mw >= t.p90_demand_mw
             THEN 'High demand' ELSE 'Other demand' END AS demand_cohort
    FROM project_reporting.vw_demand_observation d
    JOIN thresholds t USING (authority_key, month_start)
    WHERE d.actual_demand_mw > 0
), cohort_totals AS (
    SELECT d.authority_key, d.authority_code, d.month_start, d.demand_cohort,
           d.p90_demand_mw, count(*) AS eligible_demand_hours,
           count(g.utc_hour_end) AS matched_generation_hours,
           sum(g.available_fuel_mw) AS signed_total_mwh
    FROM demand_cohorts d
    LEFT JOIN project_reporting.vw_generation_authority_hour g
      USING (authority_key, utc_hour_end)
    GROUP BY d.authority_key, d.authority_code, d.month_start, d.demand_cohort, d.p90_demand_mw
), hourly_group AS (
    SELECT f.authority_key, f.utc_hour_end, e.source_group,
           sum(f.generation_mw) AS group_mwh
    FROM project_dw.fact_hourly_generation f
    JOIN project_dw.dim_energy_source e USING (energy_source_key)
    GROUP BY f.authority_key, f.utc_hour_end, e.source_group
), group_totals AS (
    SELECT d.authority_key, d.month_start, d.demand_cohort, g.source_group,
           count(*) AS observed_group_hours, sum(g.group_mwh) AS signed_group_mwh
    FROM demand_cohorts d
    JOIN hourly_group g USING (authority_key, utc_hour_end)
    GROUP BY d.authority_key, d.month_start, d.demand_cohort, g.source_group
)
SELECT c.*, e.source_group, coalesce(g.observed_group_hours, 0) AS observed_group_hours,
       g.signed_group_mwh, 100.0 * g.signed_group_mwh
           / nullif(c.signed_total_mwh, 0) AS signed_mix_share_pct
FROM cohort_totals c
CROSS JOIN (SELECT DISTINCT source_group FROM project_dw.dim_energy_source) e
LEFT JOIN group_totals g USING (authority_key, month_start, demand_cohort, source_group);

-- Q10 grain: authority and operating month. Observed rows use the EIA
-- operating date; absent rows use the local hour ending under the known BA
-- reporting timezone (midnight belongs to the preceding operating date).
CREATE OR REPLACE VIEW project_reporting.vw_q10_source_quality AS
WITH expected AS (
    SELECT a.authority_key, a.authority_code, g.utc_hour_end,
           date_trunc('month', (g.utc_hour_end AT TIME ZONE
             CASE a.authority_code WHEN 'CISO' THEN 'America/Los_Angeles'
                WHEN 'ERCO' THEN 'America/Chicago'
                WHEN 'ISNE' THEN 'America/New_York'
                WHEN 'NYIS' THEN 'America/New_York'
                WHEN 'PJM' THEN 'America/New_York' END)
             - interval '1 microsecond')::date AS inferred_month
    FROM project_dw.expected_hour_grid g
    JOIN project_dw.dim_balancing_authority a USING (authority_key)
), totals AS (
    SELECT e.authority_key, e.authority_code,
           coalesce(r.month_start, e.inferred_month) AS month_start,
           count(*) AS expected_hours,
           count(r.utc_hour_end) AS observed_hours,
           count(*) FILTER (WHERE r.utc_hour_end IS NULL) AS absent_row_hours,
           count(*) FILTER (WHERE r.utc_hour_end IS NOT NULL AND r.actual_demand_mw IS NULL)
               AS null_actual_hours,
           count(*) FILTER (WHERE r.actual_demand_mw < 0) AS negative_actual_hours,
           count(*) FILTER (WHERE r.actual_demand_mw = 0) AS zero_actual_hours,
           count(*) FILTER (WHERE r.utc_hour_end IS NOT NULL AND r.forecast_demand_mw IS NULL)
               AS null_forecast_hours,
           count(*) FILTER (WHERE r.forecast_demand_mw < 0) AS negative_forecast_hours,
           count(*) FILTER (WHERE r.forecast_demand_mw = 0) AS zero_forecast_hours,
           count(*) FILTER (WHERE r.utc_hour_end IS NOT NULL AND r.total_generation_mw IS NULL)
               AS null_total_generation_hours,
           count(*) FILTER (WHERE r.total_generation_mw < 0) AS negative_total_generation_hours,
           count(*) FILTER (WHERE r.total_generation_mw = 0) AS zero_total_generation_hours,
           count(*) FILTER (WHERE r.utc_hour_end IS NOT NULL AND r.observed_fuel_count IS NULL)
               AS no_numeric_fuel_hours,
           count(r.residual_mw) AS comparable_hours,
           count(*) FILTER (WHERE abs(r.residual_mw) > r.tolerance_mw) AS residual_failure_hours,
           count(*) FILTER (WHERE r.utc_hour_end IS NULL OR r.actual_demand_mw IS NULL
             OR r.actual_demand_mw < 0 OR r.forecast_demand_mw IS NULL OR r.forecast_demand_mw < 0
             OR r.total_generation_mw IS NULL) AS affected_core_hours
    FROM expected e
    LEFT JOIN project_reporting.vw_generation_reconciliation_hour r USING (authority_key, utc_hour_end)
    GROUP BY e.authority_key, e.authority_code, coalesce(r.month_start, e.inferred_month)
), fuel AS (
    SELECT authority_key, month_start, sum(supplied_blank_hours)::bigint AS supplied_blank_cells,
           sum(absent_header_hours)::bigint AS absent_header_cells,
           sum(unknown_header_hours)::bigint AS unknown_header_cells,
           sum(observed_zero_hours)::bigint AS observed_zero_fuel_cells,
           sum(observed_negative_hours)::bigint AS observed_negative_fuel_cells
    FROM project_reporting.vw_q07_generation_by_source GROUP BY authority_key, month_start
)
SELECT totals.*, fuel.supplied_blank_cells, fuel.absent_header_cells, fuel.unknown_header_cells,
       fuel.observed_zero_fuel_cells, fuel.observed_negative_fuel_cells,
       100.0 * affected_core_hours / nullif(expected_hours, 0) AS affected_core_hours_pct,
       100.0 * residual_failure_hours / nullif(comparable_hours, 0) AS residual_failure_pct
FROM totals LEFT JOIN fuel USING (authority_key, month_start);

-- Grain: one month of the operating-date dimension, shared by all BI facts.
CREATE OR REPLACE VIEW project_reporting.vw_dashboard_month AS
SELECT DISTINCT date_trunc('month', calendar_date)::date AS month_start,
       calendar_year, month_number, to_char(calendar_date, 'YYYY-MM') AS year_month, season
FROM project_dw.dim_date;

-- Grain: one authority, operating month and tied peak timestamp.
-- Normalize UTC before Power Query converts the value to a model datetime.
CREATE OR REPLACE VIEW project_reporting.vw_dashboard_peak AS
SELECT authority_key, month_start, peak_actual_demand_mw,
       utc_hour_end AT TIME ZONE 'UTC' AS peak_utc,
       local_hour_end, utc_offset_minutes, tied_peak_timestamp_count
FROM project_reporting.vw_q03_monthly_peaks;
