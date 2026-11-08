# Step 1 — Foundation

**Owner:** ________ · **Marks:** Database Implementation · **Needs first:** nothing (push this one first)

## Your job
Give every teammate a working empty database with the three schemas, and prove Python can talk to it.

## Create these files
- `00_create_database.sql` — create database `powerpulse_dw`.
- `01_create_schemas.sql` — inside `powerpulse_dw`, create schemas `project_staging`, `project_dw`, `project_reporting` (`CREATE SCHEMA IF NOT EXISTS`).
- `../../etl/00_test_connection.py` — read `.env` (python-dotenv), connect with psycopg, print the PostgreSQL version and the three schema names.

## Done when
- In psql or pgAdmin, `\dn` lists the three schemas.
- `python etl/00_test_connection.py` prints them.
- Both scripts can be run twice without errors (`IF NOT EXISTS`).

## Also yours later (Step 5B)
`sql/06_reporting/`, `etl/run_all.py`, the final README run order and the `phase2-submission` tag.
