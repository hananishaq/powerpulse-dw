-- Muaz candidate experiments, PostgreSQL 16+. Re-runnable.
-- Execute only on the disposable benchmark database until results are reviewed.
-- Existing PK/UNIQUE and duplicate baseline indexes are preserved for comparison.
CREATE INDEX IF NOT EXISTS idx_p3_demand_authority_date
    ON project_dw.fact_hourly_demand (authority_key, date_key)
    INCLUDE (actual_demand_mw);

CREATE INDEX IF NOT EXISTS idx_p3_generation_source_date_authority
    ON project_dw.fact_hourly_generation (energy_source_key, date_key, authority_key)
    INCLUDE (generation_mw);
