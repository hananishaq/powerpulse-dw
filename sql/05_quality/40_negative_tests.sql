-- Session-local scratch copies have no constraints so the detector, not an insert
-- rejection, is tested. All temporary objects are dropped before returning.
CREATE TEMP TABLE dq_test_demand AS SELECT * FROM project_dw.fact_hourly_demand LIMIT 1;
INSERT INTO dq_test_demand SELECT * FROM dq_test_demand;
SELECT project_reporting.record_check('negative_duplicate_detector','Negative test',1,COUNT(*),
 'Detector found the injected duplicate grain; zero would mean the detector failed')
FROM (SELECT authority_key,utc_hour_end FROM dq_test_demand
      GROUP BY authority_key,utc_hour_end HAVING COUNT(*)>1) x;
UPDATE dq_test_demand SET authority_key=-1;
SELECT project_reporting.record_check('negative_orphan_detector','Negative test',2,COUNT(*),
 'Detector found both scratch rows with an unknown authority')
FROM dq_test_demand f LEFT JOIN project_dw.dim_balancing_authority a USING(authority_key)
WHERE a.authority_key IS NULL;
DROP TABLE dq_test_demand;

CREATE TEMP TABLE dq_test_coverage AS SELECT * FROM project_reporting.vw_expected_hours;
DELETE FROM dq_test_coverage WHERE authority_code='CISO';
SELECT project_reporting.record_check('negative_missing_authority_detector','Negative test',17544,COUNT(*),
 'Independent expected coverage catches an entirely absent authority')
FROM project_reporting.vw_expected_hours e LEFT JOIN dq_test_coverage t USING(authority_code,utc_hour_end)
WHERE t.authority_code IS NULL;
DROP TABLE dq_test_coverage;

CREATE TEMP TABLE dq_test_boundary AS SELECT * FROM project_reporting.vw_expected_hours;
DELETE FROM dq_test_boundary WHERE authority_code='CISO'
 AND utc_hour_end=(SELECT MIN(utc_hour_end) FROM dq_test_boundary WHERE authority_code='CISO');
SELECT project_reporting.record_check('negative_boundary_hour_detector','Negative test',1,COUNT(*),
 'Independent expected coverage catches a missing first hour')
FROM project_reporting.vw_expected_hours e LEFT JOIN dq_test_boundary t USING(authority_code,utc_hour_end)
WHERE t.authority_code IS NULL;
DROP TABLE dq_test_boundary;

-- A realistic mixed-grain join multiplies demand even when all FKs are valid.
WITH sample AS (SELECT authority_key,utc_hour_end,actual_demand_mw
 FROM project_dw.fact_hourly_demand WHERE actual_demand_mw>0 ORDER BY demand_key LIMIT 1),
 joined AS (SELECT d.* FROM sample d CROSS JOIN generate_series(1,2))
SELECT project_reporting.record_check('negative_fanout_detector','Negative test',1,
 CASE WHEN (SELECT SUM(actual_demand_mw) FROM joined) > (SELECT SUM(actual_demand_mw) FROM sample)
 THEN 1 ELSE 0 END,'Unsafe detail join changes demand totals; safe-join accuracy checks must detect it');
