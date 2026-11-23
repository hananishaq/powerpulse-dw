# Hanan Phase 3 handoff

Owner: Hanan Ishaq, 24L-2537. Reviewer: Muaz Fahad.

## Muaz

- Review `p2_q03_q04.sql` and confirm Q03/Q04 eligibility matches the shared
  demand contract.
- Use the accepted Q05 additive components for MAE and WAPE. Hanan's BI spec
  recalculates both metrics after filters.
- Compare high-error periods with Q03 peak timestamps without joining forecast
  rows at a different grain.

## Emaad

- Install `p2_profile_views.sql` after `p1_demand_views.sql`.
- Import Q03 and Q04 at their declared grains into the Detailed Analysis page.
- Use shared authority and calendar dimensions. Keep demand and generation facts
  separated.
- Integrate the visual and DAX contract in `bi/phase3/p2_detail_spec.md`.
- Supply the generation view required for fuel composition. Preserve signed MWh
  and mapped source groups.

## Qasim

- Use `business_insight.md` as Hanan's checked contribution to the Business
  Insights report.
- Use `presentation/phase3/PowerPulse_Peak_Demand_OLAP_Analysis.pptx` or the companion Markdown
  slide source when assembling the final deck.
- Preserve the five-authority, 2024-2025 scope and the distinction between an
  authority peak and a simultaneous regional peak.
- The OLAP examples use operating year 2025. ROLLUP returns 45 detail rows, 42
  source-group subtotals, 5 regional subtotals, and 1 grand total. CUBE returns
  20 region-season details, 5 region totals, 4 season totals, and 1 grand total.

## Reproducible run order

1. Run `sql/06_reporting/p1_demand_views.sql`.
2. Run `sql/06_reporting/p2_profile_views.sql`.
3. Run `sql/07_phase3_analytics/p2_q03_q04.sql`.
4. Run both scripts in `sql/08_phase3_olap/`.
5. Compare the output with `reports/phase3/hanan/validation.json`.
