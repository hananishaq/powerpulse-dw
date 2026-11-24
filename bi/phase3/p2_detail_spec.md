# Detailed Analysis page specification

Owner: Hanan Ishaq, 24L-2537. Reviewer: Muaz Fahad.

This page uses Hanan's Q03 and Q04 views, Mohid's authority analysis contract,
and two explicit teammate dependencies. It is an integration specification for
Emaad's master PBIX. Database credentials stay in Power BI's local data-source
settings and never enter the repository.

## Data sources and grain

| Model table | PostgreSQL source | Grain |
|---|---|---|
| MonthlyPeak | `project_reporting.vw_q03_monthly_peaks` | Authority, operating month, tied peak UTC timestamp |
| SeasonalProfile | `project_reporting.vw_q04_month_daytype` | Authority, operating month, weekday/weekend; includes calendar year and season |
| AuthorityAnalysis | `project_reporting.vw_authority_analysis` | Authority and operating month |
| ForecastPerformance | `project_reporting.vw_q05_forecast_accuracy` | Authority and operating month |
| FuelComposition | Emaad generation reporting view | Authority, UTC hour, mapped source category |

Create shared `Authority` and `CalendarMonth` dimensions. Use single-direction
one-to-many relationships from dimensions to facts. Keep generation and demand
tables unrelated at fact level. Any combined generation/demand table must first
aggregate generation to authority and UTC hour.

Connect `CalendarMonth[month_start]` (unique, DATE, first day of each month)
to `SeasonalProfile[month_start]`, `MonthlyPeak[month_start]`, and
`AuthorityAnalysis[month_start]` with active one-to-many, single-direction
relationships. Connect `Authority[authority_key]` to each table's authority
key. Reuse the Executive Overview's shared month dimension (named `Month` in
Mohid's source model) when integrating; do not create disconnected duplicate
month slicers. Use year, month and season fields from that month dimension
and authority/region fields from `Authority` for shared slicers.
If the shared month dimension has no season column, add one using its
operating `month_number`: 12/1/2 = Winter, 3/4/5 = Spring, 6/7/8 = Summer,
9/10/11 = Autumn. Keep the calendar year unchanged for December.

The original `vw_q04_season_daytype` remains the full-season SQL output and a
reconciliation reference. Import the monthly view for `SeasonalProfile`:
the seasonal output has already combined months and cannot respond to a
month selection. Keep the existing DAX below; summed monthly components
recalculate the mean for the selected months, seasons and day types.

`MonthlyPeak[utc_hour_end]` is the observation key. Display it in UTC and show
`local_hour_end` plus `utc_offset_minutes` in tooltips. A month can contain more
than one row when peak MW is tied. `SeasonalProfile[calendar_year]` comes from
the publisher's operating date. Winter 2025 contains January, February, and
December 2025.

## Measures

Use explicit measures. Format MW and MWh as whole numbers with thousands
separators. Format percentages with two decimal places.

```DAX
Observed Demand MWh =
SUM ( SeasonalProfile[demand_sum_mw] )

Eligible Demand Hours =
SUM ( SeasonalProfile[eligible_demand_hours] )

Observed Authority Hours =
SUM ( SeasonalProfile[observed_authority_hours] )

Mean Demand MW =
DIVIDE ( [Observed Demand MWh], [Eligible Demand Hours] )

Observed Demand Coverage =
DIVIDE ( [Eligible Demand Hours], [Observed Authority Hours] )

Peak Demand MW =
MAX ( MonthlyPeak[peak_actual_demand_mw] )

Selected Mean Demand MW =
DIVIDE (
    SUM ( AuthorityAnalysis[observed_demand_mwh] ),
    SUM ( AuthorityAnalysis[eligible_demand_hours] )
)

Selected Demand Segment =
VAR MeanMW = [Selected Mean Demand MW]
RETURN
    SWITCH (
        TRUE (),
        ISBLANK ( MeanMW ), "No eligible demand",
        MeanMW < 10000, "Below 10 GW",
        MeanMW < 30000, "10 to below 30 GW",
        "30 GW or above"
    )
```

Muaz's Q05 view supplies the additive forecast components below. Connect
`ForecastPerformance[month_start]` to the shared month dimension and its
authority key to `Authority`. Recalculate both metrics after filtering.
See `docs/phase3/muaz_forecast_performance.md` for the Q06 monthly/hour input,
eligibility, validated results and full measure handoff. Emaad's acceptance
and native master PBIX integration remain pending.

```DAX
Forecast MAE MW =
DIVIDE (
    SUM ( ForecastPerformance[abs_error_sum_mw] ),
    SUM ( ForecastPerformance[eligible_forecast_pairs] )
)

Forecast WAPE =
DIVIDE (
    SUM ( ForecastPerformance[abs_error_sum_mw] ),
    SUM ( ForecastPerformance[eligible_actual_sum_mw] )
)
```

## Page layout

Use a 1280 by 720 canvas. Follow the master report's typography and navigation.
The visual order below also defines keyboard and reading order.

