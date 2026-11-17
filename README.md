# PowerPulse - Electricity Demand & Generation Data Warehouse

DL3004 Data Warehouse & Business Intelligence Lab, FAST NUCES Lahore. Submitted to Mr Shahzeb Mubashar.

| Member | Roll number |
|---|---|
| Mohid | 24L-2510 |
| Hanan | 24L-2537 |
| Muaz Fahad | 24L-2563 |
| Emaad | 24I-2516 |
| Qasim | 24L-2517 |

A PostgreSQL dimensional warehouse over real EIA-930 data for CISO, ERCO, ISNE, NYIS and PJM. Operating dates span 2024-01-01 through 2025-12-31. Two hourly facts share five dimensions; no synthetic warehouse data is used.

```text
Committed source CSVs -> project_staging -> project_dw -> project_reporting -> BI
                           cleaning       dimensions     Q01-Q10 views
                                            facts        persisted quality results
```

## Setup and complete execution

Install PostgreSQL 16+ and Python 3.10+. The selected CSVs and reference files are already committed; normal execution does not download EIA data. Use Git clone so `.gitattributes` restores the manifest's CRLF CSV bytes consistently on Windows and Linux. GitHub-generated source ZIPs may use normalized LF bytes and fail the strict input hash audit.

```powershell
git clone https://github.com/hananishaq/powerpulse-dw.git
cd powerpulse-dw
python -m venv .venv
.\.venv\Scripts\Activate.ps1
pip install -r requirements.txt
Copy-Item .env.example .env
```

On Linux/macOS use `source .venv/bin/activate` and `cp .env.example .env`. Edit `.env` with your own local database settings. Do not commit it. Existing environment variables take precedence over `.env`.

```text
PGHOST=localhost
PGPORT=5432
PGDATABASE=powerpulse_dw
PGUSER=postgres
PGPASSWORD=your_local_password
```

```shell
python etl/run_all.py --bootstrap --report
```

`--bootstrap` creates the configured database only if absent. It requires CREATEDB privilege and access to maintenance database `postgres`. Otherwise have an administrator create the database and run without `--bootstrap`. No existing database is dropped. Staging is rebuilt from the committed inputs; dimensions and facts are upserted.

The runner creates schemas, calls staging/dimension/fact loaders, installs reporting, independently validates the warehouse and optionally renders the PDF. It stops on failure and records each stage. This is a frozen-baseline runner, not automatic ingestion of new source revisions.

## Repeatability and meaningful failure tests

Run the pipeline again, then execute the transactional integration suite and rebuild the report:

```shell
python etl/run_all.py --bootstrap
python tests/integration_checks.py
python reports/phase2/build_data_quality_report.py
```

The second pipeline compares business-key-to-surrogate-key digests for all five dimensions and both facts. The integration suite proves the actual quality SQL fails after demand corruption, a missing generation observation and a lost boundary hour; tests tied peaks, undefined forecast/share ratios and all-null fuel categories; then confirms baseline restoration. Every mutation is rolled back. Use a disposable local project database.

Default quality runs also exercise duplicate, unknown-key, missing-authority, boundary-hour and fan-out detectors using temporary scratch data. Exit code 0 means PASS; an unexpected mismatch or execution error returns nonzero.

## Deliverables and evidence

| Artifact | Purpose |
|---|---|
| [Data Quality Report](reports/phase2/Data_Quality_Report.pdf) | Measured results, findings, hashes and reproduction |
| [Data Cleaning Report](reports/phase2/Data_Cleaning_Report.pdf) | Qasim's cleaning rules, examples and self-test |
| [Latest DQ results](reports/phase2/evidence/latest_dq.json) | Exact run, expected/actual values and monthly coverage |
| [Latest pipeline log](reports/phase2/evidence/latest_pipeline.json) | Stage outcomes, original loader output and identity fingerprints |
| [Integration tests](reports/phase2/evidence/integration_tests.json) | Rolled-back failure detection and reporting tests |
| [Consolidated SQL](sql/00_setup/10_install_warehouse.psql) | Physical structures and views via psql |
| [Implementation notes](docs/phase2/MOHID_IMPLEMENTATION.md) | Ownership, controls, reporting rules and limitations |

Database results persist in `project_reporting.dq_run` and `project_reporting.dq_check_result`. Inspect the latest completed run:

```sql
SELECT check_name,category,expected,actual,status
FROM project_reporting.vw_latest_dq_results
ORDER BY category,check_name;
```

The PDF is generated from measured JSON, not prefilled expected values. Archived evidence retains run IDs. The code base revision records HEAD at execution; the implementation accompanying the report is the commit containing it.

## Frozen-baseline acceptance targets

