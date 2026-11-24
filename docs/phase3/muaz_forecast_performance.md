# Muaz: forecast analytics and performance

Owner: Muaz Fahad, 24L-2563. Assigned reviewer: Emaad.

## Run order

Use PostgreSQL 16+ and the repository Python requirements. Configure a local
`.env` using `.env.example`; keep credentials out of Git. The database must
exist. `etl/run_all.py --phase3` loads the baseline and Mohid's prerequisites;
it does not automatically install Muaz's package.

```powershell
python etl/run_all.py --phase3
python etl/06_run_phase3_muaz.py --export-dir reports/phase3/muaz/results
```

An already-loaded warehouse can start at the second command. SQL installation
and fail-on-error validation share one transaction. A failed check rolls back
the installation. Optional CSV exports share one repeatable-read, read-only
snapshot. `--from-month` and `--to-month` accept first-of-month dates, with an
exclusive end; `--authority CISO` restricts the exports.

Run `sql/07_phase3_analytics/p3_q05_q06.sql` for Q05, Q06, a month-filtered Q06
example and file/hash lineage. `p3_validate.sql` is the independent SQL gate.

## View contract

All views are in `project_reporting`.

| View | One row per | Purpose |
|---|---|---|
| `vw_q05_forecast_accuracy` | authority + operating month | Q05 bias, MAE, WAPE, underforecast percentage, counts/components |
| `vw_q06_underforecast_pattern` | authority + calendar year + season + local hour ending | Q06 full-season analytical output |
| `vw_forecast_month_hour_components` | authority + operating month + local hour ending | Shared additive components; month-filterable Q06 BI input |

Every error metric uses actual > 0 and forecast >= 0, both present. Error is
actual minus forecast, so positive bias means underforecast. Equal forecasts
remain eligible and count in the underforecast denominator. Missing pairs,
zero/negative actuals and negative forecasts are excluded from every metric.
True zero forecasts remain eligible when actual is positive.

`eligible_forecast_pairs`, `excluded_forecast_pairs`, `observed_authority_hours`,
`underforecast_pairs`, `equal_forecast_pairs`, and `overforecast_pairs` are
additive counts. `eligible_actual_sum_mw`, `eligible_forecast_sum_mw`,
`signed_error_sum_mw`, and `abs_error_sum_mw` are additive across disjoint groups
with eligible pairs; an all-ineligible group retains NULL sums. Q05 retains
internal missing months with zero counts and NULL metrics.

Recalculate bias = signed error / pair count, MAE = absolute error / pair
count, WAPE % = 100 * absolute error / eligible actual, and underforecast % =
100 * underforecast count / pair count. Do not average precomputed percentages
or group means. Undefined ratios remain NULL/N/A. Coverage uses observed
records; it does not establish expected-hour completeness.

Month/season/day labels use the source operating date; UTC identifies distinct
observations. Repeated autumn local hours remain separate inputs. Winter uses
January, February and December of the same calendar year. Aggregate views do
not split a month by snapshot; the analytical lineage query lists all versions.

## Power BI handoff to Emaad

Import Q05 as `ForecastPerformance` and relate its `authority_key` and
`month_start` to the shared Authority and Month dimensions, one-to-many with
single-direction filtering. For hour/season comparisons, import
`vw_forecast_month_hour_components` as `ForecastPattern` and use the same
dimensions. The full-season Q06 view cannot filter individual months.

```DAX
Forecast MAE MW =
DIVIDE ( SUM ( ForecastPerformance[abs_error_sum_mw] ),
         SUM ( ForecastPerformance[eligible_forecast_pairs] ) )

Forecast WAPE =
DIVIDE ( SUM ( ForecastPerformance[abs_error_sum_mw] ),
         SUM ( ForecastPerformance[eligible_actual_sum_mw] ) )

Forecast Bias MW =
DIVIDE ( SUM ( ForecastPerformance[signed_error_sum_mw] ),
         SUM ( ForecastPerformance[eligible_forecast_pairs] ) )

Underforecast Frequency =
DIVIDE ( SUM ( ForecastPerformance[underforecast_pairs] ),
         SUM ( ForecastPerformance[eligible_forecast_pairs] ) )
```

Format WAPE and frequency as percentages without multiplying the DAX ratios
by 100; SQL `_pct` fields already contain percentage points. Format MW to two
decimals and counts as integers. For Q06, use the same expressions over
`ForecastPattern`. Sort local hour numerically 0-23, never alphabetically.
Show eligible/excluded pairs in tooltips. Use blank/N/A for undefined rates.
Fuel and day-type slicers must not filter these monthly/hour forecast tables.

Use the forecast comparison on Detailed Analysis: authority axis, MAE columns,
WAPE line, pair counts in tooltip. Validate full scope, one authority/month,
noncontiguous months, both years and an empty selection with the filtered
components query in `p3_q05_q06.sql`. Master PBIX integration and native refresh
remain Emaad's responsibility; no desktop acceptance is claimed here.

## Disposable validation and benchmark

Create a separate database named `powerpulse_muaz_benchmark`. Point the PG*
environment variables or local `.env` at it and load the same baseline first.
Do not run fixture tests or index experiments on the master warehouse.

```powershell
# PostgreSQL credentials must already be configured locally.
$env:PGDATABASE = 'powerpulse_muaz_benchmark'
python etl/run_all.py --phase3
python etl/06_run_phase3_muaz.py
python tests/phase3_muaz_checks.py --disposable
python etl/07_benchmark_phase3_muaz.py --disposable
python reports/phase3/build_indexing_report.py
```

The test suite independently parses every CSV with Decimal arithmetic and
checks all Q05/Q06/month-hour groups. Real-view fixtures cover missing pairs,
zero/negative actuals, negative forecasts, equal pairs, positive/negative bias,
zero forecasts, no eligible pairs and an internal missing month. Fixture
mutations roll back. Reinstallation and the analytical SQL are checked too.

The benchmark refuses a database without benchmark/scratch in its name and
requires `--disposable`. It refuses existing candidate names or equivalent
definitions, inventories existing indexes, VACUUM ANALYZEs facts and ANALYZEs
dimensions once before measurement. It uses one warm-up plus five measured
EXPLAIN ANALYZE runs for each of three fixed queries in each arm. Both
candidates are added together for the after arm. Candidate DDL rolls back at
the end; existing indexes are preserved. For another run use a fresh empty
`--output-dir`, then pass it to the report builder with `--evidence-dir`.

Raw JSON plans, readable outlines, all thirty measured runs, costs, settings,
query hashes and result checksums are in `reports/phase3/performance/`. Timings
are local warm-cache observations, not a production latency promise. Fixed
before-then-after order, five samples, unchanged duplicate baseline indexes,
and no concurrent-write benchmark limit the conclusions. Candidate INCLUDE
columns consume storage and add write/vacuum maintenance; measured sizes are
reported, while write overhead was not quantified.

## Contribution status

Forecast SQL, measured benchmarks, Indexing Report, checked insight, two slide
drafts and the Hanan review are supplied. Emaad's human review, final PBIX
acceptance and the team quality/release gates remain pending. Existing Phase 2
quality-package gaps are recorded separately and are not silently claimed fixed.
