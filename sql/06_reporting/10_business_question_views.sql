-- M01: each observation covers one hour. Nonnegative numeric actuals qualify.
CREATE OR REPLACE VIEW project_reporting.vw_q01_monthly_demand_energy AS
SELECT authority_code, calendar_year, month_number,
       SUM(actual_demand_mw) FILTER (WHERE actual_demand_mw >= 0) AS demand_energy_mwh,
       COUNT(*) FILTER (WHERE actual_demand_mw >= 0) AS eligible_hours,
       COUNT(*) FILTER (WHERE actual_demand_mw IS NULL) AS missing_measure_hours,
       COUNT(*) AS present_hours,
       STRING_AGG(DISTINCT file_name || '@' || LEFT(sha256,12), ', ') AS source_versions
FROM project_reporting.vw_demand_detail
GROUP BY authority_code, calendar_year, month_number;

CREATE OR REPLACE VIEW project_reporting.vw_q02_local_hour_demand AS
SELECT authority_code, hour_ending,
       AVG(actual_demand_mw) FILTER (WHERE actual_demand_mw >= 0) AS mean_demand_mw,
       COUNT(*) FILTER (WHERE actual_demand_mw >= 0) AS eligible_observations,
       COUNT(*) FILTER (WHERE actual_demand_mw IS NULL) AS missing_observations,
       STRING_AGG(DISTINCT file_name || '@' || LEFT(sha256,12), ', ') AS source_versions
FROM project_reporting.vw_demand_detail GROUP BY authority_code,hour_ending;

CREATE OR REPLACE VIEW project_reporting.vw_q03_monthly_peak_demand AS
WITH ranked AS (
 SELECT *, MAX(actual_demand_mw) OVER (PARTITION BY authority_code,calendar_year,month_number) AS peak_mw,
   COUNT(*) OVER (PARTITION BY authority_code,calendar_year,month_number) AS eligible_hours
 FROM project_reporting.vw_demand_detail WHERE actual_demand_mw >= 0
)
SELECT authority_code,calendar_year,month_number,peak_mw,eligible_hours,
       utc_hour_end,local_hour_end,utc_offset_minutes,file_name,sha256,source_row_number
FROM ranked WHERE actual_demand_mw = peak_mw;

CREATE OR REPLACE VIEW project_reporting.vw_q04_seasonal_day_type AS
SELECT authority_code,calendar_year,season,
       CASE WHEN weekday_number IN (6,7) THEN 'Weekend' ELSE 'Weekday' END AS day_type,
       AVG(actual_demand_mw) FILTER (WHERE actual_demand_mw >= 0) AS mean_demand_mw,
       COUNT(*) FILTER (WHERE actual_demand_mw >= 0) AS eligible_hours,
       COUNT(*) FILTER (WHERE actual_demand_mw IS NULL) AS missing_hours,
       STRING_AGG(DISTINCT file_name || '@' || LEFT(sha256,12), ', ') AS source_versions
FROM project_reporting.vw_demand_detail GROUP BY authority_code,calendar_year,season,day_type;

-- M04-M07: one eligibility set. Error = actual minus forecast.
CREATE OR REPLACE VIEW project_reporting.vw_forecast_pairs AS
SELECT *, actual_demand_mw - forecast_demand_mw AS error_mw,
       (actual_demand_mw > 0 AND forecast_demand_mw >= 0) IS TRUE AS eligible
FROM project_reporting.vw_demand_detail;

CREATE OR REPLACE VIEW project_reporting.vw_q05_monthly_forecast_accuracy AS
SELECT authority_code,calendar_year,month_number,
       COUNT(*) FILTER (WHERE eligible) AS eligible_pairs,
       COUNT(*) FILTER (WHERE NOT eligible) AS excluded_pairs,
       AVG(error_mw) FILTER (WHERE eligible) AS bias_mw,
       AVG(ABS(error_mw)) FILTER (WHERE eligible) AS mae_mw,
       100 * SUM(ABS(error_mw)) FILTER (WHERE eligible)
         / NULLIF(SUM(actual_demand_mw) FILTER (WHERE eligible),0) AS wape_pct,
       SUM(ABS(error_mw)) FILTER (WHERE eligible) AS absolute_error_sum_mw,
       SUM(actual_demand_mw) FILTER (WHERE eligible) AS actual_sum_mw,
       STRING_AGG(DISTINCT file_name || '@' || LEFT(sha256,12), ', ') AS source_versions
FROM project_reporting.vw_forecast_pairs GROUP BY authority_code,calendar_year,month_number;

