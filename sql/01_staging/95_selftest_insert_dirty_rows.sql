-- =====================================================================
-- PowerPulse | Phase 2 | Step 2 - Cleaning self-test, part 1 of 3
-- Owner: Qasim Tanveer
-- The real EIA data is already tidy (0 rows rejected), so this script proves the
-- cleaning rules WORK by adding 9 deliberately dirty rows to the RAW table.
-- Dirty rows are marked with subset_row_number = 0 and use source_row >= 900001 (or 1).
--
-- Order of use (LOCAL database only - never on a shared one):
--   1. run this file                        (adds the 9 dirty rows)
--   2. run 10_clean_staging.sql             (cleaning must catch them)
--   3. inspect  SELECT * FROM project_staging.stg_load_exception;
--   4. run 96_selftest_remove_dirty_rows.sql, then 10_clean_staging.sql again
--   (python etl/01_load_staging.py --self-test does all of this automatically)
--
-- Expected after step 2:  clean = 87,722 rows | rejected = 7 | cell values set to NULL = 1
-- =====================================================================

-- Make sure no earlier dirty rows are left over
DELETE FROM project_staging.stg_eia930_balance_raw WHERE subset_row_number = 0;

INSERT INTO project_staging.stg_eia930_balance_raw
    (source_file, source_row, subset_row_number, balancing_authority, region, data_date, hour_number,
     local_time_end, utc_time_end, demand_forecast_mw, demand_mw, net_generation_mw, gen_coal, gen_natural_gas)
VALUES
 -- D1 KEPT: dirty text ' pjm ' / 'mida ' is trimmed and upper-cased (rule C02) -> PJM / MIDA
 ('EIA930_BALANCE_2025_Jul_Dec.csv', '900001', 0, ' pjm ', 'mida ', '01/01/2040', '5',
  '01/01/2040 4:00:00 AM', '01/01/2040 9:00:00 AM', '1000', '1100', '1050', '10', '20'),
 -- D9 KEPT: non-numeric demand 'N/A' becomes NULL and is logged (rule C06); the row is kept
 ('EIA930_BALANCE_2025_Jul_Dec.csv', '900009', 0, 'CISO', 'CAL', '01/01/2041', '1',
  '01/01/2041 1:00:00 AM', '01/01/2041 9:00:00 AM', '500', 'N/A', '450', NULL, NULL);

INSERT INTO project_staging.stg_eia930_balance_raw
    (source_file, source_row, subset_row_number, balancing_authority, region, data_date, hour_number,
     local_time_end, utc_time_end, demand_mw)
SELECT r.source_file, '1', 0, r.balancing_authority, r.region, r.data_date, r.hour_number,
       r.local_time_end, r.utc_time_end, '1'
FROM project_staging.stg_eia930_balance_raw r
WHERE r.subset_row_number > 0
ORDER BY r.raw_row_id
LIMIT 1;    -- D2 REJECTED (C09): same authority + UTC hour as a real row -> duplicate

INSERT INTO project_staging.stg_eia930_balance_raw
    (source_file, source_row, subset_row_number, balancing_authority, region, data_date, hour_number,
     local_time_end, utc_time_end, demand_mw)
VALUES
 -- D3 REJECTED (C03): authority code is not in the reference table
 ('EIA930_BALANCE_2025_Jul_Dec.csv', '900003', 0, 'XXXX', 'CAL', '01/01/2042', '1', '01/01/2042 1:00:00 AM', '01/01/2042 9:00:00 AM', '1'),
 -- D4 REJECTED (C04): impossible date
 ('EIA930_BALANCE_2025_Jul_Dec.csv', '900004', 0, 'CISO', 'CAL', '13/45/2043', '1', '01/01/2043 1:00:00 AM', '01/01/2043 9:00:00 AM', '1'),
 -- D5 REJECTED (C05): Hour Number 26 is outside 1..25
 ('EIA930_BALANCE_2025_Jul_Dec.csv', '900005', 0, 'CISO', 'CAL', '01/01/2044', '26', '01/01/2044 1:00:00 AM', '01/01/2044 9:00:00 AM', '1'),
 -- D6 REJECTED (C03): region TEX does not belong to CISO (reference says CAL)
 ('EIA930_BALANCE_2025_Jul_Dec.csv', '900006', 0, 'CISO', 'TEX', '01/01/2045', '1', '01/01/2045 1:00:00 AM', '01/01/2045 9:00:00 AM', '1'),
 -- D7 REJECTED (C05): local label equals UTC label -> offset 0, not a valid U.S. offset
 ('EIA930_BALANCE_2025_Jul_Dec.csv', '900007', 0, 'CISO', 'CAL', '01/01/2046', '1', '01/01/2046 9:00:00 AM', '01/01/2046 9:00:00 AM', '1'),
 -- D8 REJECTED (C01): source file is not in the manifest
 ('NOT_IN_MANIFEST.csv',            '900008', 0, 'CISO', 'CAL', '01/01/2047', '1', '01/01/2047 1:00:00 AM', '01/01/2047 9:00:00 AM', '1');

SELECT COUNT(*) AS dirty_rows_added FROM project_staging.stg_eia930_balance_raw WHERE subset_row_number = 0;
