-- PowerPulse Phase 3 / Mohid / PostgreSQL 16+
-- Dependencies: Phase 2 demand fact and date/hour/authority/snapshot dimensions.
-- Re-runnable, additive reporting objects only. No fact or dimension changes.
-- Run the whole file as one transaction (the Phase 3 runner does this).
CREATE SCHEMA IF NOT EXISTS project_reporting;

-- One existing demand observation per authority/UTC instant. This view never
-- joins generation. Nulls and negative demand remain visible for diagnosis.
CREATE OR REPLACE VIEW project_reporting.vw_demand_observation AS
SELECT f.demand_key, f.authority_key, a.authority_code, a.authority_name,
       a.region_code, a.region_name, f.date_key, d.calendar_date,
       date_trunc('month', d.calendar_date)::date AS month_start,
       d.calendar_year, d.month_number, d.season, d.weekday_number,
       f.hour_key, h.hour_ending, h.hour_label,
       f.utc_hour_end, f.local_hour_end, f.utc_offset_minutes,
       f.actual_demand_mw, f.forecast_demand_mw, f.total_generation_mw,
       CASE WHEN f.actual_demand_mw >= 0 THEN f.actual_demand_mw END
           AS eligible_actual_demand_mw,
       (f.actual_demand_mw > 0 AND f.forecast_demand_mw >= 0) IS TRUE
           AS is_forecast_eligible,
       f.source_snapshot_key, f.source_row_number
FROM project_dw.fact_hourly_demand f
JOIN project_dw.dim_date d USING (date_key)
JOIN project_dw.dim_hour h USING (hour_key)
JOIN project_dw.dim_balancing_authority a USING (authority_key);

-- Q01 grain: authority + operating month. A month spine within each authority's
-- observed span preserves wholly absent internal months. It does not invent
-- observations or infer expected operating dates from UTC clock labels.
CREATE OR REPLACE VIEW project_reporting.vw_q01_monthly_demand_energy AS
WITH bounds AS (
    SELECT authority_key, min(month_start) AS first_month,
           max(month_start) AS last_month
    FROM project_reporting.vw_demand_observation GROUP BY authority_key
), months AS (
    SELECT b.authority_key, m::date AS month_start
    FROM bounds b
    CROSS JOIN LATERAL generate_series(b.first_month::timestamp,
        b.last_month::timestamp, interval '1 month') m
), totals AS (
    SELECT authority_key, month_start, count(*) AS observed_authority_hours,
           count(eligible_actual_demand_mw) AS eligible_demand_hours,
           count(*) FILTER (WHERE actual_demand_mw IS NULL) AS null_actual_hours,
           count(*) FILTER (WHERE actual_demand_mw < 0) AS negative_actual_hours,
           sum(eligible_actual_demand_mw) AS observed_demand_mwh,
           count(DISTINCT source_snapshot_key) AS source_snapshot_count
    FROM project_reporting.vw_demand_observation
    GROUP BY authority_key, month_start
), assembled AS (
    SELECT m.authority_key, a.authority_code, a.authority_name,
           a.region_code, a.region_name, m.month_start,
           extract(year FROM m.month_start)::integer AS calendar_year,
           extract(month FROM m.month_start)::integer AS month_number,
           to_char(m.month_start, 'YYYY-MM') AS year_month,
           coalesce(t.observed_authority_hours, 0::bigint) AS observed_authority_hours,
           coalesce(t.eligible_demand_hours, 0::bigint) AS eligible_demand_hours,
           coalesce(t.null_actual_hours, 0::bigint) AS null_actual_hours,
           coalesce(t.negative_actual_hours, 0::bigint) AS negative_actual_hours,
           t.observed_demand_mwh,
           t.observed_demand_mwh / nullif(t.eligible_demand_hours, 0)
               AS mean_hourly_demand_mw,
           100.0 * t.eligible_demand_hours / nullif(t.observed_authority_hours, 0)
               AS observed_demand_coverage_pct,
           coalesce(t.source_snapshot_count, 0::bigint) AS source_snapshot_count
    FROM months m
    JOIN project_dw.dim_balancing_authority a USING (authority_key)
    LEFT JOIN totals t USING (authority_key, month_start)
), prior AS (
    SELECT assembled.*,
           lag(observed_demand_mwh) OVER (
               PARTITION BY authority_key ORDER BY month_start)
               AS previous_month_demand_mwh
    FROM assembled
)
SELECT prior.*,
       100.0 * (observed_demand_mwh - previous_month_demand_mwh)
           / nullif(previous_month_demand_mwh, 0) AS demand_mom_growth_pct
FROM prior;

