-- PowerPulse Phase 3 / Hanan Ishaq (24L-2537) / PostgreSQL 16+
-- CUBE of region by meteorological season for source operating year 2025.
-- Demand eligibility is actual_demand_mw >= 0. Means are calculated directly
-- from eligible observations at every level, never from subgroup averages.

WITH params AS (
    SELECT 2025::smallint AS selected_year
), cube_result AS (
    SELECT a.region_name, d.season,
           grouping(a.region_name) AS region_is_total,
           grouping(d.season) AS season_is_total,
           sum(f.actual_demand_mw) FILTER (
               WHERE f.actual_demand_mw >= 0
           ) AS observed_demand_mwh,
           avg(f.actual_demand_mw) FILTER (
               WHERE f.actual_demand_mw >= 0
           ) AS mean_eligible_demand_mw,
           count(*) FILTER (
               WHERE f.actual_demand_mw >= 0
           ) AS eligible_demand_observations,
           count(*) AS observed_authority_hours,
           count(*) FILTER (WHERE f.actual_demand_mw IS NULL)
               AS null_actual_hours,
           count(*) FILTER (WHERE f.actual_demand_mw < 0)
               AS negative_actual_hours
    FROM project_dw.fact_hourly_demand f
    JOIN project_dw.dim_balancing_authority a USING (authority_key)
    JOIN project_dw.dim_date d USING (date_key)
    CROSS JOIN params p
    WHERE d.calendar_year = p.selected_year
    GROUP BY CUBE (a.region_name, d.season)
)
SELECT 2025 AS selected_year,
       CASE WHEN region_is_total = 1 THEN 'All regions'
            ELSE region_name END AS region_name,
       CASE WHEN season_is_total = 1 THEN 'All seasons'
            ELSE season END AS season,
       CASE
           WHEN region_is_total = 1 AND season_is_total = 1 THEN 'Grand total'
           WHEN season_is_total = 1 THEN 'Region total'
           WHEN region_is_total = 1 THEN 'Season total'
           ELSE 'Region-season detail'
       END AS aggregation_level,
       observed_demand_mwh, mean_eligible_demand_mw,
       eligible_demand_observations, observed_authority_hours,
       null_actual_hours, negative_actual_hours,
       region_is_total, season_is_total
FROM cube_result
ORDER BY region_is_total, region_name NULLS LAST,
         season_is_total,
         CASE season WHEN 'Winter' THEN 1 WHEN 'Spring' THEN 2
                     WHEN 'Summer' THEN 3 WHEN 'Autumn' THEN 4 ELSE 5 END;

DO $$
BEGIN
    IF EXISTS (
        WITH cube_values AS (
            SELECT a.region_name, d.season,
                   grouping(a.region_name) AS gr,
                   grouping(d.season) AS gs,
                   sum(f.actual_demand_mw) FILTER (
                       WHERE f.actual_demand_mw >= 0
                   ) AS mwh,
                   avg(f.actual_demand_mw) FILTER (
                       WHERE f.actual_demand_mw >= 0
                   ) AS mean_mw,
                   count(*) FILTER (
                       WHERE f.actual_demand_mw >= 0
                   ) AS eligible,
                   count(*) AS observed
            FROM project_dw.fact_hourly_demand f
            JOIN project_dw.dim_balancing_authority a USING (authority_key)
            JOIN project_dw.dim_date d USING (date_key)
            WHERE d.calendar_year = 2025
            GROUP BY CUBE (a.region_name, d.season)
        ), expected AS (
            SELECT a.region_name, d.season, 0 AS gr, 0 AS gs,
                   sum(f.actual_demand_mw) FILTER (
                       WHERE f.actual_demand_mw >= 0
                   ) AS mwh,
                   avg(f.actual_demand_mw) FILTER (
                       WHERE f.actual_demand_mw >= 0
                   ) AS mean_mw,
                   count(*) FILTER (
                       WHERE f.actual_demand_mw >= 0
                   ) AS eligible,
                   count(*) AS observed
            FROM project_dw.fact_hourly_demand f
            JOIN project_dw.dim_balancing_authority a USING (authority_key)
            JOIN project_dw.dim_date d USING (date_key)
            WHERE d.calendar_year = 2025
            GROUP BY a.region_name, d.season
            UNION ALL
            SELECT a.region_name, NULL, 0, 1,
                   sum(f.actual_demand_mw) FILTER (
                       WHERE f.actual_demand_mw >= 0),
                   avg(f.actual_demand_mw) FILTER (
                       WHERE f.actual_demand_mw >= 0),
                   count(*) FILTER (WHERE f.actual_demand_mw >= 0), count(*)
            FROM project_dw.fact_hourly_demand f
            JOIN project_dw.dim_balancing_authority a USING (authority_key)
            JOIN project_dw.dim_date d USING (date_key)
            WHERE d.calendar_year = 2025
            GROUP BY a.region_name
            UNION ALL
            SELECT NULL, d.season, 1, 0,
                   sum(f.actual_demand_mw) FILTER (
                       WHERE f.actual_demand_mw >= 0),
                   avg(f.actual_demand_mw) FILTER (
                       WHERE f.actual_demand_mw >= 0),
                   count(*) FILTER (WHERE f.actual_demand_mw >= 0), count(*)
            FROM project_dw.fact_hourly_demand f
            JOIN project_dw.dim_date d USING (date_key)
            WHERE d.calendar_year = 2025
            GROUP BY d.season
            UNION ALL
            SELECT NULL, NULL, 1, 1,
                   sum(f.actual_demand_mw) FILTER (
                       WHERE f.actual_demand_mw >= 0),
                   avg(f.actual_demand_mw) FILTER (
                       WHERE f.actual_demand_mw >= 0),
                   count(*) FILTER (WHERE f.actual_demand_mw >= 0), count(*)
            FROM project_dw.fact_hourly_demand f
            JOIN project_dw.dim_date d USING (date_key)
            WHERE d.calendar_year = 2025
        ), differences AS (
            (SELECT * FROM cube_values EXCEPT SELECT * FROM expected)
            UNION ALL
            (SELECT * FROM expected EXCEPT SELECT * FROM cube_values)
        )
        SELECT 1 FROM differences
    ) THEN
        RAISE EXCEPTION 'CUBE levels differ from independent aggregations';
    END IF;

    RAISE NOTICE 'PASS: CUBE detail, region, season and grand-total levels';
END $$;
