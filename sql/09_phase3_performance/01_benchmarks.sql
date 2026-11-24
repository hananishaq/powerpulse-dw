-- Fixed parameters: source operating July 2025. Do not edit between arms.
-- Runner records exact SQL bytes, result checksums and JSON/text plans.

-- benchmark: demand_authority_month
SELECT a.authority_code, count(*) AS observed_hours,
       count(*) FILTER (WHERE f.actual_demand_mw >= 0) AS eligible_hours,
       sum(f.actual_demand_mw) FILTER (WHERE f.actual_demand_mw >= 0) AS demand_mwh
FROM project_dw.fact_hourly_demand f
JOIN project_dw.dim_balancing_authority a USING (authority_key)
JOIN project_dw.dim_date d USING (date_key)
WHERE a.authority_code = 'CISO'
  AND d.calendar_date >= DATE '2025-07-01'
  AND d.calendar_date < DATE '2025-08-01'
GROUP BY a.authority_code ORDER BY a.authority_code;

-- benchmark: generation_fuel_month
SELECT s.source_label, a.authority_code,
       count(*) AS generation_observations, sum(f.generation_mw) AS signed_mwh
FROM project_dw.fact_hourly_generation f
JOIN project_dw.dim_energy_source s USING (energy_source_key)
JOIN project_dw.dim_balancing_authority a USING (authority_key)
JOIN project_dw.dim_date d USING (date_key)
WHERE s.source_column = 'Net Generation (MW) from Natural Gas'
  AND d.calendar_date >= DATE '2025-07-01'
  AND d.calendar_date < DATE '2025-08-01'
GROUP BY s.source_label, a.authority_code ORDER BY s.source_label, a.authority_code;

-- benchmark: demand_cube_2025
SELECT a.region_name, d.season,
       grouping(a.region_name) AS region_is_total, grouping(d.season) AS season_is_total,
       sum(f.actual_demand_mw) FILTER (WHERE f.actual_demand_mw >= 0) AS demand_mwh,
       avg(f.actual_demand_mw) FILTER (WHERE f.actual_demand_mw >= 0) AS mean_demand_mw,
       count(*) FILTER (WHERE f.actual_demand_mw >= 0) AS eligible_hours,
       count(*) AS observed_hours
FROM project_dw.fact_hourly_demand f
JOIN project_dw.dim_balancing_authority a USING (authority_key)
JOIN project_dw.dim_date d USING (date_key)
WHERE d.calendar_year = 2025
GROUP BY CUBE(a.region_name, d.season)
ORDER BY grouping(a.region_name), a.region_name NULLS LAST,
         grouping(d.season), d.season NULLS LAST;
