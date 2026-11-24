-- Muaz: fail-on-error validation, no changes to warehouse data.
DO $$
BEGIN
    IF EXISTS (
        WITH expected AS (
            SELECT f.authority_key,
                   date_trunc('month', d.calendar_date)::date AS month_start,
                   h.hour_ending,
                   count(*) AS observed_authority_hours,
                   count(*) FILTER (WHERE f.actual_demand_mw > 0
                       AND f.forecast_demand_mw >= 0) AS eligible_forecast_pairs,
                   count(*) FILTER (WHERE (f.actual_demand_mw > 0
                       AND f.forecast_demand_mw >= 0) IS NOT TRUE) AS excluded_forecast_pairs,
                   sum(f.actual_demand_mw) FILTER (WHERE f.actual_demand_mw > 0
                       AND f.forecast_demand_mw >= 0) AS eligible_actual_sum_mw,
                   sum(f.forecast_demand_mw) FILTER (WHERE f.actual_demand_mw > 0
                       AND f.forecast_demand_mw >= 0) AS eligible_forecast_sum_mw,
                   sum(f.actual_demand_mw-f.forecast_demand_mw)
                       FILTER (WHERE f.actual_demand_mw > 0 AND f.forecast_demand_mw >= 0)
                       AS signed_error_sum_mw,
                   sum(abs(f.actual_demand_mw-f.forecast_demand_mw))
                       FILTER (WHERE f.actual_demand_mw > 0 AND f.forecast_demand_mw >= 0)
                       AS abs_error_sum_mw,
                   count(*) FILTER (WHERE f.actual_demand_mw > 0
                       AND f.forecast_demand_mw >= 0
                       AND f.actual_demand_mw > f.forecast_demand_mw) AS underforecast_pairs,
                   count(*) FILTER (WHERE f.actual_demand_mw > 0
                       AND f.forecast_demand_mw >= 0
                       AND f.actual_demand_mw = f.forecast_demand_mw) AS equal_forecast_pairs,
                   count(*) FILTER (WHERE f.actual_demand_mw > 0
                       AND f.forecast_demand_mw >= 0
                       AND f.actual_demand_mw < f.forecast_demand_mw) AS overforecast_pairs
            FROM project_dw.fact_hourly_demand f
            JOIN project_dw.dim_date d USING (date_key)
            JOIN project_dw.dim_hour h USING (hour_key)
            GROUP BY f.authority_key, date_trunc('month', d.calendar_date)::date,
                     h.hour_ending
        ), differences AS (
            (SELECT * FROM expected EXCEPT
             SELECT authority_key, month_start, hour_ending,
                    observed_authority_hours, eligible_forecast_pairs, excluded_forecast_pairs,
                    eligible_actual_sum_mw, eligible_forecast_sum_mw,
                    signed_error_sum_mw, abs_error_sum_mw,
                    underforecast_pairs, equal_forecast_pairs, overforecast_pairs
             FROM project_reporting.vw_forecast_month_hour_components)
            UNION ALL
            (SELECT authority_key, month_start, hour_ending,
                    observed_authority_hours, eligible_forecast_pairs, excluded_forecast_pairs,
                    eligible_actual_sum_mw, eligible_forecast_sum_mw,
                    signed_error_sum_mw, abs_error_sum_mw,
                    underforecast_pairs, equal_forecast_pairs, overforecast_pairs
             FROM project_reporting.vw_forecast_month_hour_components
             EXCEPT SELECT * FROM expected)
        )
        SELECT 1 FROM differences
    ) THEN RAISE EXCEPTION 'Forecast components differ from independent demand facts'; END IF;

    IF EXISTS (
        SELECT 1 FROM project_reporting.vw_q05_forecast_accuracy q
        FULL JOIN project_reporting.vw_authority_analysis a USING(authority_key, month_start)
        WHERE q.observed_authority_hours IS DISTINCT FROM a.observed_authority_hours
           OR q.eligible_forecast_pairs IS DISTINCT FROM a.eligible_forecast_pairs
           OR q.excluded_forecast_pairs IS DISTINCT FROM a.excluded_forecast_pairs
           OR q.eligible_actual_sum_mw IS DISTINCT FROM a.eligible_actual_sum_mw
           OR q.signed_error_sum_mw IS DISTINCT FROM a.signed_error_sum_mw
           OR q.abs_error_sum_mw IS DISTINCT FROM a.abs_error_sum_mw
           OR q.underforecast_pairs IS DISTINCT FROM a.underforecast_pairs
           OR q.forecast_bias_mw IS DISTINCT FROM a.forecast_bias_mw
           OR q.forecast_mae_mw IS DISTINCT FROM a.forecast_mae_mw
           OR q.forecast_wape_pct IS DISTINCT FROM a.forecast_wape_pct
    ) THEN RAISE EXCEPTION 'Q05 disagrees with shared authority/month contract'; END IF;

    IF EXISTS (
        SELECT authority_key, month_start FROM project_reporting.vw_q05_forecast_accuracy
        GROUP BY 1,2 HAVING count(*) <> 1
    ) OR EXISTS (
        SELECT authority_key, month_start, hour_ending
        FROM project_reporting.vw_forecast_month_hour_components
        GROUP BY 1,2,3 HAVING count(*) <> 1
    ) OR EXISTS (
        SELECT authority_key, calendar_year, season, hour_ending
        FROM project_reporting.vw_q06_underforecast_pattern
        GROUP BY 1,2,3,4 HAVING count(*) <> 1
    ) THEN RAISE EXCEPTION 'Forecast reporting grain is not unique'; END IF;

    IF EXISTS (
        WITH rates AS (
            SELECT observed_authority_hours, eligible_forecast_pairs, excluded_forecast_pairs,
                   eligible_actual_sum_mw, signed_error_sum_mw, abs_error_sum_mw,
                   underforecast_pairs, equal_forecast_pairs, overforecast_pairs,
                   forecast_bias_mw, forecast_mae_mw, forecast_wape_pct, underforecast_pct
            FROM project_reporting.vw_q05_forecast_accuracy
            UNION ALL
            SELECT observed_authority_hours, eligible_forecast_pairs, excluded_forecast_pairs,
                   eligible_actual_sum_mw, signed_error_sum_mw, abs_error_sum_mw,
                   underforecast_pairs, equal_forecast_pairs, overforecast_pairs,
                   forecast_bias_mw, forecast_mae_mw, forecast_wape_pct, underforecast_pct
            FROM project_reporting.vw_q06_underforecast_pattern
        )
        SELECT 1 FROM rates
        WHERE eligible_forecast_pairs + excluded_forecast_pairs <> observed_authority_hours
           OR underforecast_pairs + equal_forecast_pairs + overforecast_pairs <> eligible_forecast_pairs
           OR forecast_bias_mw IS DISTINCT FROM
                  signed_error_sum_mw / nullif(eligible_forecast_pairs, 0)
           OR forecast_mae_mw IS DISTINCT FROM
                  abs_error_sum_mw / nullif(eligible_forecast_pairs, 0)
           OR forecast_wape_pct IS DISTINCT FROM
                  100.0 * abs_error_sum_mw / nullif(eligible_actual_sum_mw, 0)
           OR underforecast_pct IS DISTINCT FROM
                  100.0 * underforecast_pairs / nullif(eligible_forecast_pairs, 0)
           OR (eligible_forecast_pairs = 0 AND
               (eligible_actual_sum_mw IS NOT NULL OR abs_error_sum_mw IS NOT NULL
                OR signed_error_sum_mw IS NOT NULL))
    ) THEN RAISE EXCEPTION 'Forecast denominator, partition, null or rate contract failed'; END IF;

    RAISE NOTICE 'PASS: forecast facts, shared Q05 components, grains and rate/null contracts';
END $$;
