#!/usr/bin/env python3
"""Install and reconcile the complete Phase 3 reporting layer transactionally."""
from pathlib import Path

import psycopg
from dotenv import load_dotenv

ROOT = Path(__file__).resolve().parents[1]
SCRIPTS = (
    "06_reporting/p1_demand_views.sql",
    "06_reporting/p2_profile_views.sql",
    "06_reporting/p3_forecast_views.sql",
    "06_reporting/p4_generation_views.sql",
    "06_reporting/p5_decision_views.sql",
    "07_phase3_analytics/p1_validate.sql",
    "07_phase3_analytics/p3_validate.sql",
    "07_phase3_analytics/p4_validate.sql",
)


def main():
    load_dotenv(ROOT / ".env")
    with psycopg.connect(connect_timeout=10) as conn:
        for relative in SCRIPTS:
            print(relative, flush=True)
            conn.execute((ROOT / "sql" / relative).read_text(encoding="utf-8"))
    print("Phase 3 views installed and reconciled.", flush=True)


if __name__ == "__main__":
    main()
