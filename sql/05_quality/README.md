# Step 5A — Data quality validation

**Owner:** ________ · **Marks:** Data Quality Validation (10) · **Needs first:** Steps 3 and 4 pushed

## Your job
Prove the warehouse is complete, accurate and consistent, and record every result in a table (not just printed output).

## Create these files
- `00_create_dq_result_table.sql` — `dq_check_result` (check name, category, expected, actual, status PASS/FAIL, run time).
- `10_completeness_checks.sql`, `20_accuracy_checks.sql`, `30_integrity_checks.sql`.
- `40_negative_tests.sql` — on a scratch copy, inject a duplicate row and an orphan key and show the checks FAIL.
- `../../etl/04_run_quality_checks.py` — runs everything and prints a PASS/FAIL summary.
- `../../reports/phase2/Data_Quality_Report.pdf`.

## Checks and the numbers you should get
| Type | Check | Expected |
|---|---|---|
| Completeness | blank actual demand / forecast / total generation | 218 / 218 / 218 |
| Completeness | authority-hours with any blank core measure (all three blank) | 316 (120) |
| Completeness | expected-hour grid vs demand fact | 0 missing hours |
| Accuracy | row counts vs source manifest | 87,720 demand · 727,720 generation |
| Accuracy | total demand MWh: fact vs staging | equal |
| Accuracy | fuel sum vs total generation, residual beyond max(10 MW, 1%) | 6,958 flagged of 87,471 comparable (PJM 6,873, ERCO 85) |
| Accuracy | forecast-eligible pairs (actual > 0, forecast ≥ 0) | 87,399 |
| Integrity | orphan foreign keys, both facts | 0 |
| Integrity | duplicate business keys, both facts | 0 |
| Integrity | join generation (aggregated first) to demand | demand count and total unchanged |

If your number differs, find out why before reporting it — a mismatch is either a bug or a finding.
