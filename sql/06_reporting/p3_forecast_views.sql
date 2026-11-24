-- PowerPulse Phase 3 / Muaz Fahad (24L-2563). PostgreSQL 16+.
-- Prerequisite: p1_demand_views.sql. Install this whole file in one transaction.
-- Power/errors: MW. Positive actual-minus-forecast bias means underforecast.
-- Every metric uses the SAME pair population: actual > 0 AND forecast >= 0.

CREATE SCHEMA IF NOT EXISTS project_reporting;

-- Shared BI components: authority + operating month + local hour ending.
-- Month is retained so the Q06 visual can respond to the shared month slicer.
-- DST repeated local hours remain separate UTC observations in each bucket.
CREATE OR REPLACE VIEW project_reporting.vw_forecast_month_hour_components AS
SELECT authority_key, authority_code, authority_name, region_code, region_name,
       month_start, calendar_year, month_number, season, hour_ending, hour_label,
       count(*) AS observed_authority_hours,
       count(*) FILTER (WHERE is_forecast_eligible) AS eligible_forecast_pairs,
       count(*) FILTER (WHERE NOT is_forecast_eligible) AS excluded_forecast_pairs,
       sum(actual_demand_mw) FILTER (WHERE is_forecast_eligible)
           AS eligible_actual_sum_mw,
       sum(forecast_demand_mw) FILTER (WHERE is_forecast_eligible)
           AS eligible_forecast_sum_mw,
       sum(actual_demand_mw - forecast_demand_mw)
           FILTER (WHERE is_forecast_eligible) AS signed_error_sum_mw,
       sum(abs(actual_demand_mw - forecast_demand_mw))
           FILTER (WHERE is_forecast_eligible) AS abs_error_sum_mw,
       count(*) FILTER (WHERE is_forecast_eligible
           AND actual_demand_mw > forecast_demand_mw) AS underforecast_pairs,
       count(*) FILTER (WHERE is_forecast_eligible
           AND actual_demand_mw = forecast_demand_mw) AS equal_forecast_pairs,
       count(*) FILTER (WHERE is_forecast_eligible
           AND actual_demand_mw < forecast_demand_mw) AS overforecast_pairs
FROM project_reporting.vw_demand_observation
GROUP BY authority_key, authority_code, authority_name, region_code, region_name,
         month_start, calendar_year, month_number, season, hour_ending, hour_label;

-- Q05: authority + operating month. Reuse Q01's internal month spine; a wholly
-- missing internal month has zero counts and NULL sums/rates, not invented data.
CREATE OR REPLACE VIEW project_reporting.vw_q05_forecast_accuracy AS
WITH components AS (
    SELECT authority_key, month_start,
           sum(eligible_forecast_pairs)::bigint AS eligible_forecast_pairs,
           sum(excluded_forecast_pairs)::bigint AS excluded_forecast_pairs,
           sum(eligible_actual_sum_mw) AS eligible_actual_sum_mw,
           sum(eligible_forecast_sum_mw) AS eligible_forecast_sum_mw,
           sum(signed_error_sum_mw) AS signed_error_sum_mw,
           sum(abs_error_sum_mw) AS abs_error_sum_mw,
           sum(underforecast_pairs)::bigint AS underforecast_pairs,
           sum(equal_forecast_pairs)::bigint AS equal_forecast_pairs,
           sum(overforecast_pairs)::bigint AS overforecast_pairs
    FROM project_reporting.vw_forecast_month_hour_components
    GROUP BY authority_key, month_start
), monthly AS (
    SELECT m.authority_key, m.authority_code, m.authority_name,
           m.region_code, m.region_name, m.month_start,
           m.calendar_year, m.month_number, m.year_month,
           m.observed_authority_hours,
           coalesce(c.eligible_forecast_pairs, 0::bigint) AS eligible_forecast_pairs,
           coalesce(c.excluded_forecast_pairs, 0::bigint) AS excluded_forecast_pairs,
           c.eligible_actual_sum_mw, c.eligible_forecast_sum_mw,
           c.signed_error_sum_mw, c.abs_error_sum_mw,
           coalesce(c.underforecast_pairs, 0::bigint) AS underforecast_pairs,
           coalesce(c.equal_forecast_pairs, 0::bigint) AS equal_forecast_pairs,
           coalesce(c.overforecast_pairs, 0::bigint) AS overforecast_pairs
    FROM project_reporting.vw_q01_monthly_demand_energy m
    LEFT JOIN components c USING (authority_key, month_start)
)
SELECT monthly.*,
       signed_error_sum_mw / nullif(eligible_forecast_pairs, 0) AS forecast_bias_mw,
       abs_error_sum_mw / nullif(eligible_forecast_pairs, 0) AS forecast_mae_mw,
       100.0 * abs_error_sum_mw / nullif(eligible_actual_sum_mw, 0) AS forecast_wape_pct,
       100.0 * underforecast_pairs / nullif(eligible_forecast_pairs, 0)
           AS underforecast_pct,
       100.0 * eligible_forecast_pairs / nullif(observed_authority_hours, 0)
           AS observed_pair_coverage_pct
