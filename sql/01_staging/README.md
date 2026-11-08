# Step 2 — Staging and cleaning

**Owner:** ________ · **Marks:** ETL Pipeline · **Needs first:** Step 1 (schemas exist)

## Your job
Land the four source CSVs in `project_staging`, then clean them into one typed table the rest of the team reads.
Table and column names are fixed in `docs/phase2/TASKS.md` (shared contract) — do not rename.

## Create these files
- `00_create_staging_tables.sql` — raw landing table (all TEXT), the four reference/contract tables, `stg_load_exception`.
- `10_clean_staging.sql` — build `stg_eia930_balance_clean` (typed, standardized, de-duplicated).
- `../../etl/01_load_staging.py` — `COPY` the CSVs from `data_acquisition/data/` and load the reference CSVs and `source_manifest.json`.
- `../../reports/phase2/Data_Cleaning_Report.pdf` — before/after counts for every rule.

## Facts about the data you must handle
- The 2024 Jan–Jun file has **46 columns** (9 fuel columns); the other three have **67** (16 fuel columns). Load each file with its own column list.
- Use only the reported columns. Ignore `(Imputed)` and `(Adjusted)` columns. Keep `_SourceFile` and `_SourceRow` as `source_file` / `source_row`.
- Timestamps look like `01/01/2024 9:00:00 AM`. UTC goes to `timestamptz`; local goes to a plain `timestamp`. `utc_offset_minutes` = local minus UTC (values -480 to -240).
- `Hour Number` goes up to 25 on the autumn clock-change day. Never derive the date from the local label; use `Data Date` (midnight labels belong to the previous day).
- Blank cell → `NULL`, never 0. 218 blanks in each of demand, forecast and total generation (316 hours have at least one). Keep these rows.
- Trim and upper-case the authority code (`" ciso "` → `CISO`). Show this rule working even though the real data is already tidy.
- Rows per file must equal: 21,835 · 22,085 · 21,715 · 22,085 (total 87,720). Duplicates on (authority, UTC hour) should be 0 — report that count.

## Done when
`stg_eia930_balance_clean` has 87,720 rows, the 5 / 19 / 4-row reference tables are loaded, and every rejected row (if any) is in `stg_load_exception` with a reason.
