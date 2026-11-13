-- Load hour dimension
INSERT INTO project_dw.dim_hour (hour_ending, hour_label)
SELECT h, LPAD(h::text, 2, '0')
FROM generate_series(0, 23) AS h
ON CONFLICT (hour_ending) DO UPDATE
SET hour_label = EXCLUDED.hour_label;
