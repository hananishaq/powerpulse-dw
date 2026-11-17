# Phase 2 reports and measured evidence

| Artifact | Purpose |
|---|---|
| `Data_Cleaning_Report.pdf` | Qasim's staging rules, counts, examples and self-test |
| `Data_Quality_Report.pdf` | Mohid's measured checks, findings and reproduction |
| `build_data_quality_report.py` | Builds the PDF from exported results |
| `evidence/latest_dq.json` | Quality run, source audit and monthly coverage |
| `evidence/latest_pipeline.json` | Integrated stages and identity fingerprints |
| `evidence/integration_tests.json` | Rolled-back detector/reporting tests |

Run the full pipeline twice, execute `python tests/integration_checks.py`, then `python reports/phase2/build_data_quality_report.py`. For an archived run pass `--evidence reports/phase2/evidence/dq_RUN_ID.json`.

The PDF reports the selected run's actual status and error, including FAIL/ERROR outcomes. Source expectations must never be relabeled as successful database execution.
