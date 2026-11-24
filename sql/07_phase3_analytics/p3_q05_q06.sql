-- Muaz Fahad / Q05-Q06. Run p1_demand_views.sql, then p3_forecast_views.sql.
-- Dates are source operating dates, not UTC-date approximations.

-- Q05: monthly same-pair accuracy, worst WAPE first within each month.
WITH params AS (
    SELECT DATE '2024-01-01' AS from_month, DATE '2026-01-01' AS to_month,
           ARRAY['CISO','ERCO','ISNE','NYIS','PJM']::text[] AS authorities
)
SELECT v.*,
       CASE WHEN forecast_wape_pct IS NOT NULL THEN
           dense_rank() OVER (PARTITION BY month_start
                             ORDER BY forecast_wape_pct DESC NULLS LAST)
       END AS wape_rank
FROM project_reporting.vw_q05_forecast_accuracy v CROSS JOIN params p
WHERE month_start >= p.from_month AND month_start < p.to_month
  AND authority_code = ANY(p.authorities)
ORDER BY month_start, wape_rank, authority_code;

-- Q06: season/local-hour underforecast patterns, with year kept explicit.
SELECT * FROM project_reporting.vw_q06_underforecast_pattern
WHERE calendar_year BETWEEN 2024 AND 2025
ORDER BY authority_code, calendar_year,
         CASE season WHEN 'Winter' THEN 1 WHEN 'Spring' THEN 2
                     WHEN 'Summer' THEN 3 ELSE 4 END,
         hour_ending;

-- Filterable BI example: PJM June 2025, preserving one denominator per measure.
SELECT authority_code, hour_ending,
       sum(eligible_forecast_pairs) AS eligible_forecast_pairs,
       sum(excluded_forecast_pairs) AS excluded_forecast_pairs,
       sum(signed_error_sum_mw) / nullif(sum(eligible_forecast_pairs), 0) AS bias_mw,
       sum(abs_error_sum_mw) / nullif(sum(eligible_forecast_pairs), 0) AS mae_mw,
       100.0 * sum(abs_error_sum_mw) / nullif(sum(eligible_actual_sum_mw), 0) AS wape_pct,
       100.0 * sum(underforecast_pairs) / nullif(sum(eligible_forecast_pairs), 0)
           AS underforecast_pct
FROM project_reporting.vw_forecast_month_hour_components
WHERE authority_code = 'PJM' AND month_start = DATE '2025-06-01'
GROUP BY authority_code, hour_ending ORDER BY hour_ending;

-- Nonadditive lineage: list contributing snapshots once per authority/month.
SELECT o.authority_code, o.month_start, s.file_name, s.sha256,
       count(*) AS observed_rows,
       count(*) FILTER (WHERE o.is_forecast_eligible) AS eligible_pairs
FROM project_reporting.vw_demand_observation o
JOIN project_dw.dim_source_snapshot s USING (source_snapshot_key)
GROUP BY o.authority_code, o.month_start, s.file_name, s.sha256
ORDER BY o.authority_code, o.month_start, s.file_name;
