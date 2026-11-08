# Step 3 (part 2) — Dimension loads

**Owner:** ________ · **Marks:** Surrogate Keys · **Needs first:** Step 2 staging tables and `sql/02_dw/`

## Your job
Fill the five dimensions from staging and show business key → surrogate key clearly.

## Create these files (one per dimension)
- `10_load_dim_hour.sql` — 24 rows, `hour_ending` 0–23, label `00`–`23`.
- `11_load_dim_date.sql` — one row per calendar date from `Data Date`: 731 rows, 2024-01-01 to 2025-12-31. Include ISO week year/number, weekday number (document your numbering), meteorological season (Dec–Feb winter, Mar–May spring, Jun–Aug summer, Sep–Nov autumn).
- `12_load_dim_balancing_authority.sql` — 5 rows from `stg_authority_reference` (Type 1: update names on reload).
- `13_load_dim_energy_source.sql` — 19 rows from `stg_energy_source_mapping`; natural key is the exact header text in `source_column`.
- `14_load_dim_source_snapshot.sql` — 4 rows from `stg_source_file` (natural key: file name + SHA-256).
- `../../etl/02_load_dimensions.py` — runs the five scripts in order and logs row counts.

## Done when
- 731 + 24 + 5 + 19 + 4 = **783** dimension rows.
- Running the loads a second time changes **nothing**: same counts, same surrogate keys (`INSERT ... ON CONFLICT (natural key) DO UPDATE/NOTHING`).
- A screenshot or query showing e.g. `authority_code = 'CISO'` → `authority_key = 1` for the report.
