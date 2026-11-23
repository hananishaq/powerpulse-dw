-- Signed generation by region, source group and source label for operating year 2025.
SET statement_timeout = '10min';
SET temp_file_limit = '2GB';
SET max_parallel_workers_per_gather = 0;

WITH generation_detail AS MATERIALIZED (
    SELECT a.region_name, s.source_group, s.source_label,
           sum(f.generation_mw) AS signed_generation_mwh,
           count(*) AS generation_observations
    FROM project_dw.fact_hourly_generation f
    JOIN project_dw.dim_balancing_authority a USING (authority_key)
    JOIN project_dw.dim_energy_source s USING (energy_source_key)
    JOIN project_dw.dim_date d USING (date_key)
    WHERE d.calendar_year = 2025
    GROUP BY a.region_name, s.source_group, s.source_label
), rollup_result AS (
    SELECT region_name, source_group, source_label,
           grouping(region_name) AS region_is_total,
           grouping(source_group) AS source_group_is_total,
           grouping(source_label) AS source_label_is_total,
           sum(signed_generation_mwh) AS signed_generation_mwh,
           coalesce(sum(generation_observations), 0)::bigint AS generation_observations
    FROM generation_detail
    GROUP BY ROLLUP (region_name, source_group, source_label)
)
SELECT 2025 AS selected_year,
       CASE WHEN region_is_total = 1 THEN 'All regions' ELSE region_name END AS region_name,
       CASE WHEN source_group_is_total = 1 THEN 'All source groups' ELSE source_group END AS source_group,
       CASE WHEN source_label_is_total = 1 THEN 'All source labels' ELSE source_label END AS source_label,
       CASE
           WHEN region_is_total = 1 THEN 'Grand total'
           WHEN source_group_is_total = 1 THEN 'Region total'
           WHEN source_label_is_total = 1 THEN 'Source group subtotal'
           ELSE 'Source label detail'
       END AS aggregation_level,
       signed_generation_mwh, generation_observations,
       region_is_total, source_group_is_total, source_label_is_total
FROM rollup_result
ORDER BY region_is_total, region_name, source_group_is_total, source_group,
         source_label_is_total, source_label;
