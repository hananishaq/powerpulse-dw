# Independent quality validation - Mohid

Run `python etl/04_run_quality_checks.py` after loading facts. It verifies source hashes/counts, parses CSV rows independently into temporary tables, installs reporting and executes completeness, accuracy, integrity and scratch negative tests. It saves results by run in `project_reporting.dq_check_result`, exports JSON and returns nonzero on FAIL/ERROR.

Check files rely on the runner's temporary source tables and session run ID; do not execute them in a different SQL session. `--skip-negative-tests` is available for a baseline-only audit. The integration suite additionally proves actual check FAIL results under rolled-back mutations.

Expected baseline: 87,720 demand facts; 727,720 fuel facts; 783 dimension members; 218 NULLs per core measure; 87,399 eligible forecast pairs; 6,958 residual flags among 87,471 comparable hours. Zero orphan keys, duplicate grains and missing expected hours are required. Source NULLs and residuals remain visible.

See the root README and `docs/phase2/MOHID_IMPLEMENTATION.md` for full metric eligibility, evidence and upstream limitations.