CREATE OR REPLACE VIEW project_reporting.vw_q06_underforecast_patterns AS
SELECT authority_code,calendar_year,season,hour_ending,
       COUNT(*) FILTER (WHERE eligible) AS eligible_pairs,
       COUNT(*) FILTER (WHERE NOT eligible) AS excluded_pairs,
       AVG(error_mw) FILTER (WHERE eligible) AS bias_mw,
       100.0 * COUNT(*) FILTER (WHERE eligible AND error_mw > 0)
          / NULLIF(COUNT(*) FILTER (WHERE eligible),0) AS underforecast_pct,
       STRING_AGG(DISTINCT file_name || '@' || LEFT(sha256,12), ', ') AS source_versions
FROM project_reporting.vw_forecast_pairs GROUP BY authority_code,calendar_year,season,hour_ending;

-- Include all-null categories explicitly; NULL energy means no reported observations.
CREATE OR REPLACE VIEW project_reporting.vw_q07_monthly_generation_by_fuel AS
WITH periods AS (
 SELECT DISTINCT authority_key,authority_code,calendar_year,month_number
 FROM project_reporting.vw_demand_detail
)
SELECT p.authority_code,p.calendar_year,p.month_number,e.source_column,e.source_group,
       SUM(g.generation_mw) AS generation_energy_mwh,
       COUNT(g.generation_key) AS reported_observations,
       COUNT(g.generation_key) FILTER (WHERE g.generation_mw < 0) AS negative_observations,
       STRING_AGG(DISTINCT g.file_name || '@' || LEFT(g.sha256,12), ', ') AS source_versions
FROM periods p CROSS JOIN project_dw.dim_energy_source e
LEFT JOIN project_reporting.vw_generation_detail g
 ON g.authority_key=p.authority_key AND g.calendar_year=p.calendar_year
 AND g.month_number=p.month_number AND g.energy_source_key=e.energy_source_key
GROUP BY p.authority_code,p.calendar_year,p.month_number,e.source_column,e.source_group;

CREATE OR REPLACE VIEW project_reporting.vw_q08_wind_solar_share AS
WITH classified AS (
 SELECT *, (wind_observations > 0 AND solar_observations > 0
            AND total_generation_mw > 0 AND reconciliation_flagged IS FALSE) IS TRUE AS eligible
 FROM project_reporting.vw_hourly_comparison
)
SELECT authority_code,calendar_year,month_number,
       COUNT(*) FILTER (WHERE eligible) AS eligible_hours,
       COUNT(*) FILTER (WHERE NOT eligible) AS excluded_hours,
       SUM(wind_mw + solar_mw) FILTER (WHERE eligible) AS wind_solar_energy_mwh,
       SUM(total_generation_mw) FILTER (WHERE eligible) AS matched_total_energy_mwh,
       100 * SUM(wind_mw + solar_mw) FILTER (WHERE eligible)
          / NULLIF(SUM(total_generation_mw) FILTER (WHERE eligible),0) AS wind_solar_share_pct,
       STRING_AGG(DISTINCT fuel_category_versions, ' | ') AS fuel_category_versions,
       STRING_AGG(DISTINCT file_name || '@' || LEFT(sha256,12), ', ') AS source_versions
FROM classified GROUP BY authority_code,calendar_year,month_number;

