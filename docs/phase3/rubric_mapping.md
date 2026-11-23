# Phase 3 rubric mapping

The assignment uses retail examples. PowerPulse's approved Phase 1 design is
an electricity warehouse, with no revenue, orders or customers. This package
uses domain labels and does not invent retail measures.

| Brief item | PowerPulse implementation | Owner / status |
|---|---|---|
| SUM / AVG / COUNT | Q01/Q02 analytical SQL and direct fact demonstration | Mohid implemented |
| Monthly sales / `vw_monthly_sales` | Compatibility alias of `vw_q01_monthly_demand_energy`, MWh and trend | Mohid implemented |
| Customer analysis / `vw_customer_analysis` | Compatibility alias of `vw_authority_analysis`, authority/month planning segments | Mohid implemented |
| Revenue KPI | Observed demand energy, MWh | Mohid overview |
| Orders KPI | Observed authority-hour records | Mohid overview |
| Customers KPI | Distinct authorities with observations in the current selection | Mohid overview |
| Product analysis / `vw_product_performance` | Q07 original fuel category and mapped source group | Emaad integration item |
| Regional analysis | Region/authority comparison of the five sampled BAs | Hanan integration item |
| ROLLUP / CUBE | Generation hierarchy and demand cross-tab | Hanan integration item |
| Before/after EXPLAIN ANALYZE and index report | Measured comparison of identical queries | Muaz integration item |
| Three dashboard pages | Mohid supplies Executive Overview; Emaad integrates all pages | Team integration item |
| Business decisions / final report | Mohid supplies a checked demand finding | Qasim assembles |

Both reporting aliases owned by Mohid now use the handout's literal view names.
Their comments and columns identify the electricity interpretation. Revenue,
customer and order data are absent from the approved source, so the Executive
Overview labels its KPIs as demand energy, observed hours and reporting
authorities. This mapping is explicit; no instructor approval is claimed.
No empty product view or fabricated retail data is included.

The Phase 3 deliverables remain analytical SQL, OLAP SQL, reporting SQL, Indexing
Report PDF, dashboard PBIX, Dashboard Screenshots PDF, Business Insights PDF and
final PowerPoint. Mohid's contribution is one part of this shared submission.
