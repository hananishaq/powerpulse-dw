# PowerPulse — Electricity Demand & Generation Data Warehouse

**DL3004 Data Warehouse & Business Intelligence Lab — Final Project**
FAST NUCES Lahore · Submitted to: Mr Shahzeb Mubashar

| Group member | Roll number |
|---|---|
| Mohid | 24L-2510 |
| Hanan | 24L-2537 |
| Muaz Fahad | 24L-2563 |
| Emaad | 24I-2516 |
| Qasim | 24L-2517 |

## What this project is

A PostgreSQL dimensional warehouse over real **EIA-930 hourly grid data** for five U.S. balancing
authorities (CISO, ERCO, ISNE, NYIS, PJM), operating dates 1 Jan 2024 – 31 Dec 2025.
Two hourly periodic-snapshot facts (demand/forecast and net generation by fuel) share five
conformed dimensions. Source: official EIA bulk CSVs — no synthetic data.

## Status

| Phase | Scope | Status |
|---|---|---|
| 1 | Business analysis & dimensional design (30%) | ✅ Complete — see `docs/phase1/` |
| 2 | Physical DW implementation & ETL pipeline (40%) | 🔧 In progress — task board `docs/phase2/TASKS.md`, plan `docs/phase2/PHASE2_PLAN.md` |

## Measured source facts (Phase 1 evidence)

- 87,720 authority-hour rows (5 × 17,544 UTC hours), 731 operating dates, 0 duplicate authority/UTC keys, 0 missing hours.
- 727,720 numeric reported fuel observations across 19 distinct fuel headers (16 contain data).
- Source blanks: 218 blank values in **each** of actual demand, forecast and total generation. These fall on 316 distinct authority-hours (120 are missing all three).
- 87,399 eligible forecast pairs (actual > 0, forecast ≥ 0).
- Negative net generation is real source data and is retained.

## Repository layout

```
docs/phase1/          Phase 1 submission PDFs, Excel data dictionary, schema atlas, ERD (06b)
docs/phase2/          Task board (who does what), 5-step plan, Phase 1 → Phase 2 name mapping
design/               DBML (dbdiagram.io) and draw.io sources of the schema
data_acquisition/     Download/profile scripts + the selected raw CSVs, manifest, profile (Phase 1 evidence)
sql/00_setup/         Database + schema creation
sql/01_staging/       project_staging tables and cleaning SQL
sql/02_dw/            project_dw DDL (dimensions and facts)
sql/03_dimension_load/
sql/04_fact_load/
sql/05_quality/       Data-quality checks
sql/06_reporting/     project_reporting views
etl/                  Python ETL / orchestration scripts
reports/phase2/       Data Cleaning Report and Data Quality Report (PDF)
```

## Warehouse architecture

```
Source CSVs  →  project_staging  →  project_dw  →  project_reporting  →  Power BI
```

## Getting started (Phase 2 — filled in as steps are completed)

1. Install PostgreSQL 16+ and Python 3.10+.
2. `python -m venv .venv` then activate it, then `pip install -r requirements.txt`.
3. Copy `.env.example` to `.env` and set your database password.
4. Run the SQL scripts in numeric folder order (`sql/00_setup` → `sql/06_reporting`).

## Re-acquiring the source data

The delivered `data_acquisition/data/` already contains the selected rows. To rebuild from the official
EIA files, see `data_acquisition/README.md`.
