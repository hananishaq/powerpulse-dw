CREATE OR REPLACE VIEW project_reporting.vw_demand_detail AS
SELECT f.*, a.authority_code, a.authority_name, a.region_code,
       d.calendar_date, d.calendar_year, d.month_number, d.season,
       d.weekday_number, h.hour_ending, ss.file_name, ss.sha256
FROM project_dw.fact_hourly_demand f
JOIN project_dw.dim_balancing_authority a USING (authority_key)
JOIN project_dw.dim_date d USING (date_key)
JOIN project_dw.dim_hour h USING (hour_key)
JOIN project_dw.dim_source_snapshot ss USING (source_snapshot_key);

CREATE OR REPLACE VIEW project_reporting.vw_generation_detail AS
SELECT f.*, a.authority_code, d.calendar_date, d.calendar_year,
       d.month_number, h.hour_ending, e.source_column, e.source_group,
       e.source_label, ss.file_name, ss.sha256
FROM project_dw.fact_hourly_generation f
JOIN project_dw.dim_balancing_authority a USING (authority_key)
JOIN project_dw.dim_date d USING (date_key)
JOIN project_dw.dim_hour h USING (hour_key)
JOIN project_dw.dim_energy_source e USING (energy_source_key)
JOIN project_dw.dim_source_snapshot ss USING (source_snapshot_key);

CREATE OR REPLACE VIEW project_reporting.vw_generation_hourly AS
SELECT authority_key, utc_hour_end,
       SUM(generation_mw) AS available_fuel_mw,
       COUNT(*) AS reported_fuel_observations,
       SUM(generation_mw) FILTER (WHERE source_group = 'Wind') AS wind_mw,
       SUM(generation_mw) FILTER (WHERE source_group = 'Solar') AS solar_mw,
       COUNT(*) FILTER (WHERE source_group = 'Wind') AS wind_observations,
       COUNT(*) FILTER (WHERE source_group = 'Solar') AS solar_observations,
       COUNT(*) FILTER (WHERE generation_mw < 0) AS negative_fuel_observations,
       STRING_AGG(DISTINCT source_column, '; ' ORDER BY source_column) AS fuel_category_versions
FROM project_reporting.vw_generation_detail
GROUP BY authority_key, utc_hour_end;

CREATE OR REPLACE VIEW project_reporting.vw_hourly_comparison AS
SELECT d.*, g.available_fuel_mw, g.reported_fuel_observations,
       g.wind_mw, g.solar_mw, g.wind_observations, g.solar_observations,
       g.negative_fuel_observations, g.fuel_category_versions,
       g.available_fuel_mw - d.total_generation_mw AS residual_mw,
       (d.total_generation_mw IS NOT NULL AND g.reported_fuel_observations > 0)
           AS reconciliation_comparable,
       CASE WHEN d.total_generation_mw IS NOT NULL AND g.reported_fuel_observations > 0
            THEN ABS(g.available_fuel_mw - d.total_generation_mw)
                 > GREATEST(10::numeric, 0.01 * ABS(d.total_generation_mw))
       END AS reconciliation_flagged
FROM project_reporting.vw_demand_detail d
LEFT JOIN project_reporting.vw_generation_hourly g USING (authority_key, utc_hour_end);

CREATE OR REPLACE VIEW project_reporting.vw_expected_hours AS
SELECT c.authority_code, t.utc_hour_end,
       ((t.utc_hour_end AT TIME ZONE c.time_zone) - INTERVAL '1 second')::date
           AS operating_date
FROM project_reporting.dq_expected_coverage c
CROSS JOIN LATERAL generate_series(c.first_utc,c.last_utc,INTERVAL '1 hour') t(utc_hour_end);
