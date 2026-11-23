-- Mohid / Phase 3 analytical submission. Run after p1_demand_views.sql.
-- Edit the dates and authority list in each params CTE for another selection.
-- Dates filter source operating months, not UTC dates.

-- Q01: monthly energy, coverage and growth. SUM and COUNT are implemented in
-- the reporting view. Growth compares adjacent calendar months before filters.
WITH params AS (
    SELECT DATE '2024-01-01' AS from_month, DATE '2026-01-01' AS to_month,
           ARRAY['CISO','ERCO','ISNE','NYIS','PJM']::text[] AS authorities
)
SELECT v.*
FROM project_reporting.vw_q01_monthly_demand_energy v CROSS JOIN params p
WHERE v.month_start >= p.from_month AND v.month_start < p.to_month
  AND v.authority_code = ANY(p.authorities)
ORDER BY v.authority_code, v.month_start;

-- Q02: highest mean local-hour demand by authority, keeping every tied rank.
-- Divide additive components, avoiding an unweighted average of month means.
WITH params AS (
    SELECT DATE '2024-01-01' AS from_month, DATE '2026-01-01' AS to_month,
           ARRAY['CISO','ERCO','ISNE','NYIS','PJM']::text[] AS authorities
), profile AS (
    SELECT v.authority_code, v.hour_ending,
           sum(v.observed_authority_hours) AS observed_authority_hours,
           sum(v.eligible_demand_hours) AS eligible_demand_hours,
           sum(v.demand_sum_mw) AS demand_sum_mw,
           sum(v.demand_sum_mw) / nullif(sum(v.eligible_demand_hours), 0)
               AS mean_hourly_demand_mw
    FROM project_reporting.vw_q02_hourly_profile v CROSS JOIN params p
    WHERE v.month_start >= p.from_month AND v.month_start < p.to_month
      AND v.authority_code = ANY(p.authorities)
    GROUP BY v.authority_code, v.hour_ending
)
SELECT *, CASE WHEN mean_hourly_demand_mw IS NOT NULL THEN
       dense_rank() OVER (PARTITION BY authority_code
           ORDER BY mean_hourly_demand_mw DESC NULLS LAST) END AS demand_rank
FROM profile
ORDER BY authority_code, demand_rank NULLS LAST, hour_ending;

-- Direct SUM/AVG/COUNT demonstration, independent of the aggregate views.
SELECT authority_code,
       sum(eligible_actual_demand_mw * 1.0) AS observed_demand_mwh,
       avg(eligible_actual_demand_mw) AS mean_hourly_demand_mw,
       count(*) AS observed_authority_hours,
       count(eligible_actual_demand_mw) AS eligible_demand_hours
FROM project_reporting.vw_demand_observation
GROUP BY authority_code ORDER BY authority_code;

-- Source lineage: select the same operating window as the executive page.
SELECT DISTINCT o.authority_code, o.month_start, s.source_snapshot_key,
       s.file_name, s.sha256, s.retrieved_at_utc
FROM project_reporting.vw_demand_observation o
JOIN project_dw.dim_source_snapshot s USING (source_snapshot_key)
WHERE o.calendar_date >= DATE '2024-01-01' AND o.calendar_date < DATE '2026-01-01'
ORDER BY o.authority_code, o.month_start, s.source_snapshot_key;
