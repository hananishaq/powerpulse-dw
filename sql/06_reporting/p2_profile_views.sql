-- PowerPulse Phase 3 / Hanan Ishaq (24L-2537) / PostgreSQL 16+
-- Dependencies: project_reporting.vw_demand_observation from p1_demand_views.sql.
-- Re-runnable reporting views for Q03 and Q04. Warehouse data is not changed.

CREATE SCHEMA IF NOT EXISTS project_reporting;

-- Q03 grain: one row per authority + source operating month + tied peak UTC
-- timestamp. Months without eligible demand retain one row with NULL peak and
-- timestamp values. Eligible demand is nonnegative actual demand. UTC is the
-- observation key; local labels and offsets are presentation attributes.
CREATE OR REPLACE VIEW project_reporting.vw_q03_monthly_peaks AS
WITH monthly AS (
    SELECT authority_key, month_start,
           count(*) AS observed_authority_hours,
           count(eligible_actual_demand_mw) AS eligible_demand_hours,
           count(*) FILTER (WHERE actual_demand_mw IS NULL) AS null_actual_hours,
           count(*) FILTER (WHERE actual_demand_mw < 0) AS negative_actual_hours,
           max(eligible_actual_demand_mw) AS peak_actual_demand_mw
    FROM project_reporting.vw_demand_observation
    GROUP BY authority_key, month_start
), peaks AS (
    SELECT m.authority_key, m.month_start,
           m.observed_authority_hours, m.eligible_demand_hours,
           m.null_actual_hours, m.negative_actual_hours,
           m.peak_actual_demand_mw,
           o.demand_key, o.utc_hour_end, o.local_hour_end,
           o.utc_offset_minutes, o.hour_ending, o.hour_label,
           o.source_snapshot_key, o.source_row_number
    FROM monthly m
    LEFT JOIN project_reporting.vw_demand_observation o
      ON o.authority_key = m.authority_key
     AND o.month_start = m.month_start
     AND o.eligible_actual_demand_mw = m.peak_actual_demand_mw
)
SELECT p.authority_key, a.authority_code, a.authority_name,
       a.region_code, a.region_name, p.month_start,
       extract(year FROM p.month_start)::integer AS calendar_year,
       extract(month FROM p.month_start)::integer AS month_number,
       to_char(p.month_start, 'YYYY-MM') AS year_month,
       p.peak_actual_demand_mw,
       p.utc_hour_end, p.local_hour_end, p.utc_offset_minutes,
       p.hour_ending, p.hour_label,
       count(p.demand_key) OVER (
           PARTITION BY p.authority_key, p.month_start
       ) AS tied_peak_timestamp_count,
       p.observed_authority_hours, p.eligible_demand_hours,
       p.null_actual_hours, p.negative_actual_hours,
       100.0 * p.eligible_demand_hours
           / nullif(p.observed_authority_hours, 0) AS observed_demand_coverage_pct,
       p.source_snapshot_key, p.source_row_number
FROM peaks p
JOIN project_dw.dim_balancing_authority a USING (authority_key);

-- Q04 grain: authority + operating calendar year + meteorological season +
-- weekday/weekend. Winter uses the operating date's calendar year, so December
-- and January/February are not combined into a cross-year winter label.
-- Additive fields can be rolled up. Recalculate a mean as
-- SUM(demand_sum_mw) / NULLIF(SUM(eligible_demand_hours), 0).
CREATE OR REPLACE VIEW project_reporting.vw_q04_season_daytype AS
SELECT authority_key, authority_code, authority_name,
       region_code, region_name, calendar_year, season,
       CASE WHEN weekday_number BETWEEN 1 AND 5
            THEN 'Weekday' ELSE 'Weekend' END AS day_type,
       count(*) AS observed_authority_hours,
       count(eligible_actual_demand_mw) AS eligible_demand_hours,
       count(*) FILTER (WHERE actual_demand_mw IS NULL) AS null_actual_hours,
       count(*) FILTER (WHERE actual_demand_mw < 0) AS negative_actual_hours,
       sum(eligible_actual_demand_mw) AS demand_sum_mw,
       avg(eligible_actual_demand_mw) AS mean_demand_mw,
       100.0 * count(eligible_actual_demand_mw)
           / nullif(count(*), 0) AS observed_demand_coverage_pct
FROM project_reporting.vw_demand_observation
GROUP BY authority_key, authority_code, authority_name,
         region_code, region_name, calendar_year, season,
         CASE WHEN weekday_number BETWEEN 1 AND 5
              THEN 'Weekday' ELSE 'Weekend' END;

COMMENT ON VIEW project_reporting.vw_q03_monthly_peaks IS
    'Q03. One row per authority/operating month/tied peak UTC timestamp. Nonnegative actual demand is eligible. All ties are retained; a month without eligible demand has one NULL peak row. Coverage uses observed records, not the expected-hour grid.';

COMMENT ON VIEW project_reporting.vw_q04_season_daytype IS
    'Q04. Authority/calendar-year/meteorological-season/day-type profile from source operating dates. Weekdays are ISO 1-5. Winter stays within calendar year. Roll up means from demand_sum_mw and eligible_demand_hours.';

-- BI input for Q04: retain month so CalendarMonth slicers restrict the actual
-- observations before seasonal means are calculated. The original seasonal
-- view above remains the full-season analytical output.
CREATE OR REPLACE VIEW project_reporting.vw_q04_month_daytype AS
SELECT authority_key, authority_code, authority_name,
       region_code, region_name, month_start, calendar_year, month_number,
       season,
       CASE WHEN weekday_number BETWEEN 1 AND 5
            THEN 'Weekday' ELSE 'Weekend' END AS day_type,
       count(*) AS observed_authority_hours,
       count(eligible_actual_demand_mw) AS eligible_demand_hours,
       count(*) FILTER (WHERE actual_demand_mw IS NULL) AS null_actual_hours,
       count(*) FILTER (WHERE actual_demand_mw < 0) AS negative_actual_hours,
       sum(eligible_actual_demand_mw) AS demand_sum_mw,
       avg(eligible_actual_demand_mw) AS mean_demand_mw,
       100.0 * count(eligible_actual_demand_mw)
           / nullif(count(*), 0) AS observed_demand_coverage_pct
FROM project_reporting.vw_demand_observation
GROUP BY authority_key, authority_code, authority_name,
         region_code, region_name, month_start, calendar_year, month_number,
         season,
         CASE WHEN weekday_number BETWEEN 1 AND 5
              THEN 'Weekday' ELSE 'Weekend' END;

COMMENT ON VIEW project_reporting.vw_q04_month_daytype IS
    'Q04 BI input. One row per authority/operating month/day-type. Filter month_start before rolling up to season. Recalculate means and coverage from additive sums/counts; never average monthly means. Original seasonal Q04 output is unchanged.';
