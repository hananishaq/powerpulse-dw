-- Load balancing authority dimension
INSERT INTO project_dw.dim_balancing_authority (
    authority_code,
    authority_name,
    region_code,
    region_name
)
SELECT
    authority_code,
    authority_name,
    region_code,
    region_name
FROM project_staging.stg_authority_reference
ON CONFLICT (authority_code) DO UPDATE
SET authority_name = EXCLUDED.authority_name,
    region_code = EXCLUDED.region_code,
    region_name = EXCLUDED.region_name;
