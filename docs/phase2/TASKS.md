# Phase 2 responsibility and handoff board

The supplied four-student division governs ownership. The older five-step plan is implementation context.

| Owner | Scope | Implementation / remaining handoff |
|---|---|---|
| Qasim | Staging, cleaning and Cleaning Report | Scripts, verification, self-test and PDF present; reproduce integrated evidence |
| Emaad | Warehouse DDL, keys and dimensions | Core implementation present; per-table loader failure logic and domain CHECK hardening remain upstream |
| Muaz | Facts, mapping and complete ETL | Fact scripts present; mapping quarantine, exact operation counts and revision withdrawal remain upstream |
| Mohid | Quality, reporting, report and integration | Setup, SQL package, all ten views, independent validation, tests, wrapper, PDF builder, documentation and CI supplied |

## Mohid implementation checklist

- [x] Database/schemas and connection test
- [x] Consolidated physical SQL entry point
- [x] Independent source hash/count/row checks
- [x] Persisted completeness, accuracy and integrity results
- [x] Scratch negative tests and transactional failure/reporting tests
- [x] Q01-Q10 reporting with eligibility, units and source versions
- [x] Integration runner with stage logs and identity fingerprints
- [x] Measured Data Quality Report builder
- [x] README, execution notes and CI

Actual test status is established by `reports/phase2/evidence/latest_dq.json`, `latest_pipeline.json` and `integration_tests.json`, not this checklist. The submission PDF is `reports/phase2/Data_Quality_Report.pdf`.

The full runner is assigned to Muaz in the division. Mohid added an integration wrapper to make the current baseline reproducible without claiming completion of unrelated fact-loader enhancements.

Execution order: setup -> source import/cleaning -> dimensions -> facts -> reporting/quality -> PDF. Use `python etl/run_all.py --bootstrap --report`, repeat for stable key mappings, then run `python tests/integration_checks.py`.

Never commit passwords, `.env` or database directories. Preserve NULLs, signed generation and exact source-header semantics. Source revisions require explicit partition handling by the fact-load owner.