| Visual | Title | Fields and measures | Sorting and tooltips |
|---|---|---|---|
| Slicers | Operating period and authority | Year, month, authority, region, season, day type | Year then month ascending. Multi-select enabled |
| Clustered bar | Mean demand by authority and region | Axis authority, small multiple or legend region, value `Mean Demand MW` | Descending mean. Tooltip eligible hours, observed hours, coverage |
| Clustered column | Seasonal weekday and weekend profile | Axis season, legend day type, value `Mean Demand MW` | Winter, Spring, Summer, Autumn. Tooltip demand MWh and eligible hours |
| Line with markers | Monthly peak demand | Axis month start, value `Peak Demand MW`, small multiple authority | Month ascending. Tooltip UTC timestamp, local timestamp, offset, tie count, coverage |
| Table | Authority planning segment | Authority, `Selected Mean Demand MW`, `Selected Demand Segment`, coverage | Mean descending. Conditional color by agreed segment |
| Combo chart | Forecast error | Authority on axis, MAE MW columns, WAPE line | Depends on Muaz Q05. Tooltip pair count and excluded-pair count |
| 100% stacked bar | Fuel composition | Authority on axis, source group legend, signed generation MWh value | Depends on Emaad. Show signed MWh tooltip and observation count |

The monthly peak line uses `MAX`, so tied peak rows do not double the MW value.
Add a drill-through table listing every tied UTC timestamp. Never sum peak MW
across months or authorities.

## Slicer interactions

- Year, month, authority, and region filter all demand visuals.
- Season and day type filter the seasonal profile and authority comparison.
- Season comes from the shared month dimension. Day type comes from
  `SeasonalProfile` and filters the two profile visuals only; the monthly
  segmentation, peak and forecast inputs do not support a day-type filter.
  In Power BI Edit interactions, disable the day-type slicer's interaction
  with those other visuals.
- Season can filter the fuel visual only when Emaad exposes the same operating
  date semantics.
- Fuel categories filter only generation visuals.
- Selecting an authority cross-highlights peak, profile, segmentation, forecast,
  and fuel visuals through the shared authority dimension.
- Enable the forecast visual after Emaad accepts the supplied Q05 view and
  validates its measures against SQL under the same slicers.

## Validation SQL

Validate the PJM 2025 summer profile shown on the page.

```sql
SELECT day_type,
       sum(observed_authority_hours) AS observed_authority_hours,
       sum(eligible_demand_hours) AS eligible_demand_hours,
       sum(demand_sum_mw) AS demand_sum_mw,
       sum(demand_sum_mw) / NULLIF(sum(eligible_demand_hours), 0) AS mean_demand_mw,
       100.0 * sum(eligible_demand_hours)
           / NULLIF(sum(observed_authority_hours), 0) AS observed_demand_coverage_pct
FROM project_reporting.vw_q04_month_daytype
WHERE authority_code = 'PJM'
  AND calendar_year = 2025
  AND season = 'Summer'
GROUP BY day_type
ORDER BY day_type;
```

Expected means are 109,686.3455 MW for weekdays and 100,980.6543 MW for
weekends. Both cohorts have 100% eligible coverage among their 1,560 and 648
observed records.

For the month-filter acceptance check, add
`AND month_start = DATE '2025-06-01'` to that query. Compare its sums, counts,
mean and coverage with a direct demand-fact query restricted to PJM and
June 2025 operating dates. Selecting June must show June observations only,
not the June-August seasonal total. Repeat with June and August together,
both years, and a season/month combination with no matching observations.
For the empty combination, the mean and coverage must be blank/N/A.

Validate the peak visual and its timestamp.

```sql
SELECT authority_code, month_start, peak_actual_demand_mw,
       utc_hour_end AT TIME ZONE 'UTC' AS utc_hour_end,
       local_hour_end, utc_offset_minutes, tied_peak_timestamp_count,
       observed_authority_hours, eligible_demand_hours
FROM project_reporting.vw_q03_monthly_peaks
WHERE authority_code = 'PJM'
  AND month_start = DATE '2025-06-01';
```

Expected peak is 160,560 MW at 2025-06-23 22:00 UTC and 18:00 local with a
-240 minute offset. June has 720 observed and eligible hours.

For every page selection, compare `Mean Demand MW` with
`SUM(demand_sum_mw) / NULLIF(SUM(eligible_demand_hours), 0)`. Compare forecast
measures from their components and compare fuel totals with Emaad's signed
generation query.

## Limitations

- Coverage is eligibility among existing demand rows. Expected-hour completeness
  remains a separate grid check.
- Peak timestamps describe individual authorities. Peaks across authorities are
  not simultaneous regional power unless aligned by UTC before aggregation.
- The dataset has no tied authority-month maximum, although Q03 and its fixture
  retain every tie.
- Winter labels stay within an operating calendar year.
- Signed generation includes negative storage and balancing observations.
- Source data covers five authorities for 2024 and 2025. It is not a complete
  national market or a causal model.
- Forecast SQL is supplied; native forecast-visual integration and acceptance
  remain pending with Emaad. Fuel composition
  depends on Emaad's mapped generation view and master model integration.
