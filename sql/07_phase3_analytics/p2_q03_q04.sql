-- PowerPulse Phase 3 / Hanan Ishaq (24L-2537) / PostgreSQL 16+
-- Run after p1_demand_views.sql and p2_profile_views.sql.
-- The result queries are followed by fail-on-error independent reconciliations.

-- Q03: monthly peak demand with every tied UTC timestamp retained.
WITH params AS (
    SELECT DATE '2024-01-01' AS from_month, DATE '2026-01-01' AS to_month,
           ARRAY['CISO','ERCO','ISNE','NYIS','PJM']::text[] AS authorities
)
SELECT v.*
FROM project_reporting.vw_q03_monthly_peaks v
CROSS JOIN params p
WHERE v.month_start >= p.from_month
  AND v.month_start < p.to_month
  AND v.authority_code = ANY(p.authorities)
ORDER BY v.authority_code, v.month_start, v.utc_hour_end NULLS LAST;

-- Q04: seasonal weekday/weekend demand profile. The calendar year comes from
-- the source operating date. Winter 2025 means Jan-Feb and Dec 2025.
WITH params AS (
    SELECT 2024 AS from_year, 2025 AS to_year,
           ARRAY['CISO','ERCO','ISNE','NYIS','PJM']::text[] AS authorities
)
SELECT v.*
FROM project_reporting.vw_q04_season_daytype v
CROSS JOIN params p
WHERE v.calendar_year BETWEEN p.from_year AND p.to_year
  AND v.authority_code = ANY(p.authorities)
ORDER BY v.authority_code, v.calendar_year,
         CASE v.season WHEN 'Winter' THEN 1 WHEN 'Spring' THEN 2
                       WHEN 'Summer' THEN 3 ELSE 4 END,
         v.day_type;

