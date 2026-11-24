-- Frozen source-header register from data_acquisition/data/source_manifest.json.
-- Grain: one known publication SHA-256. New versions require a manifest update.
CREATE OR REPLACE VIEW project_reporting.vw_generation_source_headers AS
SELECT sha256, fuel_headers FROM (VALUES
    ('26768c495c3ba987e29d79df2e40d4e741f9dbcff086f53c12ff774465756a10', ARRAY['Net Generation (MW) from Coal', 'Net Generation (MW) from Natural Gas', 'Net Generation (MW) from Nuclear', 'Net Generation (MW) from All Petroleum Products', 'Net Generation (MW) from Hydropower and Pumped Storage', 'Net Generation (MW) from Solar', 'Net Generation (MW) from Wind', 'Net Generation (MW) from Other Fuel Sources', 'Net Generation (MW) from Unknown Fuel Sources']),
    ('a602a8e577cfdd2fa3083413eaa4dd8ba7f0d2b26a2986f8f6d22917465ea49f', ARRAY['Net Generation (MW) from Coal', 'Net Generation (MW) from Natural Gas', 'Net Generation (MW) from Nuclear', 'Net Generation (MW) from All Petroleum Products', 'Net Generation (MW) from Hydropower Excluding Pumped Storage', 'Net Generation (MW) from Pumped Storage', 'Net Generation (MW) from Solar without Integrated Battery Storage', 'Net Generation (MW) from Solar with Integrated Battery Storage', 'Net Generation (MW) from Wind without Integrated Battery Storage', 'Net Generation (MW) from Wind with Integrated Battery Storage', 'Net Generation (MW) from Battery Storage', 'Net Generation (MW) from Other Energy Storage', 'Net Generation (MW) from Unknown Energy Storage', 'Net Generation (MW) from Geothermal', 'Net Generation (MW) from Other Fuel Sources', 'Net Generation (MW) from Unknown Fuel Sources']),
    ('fac4bb991dfa1dab3b4b35300ccab54ac99be13a40ce91954db8ddafb2816242', ARRAY['Net Generation (MW) from Coal', 'Net Generation (MW) from Natural Gas', 'Net Generation (MW) from Nuclear', 'Net Generation (MW) from All Petroleum Products', 'Net Generation (MW) from Hydropower Excluding Pumped Storage', 'Net Generation (MW) from Pumped Storage', 'Net Generation (MW) from Solar without Integrated Battery Storage', 'Net Generation (MW) from Solar with Integrated Battery Storage', 'Net Generation (MW) from Wind without Integrated Battery Storage', 'Net Generation (MW) from Wind with Integrated Battery Storage', 'Net Generation (MW) from Battery Storage', 'Net Generation (MW) from Other Energy Storage', 'Net Generation (MW) from Unknown Energy Storage', 'Net Generation (MW) from Geothermal', 'Net Generation (MW) from Other Fuel Sources', 'Net Generation (MW) from Unknown Fuel Sources']),
    ('1146158b972439db7c7f4cc7d0491e07644ddbf244d03b8ecb44cb2c833d10f1', ARRAY['Net Generation (MW) from Coal', 'Net Generation (MW) from Natural Gas', 'Net Generation (MW) from Nuclear', 'Net Generation (MW) from All Petroleum Products', 'Net Generation (MW) from Hydropower Excluding Pumped Storage', 'Net Generation (MW) from Pumped Storage', 'Net Generation (MW) from Solar without Integrated Battery Storage', 'Net Generation (MW) from Solar with Integrated Battery Storage', 'Net Generation (MW) from Wind without Integrated Battery Storage', 'Net Generation (MW) from Wind with Integrated Battery Storage', 'Net Generation (MW) from Battery Storage', 'Net Generation (MW) from Other Energy Storage', 'Net Generation (MW) from Unknown Energy Storage', 'Net Generation (MW) from Geothermal', 'Net Generation (MW) from Other Fuel Sources', 'Net Generation (MW) from Unknown Fuel Sources'])
) AS manifest(sha256, fuel_headers);

-- Grain: one generation-bearing authority and UTC hour. The hour is the
-- operand for reconciliation and preserves each component's signed net power.
CREATE OR REPLACE VIEW project_reporting.vw_generation_authority_hour AS
SELECT g.authority_key, g.utc_hour_end, min(g.date_key) AS date_key,
       sum(g.generation_mw) AS available_fuel_mw, count(*) AS observed_fuel_count,
       sum(g.generation_mw) FILTER (WHERE e.source_group = 'Wind') AS wind_mw,
       sum(g.generation_mw) FILTER (WHERE e.source_group = 'Solar') AS solar_mw,
       count(*) FILTER (WHERE e.source_group = 'Wind') AS observed_wind_count,
       count(*) FILTER (WHERE e.source_group = 'Solar') AS observed_solar_count,
       array_agg(DISTINCT e.source_label ORDER BY e.source_label)
           FILTER (WHERE e.source_group = 'Wind') AS observed_wind_labels,
       array_agg(DISTINCT e.source_label ORDER BY e.source_label)
           FILTER (WHERE e.source_group = 'Solar') AS observed_solar_labels,
       array_agg(DISTINCT g.source_snapshot_key ORDER BY g.source_snapshot_key)
           AS generation_snapshot_keys,
       array_agg(DISTINCT s.sha256 ORDER BY s.sha256) AS generation_source_hashes,
       array_agg(DISTINCT g.source_row_number ORDER BY g.source_row_number)
           AS generation_source_rows
