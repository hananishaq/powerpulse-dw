-- psql entry point: connect to postgres, outside a transaction.
-- Example: psql -U postgres -d postgres -v ON_ERROR_STOP=1 -f this_file.sql
-- For a custom database name use: psql ... -v target_db=your_database
\set ON_ERROR_STOP on
\if :{?target_db}
\else
\set target_db powerpulse_dw
\endif
SELECT format('CREATE DATABASE %I', :'target_db')
WHERE NOT EXISTS (SELECT 1 FROM pg_database WHERE datname = :'target_db')
\gexec
