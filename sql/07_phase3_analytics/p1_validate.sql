-- Fails with an exception on any reconciliation error. No data is changed.
-- Dynamic comparisons work after legitimate source revisions as well.
DO $$
BEGIN
    IF (SELECT count(*) FROM project_reporting.vw_demand_observation)
       <> (SELECT count(*) FROM project_dw.fact_hourly_demand) THEN
        RAISE EXCEPTION 'Observation view lost or multiplied demand rows';
    END IF;

    IF EXISTS (
        SELECT authority_key, month_start FROM
            project_reporting.vw_q01_monthly_demand_energy
        GROUP BY authority_key, month_start HAVING count(*) <> 1
    ) THEN RAISE EXCEPTION 'Monthly view is not unique at declared grain'; END IF;

    IF EXISTS (
        WITH base AS (
            SELECT f.authority_key,
                   date_trunc('month', d.calendar_date)::date AS month_start,
                   count(*) AS n,
                   count(*) FILTER (WHERE f.actual_demand_mw >= 0) AS eligible,
                   sum(f.actual_demand_mw) FILTER (WHERE f.actual_demand_mw >= 0) AS energy
            FROM project_dw.fact_hourly_demand f
            JOIN project_dw.dim_date d USING (date_key)
            GROUP BY f.authority_key, date_trunc('month', d.calendar_date)::date
        )
        SELECT 1 FROM base b FULL JOIN
            project_reporting.vw_q01_monthly_demand_energy v
            USING (authority_key, month_start)
        WHERE coalesce(b.n, 0) IS DISTINCT FROM v.observed_authority_hours
           OR coalesce(b.eligible, 0) IS DISTINCT FROM v.eligible_demand_hours
           OR b.energy IS DISTINCT FROM v.observed_demand_mwh
    ) THEN RAISE EXCEPTION 'Q01 differs from independently grouped fact'; END IF;

    IF EXISTS (
        WITH base AS (
            SELECT f.authority_key,
                   date_trunc('month', d.calendar_date)::date AS month_start,
                   h.hour_ending, count(*) AS n,
                   count(*) FILTER (WHERE f.actual_demand_mw >= 0) AS eligible,
                   sum(f.actual_demand_mw) FILTER (WHERE f.actual_demand_mw >= 0) AS total,
                   avg(f.actual_demand_mw) FILTER (WHERE f.actual_demand_mw >= 0) AS mean
            FROM project_dw.fact_hourly_demand f
            JOIN project_dw.dim_date d USING (date_key)
            JOIN project_dw.dim_hour h USING (hour_key)
            GROUP BY f.authority_key, date_trunc('month', d.calendar_date)::date, h.hour_ending
        )
        SELECT 1 FROM base b FULL JOIN project_reporting.vw_q02_hourly_profile v
            USING (authority_key, month_start, hour_ending)
        WHERE b.n IS DISTINCT FROM v.observed_authority_hours
           OR b.eligible IS DISTINCT FROM v.eligible_demand_hours
           OR b.total IS DISTINCT FROM v.demand_sum_mw
           OR b.mean IS DISTINCT FROM v.mean_hourly_demand_mw
    ) THEN RAISE EXCEPTION 'Q02 differs from independently grouped fact'; END IF;

    IF EXISTS (
        SELECT 1 FROM project_reporting.vw_authority_analysis
        WHERE eligible_forecast_pairs + excluded_forecast_pairs <> observed_authority_hours
           OR eligible_demand_hours + null_actual_hours + negative_actual_hours
                <> observed_authority_hours
           OR underforecast_pairs > eligible_forecast_pairs
           OR (eligible_forecast_pairs = 0 AND forecast_wape_pct IS NOT NULL)
           OR (eligible_demand_hours = 0 AND observed_demand_mwh IS NOT NULL)
    ) THEN RAISE EXCEPTION 'Eligibility, null or pair-count contract failed'; END IF;

    IF EXISTS (
        SELECT 1 FROM project_reporting.vw_q01_monthly_demand_energy
        WHERE (previous_month_demand_mwh IS NULL OR previous_month_demand_mwh = 0)
          AND demand_mom_growth_pct IS NOT NULL
    ) THEN RAISE EXCEPTION 'MoM zero/missing prior denominator not guarded'; END IF;

    RAISE NOTICE 'PASS: observation grain, Q01, Q02, eligibility and MoM guards';
END $$;
