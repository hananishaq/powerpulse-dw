# Phase 3 reporting contract

Owner: Mohid (24L-2510). Implementation baseline: `27edc1213458`.
SQL targets PostgreSQL 16+. All names are in `project_reporting`.

## Implemented by Mohid

| View | Exactly one row per | Purpose |
|---|---|---|
| `vw_demand_observation` | authority + UTC hour | Reusable demand input, local labels, forecast eligibility and source locators |
| `vw_q01_monthly_demand_energy` | authority + operating month | Q01/M01 energy, counts, coverage and consecutive-month growth |
| `vw_q02_hourly_profile` | authority + operating month + local hour | Q02/M02 profile with additive components |
| `vw_authority_analysis` | authority + operating month | Demand and forecast components with documented planning segments |

The generic handout names `vw_monthly_sales` and `vw_customer_analysis` are
also supplied as compatibility aliases of Q01 and authority analysis. They
retain electricity columns and units. `vw_product_performance` belongs to the
generation owner's contribution and is not fabricated here.

`authority_key` is the warehouse surrogate key. `authority_code` is the BA code.
`month_start` is a PostgreSQL DATE for the first day of the source operating
month. `year_month` is `YYYY-MM`, never a month name without its year.

### Q01 and authority analysis columns

| Column | Unit / definition | Aggregation |
|---|---|---|
| `observed_demand_mwh` | SUM(nonnegative actual MW x 1 hour) | SUM; all-ineligible groups stay NULL |
| `observed_authority_hours` | Existing demand fact records | SUM |
| `eligible_demand_hours` | Actual demand numeric and >= 0 | SUM |
| `null_actual_hours` | Present records with missing actual demand | SUM |
| `negative_actual_hours` | Present records with actual < 0 | SUM; retained for diagnosis |
| `mean_hourly_demand_mw` | Observed MWh / eligible hours | Recalculate from components |
| `observed_demand_coverage_pct` | 100 x eligible hours / observed hours | Recalculate from counts |
| `previous_month_demand_mwh` | Previous calendar month's observed energy | Never SUM across months |
| `demand_mom_growth_pct` | 100 x (current - prior) / prior | Recalculate for selected cohort |
| `source_snapshot_count` | Distinct versions contributing to this authority/month | Nonadditive |

Monthly spines fill missing internal months inside each authority's observed
span. A missing month has zero observed/eligible hours and NULL energy. The
first month, a missing prior month or a zero prior denominator produces NULL
growth. A month with only valid zero demand has **zero**, not NULL, energy.
Partial coverage remains visible; growth describes observed totals, not a
coverage-adjusted estimate. Do not use coverage among observed rows as proof
that the expected-hour grid has no gaps.

### Q02 columns

`hour_ending` is the source local end-label hour 0-23. A midnight end label
continues to use the publisher's `Data Date`. Both autumn occurrences of a
local hour remain separate UTC observations in that bucket.

`demand_sum_mw`, `eligible_demand_hours`, `observed_authority_hours`,
`null_actual_hours` and `negative_actual_hours` are additive. Roll up a profile
using `SUM(demand_sum_mw) / NULLIF(SUM(eligible_demand_hours), 0)`. Do not average
monthly means. No numeric fuel fact or generation join is needed for Q01/Q02.

### Forecast components in authority analysis

M04-M07 use exactly the rows where actual > 0 and forecast >= 0, both present.
`eligible_forecast_pairs`, `excluded_forecast_pairs` and `underforecast_pairs`
are counts. `eligible_actual_sum_mw`, `abs_error_sum_mw` and
`signed_error_sum_mw` are sums over the same eligible pairs.

* WAPE % = 100 x abs error sum / eligible actual sum.
* MAE MW = abs error sum / pair count.
* Bias MW = signed error sum / pair count; positive means underforecast.

This small shared component calculation lets Mohid's package run independently
of Q05. Muaz remains the owner of Q05/Q06; compare his results with these
components rather than introducing a second definition.

### Planning segments

`demand_segment` uses mean demand: below 10 GW, 10 to below 30 GW, 30 GW or
above, and no eligible demand. `forecast_error_segment` uses monthly WAPE:
below 5%, 5 to below 10%, 10% or above, and no eligible pairs. These fixed
thresholds are project choices, not industry standards or formal risk ratings.
Units in the source columns remain MW. Segments describe **authority-months**.
A filtered two-year selection can put the same authority in several bands.
For one band per authority over that selection, aggregate components first
and reclassify in a measure. Do not count segment rows as distinct customers.

## Other owners' integration points (not implemented here)

Hanan owns Q03/Q04 and ROLLUP/CUBE. Muaz owns Q05/Q06 and indexing. Emaad owns
Q07/Q08, `vw_generation_authority_hour` and the master PBIX. Qasim owns Q09/Q10
and the assembled insights/screenshots/presentation. Their proposed view names
remain as defined in the work plan; this package does not overwrite them or
claim they are complete.

Every generation-to-demand join must reduce generation to authority + UTC hour
first. Ratios use the same matched cohort. Keep signed generation and distinguish
absent headers from blanks. Validate demand count/energy before and after joins.

## Lineage and reproducibility

The observation view retains `source_snapshot_key` and `source_row_number`.
The analytical SQL includes an authority/month file/hash lineage query.
Aggregate views intentionally do not group by source snapshot, which would
split a monthly result. Record all contributing hashes with exported evidence.
Never add different publication versions together as separate observations.
