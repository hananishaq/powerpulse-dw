CREATE INDEX IF NOT EXISTS idx_demand_authority_key
    ON project_dw.fact_hourly_demand(authority_key);
CREATE INDEX IF NOT EXISTS idx_demand_date_key
    ON project_dw.fact_hourly_demand(date_key);
CREATE INDEX IF NOT EXISTS idx_demand_hour_key
    ON project_dw.fact_hourly_demand(hour_key);
CREATE INDEX IF NOT EXISTS idx_demand_snapshot_key
    ON project_dw.fact_hourly_demand(source_snapshot_key);

CREATE INDEX IF NOT EXISTS idx_generation_authority_key
    ON project_dw.fact_hourly_generation(authority_key);
CREATE INDEX IF NOT EXISTS idx_generation_date_key
    ON project_dw.fact_hourly_generation(date_key);
CREATE INDEX IF NOT EXISTS idx_generation_hour_key
    ON project_dw.fact_hourly_generation(hour_key);
CREATE INDEX IF NOT EXISTS idx_generation_energy_source_key
    ON project_dw.fact_hourly_generation(energy_source_key);
CREATE INDEX IF NOT EXISTS idx_generation_snapshot_key
    ON project_dw.fact_hourly_generation(source_snapshot_key);

CREATE INDEX IF NOT EXISTS idx_expected_hour_grid_utc_hour_end
    ON project_dw.expected_hour_grid(utc_hour_end);
