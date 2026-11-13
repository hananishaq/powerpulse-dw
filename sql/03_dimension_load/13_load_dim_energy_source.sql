-- Load energy source dimension
INSERT INTO project_dw.dim_energy_source (
    source_column,
    source_label,
    source_group
)
SELECT
    source_column,
    source_label,
    source_group
FROM project_staging.stg_energy_source_mapping
ON CONFLICT (source_column) DO UPDATE
SET source_label = EXCLUDED.source_label,
    source_group = EXCLUDED.source_group;
