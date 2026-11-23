# Phase 3: Mohid's demand and Executive Overview package

This folder documents Mohid's completed demand and Executive Overview
contribution. Other students' outputs remain separate team deliverables.

## Files to use

| Purpose | File |
|---|---|
| Observation input, Q01, Q02 and authority reporting views | `sql/06_reporting/p1_demand_views.sql` |
| Analytical queries, ranked local-hour profiles, lineage | `sql/07_phase3_analytics/p1_q01_q02.sql` |
| Fail-on-error fact-to-view reconciliation | `sql/07_phase3_analytics/p1_validate.sql` |
| Transactional install, checks and optional CSV export | `etl/05_run_phase3_mohid.py` |
| Shared definitions and proposed integration interfaces | `docs/phase3/view_contract.md` |
| Retail-to-electricity rubric mapping | `docs/phase3/rubric_mapping.md` |
| Editable Executive Overview with PostgreSQL queries and DAX | `bi/phase3/mohid/PowerPulse_Overview.pbip` |
| Populated overview, ready to open without credentials | `bi/phase3/mohid/PowerPulse_Overview.pbix` |
| Personal overview PDF for the screenshot/report handoff | `reports/phase3/mohid/Executive_Overview.pdf` |
| Open/refresh guide, layout and SQL comparisons | `bi/phase3/p1_overview_spec.md` |
| Measured demand finding for Qasim's report | `reports/phase3/mohid/demand_insight.md` |
| Validation evidence and boundaries | `reports/phase3/mohid/validation.json` |
| Two editable contributed slides for the final deck | `presentation/phase3/mohid_demand_overview.pptx` |

## Run order

Use PostgreSQL 16+ and Python 3.10+. Install the repository requirements and
copy `.env.example` to `.env` with your local settings. Do not commit `.env`.

For a new local database, create `powerpulse_dw` in pgAdmin or psql first. The
repository's `sql/00_setup/` currently contains setup instructions rather than
database-creation scripts. Then:

1. Run `python etl/01_load_staging.py`.
2. Execute `sql/02_dw/00_create_dimensions.sql` and `01_create_facts.sql`.
3. Run `python etl/02_load_dimensions.py`. First loads may add dimension members;
   the stability check protects keys that already existed.
4. Run `python etl/03_load_facts.py`.
5. Run `python etl/05_run_phase3_mohid.py` to install the views and validate them.
6. Run `sql/07_phase3_analytics/p1_q01_q02.sql` in pgAdmin/psql for analytical
   outputs, ranks and source-hash lineage.
7. Open and refresh the Power BI source project as described in the BI guide.

Alternatively, after creating the database, use:

```text
python etl/run_all.py --phase3 --refresh-bi-snapshot
```

The pipeline creates the warehouse tables before dimension loading and includes
Mohid's reporting validation when `--phase3` is supplied. Without this flag it
continues to run the Phase 2 load only. An initialized database can start at step 5.
The Phase 3 runner uses one transaction for view changes and validation, so
failed validation rolls back that installation. Exports use a read-only,
repeatable-read transaction for mutually consistent files.

Optional result export:

```text
python etl/05_run_phase3_mohid.py --from-month 2024-01-01 --to-month 2026-01-01 --export-dir reports/phase3/mohid/results
python etl/05_run_phase3_mohid.py --from-month 2024-01-01 --to-month 2024-02-01 --authority CISO
```

The end month is exclusive; both dates must be the first of a month. Exported
CSV nulls are empty fields; numerical zero remains `0`. Result exports are
optional regenerable evidence and are not included in this commit. The SQL
view definitions can also be run directly, followed by `p1_validate.sql`, in
one transaction if Python is unavailable.

## Personal completion checklist

- [x] Q01/Q02 SQL, stable reporting contracts and generic rubric view aliases.
- [x] Reproducible install/export and snapshot regeneration commands.
- [x] Source reconciliation and first-load/rerun dimension-key checks.
- [x] Executable Executive Overview source with clear Snapshot/Warehouse modes.
- [x] Populated PBIX saved in Power BI Desktop and normal Snapshot refresh verified.
- [x] Seven native DAX filter selections matched to PostgreSQL results.
- [x] Native one-page PDF exported and visually checked for the report handoff.
- [x] Demand insight and two editable presentation slides supplied to Qasim.

The warehouse loaded twice on native PostgreSQL 16.11 with unchanged expected
counts and stable authority keys. Native database and Power BI acceptance results,
including the populated PBIX,
are recorded in `reports/phase3/mohid/validation.json`.

## Separate team integration checklist

These tasks combine other students' work into the final team submission:

- [ ] Phase 2 quality owner supplies the missing formal quality scripts/report
      and closes the warehouse-wide readiness gate, including generation.
- [ ] Hanan reviews Q01/Q02 and contributes Q03/Q04 and OLAP.
- [ ] Muaz compares his forecast components with authority analysis and supplies
      measured indexing evidence.
- [ ] Emaad integrates the completed Executive Overview into the master PBIX
      and checks interactions with the other two pages.
- [ ] Qasim incorporates the checked demand finding and two contributed slides.
- [ ] The team freezes one source revision, captures all three dashboard pages,
      opens every final PDF/PPTX/PBIX and signs off the eight deliverable types.

## Final team submission manifest

| Required output | Owner | Status in this package |
|---|---|---|
| Analytical SQL | All | Mohid Q01/Q02 supplied |
| OLAP SQL | Hanan | Team dependency |
| Reporting Views SQL | All | Mohid views supplied |
| Indexing Report PDF | Muaz | Team dependency |
| Power BI PBIX | Emaad | Mohid's populated personal PBIX and source supplied |
| Dashboard Screenshots PDF | Qasim | After final PBIX freeze |
| Business Insights PDF | Qasim + all contributors | Mohid source contribution supplied |
| Final Presentation | Qasim + all presenters | Mohid two-slide contribution supplied |

Only implementation files, project documentation, evidence needed for the lab
and the contributed presentation belong in the commit. Local database files,
Power BI `.pbi` caches, temporary exports, test installations and build scripts
used outside the repository are not submission artifacts.
