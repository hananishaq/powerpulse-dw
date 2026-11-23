# Step 5B — Reporting layer

**Owner:** Step 1 owner · **Needs first:** Step 4 facts loaded

## Your job
Publish grain-safe views in `project_reporting` that answer the ten business questions (`docs/phase1/03_Business_Questions.pdf`).

## Rules
- One view per question or per metric group, named `vw_q01_monthly_demand_energy`, `vw_q02_...` and so on.
- Always aggregate generation to authority + UTC hour **before** joining to demand (otherwise demand repeats once per fuel).
- Show units (MW vs MWh) and eligible counts next to every result; ratios with no denominator show `NULL`/N/A.
- Metric definitions M01–M12 are in `docs/phase1/02_Business_Requirements.pdf`.

## Done when
Every view runs without error, and Q1 total demand MWh agrees with the Step 5A accuracy check.

## Implemented Phase 3 demand package

`p1_demand_views.sql` creates Mohid's observation input, Q01 monthly demand,
Q02 local-hour profile and authority-analysis views. See
`../../docs/phase3/view_contract.md` for grains, units and eligibility.
Run `python etl/05_run_phase3_mohid.py` from the repository root to install
them transactionally and execute the reconciliation checks. The remaining
Q03-Q10 views are owned by the other students and are not provided by this file.
