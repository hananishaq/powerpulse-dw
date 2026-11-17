SELECT project_reporting.record_check('demand_orphan_or_null_keys','Integrity',0,COUNT(*),
 'All four references checked, including NULLs')
FROM project_dw.fact_hourly_demand f
LEFT JOIN project_dw.dim_balancing_authority a USING(authority_key)
LEFT JOIN project_dw.dim_date d USING(date_key)
LEFT JOIN project_dw.dim_hour h USING(hour_key)
LEFT JOIN project_dw.dim_source_snapshot s USING(source_snapshot_key)
WHERE a.authority_key IS NULL OR d.date_key IS NULL OR h.hour_key IS NULL OR s.source_snapshot_key IS NULL;
SELECT project_reporting.record_check('generation_orphan_or_null_keys','Integrity',0,COUNT(*),
 'All five references checked, including NULLs')
FROM project_dw.fact_hourly_generation f
LEFT JOIN project_dw.dim_balancing_authority a USING(authority_key)
LEFT JOIN project_dw.dim_date d USING(date_key)
LEFT JOIN project_dw.dim_hour h USING(hour_key)
LEFT JOIN project_dw.dim_energy_source e USING(energy_source_key)
LEFT JOIN project_dw.dim_source_snapshot s USING(source_snapshot_key)
WHERE a.authority_key IS NULL OR d.date_key IS NULL OR h.hour_key IS NULL
 OR e.energy_source_key IS NULL OR s.source_snapshot_key IS NULL;
SELECT project_reporting.record_check('duplicate_demand_grains','Integrity',0,COUNT(*),
 'Demand grain is authority + UTC hour') FROM (
 SELECT authority_key,utc_hour_end FROM project_dw.fact_hourly_demand
 GROUP BY authority_key,utc_hour_end HAVING COUNT(*)>1
) x;
SELECT project_reporting.record_check('duplicate_generation_grains','Integrity',0,COUNT(*),
 'Generation grain adds original fuel category') FROM (
 SELECT authority_key,utc_hour_end,energy_source_key FROM project_dw.fact_hourly_generation
 GROUP BY authority_key,utc_hour_end,energy_source_key HAVING COUNT(*)>1
) x;
SELECT project_reporting.record_check('unmatched_staging_dimensions','Integrity',0,COUNT(*),
 'Checks candidates before INNER JOINs can hide missing dimension matches')
FROM project_staging.stg_eia930_balance_clean c
LEFT JOIN project_dw.dim_balancing_authority a ON a.authority_code=c.authority_code
LEFT JOIN project_dw.dim_date d ON d.calendar_date=c.data_date
LEFT JOIN project_dw.dim_hour h ON h.hour_ending=EXTRACT(HOUR FROM c.local_hour_end)
LEFT JOIN project_dw.dim_source_snapshot s ON s.file_name=c.source_file AND s.sha256=c.source_sha256
WHERE a.authority_key IS NULL OR d.date_key IS NULL OR h.hour_key IS NULL OR s.source_snapshot_key IS NULL;
SELECT project_reporting.record_check('unmatched_fuel_mapping','Integrity',0,COUNT(*),
 'Exact original fuel header must resolve to a dimension member')
FROM project_staging.stg_energy_source_mapping m LEFT JOIN project_dw.dim_energy_source e
 ON e.source_column=m.source_column WHERE e.energy_source_key IS NULL;
SELECT project_reporting.record_check('dimension_source_hash_mismatches','Integrity',0,COUNT(*),
 'Every current manifest file/hash exists as an immutable source dimension member')
FROM project_staging.stg_source_file s LEFT JOIN project_dw.dim_source_snapshot d
 ON d.file_name=s.file_name AND d.sha256=s.sha256
WHERE d.source_snapshot_key IS NULL OR ROW(d.source_url,d.source_row_count,d.retrieved_at_utc)
 IS DISTINCT FROM ROW(s.source_url,s.source_row_count,s.retrieved_at_utc);

SELECT project_reporting.record_check('fuel_category_semantics','Integrity',0,COUNT(*),
 'Original headers, labels and roll-up meanings agree with the supplied reference CSV')
FROM dq_source_fuel_reference r FULL JOIN project_dw.dim_energy_source e USING(source_column)
WHERE r.source_column IS NULL OR e.source_column IS NULL
 OR ROW(r.source_label,r.source_group) IS DISTINCT FROM ROW(e.source_label,e.source_group);
SELECT project_reporting.record_check('authority_reference_attributes','Integrity',0,COUNT(*),
 'Current authority labels and region attributes agree with the supplied reference CSV')
FROM dq_source_authority_reference r FULL JOIN project_dw.dim_balancing_authority a USING(authority_code)
WHERE r.authority_code IS NULL OR a.authority_code IS NULL
 OR ROW(r.authority_name,r.region_code,r.region_name) IS DISTINCT FROM ROW(a.authority_name,a.region_code,a.region_name);
SELECT project_reporting.record_check('date_dimension_attributes','Integrity',0,COUNT(*),
 'Calendar and ISO attributes are deterministic functions of the operating date')
FROM project_dw.dim_date WHERE
 ROW(calendar_year,quarter_number,month_number,iso_week_year,iso_week_number,weekday_number,season)
 IS DISTINCT FROM ROW(EXTRACT(YEAR FROM calendar_date)::smallint,EXTRACT(QUARTER FROM calendar_date)::smallint,
 EXTRACT(MONTH FROM calendar_date)::smallint,EXTRACT(ISOYEAR FROM calendar_date)::smallint,
 EXTRACT(WEEK FROM calendar_date)::smallint,EXTRACT(ISODOW FROM calendar_date)::smallint,
 CASE WHEN EXTRACT(MONTH FROM calendar_date) IN (12,1,2) THEN 'Winter'
      WHEN EXTRACT(MONTH FROM calendar_date) IN (3,4,5) THEN 'Spring'
      WHEN EXTRACT(MONTH FROM calendar_date) IN (6,7,8) THEN 'Summer' ELSE 'Autumn' END);
SELECT project_reporting.record_check('hour_dimension_attributes','Integrity',0,COUNT(*),
 'Hour labels are zero-padded 00-23 source local hour-ending buckets')
FROM project_dw.dim_hour WHERE hour_ending NOT BETWEEN 0 AND 23 OR hour_label<>LPAD(hour_ending::text,2,'0');
