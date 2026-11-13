CREATE TABLE IF NOT EXISTS project_dw.expected_hour_grid (
    authority_key BIGINT NOT NULL REFERENCES project_dw.dim_balancing_authority(authority_key),
    utc_hour_end TIMESTAMPTZ NOT NULL,
    PRIMARY KEY (authority_key, utc_hour_end)
);

INSERT INTO project_dw.expected_hour_grid (authority_key, utc_hour_end)
SELECT
    authority_key,
    generate_series(
        MIN(utc_hour_end),
        MAX(utc_hour_end),
        INTERVAL '1 hour'
    ) AS utc_hour_end
FROM project_dw.fact_hourly_demand
GROUP BY authority_key
ON CONFLICT (authority_key, utc_hour_end) DO NOTHING;

DELETE FROM project_dw.expected_hour_grid g
WHERE NOT EXISTS (
    SELECT 1
    FROM project_dw.fact_hourly_demand f
    WHERE f.authority_key = g.authority_key
      AND g.utc_hour_end BETWEEN (
          SELECT MIN(f2.utc_hour_end)
          FROM project_dw.fact_hourly_demand f2
          WHERE f2.authority_key = g.authority_key
      ) AND (
          SELECT MAX(f3.utc_hour_end)
          FROM project_dw.fact_hourly_demand f3
          WHERE f3.authority_key = g.authority_key
      )
);