FROM project_dw.fact_hourly_generation g
JOIN project_dw.dim_energy_source e USING (energy_source_key)
JOIN project_dw.dim_source_snapshot s USING (source_snapshot_key)
GROUP BY g.authority_key, g.utc_hour_end;

-- Grain: authority and demand UTC hour. The demand left join retains every
-- source observation. Missing fuel and missing totals produce no residual.
CREATE OR REPLACE VIEW project_reporting.vw_generation_reconciliation_hour AS
WITH versions AS MATERIALIZED (
    SELECT s.source_snapshot_key, s.file_name, s.sha256,
           array_agg(e.source_label ORDER BY e.source_label)
               FILTER (WHERE e.source_group = 'Wind') AS applicable_wind_labels,
           array_agg(e.source_label ORDER BY e.source_label)
               FILTER (WHERE e.source_group = 'Solar') AS applicable_solar_labels,
           h.sha256 IS NOT NULL AS known_headers
    FROM project_dw.dim_source_snapshot s
    LEFT JOIN project_reporting.vw_generation_source_headers h ON h.sha256 = s.sha256
    LEFT JOIN project_dw.dim_energy_source e ON e.source_column = ANY(h.fuel_headers)
    GROUP BY s.source_snapshot_key, s.file_name, s.sha256, h.sha256
)
SELECT d.authority_key, d.authority_code, d.month_start, d.utc_hour_end,
       d.source_snapshot_key, d.source_row_number, v.file_name, v.sha256,
       d.total_generation_mw, g.available_fuel_mw, g.observed_fuel_count,
       g.wind_mw, g.solar_mw, g.observed_wind_count, g.observed_solar_count,
       g.observed_wind_labels, g.observed_solar_labels, g.generation_snapshot_keys,
       g.generation_source_hashes, g.generation_source_rows,
       g.available_fuel_mw - d.total_generation_mw AS residual_mw,
       CASE WHEN d.total_generation_mw IS NOT NULL
            THEN greatest(10, 0.01 * abs(d.total_generation_mw)) END AS tolerance_mw,
       v.applicable_wind_labels, v.applicable_solar_labels,
       v.known_headers, d.actual_demand_mw, d.forecast_demand_mw
FROM project_reporting.vw_demand_observation d
JOIN versions v USING (source_snapshot_key)
LEFT JOIN project_reporting.vw_generation_authority_hour g
    ON g.authority_key = d.authority_key AND g.utc_hour_end = d.utc_hour_end;

-- Grain: authority, operating month, original fuel category.
-- All categories are represented for every authority-month with source rows.
CREATE OR REPLACE VIEW project_reporting.vw_q07_generation_by_source AS
WITH periods AS (
    SELECT authority_key, month_start, source_snapshot_key, count(*) AS source_hours
    FROM project_reporting.vw_demand_observation
    GROUP BY authority_key, month_start, source_snapshot_key
), headers AS (
    SELECT p.authority_key, p.month_start, e.energy_source_key,
           sum(p.source_hours) FILTER (WHERE e.source_column = ANY(h.fuel_headers))::bigint
               AS applicable_hours,
           sum(p.source_hours) FILTER (WHERE NOT (e.source_column = ANY(h.fuel_headers)))::bigint
               AS absent_header_hours,
           sum(p.source_hours) FILTER (WHERE h.sha256 IS NULL)::bigint AS unknown_header_hours
    FROM periods p
    JOIN project_dw.dim_source_snapshot s USING (source_snapshot_key)
    LEFT JOIN project_reporting.vw_generation_source_headers h ON h.sha256 = s.sha256
    CROSS JOIN project_dw.dim_energy_source e
    GROUP BY p.authority_key, p.month_start, e.energy_source_key
), totals AS (
    SELECT f.authority_key, date_trunc('month', d.calendar_date)::date AS month_start,
           f.energy_source_key, sum(f.generation_mw) AS signed_generation_mwh,
           count(*) AS numeric_observations,
           count(*) FILTER (WHERE f.generation_mw = 0) AS observed_zero_hours,
           count(*) FILTER (WHERE f.generation_mw < 0) AS observed_negative_hours,
           count(*) FILTER (WHERE e.source_column = ANY(h.fuel_headers))
               AS numeric_known_applicable_hours
    FROM project_dw.fact_hourly_generation f
    JOIN project_dw.dim_date d USING (date_key)
    JOIN project_dw.dim_energy_source e USING (energy_source_key)
    JOIN project_dw.dim_source_snapshot s USING (source_snapshot_key)
    LEFT JOIN project_reporting.vw_generation_source_headers h ON h.sha256 = s.sha256
    GROUP BY f.authority_key, date_trunc('month', d.calendar_date)::date, f.energy_source_key
)
SELECT authority_key, a.authority_code, month_start, energy_source_key,
       e.source_label, e.source_group, t.signed_generation_mwh,
       coalesce(t.numeric_observations, 0) AS numeric_observations,
       coalesce(t.observed_zero_hours, 0) AS observed_zero_hours,
       coalesce(t.observed_negative_hours, 0) AS observed_negative_hours,
       coalesce(h.applicable_hours, 0) AS applicable_hours,
       coalesce(h.applicable_hours, 0) - coalesce(t.numeric_known_applicable_hours, 0)
           AS supplied_blank_hours,
       coalesce(h.absent_header_hours, 0) AS absent_header_hours,
       coalesce(h.unknown_header_hours, 0) AS unknown_header_hours
