# Forecast review priority: CISO

Contributor: Muaz Fahad, 24L-2563. Source scope: five sampled authorities,
operating dates 2024-01-01 through 2025-12-31. Reviewer: Emaad (pending).

CISO has the highest pooled WAPE among the five sampled authorities:
**7.52%**, compared with **3.49%** for PJM. CISO's MAE is **1,922.25 MW**,
mean actual-minus-forecast bias **+1,385.54 MW**, and underforecast frequency
**74.49%**. These use the same **17,375 eligible pairs**; **169 observed
authority-hours** are excluded. WAPE is recalculated from the absolute-error
and actual-demand sums, rather than averaged across months.

The highest authority-month WAPE in the baseline is CISO in April 2025:
**10.03%**, with **720 eligible pairs and zero excluded pairs**. Its MAE is
**2,282.68 MW** and bias **+1,827.59 MW**. This is a descriptive result for the
publisher's historical forecast, which may contain revisions.

Recommend a forecast-review exercise focused on CISO's April profile and
hours with persistent positive error. Compare the next agreed evaluation
period using the same eligibility, WAPE, bias, pair count and exclusions.
Weather, original forecast publication versions, dispatch constraints and
causal drivers are not modeled; these findings do not establish why errors
occur or justify a capacity investment by themselves.

Q06 also identifies PJM summer 2024 local hour-ending 00 with mean positive
bias **9,048.92 MW** and **100% underforecast frequency across 92 pairs**.
Use this as a specific hour-profile follow-up, keeping the EIA operating-date
and midnight end-label convention. It is not a simultaneous regional peak.

Evidence: `insight_evidence.json`, `validation.json`, and the result CSVs in
this folder. Reproduce the monthly figures from
`project_reporting.vw_q05_forecast_accuracy`; recompute the authority figures
by summing its components first. The hour example comes from
`project_reporting.vw_q06_underforecast_pattern` with authority PJM, calendar
year 2024, season Summer and hour_ending 0.
