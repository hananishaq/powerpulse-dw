# Peak and seasonal demand insight

Contributor: Hanan Ishaq, 24L-2537. Verified on 24 November 2026.

PJM's mean demand during summer 2025 weekdays was **109,686.35 MW**, compared
with **100,980.65 MW** on summer weekends. The weekday cohort was therefore
**8,705.69 MW higher**, an **8.62% premium** relative to the weekend mean.
Both cohorts had complete eligible-demand coverage among their observed rows,
with 1,560 weekday hours and 648 weekend hours.

PJM also recorded the largest authority-month peak in the two-year dataset.
The peak was **160,560 MW** at **18:00 local time on 23 June 2025**, corresponding
to **22:00 UTC** with a -240 minute offset. All 720 June observations were
eligible. This timestamp belongs to one authority and should not be described as
a simultaneous five-region peak.

## Reproduction

```sql
SELECT day_type, eligible_demand_hours, mean_demand_mw,
       observed_demand_coverage_pct
FROM project_reporting.vw_q04_season_daytype
WHERE authority_code = 'PJM'
  AND calendar_year = 2025
  AND season = 'Summer'
ORDER BY day_type;

SELECT peak_actual_demand_mw,
       utc_hour_end AT TIME ZONE 'UTC' AS utc_hour_end,
       local_hour_end, utc_offset_minutes,
       observed_authority_hours, eligible_demand_hours
FROM project_reporting.vw_q03_monthly_peaks
WHERE authority_code = 'PJM'
  AND month_start = DATE '2025-06-01';
```

The Q03 and Q04 validation block independently reconciled these views to the
demand fact. The Q03 tie fixture retained both timestamps sharing a maximum.

## Decision contribution

Use the measured weekday uplift and June peak timestamp as inputs to PJM summer
planning reviews. Compare them with Muaz's forecast-error metrics before drawing
conclusions about forecast risk or resource adequacy. Weather, capacity, market
conditions, and causal drivers are outside this dataset.
