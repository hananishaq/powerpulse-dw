"""Shared connection, SQL and evidence helpers. Never log connection secrets."""
from datetime import datetime, timezone
from pathlib import Path
import json
import os
import subprocess

import psycopg
from dotenv import load_dotenv

ROOT = Path(__file__).resolve().parents[1]
EVIDENCE = ROOT / "reports" / "phase2" / "evidence"


def connection_settings(database=None):
    load_dotenv(ROOT / ".env")
    settings = dict(host=os.getenv("PGHOST", "localhost"),
                    port=os.getenv("PGPORT", "5432"),
                    dbname=database or os.getenv("PGDATABASE", "powerpulse_dw"),
                    user=os.getenv("PGUSER", "postgres"), connect_timeout=10)
    if os.getenv("PGPASSWORD"):
        settings["password"] = os.environ["PGPASSWORD"]
    return settings


def connect(database=None, **kwargs):
    conn = psycopg.connect(**connection_settings(database), **kwargs)
    conn.execute("SET TIME ZONE 'UTC'")
    return conn


def run_sql(conn, relative_path):
    conn.execute((ROOT / relative_path).read_text(encoding="utf-8"))


def revision():
    try:
        return subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=ROOT,
                                       text=True, stderr=subprocess.DEVNULL).strip()
    except (OSError, subprocess.CalledProcessError):
        return "unavailable"


def utc_now():
    return datetime.now(timezone.utc).isoformat()


def write_json(path, payload):
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(payload, indent=2, default=str) + "\n", encoding="utf-8")
