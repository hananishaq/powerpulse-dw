# Mohid - implementation and acceptance notes

## Delivered scope

Database bootstrap, schema SQL, consolidated psql structure entry, connection test, all ten reporting views, independent quality SQL/runner, persistent run/results tables, negative/integration tests, measured PDF builder, exported evidence, documentation and CI are supplied.

`etl/run_all.py` is integration glue around the student loaders. The division assigns full orchestration to Muaz; this wrapper makes the frozen baseline executable while retaining ownership of upstream enhancements.

## Quality execution contract

The validator checks selected CSV SHA-256 hashes and per-file counts, independently parses finite signed decimals and source times into temporary `dq_source_core` / `dq_source_fuel`, installs reporting and persists numeric expected/actual/status/detail results. Unexpected malformed input, bad hashes or wrong manifest counts produce ERROR, not an accepted new baseline. Each run is uniquely identified; prior runs are retained.

| SQL file | Controls |
|---|---|
| `00_create_dq_result_table.sql` | Run metadata, results, independent bounds and record_check helper |
| `10_completeness_checks.sql` | Fact/staging/file/dimension counts, NULL patterns, expected/extra hours |
| `20_accuracy_checks.sql` | Independent core/fuel row comparison, time/lineage, energy, eligibility, residuals and joins |
| `30_integrity_checks.sql` | Every FK, both grains, unmatched staging/fuel mappings and snapshot metadata |
| `40_negative_tests.sql` | Scratch duplicate/orphan/absent-authority/boundary/fan-out detection |

SQL check files depend on temporary source tables and session setting `powerpulse.dq_run_id`; use the Python runner. Default negative tests operate only on scratch tables. The transactional integration suite goes further: real quality SQL must return FAIL after controlled mutations, which are then rolled back. Missing actual results fail comparisons. No connection secrets are exported.

## Source and reporting rules

- Expected hours use authority-specific UTC bounds in frozen `profile.json`, independently of facts. IANA zones preserve DST. Midnight end labels belong to the preceding operating date; valid UTC labels can extend into January 2026.
- Demand energy/means use numeric nonnegative actuals and one-hour intervals. Forecast metrics share actual > 0 / forecast >= 0 eligibility. Error is actual minus forecast; positive bias means underforecasting. WAPE combines numerator/denominator sums.
- Signed generation stays signed. All-null categories remain visible with NULL energy and zero observations. Every DQ export lists present/absent headers by file.
- Generation is summarized at authority/hour before demand comparisons. Q09 creates hourly source-group energy objects, classifies demand, then expands the groups; demand counts are computed separately from category expansion.
- Wind/solar shares require observed components, positive total and residual within max(10 MW, 1% absolute total). Eligible/excluded counts and source category versions are exposed. No eligible denominator means NULL.
- Source NULLs and the 6,958 known residual flags are findings, not automatic corrections. Row-level comparisons detect errors that cancel in totals.

## Acceptance evidence

`latest_pipeline.json` records stage outcomes, original loader output and ordered natural-key/identity fingerprints. A baseline rerun compares all five dimension and both fact mappings. Identity sequence gaps are irrelevant.

`latest_dq.json` records PostgreSQL version, base revision, source hash audit, every quality result, observed demand energy and 120 authority-month coverage rows. Archived run files retain history. The PDF includes the run ID and is built from that JSON. The recorded revision identifies HEAD at execution; the accompanying implementation is the commit containing the report.

`integration_tests.json` covers corrupted demand, missing generation, missing boundary hour, tied peaks, undefined forecast/share metrics and all-null fuel. Every mutation and test DQ run is rolled back, then baseline restoration is checked. Use a disposable test database because transactions briefly hold row locks.

## Upstream limitations retained

1. Fact INNER JOINs do not quarantine unresolved mappings. Independent quality checks detect them before calling a run successful.
2. The original fact runner estimates inserted/updated counts and hardcodes rejects to zero. Pipeline stage status and independent DQ results do not make those original counters exact.
3. Generation upserts do not remove values withdrawn by a revised source. Extra/stale facts fail independent row comparison; automatic partition replacement remains upstream.
4. The original dimension runner gates on combined counts. New quality checks validate each dimension independently. Warehouse domain CHECK hardening remains with its owner.

This report certifies the frozen baseline and specified controls, not arbitrary future revisions or completion of all other students' tasks.

## Deliverable map

Setup/warehouse SQL, staging SQL, DW schema SQL, ETL scripts, dimension scripts, fact scripts, Cleaning Report, Quality Report and the repository represent the nine deliverables. Their presence is separate from the limitations above. Repository: https://github.com/hananishaq/powerpulse-dw. Confirm actual publication and CI status against the pushed branch/workflow.
