# PowerPulse Phase 3 evaluation package

The project analyzes EIA-930 records from five U.S. balancing authorities for
2024–2025. Electricity demand, operating-hour records and authorities are the
domain equivalents of the retail KPI examples in the lab brief. The project
contains no modeled sales transactions.

## Submission inventory

| Required deliverable | Repository path |
|---|---|
| Analytical SQL | [Q01–Q10](../../sql/07_phase3_analytics/) |
| OLAP SQL | [Generation ROLLUP and demand CUBE](../../sql/08_phase3_olap/) |
| Reporting SQL | [Reporting views](../../sql/06_reporting/) |
| Indexing Report | [Indexing_Report.pdf](../../reports/phase3/Indexing_Report.pdf) |
| Power BI Dashboard | [PowerPulse_Phase3.pbix](../../bi/phase3/PowerPulse_Phase3.pbix), [editable PBIP source](../../bi/phase3/PowerPulse_Phase3.pbip), and [refresh guide](../../bi/phase3/model_and_refresh.md) |
| Dashboard Screenshots | [Dashboard_Screenshots.pdf](../../reports/phase3/final/Dashboard_Screenshots.pdf), exported from Power BI Desktop |
| Business Insights Report | [Business_Insights_Report.pdf](../../reports/phase3/final/Business_Insights_Report.pdf) |
| Final Presentation | [PowerPulse_Final_Presentation.pptx](../../presentation/phase3/PowerPulse_Final_Presentation.pptx) |

## Reproduce

Run from the repository root after creating `powerpulse_dw` and setting local
connection parameters in `.env`.

```text
python -m pip install -r requirements.txt
python etl/run_all.py
python etl/08_run_phase3_final.py
```

Open the analytical SQL files individually to show their result sets. Start
the demo on the Executive Overview, show the monthly and authority filters on
Detailed Analysis, then use Decision Page to discuss PJM peak-readiness and the
fuel-data caveats. [Measured SQL results and filter checks](../../reports/phase3/final/validation.json)
provide evaluation baselines. The runner installs only reporting views in one
transaction and rolls back on reconciliation failure. It applies no benchmark
indexes and changes no staged or warehouse facts.

## Emaad and Qasim contributions

- Emaad's reporting files add Q07 signed monthly fuel observations and Q08
  wind/solar share. The hourly generation helper uses authority plus UTC hour,
  and source applicability uses manifest headers keyed by publication SHA-256.
  Legacy combined wind and solar labels and later storage-split labels retain
  their original meanings. Missing components remain missing. A match requires
  wind and solar observations, positive reported total and an available-fuel
  residual within the project's threshold.
- Qasim's files add Q09 demand cohorts and Q10 quality diagnostics. Q09 defines
  high demand at or above each authority-month's 90th percentile of positive
  observed demand. Its mix is descriptive and retains negative net generation.
  Q10 uses the expected UTC grid, preserves absent rows separately from missing
  measures and distinguishes supplied blanks from absent headers. The grid
  covers the observed authority bounds and cannot identify leading or trailing
  gaps outside those bounds.
- Emaad's review of Muaaz's package checked that Q05 uses sums from the same
  eligible pairs as authority analysis. The supplied indexing benchmark used
  identical results before and after indexing, five warm-cache measurements
  per arm and retained raw plans. Selective demand and fuel queries benefited
  in that environment. The broad demand CUBE used neither candidate index
  and showed no comparable improvement. The candidates remain optional.
- Mohid's formal Phase 2 quality package is on
  [mohid/phase2-quality-reporting](https://github.com/hananishaq/powerpulse-dw/tree/mohid/phase2-quality-reporting).
  The branch was checked independently with a fresh PostgreSQL 16.2 warehouse
  and passed all 61 checks, including its negative tests. Its scripts and
  alternate reporting views were kept on their existing branch.
- SQL installation, rerun and fact reconciliation passed. Emaad refreshed the
  report in Power BI Desktop on Windows, confirmed that the PJM June 2025
  selection showed 720 authority-hours and one reporting authority, and saved
  the native PBIX and screenshot PDF. The PDF confirms all three pages and the
  full-selection baseline totals. Independent teammate sign-off was not recorded.

## Source interpretation

Fuel shares use observed signed generation. A missing fuel value can constrain
interpretation without causing a large reconciliation residual. The fixed
residual threshold is a project diagnostic. The sample supports review of
forecast error, seasonal demand and reporting coverage. Resources, reserve
margins, market costs and causal drivers are outside the source data.
