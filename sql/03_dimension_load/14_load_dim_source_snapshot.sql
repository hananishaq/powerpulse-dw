-- Load immutable source snapshot dimension
INSERT INTO project_dw.dim_source_snapshot (
    file_name,
    source_url,
    sha256,
    retrieved_at_utc,
    source_row_count
)
SELECT
    file_name,
    source_url,
    sha256,
    retrieved_at_utc,
    source_row_count
FROM project_staging.stg_source_file
ON CONFLICT (file_name, sha256) DO NOTHING;
