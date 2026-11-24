DO $validation$
BEGIN
    IF EXISTS (
        SELECT 1 FROM project_reporting.vw_generation_authority_hour
        GROUP BY authority_key, utc_hour_end HAVING count(*) <> 1
    ) OR (
        SELECT count(*) FROM project_reporting.vw_generation_reconciliation_hour
    ) <> (SELECT count(*) FROM project_dw.fact_hourly_demand) THEN
        RAISE EXCEPTION 'Generation helper changed the demand join grain';
    END IF;

    IF (
        SELECT sum(d.eligible_actual_demand_mw)
        FROM project_reporting.vw_demand_observation d
        LEFT JOIN project_reporting.vw_generation_authority_hour g
        USING (authority_key, utc_hour_end)
    ) IS DISTINCT FROM (
        SELECT sum(actual_demand_mw) FROM project_dw.fact_hourly_demand
        WHERE actual_demand_mw >= 0
    ) THEN
        RAISE EXCEPTION 'Generation helper changed the demand-energy total';
    END IF;

    IF (
        SELECT ROW(sum(signed_generation_mwh), sum(numeric_observations),
                   sum(observed_negative_hours))
        FROM project_reporting.vw_q07_generation_by_source
    ) IS DISTINCT FROM (
        SELECT ROW(sum(generation_mw), count(*)::numeric,
                   count(*) FILTER (WHERE generation_mw < 0)::numeric)
        FROM project_dw.fact_hourly_generation
    ) OR EXISTS (
        SELECT 1 FROM project_reporting.vw_q07_generation_by_source
        WHERE supplied_blank_hours < 0
           OR (numeric_observations = 0) <> (signed_generation_mwh IS NULL)
    ) THEN
        RAISE EXCEPTION 'Q07 signed generation, observations or missingness do not reconcile';
    END IF;

    IF EXISTS (
        SELECT 1 FROM project_reporting.vw_q08_wind_solar_share
        WHERE matched_hours + excluded_hours <> source_hours
           OR excluded_hours <> missing_wind_hours + missing_solar_hours + missing_total_hours
             + nonpositive_total_hours + residual_failure_hours + unverified_publication_hours
           OR (matched_hours = 0) <> (wind_solar_share_pct IS NULL)
           OR (matched_hours > 0 AND (matched_reported_mwh <= 0
               OR observed_wind_components < matched_hours OR observed_solar_components < matched_hours))
    ) THEN
        RAISE EXCEPTION 'Q08 matched-hour and excluded-hour components do not reconcile';
    END IF;

    IF EXISTS (
        SELECT 1 FROM project_reporting.vw_q09_high_demand_mix
        GROUP BY authority_key, month_start, demand_cohort
        HAVING sum(signed_group_mwh) IS DISTINCT FROM max(signed_total_mwh)
            OR bool_or(observed_group_hours > matched_generation_hours
                       OR matched_generation_hours > eligible_demand_hours)
    ) OR (
        SELECT sum(eligible_demand_hours)
        FROM (SELECT DISTINCT authority_key, month_start, demand_cohort, eligible_demand_hours
              FROM project_reporting.vw_q09_high_demand_mix) cohorts
    ) <> (SELECT count(*) FROM project_dw.fact_hourly_demand WHERE actual_demand_mw > 0) THEN
        RAISE EXCEPTION 'Q09 demand cohort or signed generation does not reconcile';
    END IF;

    IF EXISTS (
        SELECT 1 FROM project_reporting.vw_q10_source_quality
        WHERE observed_hours + absent_row_hours <> expected_hours
           OR residual_failure_hours > comparable_hours
           OR affected_core_hours > expected_hours
    ) OR (SELECT sum(expected_hours) FROM project_reporting.vw_q10_source_quality)
        <> (SELECT count(*) FROM project_dw.expected_hour_grid) THEN
        RAISE EXCEPTION 'Q10 does not reconcile with the expected UTC grid';
    END IF;
END
$validation$;
