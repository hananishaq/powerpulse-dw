"""Read .env, connect, and show the database version and project schemas."""
from common import connect


def main():
    with connect() as conn:
        print(conn.execute("SELECT version()").fetchone()[0])
        schemas = [r[0] for r in conn.execute("""
            SELECT schema_name FROM information_schema.schemata
            WHERE schema_name IN ('project_staging','project_dw','project_reporting')
            ORDER BY schema_name
        """)]
        print("Schemas:", ", ".join(schemas))
        if len(schemas) != 3:
            raise SystemExit("Run database/schema setup first; a project schema is missing.")


if __name__ == "__main__":
    main()
