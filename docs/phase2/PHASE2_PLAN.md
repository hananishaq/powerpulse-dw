# PowerPulse — Phase 2 plan (5 steps)

Phase 2 = implement the Phase 1 design: **Source CSVs → project_staging → project_dw → project_reporting**.
Marks (40): Database Implementation 10 · ETL Pipeline 15 · Surrogate Keys 5 · Data Quality 10.

## Decisions to keep consistent

1. **snake_case in PostgreSQL.** Phase 1 documents use `DimDate`, `AuthorityKey` (PostgreSQL would fold these to lowercase
   run-together names). Phase 2 uses `dim_date`, `authority_key`. Full mapping of all 50 columns: `name_mapping.csv`.
2. **Source data is real**, so no synthetic data is generated. Row counts are expected to be: dim_date 731 · dim_hour 24 ·
   dim_balancing_authority 5 · dim_energy_source 19 · dim_source_snapshot 4 (**783 dimension rows**) ·
   fact_hourly_demand **87,720** · fact_hourly_generation **727,720**.
3. **ELT-style:** Python lands the CSVs in staging (`COPY`), SQL does the cleaning and loading inside PostgreSQL.
4. Every script is **re-runnable** (idempotent): running it twice must not change counts or surrogate keys.

---

## Step 1 — Foundation: environment, repo, database, schemas
**Marks:** Database Implementation (part) · **Deliverables:** PostgreSQL Database SQL scripts, GitHub repository link
- Push this repo to GitHub; add teammates and instructor as collaborators.
- Install PostgreSQL 16+ (with pgAdmin) and Python 3.10+; create `.venv`; `pip install -r requirements.txt`.
- Create database `powerpulse_dw`; create schemas `project_staging`, `project_dw`, `project_reporting`.
- Create `.env` from `.env.example`; write `etl/00_test_connection.py`.
- Files: `sql/00_setup/00_create_database.sql`, `sql/00_setup/01_create_schemas.sql`, `etl/00_test_connection.py` (later also `etl/run_all.py`)
- **Done when:** `\dn` shows the 3 schemas and Python connects using `.env`.

## Step 2 — Staging layer and cleaning
**Marks:** ETL Pipeline (part) · **Deliverables:** Staging Schema SQL, ETL scripts, Data Cleaning Report PDF (written in Step 5)
- Create `project_staging` tables. Raw landing table has **all TEXT columns** (only the reported — not Imputed/Adjusted —
  columns, plus `source_file` and `source_row`). Also load the authority reference, the 19-row energy-source mapping and the 4-row source manifest (`source_manifest.json`).
- Load the 4 CSVs with `COPY` (the first file has 9 fuel columns, the other three have 16 — load per-file and handle absent columns).
- Clean into a typed table: trim and standardize text (e.g. `" cISo "` → `CISO`), convert types (UTC with time zone, local as plain
  timestamp, numerics), blank → `NULL` (never 0), detect duplicates on (authority, UTC hour), send bad rows to `stg_load_exception`.
- Log before/after counts for every rule — this is the raw material of the Data Cleaning Report.
- Table names are fixed in `TASKS.md` (shared contract). The **Data Cleaning Report PDF** is written by the Step 2 owner once staging is done.
- Files: `sql/01_staging/*.sql`, `etl/01_load_staging.py`, `reports/phase2/Data_Cleaning_Report.pdf`
- **Done when:** staged rows = 87,720 and match the manifest per file; exception table row count is known and explained.

## Step 3 — Warehouse schema, dimensions, surrogate keys
**Marks:** Database Implementation (part) + Surrogate Key Implementation · **Deliverables:** DW Schema SQL, Dimension Load Scripts
- Create the 7 `project_dw` tables from the Phase 1 dictionary: identity primary keys, UNIQUE natural keys, FOREIGN KEYs, CHECKs.
- Load dimensions: `dim_date` (generate_series over Data Date range, ISO week, meteorological season), `dim_hour` (24),
  `dim_balancing_authority` (5, Type 1), `dim_energy_source` (19, mapped groups), `dim_source_snapshot` (4, from manifest hashes).
- Show the surrogate-key pattern: business key (`authority_code = 'CISO'`) → `authority_key = 1`.
- Files: `sql/02_dw/*.sql`, `sql/03_dimension_load/*.sql`, `etl/02_load_dimensions.py`
- **Done when:** 783 dimension rows; re-running the load leaves counts and keys unchanged.

## Step 4 — Fact loading and the expected-hour grid
**Marks:** ETL Pipeline (part) + Surrogate Key Implementation · **Deliverables:** Fact Load Scripts, ETL scripts
- `fact_hourly_demand`: one row per authority/UTC hour; look up surrogate keys by business key (authority code, Data Date,
  hour ending, file + SHA-256). Keep rows even when a measure is NULL.
- `fact_hourly_generation`: **unpivot** the 19 reported fuel columns (for example `CROSS JOIN LATERAL (VALUES ('Net Generation (MW) from Coal', gen_coal), ...)`, then join the header text to `dim_energy_source.source_column`); keep only numeric cells (zero and negative values are kept,
  blanks create no row).
- **Expected-hour grid:** helper table `project_dw.expected_hour_grid` = every authority × every UTC hour in its span
  (`generate_series`), 87,720 rows. It is not a fact. It supports Q10 / metric M11 (distinguish *absent rows* from *null measures*).
- Indexes on foreign keys; ETL run log table (start/end time, rows read/inserted/rejected).
- Files: `sql/04_fact_load/*.sql`, `etl/03_load_facts.py`
- **Done when:** facts have exactly 87,720 and 727,720 rows; no NULL foreign keys; grid anti-join against demand returns 0 missing hours.

## Step 5 — Data quality, reporting layer, reports, submission
**Marks:** Data Quality Validation · **Deliverables:** Data Quality Report PDF, Data Cleaning Report PDF, final repo
- Checks (results saved to a table, not just printed):
  - Completeness — blank counts per measure (218 / 218 / 218), 316 authority-hours with any blank, coverage per authority-month.
  - Accuracy — row counts vs manifest; total demand MWh fact vs staging; fuel-sum vs total reconciliation (M12: 6,958 hours flagged, 6,873 in PJM);
    fan-out test (joining aggregated generation must not change demand count or total).
  - Integrity — orphan foreign keys = 0; duplicate business keys = 0; expected-hour-grid gaps = 0.
- Negative tests: inject a duplicate row and an orphan key in a scratch copy and show the checks catch them.
- **5A (quality owner):** the checks and the **Data Quality Report PDF**. **5B (Step 1 owner):** `project_reporting` views for the ten business questions (grain-safe), `etl/run_all.py`, README run order, and the release tag `git tag phase2-submission`.
- Files: `sql/05_quality/*.sql`, `etl/04_run_quality_checks.py`, `reports/phase2/Data_Quality_Report.pdf`, `sql/06_reporting/*.sql`
- **Done when:** every check passes or is explained, and a teammate can rebuild the whole warehouse from the README.

---

### Deliverable → step map
| Phase 2 deliverable | Step |
|---|---|
| PostgreSQL Database SQL scripts | 1, 3 |
| Staging Schema SQL | 2 |
| DW Schema SQL | 3 |
| ETL Scripts SQL/Python | 2, 3, 4 |
| Dimension Load Scripts | 3 |
| Fact Load Scripts | 4 |
| Data Cleaning Report PDF | 2 |
| Data Quality Report PDF | 5 |
| GitHub Repository Link | 1 (final in 5) |
