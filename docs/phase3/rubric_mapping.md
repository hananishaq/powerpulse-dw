# Phase 3 rubric mapping

The assignment uses retail examples. PowerPulse's approved Phase 1 design is
an electricity warehouse, with no revenue, orders or customers. This package
uses domain labels and does not invent retail measures.

| Brief item | PowerPulse implementation | Owner / status |
|---|---|---|
| SUM / AVG / COUNT | Q01/Q02 analytical SQL and direct fact demonstration | Mohid implemented |
| Monthly sales / `vw_monthly_sales` | `vw_q01_monthly_demand_energy`, MWh and trend | Mohid implemented |
| Customer analysis / `vw_customer_analysis` | `vw_authority_analysis`, authority/month demand and error segments | Mohid implemented |
| Revenue KPI | Observed demand energy, MWh | Mohid overview |
| Orders KPI | Observed authority-hour records | Mohid overview |
| Customers KPI | Distinct authorities with observations in the current selection | Mohid overview |
| Product analysis / `vw_product_performance` | Q07 original fuel category and mapped source group | Emaad integration item |
| Regional analysis | Region/authority comparison of the five sampled BAs | Hanan integration item |
| ROLLUP / CUBE | Generation hierarchy and demand cross-tab | Hanan integration item |
| Before/after EXPLAIN ANALYZE and index report | Measured comparison of identical queries | Muaz integration item |
| Three dashboard pages | Mohid supplies Executive Overview; Emaad integrates all pages | Team integration item |
| Business decisions / final report | Mohid supplies a checked demand finding | Qasim assembles |

**Instructor confirmation remains pending.** The repository has no recorded
approval of the retail-to-electricity naming substitutions. Obtain that decision
before the final submission. If literal view names are required, add documented
compatibility aliases only after the corresponding domain views exist. Keep
electricity column names and units. No empty product view or fabricated retail
data is included merely to satisfy a filename.

The Phase 3 deliverables remain analytical SQL, OLAP SQL, reporting SQL, Indexing
Report PDF, dashboard PBIX, Dashboard Screenshots PDF, Business Insights PDF and
final PowerPoint. Mohid's contribution is one part of this shared submission.