| Control | Expected |
|---|---:|
| Date / hour / authority / fuel / snapshot dimensions | 731 / 24 / 5 / 19 / 4 |
| Total dimension records | 783 |
| Demand facts | 87,720 |
| Numeric reported fuel cells / generation facts | 727,720 |
| Independent expected authority-hours | 87,720 |
| NULL actual / forecast / total generation | 218 / 218 / 218 |
| Hours with any / all three core measures NULL | 316 / 120 |
| Eligible forecast pairs | 87,399 |
| Negative fuel observations retained | 31,007 |
| Comparable fuel-total hours | 87,471 |
| Residual flags beyond max(10 MW, 1% absolute total) | 6,958: PJM 6,873; ERCO 85 |
| Orphan keys / duplicate grains / unexplained missing hours | 0 / 0 / 0 |

Source NULLs and residual flags are real findings, not auto-correction instructions. Some valid UTC end labels fall in January 2026; operating dates still end in December 2025. MW is power; each one-hour observation times one hour yields MWh.

## Reporting catalog

Views live in `project_reporting`, expose eligible/observed counts and source versions, and label MW/MWh/percent measures.

| View | Question |
|---|---|
| `vw_q01_monthly_demand_energy` | Observed demand MWh by authority/month |
| `vw_q02_local_hour_demand` | Local hour-ending mean demand MW |
| `vw_q03_monthly_peak_demand` | Peak MW and every tied timestamp |
| `vw_q04_seasonal_day_type` | Seasonal weekday/weekend demand |
| `vw_q05_monthly_forecast_accuracy` | Bias, MAE, WAPE and eligible/excluded pairs |
| `vw_q06_underforecast_patterns` | Hourly/seasonal bias and underforecast frequency |
| `vw_q07_monthly_generation_by_fuel` | Signed generation MWh by exact header and group |
| `vw_q08_wind_solar_share` | Matched, reconciliation-screened category share |
| `vw_q09_high_demand_source_mix` | Source energy in monthly top-decile versus other hours |
| `vw_q10_monthly_source_quality` | Coverage, NULL/invalid/zero/negative measures and flags |

Aggregate generation to authority/hour before demand comparisons. All-null categories retain NULL energy and zero observation counts. Ratios without eligible denominators return NULL. Combine WAPE using its numerator/denominator sums, never averages of percentages.

## Manual execution

Python reads `.env`; psql does not. Use matching psql host/port/user settings and its password prompt. The database creation and consolidated scripts use psql commands, not pgAdmin Query Tool syntax.

```shell
psql -U postgres -d postgres -v ON_ERROR_STOP=1 -f sql/00_setup/00_create_database.sql
psql -U postgres -d powerpulse_dw -v ON_ERROR_STOP=1 -f sql/00_setup/10_install_warehouse.psql
python etl/00_test_connection.py
python etl/01_load_staging.py
python etl/02_load_dimensions.py
python etl/03_load_facts.py
python etl/04_run_quality_checks.py
python reports/phase2/build_data_quality_report.py
```

For another database name use `-v target_db=your_name` during creation and matching connection settings. In pgAdmin create the database through the UI, then execute ordinary schema SQL inside it. Quality SQL needs session-local independent source tables and a DQ run ID, so use the quality Python entry point.

Do not blindly execute every SQL file: staging's 95/96 files deliberately insert/remove dirty data, and runners already execute their dependencies.

## Layout and ownership

```text
docs/phase1/             Requirements, questions, dictionary and design evidence
docs/phase2/             Responsibility board and implementation notes
design/                  DBML and draw.io sources
data_acquisition/        Acquisition scripts, committed CSVs and manifest
sql/00_setup/            Bootstrap and consolidated structures
sql/01_staging/          Qasim: staging, cleaning and verification
sql/02_dw/               Emaad: dimensions/fact DDL
sql/03_dimension_load/   Emaad: dimension loads
sql/04_fact_load/        Muaz: fact loads and original grid helper
sql/05_quality/          Mohid: persisted validation and negative tests
sql/06_reporting/        Mohid: base views and ten business views
etl/                     Loaders, independent validator and integration runner
tests/                   Transactional database integration suite
reports/phase2/          PDFs, builders and measured JSON evidence
```

The supplied four-student division governs ownership. Mohid supplied integration glue so the submitted baseline can run completely. Original fact-loader enhancements remain upstream: mapping quarantine, exact insert/update/reject counts and removal of observations withdrawn by source revisions. The independent validator detects resulting mismatches; it does not implement those upstream behaviors. See the implementation notes.

## CI and source reacquisition

[Phase 2 validation](.github/workflows/phase2-validation.yml) builds on PostgreSQL 16, reruns, exercises integration tests and uploads evidence. Inspect GitHub's actual workflow outcome; a local pass does not assert CI has run.

Source reacquisition is documented in [data_acquisition/README.md](data_acquisition/README.md). New source versions require reviewing hashes, mappings, coverage, targets and revision behavior before accepting a new baseline.
