# Hanan slide contributions

## Slide 1 — Peak and seasonal demand

Title: **PJM summer demand is higher on weekdays**

- 2025 summer weekday mean: **109,686 MW**
- 2025 summer weekend mean: **100,981 MW**
- Weekday premium: **8,706 MW / 8.62%**
- Largest authority-month peak: **160,560 MW**
- Peak timestamp: **23 June 2025, 18:00 local / 22:00 UTC**

Visual: clustered bars for weekday and weekend mean MW by authority, with PJM
highlighted. Add a peak callout and the coverage note. PJM cohorts and June peak
month have 100% eligible coverage among observed rows.

Speaker note: Q04 uses source operating dates and calendar-year meteorological
seasons. Q03 keeps UTC and local labels and preserves tied maxima. The peak is
an authority observation and is not a simultaneous multi-region total.

## Slide 2 — PostgreSQL ROLLUP and CUBE

Title: **OLAP queries expose hierarchy and cross-tab totals safely**

- ROLLUP hierarchy: region → source group → source label
- ROLLUP rows: **45 detail + 42 group + 5 region + 1 grand total**
- 2025 signed generation grand total: **1,781,305,931 MWh**
- CUBE dimensions: region × season
- CUBE rows: **20 detail + 5 region + 4 season + 1 grand total**
- 2025 demand grand total: **1,816,431,180 MWh** from **43,677** eligible hours

Visual: a three-level hierarchy beside a four-cell grouping-level matrix.
Include `GROUPING()` labels and the independent grand-total reconciliation.

Speaker note: Generation remains signed. CUBE means come from the underlying
eligible observations, never averages of subgroup means.
