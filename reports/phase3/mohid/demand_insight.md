# Demand finding for the Business Insights Report

Contributor: Mohid Israr, 24L-2510. Reconciled on 23 November 2026.

## Finding

Across the five selected authorities, observed demand energy increased from
**1,763,112,353 MWh in 2024** to **1,816,431,180 MWh in 2025**, a **3.02%**
increase in observed totals. Over the full two-year scope, the source records
contain **3,579,543,533 MWh** of eligible observed demand energy.

July 2025 has the largest combined monthly observed total in this baseline:
**183,572,218 MWh**. This comparison sums energy over each authority's publisher
operating month. It is not a simultaneous UTC peak calculation.

## Evidence and method

Query: `project_reporting.vw_q01_monthly_demand_energy` (Q01/M01). Sum
hourly-average actual demand MW multiplied by one hour, using numeric,
nonnegative actual observations. Group by the publisher's operating date.

| Period | Observed demand MWh | Eligible demand hours |
|---|---:|---:|
| 2024 | 1,763,112,353 | 43,825 |
| 2025 | 1,816,431,180 | 43,677 |
| Both years | 3,579,543,533 | 87,502 |

Growth = 100 x (1,816,431,180 - 1,763,112,353) / 1,763,112,353.
There are 87,720 observed authority-hour records and 218 missing actual-demand
values. Eligible-demand coverage among observed records is 99.751482%.
These numbers were checked against independent Decimal aggregation of every
selected source CSV and against PostgreSQL reporting SQL. Hashes, environment
and test boundaries are recorded in `validation.json`.

Reproduce the yearly comparison:

```sql
SELECT calendar_year,
       SUM(observed_demand_mwh) AS observed_demand_mwh,
       SUM(eligible_demand_hours) AS eligible_demand_hours
FROM project_reporting.vw_q01_monthly_demand_energy
WHERE month_start >= DATE '2024-01-01'
  AND month_start < DATE '2026-01-01'
GROUP BY calendar_year
ORDER BY calendar_year;
```

## Recommended management action

Use the authority-specific monthly trends and Q02 local-hour profiles to review
seasonal planning assumptions, with particular attention to summer demand.
Compare each authority separately before changing capacity or staffing plans.
Use Hanan's Q03 peak analysis and Muaz's forecast-error results to decide which
specific periods need further investigation.

Suggested follow-up: for each authority, record its highest-demand local hour
and month, coverage and eligible observation count, then review whether planned
resources cover the observed seasonal pattern. This is a review recommendation,
not a claim that the dataset proves an electricity capacity shortage.

## Limitations to preserve in the final report

* The scope is CISO, ERCO, ISNE, NYIS and PJM; it does not represent the entire
  U.S. grid or a global electricity market.
* 2024 is a leap year. The years also have different eligible observation
  counts. The 3.02% comparison is of observed energy totals, not a normalized,
  weather-adjusted or coverage-adjusted growth estimate.
* Missing actual demand remains NULL and contributes no estimated energy.
  Coverage among observed rows does not replace an expected-grid missing-row test.
* Local operating months are appropriate for this energy comparison. Sum MW
  across authorities only at aligned UTC instants when discussing power peaks.
* Historical source revisions can change results. Recompute evidence after a
  source hash changes. The source observations do not identify a causal driver.

## Presentation handoff

`presentation/phase3/mohid_demand_overview.pptx` contains two editable slides:
the project demand scope and a monthly trend with the checked yearly finding.
Speaker notes contain the source and metric details. Qasim can combine these
with the other four students' contributions into the final presentation.