CREATE OR REPLACE VIEW project_reporting.vw_q09_high_demand_source_mix AS
WITH generation_groups AS (
 SELECT authority_key,utc_hour_end,source_group,SUM(generation_mw) AS energy_mwh,
        COUNT(*) AS observations,
        STRING_AGG(DISTINCT file_name || '@' || LEFT(sha256,12), ', ') AS versions
 FROM project_reporting.vw_generation_detail GROUP BY authority_key,utc_hour_end,source_group
), generation_hours AS MATERIALIZED (
 SELECT authority_key,utc_hour_end,
        jsonb_object_agg(source_group,jsonb_build_object('energy',energy_mwh,
                        'observations',observations,'versions',versions)) AS groups
 FROM generation_groups GROUP BY authority_key,utc_hour_end
), thresholds AS MATERIALIZED (
 SELECT authority_key,calendar_year,month_number,
   percentile_cont(0.9) WITHIN GROUP (ORDER BY actual_demand_mw) AS p90_mw
 FROM project_reporting.vw_demand_detail WHERE actual_demand_mw > 0
 GROUP BY authority_key,calendar_year,month_number
), classified AS (
 SELECT d.*, g.groups,t.p90_mw,CASE WHEN d.actual_demand_mw >= t.p90_mw THEN 'High demand' ELSE 'Other eligible' END AS demand_band
 FROM project_reporting.vw_demand_detail d JOIN thresholds t USING(authority_key,calendar_year,month_number)
 LEFT JOIN generation_hours g USING(authority_key,utc_hour_end)
 WHERE d.actual_demand_mw > 0
), bands AS (
 SELECT authority_code,calendar_year,month_number,demand_band,MAX(p90_mw) AS p90_mw,
        COUNT(*) AS eligible_demand_hours
 FROM classified GROUP BY authority_code,calendar_year,month_number,demand_band
), energy AS (
 SELECT d.authority_code,d.calendar_year,d.month_number,d.demand_band,g.key AS source_group,
        SUM((g.value->>'energy')::numeric) AS generation_energy_mwh,
        SUM((g.value->>'observations')::bigint) AS reported_fuel_observations,
        COUNT(DISTINCT d.utc_hour_end) AS observed_fuel_hours,
        STRING_AGG(DISTINCT g.value->>'versions', ', ') AS source_versions
 FROM classified d CROSS JOIN LATERAL jsonb_each(d.groups) g
 GROUP BY d.authority_code,d.calendar_year,d.month_number,d.demand_band,g.key
)
SELECT b.*,e.source_group,e.generation_energy_mwh,e.reported_fuel_observations,
       e.observed_fuel_hours,e.source_versions
FROM bands b LEFT JOIN energy e USING(authority_code,calendar_year,month_number,demand_band);

CREATE OR REPLACE VIEW project_reporting.vw_q10_monthly_source_quality AS
WITH invalid_cells AS (
 SELECT c.authority_code,c.utc_hour_end,COUNT(*) AS n
 FROM project_staging.stg_load_exception e
 JOIN project_staging.stg_eia930_balance_clean c
  ON c.source_file=e.source_file AND c.source_row::text=e.source_row
 WHERE e.action_taken='VALUE_SET_NULL'
 GROUP BY c.authority_code,c.utc_hour_end
)
SELECT x.authority_code,EXTRACT(YEAR FROM x.operating_date)::int AS calendar_year,
       EXTRACT(MONTH FROM x.operating_date)::int AS month_number,
       COUNT(*) AS expected_hours,COUNT(d.demand_key) AS present_hours,
       COUNT(*) FILTER (WHERE d.demand_key IS NULL) AS absent_hours,
       COUNT(*) FILTER (WHERE d.demand_key IS NOT NULL AND d.actual_demand_mw IS NULL) AS null_actual_hours,
       COUNT(*) FILTER (WHERE d.demand_key IS NOT NULL AND d.forecast_demand_mw IS NULL) AS null_forecast_hours,
       COUNT(*) FILTER (WHERE d.demand_key IS NOT NULL AND d.total_generation_mw IS NULL) AS null_generation_hours,
       100.0 * COUNT(*) FILTER (WHERE d.demand_key IS NULL OR d.actual_demand_mw IS NULL)
          / NULLIF(COUNT(*),0) AS missing_actual_pct,
       COUNT(*) FILTER (WHERE d.actual_demand_mw = 0) AS zero_actual_hours,
       COUNT(*) FILTER (WHERE d.actual_demand_mw < 0) AS negative_actual_hours,
       COUNT(*) FILTER (WHERE d.forecast_demand_mw < 0) AS negative_forecast_hours,
       COUNT(*) FILTER (WHERE d.reconciliation_comparable) AS comparable_hours,
       COUNT(*) FILTER (WHERE d.reconciliation_flagged) AS reconciliation_flags,
       SUM(d.negative_fuel_observations) AS negative_fuel_observations,
       STRING_AGG(DISTINCT d.file_name || '@' || LEFT(d.sha256,12), ', ') AS source_versions,
       SUM(COALESCE(i.n,0)) AS invalid_numeric_cells
FROM project_reporting.vw_expected_hours x
LEFT JOIN project_reporting.vw_hourly_comparison d
 ON d.authority_code=x.authority_code AND d.utc_hour_end=x.utc_hour_end
LEFT JOIN invalid_cells i ON i.authority_code=x.authority_code AND i.utc_hour_end=x.utc_hour_end
GROUP BY x.authority_code,EXTRACT(YEAR FROM x.operating_date),EXTRACT(MONTH FROM x.operating_date);

COMMENT ON VIEW project_reporting.vw_q09_high_demand_source_mix IS
'Generation energy by fuel group in demand sets; no demand measure is summed after the fuel join. Signed observed energy, not an unqualified percentage share.';
