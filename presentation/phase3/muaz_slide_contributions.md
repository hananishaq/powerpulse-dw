# Muaz: two slide drafts for Qasim

These are source drafts for the final PowerPoint, with editable chart data and
speaker notes. They are not a rendered or desktop-validated presentation.

## Slide 1 — CISO has the highest relative forecast error in the sample

Horizontal bar chart: pooled 2024-2025 WAPE %, sorted descending.

| Authority | WAPE % | Eligible pairs | Excluded hours |
|---|---:|---:|---:|
| CISO | 7.517648 | 17,375 | 169 |
| PJM | 3.488938 | 17,471 | 73 |
| NYIS | 3.254310 | 17,539 | 5 |
| ISNE | 2.454234 | 17,542 | 2 |
| ERCO | 2.308219 | 17,472 | 72 |

Callout: CISO April 2025 WAPE 10.03%; bias +1,827.59 MW; 720 pairs, 0 excluded.
Action: review the CISO April/hour profile and track WAPE and bias under the
same eligibility in the next agreed evaluation period.

Speaker notes: Forecast eligibility is actual > 0 and forecast >= 0, both present.
Positive actual-minus-forecast bias means underforecast. WAPE uses pooled
sums; it is not the average of monthly percentages. The source contains the
publisher's historical forecasts, potentially revised. Five authorities are a
limited sample, and this analysis does not establish causes.

Source: `reports/phase3/muaz/insight_evidence.json`; Q05/Q06 views.

## Slide 2 — Covering indexes improve the two selective query cases

Grouped horizontal bars: before/after median execution ms from the measured
benchmark. Use a separate panel for the broad CUBE so the scales stay readable.
Read exact values from `reports/phase3/performance/summary.json` and use the
Indexing Report's table; do not copy timings from an older experiment.

Show each query's estimated cost and index-used indicator beside its bars.
Footnote: 1 warm-up + 5 measurements per arm; warm cache; same data, SQL and
settings; all result checksums unchanged. Both candidates were tested together
on a disposable database and rolled back afterward.

Speaker notes: The authority/date demand index and source/date/authority
generation index include their required measure columns. Report measured
storage and acknowledge unmeasured write-maintenance overhead. The broad
CUBE uses no candidate index and has unchanged planner cost; a small timing
difference is not strong evidence of a speed change. Seven duplicate-index
groups remain in the baseline and require separate reviewed cleanup.

Source: `reports/phase3/Indexing_Report.pdf`, all 30 raw runs and saved JSON plans.
