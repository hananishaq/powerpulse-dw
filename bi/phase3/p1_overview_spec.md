# Executive Overview: implementation and integration

Owner: Mohid. Integrator: Emaad.

The editable source project is
[`mohid/PowerPulse_Overview.pbip`](mohid/PowerPulse_Overview.pbip). Its PBIR report
and TMSL `model.bim` are deliberately source-controlled as text. They define a
real report page, queries, DAX measures and relationships. The companion
`mohid/PowerPulse_Overview.pbix` is the populated personal deliverable.
Emaad can integrate this completed page into the final three-page team PBIX.

## Open and refresh

1. Open `mohid/PowerPulse_Overview.pbix` to view the populated overview directly.
   It defaults to **Snapshot** mode and requires no database credentials.
2. The PBIP is the editable text source. Open it in a Desktop version supporting
   PBIR and choose Refresh to load its embedded verified reporting snapshot.
3. To use a live warehouse, change `DataMode` to **Warehouse**, set `PgServer`
   and `PgDatabase`, and supply credentials locally. The default live target is
   `localhost` / `powerpulse_dw`. This optional mode never embeds passwords.
4. To regenerate the snapshot from your warehouse, run
   `python etl/05_run_phase3_mohid.py --refresh-bi-snapshot`. It reconciles the
   views first and captures all authority-months in a repeatable-read transaction,
   regardless of optional CSV export filters. Reopen/refresh the PBIP afterward
   and save the PBIX if you want its cached data updated as well.
5. The page visibly labels Snapshot versus Warehouse mode. Snapshot metadata
   records its generation time, view SQL hash and source snapshot hashes.
   It is a portable result of the validated SQL, not an automatically live feed.

Microsoft format references:
[PBIP](https://learn.microsoft.com/en-us/power-bi/developer/projects/projects-overview),
[PBIR](https://learn.microsoft.com/en-us/power-bi/developer/projects/projects-report),
[model folder](https://learn.microsoft.com/en-us/power-bi/developer/projects/projects-dataset).

## Model contract

Import mode. In Warehouse mode, `MonthlyDemand` imports selected columns from
`project_reporting.vw_authority_analysis`. `Month` imports distinct month rows
from Q01; `Authority` imports the existing balancing-authority dimension.
Both dimensions filter MonthlyDemand through single-direction one-to-many
relationships. There is no fact-to-fact relationship. `Month[year_month]` sorts
by `month_start`. Automatic date hierarchies are unnecessary.

All authoritative DAX is embedded in `MonthlyDemand.measures` in `model.bim`.
Reporting Authorities counts fact keys with observed rows, not all dimension
members. A disconnected hidden `DataContext` table provides the data-mode label.
Snapshot mode imports the same columns from the verified embedded results.
Coverage and mean demand divide additive components. Forecast WAPE
recomputes from sums. The SQL percent fields use 0-100; DAX percentage measures
use 0-1 and percentage formatting. Do not multiply these DAX measures by 100.

Demand MoM Growth is defined only for a single month context (such as a trend
tooltip). It removes the month/year filter to find the preceding calendar month
while retaining authority filters. A missing or zero prior denominator stays
BLANK. It never adds stored growth percentages. Selected Period shows the
minimum and maximum selected months; a noncontiguous selection is a range,
not an assertion that every intervening month is selected.

## Page layout

1280 x 720 canvas, Segoe UI, dark navy headings and teal card values. Reading
and tab order: title, scope note, year/month/authority slicers, three KPI cards,
monthly trend, coverage card, selected-period card and coverage footnote.

| Visual | Field / measure | Formatting and interaction |
|---|---|---|
| Operating year slicer | Month.calendar_year | Multi-select; filters every data visual |
| Operating month slicer | Month.year_month | Chronological YYYY-MM; multi-select |
| Balancing authority slicer | Authority.authority_code | Multi-select; filters every data visual |
| Observed demand (MWh) | Observed Demand MWh | Whole MWh; blank when no eligible demand |
| Observed authority-hours | Observed Authority Hours | Integer record count |
| Reporting authorities | Reporting Authorities | Integer distinct observed BAs; 0 for empty selection |
| Monthly observed demand | Month.month_start + Observed Demand MWh | Ascending continuous month; coverage and MoM tooltips |
| Eligible demand / observed hours | Observed Demand Coverage | 2 decimal percent; blank for zero observed rows |
| Selected operating period | Selected Period | Text range of current month selection |

The trend supports ordinary visual filtering. Before the final release, Emaad
checks Desktop's Edit interactions so every slicer filters all cards and the
trend. Preserve the footnote distinguishing observed coverage from expected-hour
completeness. Fuel slicers from other pages must not filter demand through a
many-to-many fact relationship.

## SQL comparison

For the full frozen baseline, expected values are 3,579,543,533 MWh; 87,720
observed authority-hours; 5 reporting authorities; 87,502 eligible hours and
99.751482% observed demand coverage. For any selection, run:

```sql
SELECT SUM(observed_demand_mwh) AS demand_mwh,
       SUM(observed_authority_hours) AS observed_hours,
       COUNT(DISTINCT authority_key)
           FILTER (WHERE observed_authority_hours > 0) AS authorities,
       100.0 * SUM(eligible_demand_hours)
           / NULLIF(SUM(observed_authority_hours), 0) AS coverage_pct
FROM project_reporting.vw_q01_monthly_demand_energy
WHERE month_start >= DATE '2024-01-01'
  AND month_start < DATE '2026-01-01';
```

Repeat with CISO/January 2024, a single full year, both years, an empty
intersection and noncontiguous months. Validate chronological ordering and the
first/missing/zero-prior-month tooltip. A NULL energy result should display
blank/N/A, not a made-up zero. Required final integration checks are tracked in
`docs/phase3/README.md`.
