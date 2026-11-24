# PowerPulse — Electricity Demand & Generation Data Warehouse

**Final evaluation:** [Phase 3 deliverables, setup, and verification](docs/phase3/FINAL_EVALUATION.md).

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
| 2 | Physical DW implementation & ETL pipeline (40%) | Warehouse and ETL on main. Formal quality package and report on the [quality branch](https://github.com/hananishaq/powerpulse-dw/tree/mohid/phase2-quality-reporting). |
| 3 | OLAP analytics, performance & BI (30%) | Q01–Q10, OLAP, three-page Power BI project, reports and presentation. Native PBIX and screenshots pending Windows acceptance. |

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

## Phase 3 demand analytics

After loading Phase 2, run `python etl/05_run_phase3_mohid.py` to create and
reconcile Mohid's reporting views. To build from an empty configured database,
run `python etl/run_all.py --phase3 --refresh-bi-snapshot`. Analytical queries are in
`sql/07_phase3_analytics/p1_q01_q02.sql`. The editable Executive Overview
source project is `bi/phase3/mohid/PowerPulse_Overview.pbip`. Open the companion
`PowerPulse_Overview.pbix` to view the populated report in Snapshot mode without
credentials. Warehouse mode supports a live local connection. See the
[Phase 3 guide](docs/phase3/README.md) for contracts,
validation evidence, Power BI integration and the remaining team checklist.
