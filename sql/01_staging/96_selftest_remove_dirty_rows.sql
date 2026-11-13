-- =====================================================================
-- PowerPulse | Phase 2 | Step 2 - Cleaning self-test, part 3 of 3
-- Owner: Qasim Tanveer
-- Removes the 9 dirty rows added by 95_selftest_insert_dirty_rows.sql.
-- Afterwards run 10_clean_staging.sql again: clean = 87,720 rows, rejected = 0.
-- =====================================================================
DELETE FROM project_staging.stg_eia930_balance_raw WHERE subset_row_number = 0;

SELECT COUNT(*) AS dirty_rows_left_in_raw
FROM project_staging.stg_eia930_balance_raw
WHERE subset_row_number = 0;      -- must be 0