FROM headers h
FULL JOIN totals t USING (authority_key, month_start, energy_source_key)
JOIN project_dw.dim_balancing_authority a USING (authority_key)
JOIN project_dw.dim_energy_source e USING (energy_source_key);

CREATE OR REPLACE VIEW project_reporting.vw_product_performance AS
SELECT * FROM project_reporting.vw_q07_generation_by_source;
COMMENT ON VIEW project_reporting.vw_product_performance IS
    'Rubric product performance uses reported electricity generation by original energy source.';

-- Grain: authority, operating month and source publication. The source hash
-- and applicable category labels preserve the change in EIA source definitions.
CREATE OR REPLACE VIEW project_reporting.vw_q08_wind_solar_share AS
WITH classified AS (
    SELECT *,
           CASE WHEN NOT known_headers THEN 'Unknown headers'
                WHEN generation_snapshot_keys IS NOT NULL
                     AND generation_snapshot_keys <> ARRAY[source_snapshot_key]
                     THEN 'Mixed publication'
                WHEN (observed_wind_labels <@ coalesce(applicable_wind_labels, ARRAY[]::text[])) IS FALSE
                     OR (observed_solar_labels <@ coalesce(applicable_solar_labels, ARRAY[]::text[])) IS FALSE
                     THEN 'Mixed publication'
                WHEN coalesce(observed_wind_count, 0) = 0 THEN 'Missing wind'
                WHEN coalesce(observed_solar_count, 0) = 0 THEN 'Missing solar'
                WHEN total_generation_mw IS NULL THEN 'Missing reported total'
                WHEN total_generation_mw <= 0 THEN 'Nonpositive reported total'
                WHEN abs(residual_mw) > tolerance_mw THEN 'Residual above tolerance'
                ELSE 'Matched' END AS cohort
    FROM project_reporting.vw_generation_reconciliation_hour
), totals AS (
    SELECT authority_key, authority_code, month_start, source_snapshot_key,
           file_name, sha256, applicable_wind_labels, applicable_solar_labels,
           count(*) AS source_hours,
           count(*) FILTER (WHERE cohort = 'Matched') AS matched_hours,
           count(*) FILTER (WHERE cohort <> 'Matched') AS excluded_hours,
           count(*) FILTER (WHERE cohort = 'Missing wind') AS missing_wind_hours,
           count(*) FILTER (WHERE cohort = 'Missing solar') AS missing_solar_hours,
           count(*) FILTER (WHERE cohort = 'Missing reported total') AS missing_total_hours,
           count(*) FILTER (WHERE cohort = 'Nonpositive reported total') AS nonpositive_total_hours,
           count(*) FILTER (WHERE cohort = 'Residual above tolerance') AS residual_failure_hours,
           count(*) FILTER (WHERE cohort IN ('Unknown headers', 'Mixed publication'))
               AS unverified_publication_hours,
           sum(observed_wind_count) FILTER (WHERE cohort = 'Matched') AS observed_wind_components,
           sum(observed_solar_count) FILTER (WHERE cohort = 'Matched') AS observed_solar_components,
           sum(wind_mw) FILTER (WHERE cohort = 'Matched') AS matched_wind_mwh,
           sum(solar_mw) FILTER (WHERE cohort = 'Matched') AS matched_solar_mwh,
           sum(total_generation_mw) FILTER (WHERE cohort = 'Matched') AS matched_reported_mwh
    FROM classified
    GROUP BY authority_key, authority_code, month_start, source_snapshot_key,
             file_name, sha256, applicable_wind_labels, applicable_solar_labels
)
SELECT totals.*, 100.0 * (matched_wind_mwh + matched_solar_mwh)
       / nullif(matched_reported_mwh, 0) AS wind_solar_share_pct
FROM totals;
