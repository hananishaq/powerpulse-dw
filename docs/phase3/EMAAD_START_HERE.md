# Emaad: Phase 3 work guide

Your part is **Q07/Q08 generation analytics, the shared hourly generation
helper, and the final three-page Power BI dashboard**. Qasim reviews your work.
You also review Muaaz's forecast and indexing contribution.

Mohid's demand package, Hanan's peaks/OLAP package, Muaaz's forecast/indexing
package, and the BI month-filter fix are already supplied. Your generation SQL
and the master dashboard are still to be built.

## 1. Get the code and prepare your database

```powershell
git switch main
git pull --ff-only origin main
git switch -c phase3/p4-generation-bi
python -m venv .venv
.\.venv\Scripts\Activate.ps1
pip install -r requirements.txt
```

Reuse your existing branch/environment if you already created them. Create
`powerpulse_dw` in PostgreSQL first. Copy `.env.example` to `.env` if you do not
already have one, then fill in your own database settings. Never commit it.

```powershell
python etl/run_all.py --phase3
```

Next, execute these SQL files in pgAdmin Query Tool, in order:

1. `sql/06_reporting/p2_profile_views.sql`
2. `sql/07_phase3_analytics/p2_q03_q04.sql`

Then install Muaaz's views:

```powershell
python etl/06_run_phase3_muaz.py
```

`run_all.py --phase3` installs Mohid's package only; the extra steps above are
required for Hanan and Muaaz. Expected facts: **87,720 demand** and **727,720
generation** rows. Expected dimensions: **731 dates, 24 hours, 5 authorities,
19 source categories, 4 snapshots**.

## 2. Build your SQL first

Create these files:

- `sql/06_reporting/p4_generation_views.sql`
- `sql/07_phase3_analytics/p4_q07_q08.sql`
- `sql/07_phase3_analytics/p4_validate.sql` (recommended validation entry point)

Use `CREATE OR REPLACE VIEW` and declare the grain of every view.

### Shared helper: `project_reporting.vw_generation_authority_hour`

Build this first and share its column names with Qasim. It must have **one row
per authority + UTC hour**, aggregating generation before any demand join.
Include the authority/date keys, UTC timestamp, signed available-fuel sum,
wind and solar sums, observed-component flags/counts, and source lineage.

Use the exact categories and approved groups in
`data_acquisition/data/energy_source_mapping.csv`. Preserve legacy combined
hydro/storage and integrated-storage labels. Use the manifest's source headers
to distinguish a category absent from a file from a supplied blank cell.
Retain real zero and negative generation values.

### Q07: `project_reporting.vw_q07_generation_by_source`

Return monthly **signed MWh by authority, original source label and source
group**, with numeric observation counts. Keep schema absence, blanks and
observed zero distinguishable. When no numeric observation exists, energy is
NULL rather than an invented zero. Supply the rubric compatibility view
`project_reporting.vw_product_performance` over your domain result, with a
comment explaining the electricity interpretation.

### Q08: `project_reporting.vw_q08_wind_solar_share`

Left join demand to your helper on authority + UTC hour. A matched hour needs:

- At least one observed applicable wind category and one observed applicable
  solar category; expose component counts and document exactly which source
  labels contribute in each file version.
- Positive reported `total_generation_mw`.
- An available-fuel residual within
  `max(10 MW, 1% of abs(reported total generation))`.

Residual = available signed fuel sum minus reported total generation.
Missing components do not become zero. Compute share as
`100 * SUM(matched wind + solar MWh) / SUM(matched reported-total MWh)`.
Publish matched/excluded hour counts, numerator/denominator components and
source-version details. Undefined ratios stay NULL. Retain month keys for BI.

## 3. Build one master Power BI file

Save it as `bi/phase3/PowerPulse_Phase3.pbix`. You are the sole editor of this
master during integration. Use the PostgreSQL connector and document Import
mode, server/database, selected views and refresh steps in
`bi/phase3/model_and_refresh.md`. Keep credentials in local Power BI settings.

| Page | Starting material |
|---|---|
| Executive Overview | `bi/phase3/mohid/PowerPulse_Overview.pbix` and [Mohid's spec](../../bi/phase3/p1_overview_spec.md) |
| Detailed Analysis | [Hanan's spec](../../bi/phase3/p2_detail_spec.md), your fuel visuals, and Muaaz's forecast measures |
| Decision Page | Qasim supplies `bi/phase3/p5_decision_spec.md`; coordinate this dependency early |

Mohid's PBIX currently supports a frozen Snapshot mode. For the final master,
configure the warehouse connection and verify a real refresh against the
current reporting views; opening the snapshot alone is not that test.

Use shared Authority and Month dimensions with unique keys and single-direction
one-to-many relationships. Keep demand and fuel facts separate; do not use a
direct many-to-many fact join. Recalculate averages and percentages from summed
components. Keep signed fuel values visible; choose a chart that handles them
and do not silently clip negative values to fit a percentage chart.

**Use these inputs for month-filtered visuals:**

| Model table | Reporting view |
|---|---|
| SeasonalProfile | `vw_q04_month_daytype` |
| ForecastPerformance | `vw_q05_forecast_accuracy` |
| ForecastPattern | `vw_forecast_month_hour_components` |

Relate each `month_start` to the shared month dimension. The full-season Q04/Q06
outputs cannot directly support individual-month selections. Day-type and fuel
slicers must only affect visuals whose source supports those filters.

Muaaz's DAX and filtering instructions are in
[the forecast/performance guide](muaz_forecast_performance.md). His measured
index candidates are recommendations to review, not an automatic migration;
benchmark scripts are restricted to disposable databases.

## 4. Validate before handing off

- Check helper uniqueness. Left joining it must preserve demand row count and
  demand energy; never join demand straight to individual fuel rows.
- Reconcile Q07 totals/counts with generation facts; retain negative values.
- Test Q08 missing wind/solar, zero or NULL reported total, residual failures
  and no eligible hours. Compare SQL/DAX using the exact same matched cohort.
- Re-run your view installation and check unchanged results.
- Test one authority/month, a full year, both years, noncontiguous months and
  an empty selection. Compare each dashboard measure with SQL under the same
  filters; inspect units, sorting, NULL display, tooltips and navigation.
- Refresh and save the master PBIX. Have a teammate open it and change their
  local database connection successfully. Record results and limitations.

The baseline pooled forecast WAPE is **3.5901555439% over 87,399 eligible
pairs**. This is a useful full-selection check; calculate WAPE from components.
SQL `_pct` columns already contain percentage points. DAX ratios formatted as
percentages should not also be multiplied by 100.

## 5. Finish and hand off

- Give Qasim your stable helper contract early so he can implement Q09/Q10.
- Give Qasim one verified fuel finding and two slide drafts.
- Ask Qasim to review your SQL/model. Record your review of Muaaz's work.
- Give Qasim the frozen, validated PBIX for final screenshots and report/deck
  assembly. He owns those final assembled artifacts.
- Update the team manifest with your files, validation and review status.

The formal Phase 2 quality package is still absent from this checkout. Record
that as a team readiness dependency; a successful load or dashboard refresh
does not replace the missing quality gate. Final submission also needs Qasim's
remaining analytics, decisions and assembled outputs.
