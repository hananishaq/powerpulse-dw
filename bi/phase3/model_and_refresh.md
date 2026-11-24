# PowerPulse Phase 3 Power BI project

Open [PowerPulse_Phase3.pbip](PowerPulse_Phase3.pbip) in a recent Power BI
Desktop on Windows with Power BI Project and enhanced report format support.
The project includes Executive Overview, Detailed Analysis, and Decision Page.
Keep the two sibling project directories beside the PBIP when copying it.

## Warehouse setup and refresh

1. Load the warehouse with `python etl/run_all.py`, then install and reconcile all
   reporting views with `python etl/08_run_phase3_final.py`.
2. Open the PBIP. In **Transform data → Edit parameters**, set `PgServer`
   (default `localhost`, use `hostname:port` for a non-default port) and
   `PgDatabase` (default `powerpulse_dw`). The model uses PostgreSQL Import.
3. Apply changes and refresh. Enter your warehouse credentials in Desktop's
   Data Source Settings. The account needs read access to the listed objects.
   Keep credentials, caches and local database files out of Git.
4. Compare cards and selected views with
   [the SQL acceptance evidence](../../reports/phase3/final/validation.json).
   Select PJM and June 2025, then add August 2025. Check that month, authority,
   profile, fuel, forecast, and quality results follow the shared filters.
5. Use **File → Save As → Power BI Desktop file** to save
   `bi/phase3/PowerPulse_Phase3.pbix`. Open that saved file and refresh again.
   Clear the filters and export the report to PDF for
   `reports/phase3/final/Dashboard_Screenshots.pdf` after checking all three pages.

## Tables and filter behavior

| Table | PostgreSQL object |
|---|---|
| Authority | `project_dw.dim_balancing_authority` |
| Month | `project_reporting.vw_dashboard_month` |
| MonthlyDemand | `project_reporting.vw_authority_analysis` |
| MonthlyPeak | `project_reporting.vw_dashboard_peak` |
| SeasonalProfile | `project_reporting.vw_q04_month_daytype` |
| ForecastPerformance | `project_reporting.vw_q05_forecast_accuracy` |
| ForecastPattern | `project_reporting.vw_forecast_month_hour_components` |
| Fuel | `project_reporting.vw_q07_generation_by_source` |
| Renewables | `project_reporting.vw_q08_wind_solar_share` |
| HighDemandMix | `project_reporting.vw_q09_high_demand_mix` |
| Quality | `project_reporting.vw_q10_source_quality` |

Authority and Month filter the facts through one-to-many, single-direction
relationships. The day-type slicer is on SeasonalProfile. It filters the two
profile charts without propagating upstream to Month or Authority. Power and
energy are labeled MW and MWh respectively. Fuel charts use signed values and
a regular axis. Q09 divides summed group energy by the signed total for each
unique authority-month-cohort, avoiding repeated denominator rows. Q08 divides
matched wind plus solar energy by matched reported total generation. SQL
percentage points and DAX percentage formats use different scaling.

Emaad opened and refreshed the report in Power BI Desktop on Windows. All
three pages populated, and the Executive Overview showed 720 authority-hours
and one reporting authority for PJM in June 2025. The repository includes the
[saved PBIX](PowerPulse_Phase3.pbix) and the
[three-page Desktop export](../../reports/phase3/final/Dashboard_Screenshots.pdf).
