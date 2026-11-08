# Step 4 — Facts and expected-hour grid

**Owner:** ________ · **Marks:** ETL Pipeline, Surrogate Keys · **Needs first:** Step 2 clean table and Step 3 dimensions

## Your job
Load both facts by looking up surrogate keys from business keys, and build the expected-hour grid.

## Create these files
- `00_create_etl_run_log.sql` — run log table (step name, start, end, rows read / inserted / updated / rejected).
- `10_load_fact_hourly_demand.sql` — from `stg_eia930_balance_clean`; one row per authority + UTC hour; **keep rows even when a measure is NULL**.
- `20_load_fact_hourly_generation.sql` — unpivot the 19 `gen_*` columns, e.g. `CROSS JOIN LATERAL (VALUES ('Net Generation (MW) from Coal', gen_coal), ...)`; keep only `IS NOT NULL` values (zero and negative stay); join the header text to `dim_energy_source.source_column`.
- `30_build_expected_hour_grid.sql` — `project_dw.expected_hour_grid`: for each authority, every UTC hour from its first to last observed hour (`generate_series`). Not a fact table.
- `40_create_fk_indexes.sql` — indexes on foreign keys, run after loading.
- `../../etl/03_load_facts.py` — runs the scripts in order and writes to the run log.

## Key lookups
`authority_code` → `authority_key`; `data_date` → `date_key`; local hour-ending → `hour_key`; (`source_file`, SHA-256) → `source_snapshot_key`.
Take the date from `data_date`, **not** from the local timestamp.

## Done when
- `fact_hourly_demand` = **87,720**; `fact_hourly_generation` = **727,720**; `expected_hour_grid` = **87,720**.
- No NULL foreign keys; the grid anti-join against the demand fact returns **0** missing hours.
- Re-running does not create duplicates (`ON CONFLICT (...) DO UPDATE`).