FROM monthly;

-- Q06 analytical output: authority + calendar year + season + local hour.
-- For month-filtered BI visuals, import the monthly components view instead.
CREATE OR REPLACE VIEW project_reporting.vw_q06_underforecast_pattern AS
WITH components AS (
    SELECT authority_key, authority_code, authority_name, region_code, region_name,
           calendar_year, season, hour_ending, hour_label,
           sum(observed_authority_hours)::bigint AS observed_authority_hours,
           sum(eligible_forecast_pairs)::bigint AS eligible_forecast_pairs,
           sum(excluded_forecast_pairs)::bigint AS excluded_forecast_pairs,
           sum(eligible_actual_sum_mw) AS eligible_actual_sum_mw,
           sum(eligible_forecast_sum_mw) AS eligible_forecast_sum_mw,
           sum(signed_error_sum_mw) AS signed_error_sum_mw,
           sum(abs_error_sum_mw) AS abs_error_sum_mw,
           sum(underforecast_pairs)::bigint AS underforecast_pairs,
           sum(equal_forecast_pairs)::bigint AS equal_forecast_pairs,
           sum(overforecast_pairs)::bigint AS overforecast_pairs
    FROM project_reporting.vw_forecast_month_hour_components
    GROUP BY authority_key, authority_code, authority_name, region_code, region_name,
             calendar_year, season, hour_ending, hour_label
)
SELECT components.*,
       signed_error_sum_mw / nullif(eligible_forecast_pairs, 0) AS forecast_bias_mw,
       abs_error_sum_mw / nullif(eligible_forecast_pairs, 0) AS forecast_mae_mw,
       100.0 * abs_error_sum_mw / nullif(eligible_actual_sum_mw, 0) AS forecast_wape_pct,
       100.0 * underforecast_pairs / nullif(eligible_forecast_pairs, 0)
           AS underforecast_pct
FROM components;

COMMENT ON VIEW project_reporting.vw_forecast_month_hour_components IS
    'Muaz Q05/Q06 BI components at authority/operating-month/local-hour grain. Actual > 0 and forecast >= 0, both present. Sum components before calculating rates. Equality remains in the pair denominator. Null sums mean no eligible pairs. Coverage describes observed rows only.';
COMMENT ON VIEW project_reporting.vw_q05_forecast_accuracy IS
    'Q05 authority/month forecast bias MW, MAE MW, WAPE percent and pair counts. Positive bias means underforecast. Missing internal months have zero counts and undefined rates. Evaluate published historical forecasts, which may include revisions.';
COMMENT ON VIEW project_reporting.vw_q06_underforecast_pattern IS
    'Q06 authority/calendar-year/meteorological-season/local-hour pattern. Underforecast is strict actual > forecast; equality remains eligible. Winter uses Jan-Feb and Dec of the same calendar year. For month-filterable BI use vw_forecast_month_hour_components.';
