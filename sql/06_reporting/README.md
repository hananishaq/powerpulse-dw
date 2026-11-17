# Reporting - Mohid

`00_base_views.sql` exposes detail, authority/hour fuel summaries, demand comparison and independently expected hours. `10_business_question_views.sql` implements Q01-Q10. The normal integration and quality runners install both files.

Generation is summarized before demand comparisons. Forecast metrics share one eligibility set; WAPE combines sums. Shares disclose eligible/excluded hours and category versions. Peak timestamps retain ties, absent ratios return NULL and all-null fuels remain visible without zero-fill.

Source locators appear in detail views and aggregated outputs expose version strings and observation counts. Q10 separates absent rows, missing measures and invalid/zero/negative observations. Header availability by source snapshot is retained in the DQ input audit. See root README for the view catalog and controls.
