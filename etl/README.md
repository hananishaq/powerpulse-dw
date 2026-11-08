# ETL scripts (Python)

Python orchestrates; the heavy lifting is SQL inside PostgreSQL. Connection settings come from `.env` (copy `.env.example`; never commit `.env`).

| Script | Step | Owner |
|---|---|---|
| `00_test_connection.py` | 1 | Step 1 owner |
| `01_load_staging.py` | 2 | Step 2 owner |
| `02_load_dimensions.py` | 3 | Step 3 owner |
| `03_load_facts.py` | 4 | Step 4 owner |
| `04_run_quality_checks.py` | 5A | Step 5A owner |
| `run_all.py` | 5B — runs 01 → 04 in order on a fresh database | Step 1 owner |

Each script must be safe to run twice.
