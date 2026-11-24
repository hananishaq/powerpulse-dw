-- Q07: original labels and signed generation.
SELECT * FROM project_reporting.vw_q07_generation_by_source
ORDER BY authority_code, month_start, source_group, source_label;

-- Q08: publication details and exclusion counts per authority-month.
SELECT * FROM project_reporting.vw_q08_wind_solar_share
ORDER BY authority_code, month_start, source_snapshot_key;

-- Rollup uses summed, matched components and retains the cohort denominator.
SELECT authority_code, sum(matched_hours) AS matched_hours,
       sum(excluded_hours) AS excluded_hours,
       100.0 * sum(matched_wind_mwh + matched_solar_mwh)
             / nullif(sum(matched_reported_mwh), 0) AS wind_solar_share_pct
FROM project_reporting.vw_q08_wind_solar_share
GROUP BY authority_code ORDER BY authority_code;