-- Q03 and Q04 independent fact-to-view reconciliation.
DO $$
BEGIN
    IF (
        WITH fixture(authority_key, month_start, utc_hour_end, actual_demand_mw) AS (
            VALUES
                (1::bigint, DATE '2025-01-01', TIMESTAMPTZ '2025-01-01 01:00:00+00', 10::numeric),
                (1::bigint, DATE '2025-01-01', TIMESTAMPTZ '2025-01-01 02:00:00+00', 20::numeric),
                (1::bigint, DATE '2025-01-01', TIMESTAMPTZ '2025-01-01 03:00:00+00', 20::numeric)
        ), monthly AS (
            SELECT authority_key, month_start,
                   max(actual_demand_mw) AS peak_actual_demand_mw
            FROM fixture
            WHERE actual_demand_mw >= 0
            GROUP BY authority_key, month_start
        )
        SELECT count(*)
        FROM monthly m
        JOIN fixture f USING (authority_key, month_start)
        WHERE f.actual_demand_mw = m.peak_actual_demand_mw
    ) <> 2 THEN
        RAISE EXCEPTION 'Q03 tie-preservation fixture did not retain both timestamps';
    END IF;

    IF EXISTS (
        SELECT authority_key, month_start, utc_hour_end
        FROM project_reporting.vw_q03_monthly_peaks
        GROUP BY authority_key, month_start, utc_hour_end
        HAVING count(*) <> 1
    ) THEN
        RAISE EXCEPTION 'Q03 is not unique at authority/month/tied UTC grain';
    END IF;

    IF EXISTS (
        WITH monthly AS (
            SELECT f.authority_key,
                   date_trunc('month', d.calendar_date)::date AS month_start,
                   max(f.actual_demand_mw) FILTER (
                       WHERE f.actual_demand_mw >= 0
                   ) AS peak_actual_demand_mw,
                   count(*) AS observed_authority_hours,
                   count(*) FILTER (WHERE f.actual_demand_mw >= 0)
                       AS eligible_demand_hours,
                   count(*) FILTER (WHERE f.actual_demand_mw IS NULL)
                       AS null_actual_hours,
                   count(*) FILTER (WHERE f.actual_demand_mw < 0)
                       AS negative_actual_hours
            FROM project_dw.fact_hourly_demand f
            JOIN project_dw.dim_date d USING (date_key)
            GROUP BY f.authority_key,
                     date_trunc('month', d.calendar_date)::date
        ), expected AS (
            SELECT m.authority_key, m.month_start,
                   m.peak_actual_demand_mw,
                   f.utc_hour_end, f.local_hour_end,
                   m.observed_authority_hours, m.eligible_demand_hours,
                   m.null_actual_hours, m.negative_actual_hours
            FROM monthly m
            LEFT JOIN project_dw.fact_hourly_demand f
              ON f.authority_key = m.authority_key
             AND f.actual_demand_mw = m.peak_actual_demand_mw
            LEFT JOIN project_dw.dim_date d
              ON d.date_key = f.date_key
             AND date_trunc('month', d.calendar_date)::date = m.month_start
            WHERE f.demand_key IS NULL
               OR date_trunc('month', d.calendar_date)::date = m.month_start
        ), differences AS (
            (SELECT * FROM expected
             EXCEPT
             SELECT authority_key, month_start, peak_actual_demand_mw,
                    utc_hour_end, local_hour_end,
                    observed_authority_hours, eligible_demand_hours,
                    null_actual_hours, negative_actual_hours
             FROM project_reporting.vw_q03_monthly_peaks)
            UNION ALL
            (SELECT authority_key, month_start, peak_actual_demand_mw,
                    utc_hour_end, local_hour_end,
                    observed_authority_hours, eligible_demand_hours,
                    null_actual_hours, negative_actual_hours
             FROM project_reporting.vw_q03_monthly_peaks
             EXCEPT
             SELECT * FROM expected)
        )
        SELECT 1 FROM differences
    ) THEN
        RAISE EXCEPTION 'Q03 differs from independently calculated monthly maxima';
    END IF;

    IF EXISTS (
        WITH base AS (
            SELECT f.authority_key, d.calendar_year, d.season,
                   CASE WHEN d.weekday_number BETWEEN 1 AND 5
                        THEN 'Weekday' ELSE 'Weekend' END AS day_type,
                   count(*) AS observed_authority_hours,
                   count(*) FILTER (WHERE f.actual_demand_mw >= 0)
                       AS eligible_demand_hours,
                   count(*) FILTER (WHERE f.actual_demand_mw IS NULL)
                       AS null_actual_hours,
                   count(*) FILTER (WHERE f.actual_demand_mw < 0)
                       AS negative_actual_hours,
                   sum(f.actual_demand_mw) FILTER (
                       WHERE f.actual_demand_mw >= 0
                   ) AS demand_sum_mw,
                   avg(f.actual_demand_mw) FILTER (
                       WHERE f.actual_demand_mw >= 0
                   ) AS mean_demand_mw
            FROM project_dw.fact_hourly_demand f
            JOIN project_dw.dim_date d USING (date_key)
            GROUP BY f.authority_key, d.calendar_year, d.season,
                     CASE WHEN d.weekday_number BETWEEN 1 AND 5
                          THEN 'Weekday' ELSE 'Weekend' END
        )
        SELECT 1
        FROM base b
        FULL JOIN project_reporting.vw_q04_season_daytype v
          USING (authority_key, calendar_year, season, day_type)
        WHERE b.observed_authority_hours
                  IS DISTINCT FROM v.observed_authority_hours
           OR b.eligible_demand_hours
                  IS DISTINCT FROM v.eligible_demand_hours
           OR b.null_actual_hours IS DISTINCT FROM v.null_actual_hours
           OR b.negative_actual_hours IS DISTINCT FROM v.negative_actual_hours
           OR b.demand_sum_mw IS DISTINCT FROM v.demand_sum_mw
           OR b.mean_demand_mw IS DISTINCT FROM v.mean_demand_mw
    ) THEN
        RAISE EXCEPTION 'Q04 differs from independently grouped demand facts';
    END IF;

    IF EXISTS (
        SELECT authority_key, month_start, day_type
        FROM project_reporting.vw_q04_month_daytype
        GROUP BY authority_key, month_start, day_type
        HAVING count(*) <> 1
    ) THEN
        RAISE EXCEPTION 'Q04 BI input is not unique at authority/month/day-type grain';
    END IF;

    IF EXISTS (
        WITH expected AS (
            SELECT f.authority_key,
                   date_trunc('month', d.calendar_date)::date AS month_start,
                   d.calendar_year, d.month_number, d.season,
                   CASE WHEN d.weekday_number BETWEEN 1 AND 5
                        THEN 'Weekday' ELSE 'Weekend' END AS day_type,
                   count(*) AS observed_authority_hours,
                   count(*) FILTER (WHERE f.actual_demand_mw >= 0)
                       AS eligible_demand_hours,
                   count(*) FILTER (WHERE f.actual_demand_mw IS NULL)
                       AS null_actual_hours,
                   count(*) FILTER (WHERE f.actual_demand_mw < 0)
                       AS negative_actual_hours,
                   sum(f.actual_demand_mw) FILTER (WHERE f.actual_demand_mw >= 0)
                       AS demand_sum_mw,
                   avg(f.actual_demand_mw) FILTER (WHERE f.actual_demand_mw >= 0)
                       AS mean_demand_mw,
                   100.0 * count(*) FILTER (WHERE f.actual_demand_mw >= 0)
                       / nullif(count(*), 0) AS observed_demand_coverage_pct
            FROM project_dw.fact_hourly_demand f
            JOIN project_dw.dim_date d USING (date_key)
            GROUP BY f.authority_key,
                     date_trunc('month', d.calendar_date)::date,
                     d.calendar_year, d.month_number, d.season,
                     CASE WHEN d.weekday_number BETWEEN 1 AND 5
                          THEN 'Weekday' ELSE 'Weekend' END
        ), differences AS (
            (SELECT * FROM expected EXCEPT
             SELECT authority_key, month_start, calendar_year, month_number,
                    season, day_type, observed_authority_hours,
                    eligible_demand_hours, null_actual_hours, negative_actual_hours,
                    demand_sum_mw, mean_demand_mw, observed_demand_coverage_pct
             FROM project_reporting.vw_q04_month_daytype)
            UNION ALL
            (SELECT authority_key, month_start, calendar_year, month_number,
                    season, day_type, observed_authority_hours,
                    eligible_demand_hours, null_actual_hours, negative_actual_hours,
                    demand_sum_mw, mean_demand_mw, observed_demand_coverage_pct
             FROM project_reporting.vw_q04_month_daytype
             EXCEPT SELECT * FROM expected)
        )
        SELECT 1 FROM differences
    ) THEN
        RAISE EXCEPTION 'Q04 monthly BI components differ from independently grouped facts';
    END IF;

    RAISE NOTICE 'PASS: Q03 tie fixture/maxima, Q04 seasonal and month-filterable profiles';
END $$;
