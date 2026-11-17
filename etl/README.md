# ETL and validation

Configure `.env` and run `python etl/run_all.py --bootstrap --report`. Resource paths resolve from the repository rather than the current directory. Do not commit `.env`.

| Script | Responsibility |
|---|---|
| `00_test_connection.py` | Mohid: version and schema connectivity |
| `01_load_staging.py` | Qasim: import, cleaning and optional dirty-data self-test |
| `02_load_dimensions.py` | Emaad: five dimension loads |
| `03_load_facts.py` | Muaz: facts and original fact-step logs |
| `04_run_quality_checks.py` | Mohid: independent source audit, reporting and quality gate |
| `run_all.py` | Integration wrapper, stage logs, identity checks and optional PDF |
| `source_evidence.py` | Independent CSV parser and frozen coverage |
| `common.py` | Connection and evidence helpers |

Run again to verify stable identities. Quality negative tests use scratch data by default; `--skip-negative-tests` gives a baseline-only audit. `python tests/integration_checks.py` exercises rolled-back mutations and reporting edge cases. Evidence is exported to `reports/phase2/evidence/`.

The normal runner never executes staging dirty-row injection files. This is a frozen-baseline integration; upstream revision/quarantine/counter limitations remain documented in `docs/phase2/MOHID_IMPLEMENTATION.md`.