-- Q02 grain: authority + operating month + source local hour ending (0..23).
-- Retain sums and counts for weighted roll-up across months/authorities.
-- DST repetitions remain two observations inside the same local-hour bucket.
CREATE OR REPLACE VIEW project_reporting.vw_q02_hourly_profile AS
SELECT authority_key, authority_code, region_code, region_name, month_start,
       calendar_year, month_number, hour_ending, hour_label,
       count(*) AS observed_authority_hours,
       count(eligible_actual_demand_mw) AS eligible_demand_hours,
       count(*) FILTER (WHERE actual_demand_mw IS NULL) AS null_actual_hours,
       count(*) FILTER (WHERE actual_demand_mw < 0) AS negative_actual_hours,
       sum(eligible_actual_demand_mw) AS demand_sum_mw,
       avg(eligible_actual_demand_mw) AS mean_hourly_demand_mw
FROM project_reporting.vw_demand_observation
GROUP BY authority_key, authority_code, region_code, region_name, month_start,
         calendar_year, month_number, hour_ending, hour_label;

-- Segmentation support is self-contained so Mohid's package can run before Q05.
-- These components implement M04-M07, with the same pair set as the Q05 owner.
-- Thresholds are project planning bands, not industry standards or risk ratings.
CREATE OR REPLACE VIEW project_reporting.vw_authority_analysis AS
WITH forecast AS (
    SELECT authority_key, month_start,
           count(*) FILTER (WHERE is_forecast_eligible) AS eligible_forecast_pairs,
           sum(actual_demand_mw) FILTER (WHERE is_forecast_eligible)
               AS eligible_actual_sum_mw,
           sum(abs(actual_demand_mw - forecast_demand_mw))
               FILTER (WHERE is_forecast_eligible) AS abs_error_sum_mw,
           sum(actual_demand_mw - forecast_demand_mw)
               FILTER (WHERE is_forecast_eligible) AS signed_error_sum_mw,
           count(*) FILTER (WHERE is_forecast_eligible
               AND actual_demand_mw > forecast_demand_mw) AS underforecast_pairs
    FROM project_reporting.vw_demand_observation
    GROUP BY authority_key, month_start
), metrics AS (
    SELECT m.*,
           coalesce(f.eligible_forecast_pairs, 0::bigint) AS eligible_forecast_pairs,
           m.observed_authority_hours - coalesce(f.eligible_forecast_pairs, 0::bigint)
               AS excluded_forecast_pairs,
           f.eligible_actual_sum_mw, f.abs_error_sum_mw, f.signed_error_sum_mw,
           coalesce(f.underforecast_pairs, 0::bigint) AS underforecast_pairs,
           100.0 * f.abs_error_sum_mw / nullif(f.eligible_actual_sum_mw, 0)
               AS forecast_wape_pct,
           f.abs_error_sum_mw / nullif(f.eligible_forecast_pairs, 0)
               AS forecast_mae_mw,
           f.signed_error_sum_mw / nullif(f.eligible_forecast_pairs, 0)
               AS forecast_bias_mw
    FROM project_reporting.vw_q01_monthly_demand_energy m
    LEFT JOIN forecast f USING (authority_key, month_start)
)
SELECT metrics.*,
       CASE WHEN mean_hourly_demand_mw IS NULL THEN 'No eligible demand'
            WHEN mean_hourly_demand_mw < 10000 THEN 'Below 10 GW'
            WHEN mean_hourly_demand_mw < 30000 THEN '10 to below 30 GW'
            ELSE '30 GW or above' END AS demand_segment,
       CASE WHEN forecast_wape_pct IS NULL THEN 'No eligible forecast pairs'
            WHEN forecast_wape_pct < 5 THEN 'Below 5% WAPE'
            WHEN forecast_wape_pct < 10 THEN '5 to below 10% WAPE'
            ELSE '10% WAPE or above' END AS forecast_error_segment
FROM metrics;

COMMENT ON VIEW project_reporting.vw_demand_observation IS
    'M01-M07 input at authority/UTC-hour grain. Operating date comes from source Data Date. Source keys support lineage.';
COMMENT ON VIEW project_reporting.vw_q01_monthly_demand_energy IS
    'Q01/M01. Observed hourly-average MW x 1 h = MWh. Null totals stay null. Coverage denominator is observed rows, not expected grid hours. MoM is observed energy.';
COMMENT ON VIEW project_reporting.vw_q02_hourly_profile IS
    'Q02/M02. Local-hour profile by authority/month. Roll up demand_sum_mw / eligible_demand_hours, never AVG(group means).';
COMMENT ON VIEW project_reporting.vw_authority_analysis IS
    'Authority/month planning bands with M04-M07 forecast components. Thresholds are project choices. Recompute rates from sums after filtering.';
