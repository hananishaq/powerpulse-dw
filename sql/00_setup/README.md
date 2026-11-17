# Setup and consolidated physical SQL

Normal command: `python etl/run_all.py --bootstrap`. Bootstrap requires CREATEDB privilege only when the configured database is absent. Existing databases are not dropped.

For psql:

```shell
psql -U postgres -d postgres -v ON_ERROR_STOP=1 -f sql/00_setup/00_create_database.sql
psql -U postgres -d powerpulse_dw -v ON_ERROR_STOP=1 -f sql/00_setup/10_install_warehouse.psql
```

The first script uses `\gexec` outside a transaction; override the name with `-v target_db=your_name`. The consolidated entry uses `\ir` and creates structures/views, not data. Both are psql-specific. `01_create_schemas.sql` is ordinary SQL suitable for pgAdmin inside the target database.

Python reads `.env`; psql needs matching connection options/password prompt. Never commit local credentials or database files.
