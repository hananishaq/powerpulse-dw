-- Load date dimension; weekday_number uses ISO numbering: Monday=1, Sunday=7
INSERT INTO project_dw.dim_date (
    calendar_date,
    calendar_year,
    quarter_number,
    month_number,
    iso_week_year,
    iso_week_number,
    weekday_number,
    season
)
SELECT DISTINCT
    data_date,
    EXTRACT(YEAR FROM data_date)::smallint,
    EXTRACT(QUARTER FROM data_date)::smallint,
    EXTRACT(MONTH FROM data_date)::smallint,
    EXTRACT(ISOYEAR FROM data_date)::smallint,
    EXTRACT(WEEK FROM data_date)::smallint,
    EXTRACT(ISODOW FROM data_date)::smallint,
    CASE
        WHEN EXTRACT(MONTH FROM data_date) IN (12, 1, 2) THEN 'Winter'
        WHEN EXTRACT(MONTH FROM data_date) IN (3, 4, 5) THEN 'Spring'
        WHEN EXTRACT(MONTH FROM data_date) IN (6, 7, 8) THEN 'Summer'
        ELSE 'Autumn'
    END
FROM project_staging.stg_eia930_balance_clean
ON CONFLICT (calendar_date) DO UPDATE
SET calendar_year = EXCLUDED.calendar_year,
    quarter_number = EXCLUDED.quarter_number,
    month_number = EXCLUDED.month_number,
    iso_week_year = EXCLUDED.iso_week_year,
    iso_week_number = EXCLUDED.iso_week_number,
    weekday_number = EXCLUDED.weekday_number,
    season = EXCLUDED.season;
