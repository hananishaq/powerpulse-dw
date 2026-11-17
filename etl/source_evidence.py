"""Independently parse frozen CSVs for row-by-row warehouse validation."""
import csv
import hashlib
import json
from datetime import datetime, timezone
from decimal import Decimal, InvalidOperation
from urllib.parse import urlparse
from pathlib import Path

from common import ROOT

DATA = ROOT / "data_acquisition" / "data"
STAMP = "%m/%d/%Y %I:%M:%S %p"


def number(value):
    if value is None or not value.strip():
        return None
    try:
        n = Decimal(value.strip())
    except InvalidOperation as exc:
        raise ValueError(f"Malformed source number: {value!r}") from exc
    if not n.is_finite():
        raise ValueError("Non-finite source number")
    return n


def load_source_evidence(conn):
    manifest = json.loads((DATA / "source_manifest.json").read_text(encoding="utf-8"))
    profile = json.loads((DATA / "profile.json").read_text(encoding="utf-8"))
    if manifest.get("status") != "complete":
        raise ValueError("Source manifest is incomplete")
    with (DATA / "energy_source_mapping.csv").open(encoding="utf-8-sig", newline="") as stream:
        fuel_mapping = list(csv.DictReader(stream))
        headers = [r["SourceColumn"] for r in fuel_mapping]
    zones = {"CISO": "America/Los_Angeles", "ERCO": "America/Chicago",
             "ISNE": "America/New_York", "NYIS": "America/New_York", "PJM": "America/New_York"}
    conn.execute("DELETE FROM project_reporting.dq_expected_coverage")
    for a in profile["authorities"]:
        conn.execute("INSERT INTO project_reporting.dq_expected_coverage VALUES (%s,%s,%s,%s)",
                     (a["code"], a["first_utc"], a["last_utc"], zones[a["code"]]))
    conn.execute("""
        CREATE TEMP TABLE dq_source_core (
            authority_code text, utc_hour_end timestamptz, calendar_date date,
            local_hour_end timestamp, hour_ending smallint, utc_offset_minutes smallint,
            actual_demand_mw numeric, forecast_demand_mw numeric, total_generation_mw numeric,
            file_name text, sha256 text, source_row_number integer
        ) ON COMMIT PRESERVE ROWS;
        CREATE TEMP TABLE dq_source_fuel (
            authority_code text,utc_hour_end timestamptz,source_column text,
            generation_mw numeric,file_name text,sha256 text,source_row_number integer
        ) ON COMMIT PRESERVE ROWS;
        CREATE TEMP TABLE dq_source_fuel_reference (
            source_column text,source_label text,source_group text
        ) ON COMMIT PRESERVE ROWS;
        CREATE TEMP TABLE dq_source_authority_reference (
            authority_code text,authority_name text,region_code text,region_name text
        ) ON COMMIT PRESERVE ROWS;
    """)
    for row in fuel_mapping:
        conn.execute("INSERT INTO dq_source_fuel_reference VALUES (%s,%s,%s)",
                     (row["SourceColumn"],row["SourceLabel"],row["SourceGroup"]))
    with (DATA / "authority_reference.csv").open(encoding="utf-8-sig",newline="") as stream:
        for row in csv.DictReader(stream):
            conn.execute("INSERT INTO dq_source_authority_reference VALUES (%s,%s,%s,%s)",
                         (row["AuthorityCode"],row["AuthorityName"],row["RegionCode"],row["RegionName"]))
    evidence = []
    core_rows, fuel_rows = [], []
    for entry in manifest["files"]:
        path = DATA / entry["subset_file"]
        observed_hash = hashlib.sha256(path.read_bytes()).hexdigest()
        if observed_hash != entry["subset_sha256"]:
            raise ValueError(f"CSV hash mismatch: {path.name}")
        filename = Path(urlparse(entry["url"]).path).name
        n = 0
        with path.open(encoding="utf-8-sig", newline="") as stream:
            reader = csv.DictReader(stream)
            present = [h for h in headers if h in reader.fieldnames]
            for row in reader:
                if row["_SourceFile"] != filename:
                    raise ValueError(f"Unexpected source locator in {path.name}")
                n += 1
                utc = datetime.strptime(row["UTC Time at End of Hour"], STAMP).replace(tzinfo=timezone.utc)
                local = datetime.strptime(row["Local Time at End of Hour"], STAMP)
                operating_date = datetime.strptime(row["Data Date"], "%m/%d/%Y").date()
                authority = row["Balancing Authority"].strip().upper()
                rownum = int(row["_SourceRow"])
                offset = int((local - utc.replace(tzinfo=None)).total_seconds() / 60)
                core_rows.append((authority, utc, operating_date, local, local.hour, offset,
                    number(row["Demand (MW)"]), number(row["Demand Forecast (MW)"]),
                    number(row["Net Generation (MW)"]), filename, entry["sha256"], rownum))
                for header in present:
                    value = number(row[header])
                    if value is not None:
                        fuel_rows.append((authority, utc, header, value, filename, entry["sha256"], rownum))
        if n != entry["selected_rows"]:
            raise ValueError(f"CSV row count differs from manifest: {path.name}")
        evidence.append(dict(file=path.name, original_file=filename, rows=n,
            subset_sha256=observed_hash, original_sha256=entry["sha256"],
            reported_fuel_columns=present, absent_fuel_columns=[h for h in headers if h not in present]))
    with conn.cursor() as cur:
        with cur.copy("COPY dq_source_core FROM STDIN") as copy:
            for row in core_rows:
                copy.write_row(row)
        with cur.copy("COPY dq_source_fuel FROM STDIN") as copy:
            for row in fuel_rows:
                copy.write_row(row)
    conn.execute("CREATE INDEX ON dq_source_core(authority_code,utc_hour_end)")
    conn.execute("CREATE INDEX ON dq_source_fuel(authority_code,utc_hour_end,source_column)")
    conn.execute("ANALYZE dq_source_core; ANALYZE dq_source_fuel")
    return evidence
