"""Profile downloaded source CSVs without creating a warehouse. Standard library only."""
import argparse
import csv
import json
from collections import Counter, defaultdict
from datetime import datetime, timedelta
from decimal import Decimal, InvalidOperation
from pathlib import Path
from download_data import sha256

STAMP_FORMAT = "%m/%d/%Y %I:%M:%S %p"
CORE = ["Demand (MW)", "Demand Forecast (MW)", "Net Generation (MW)"]


def number(value):
    if not value.strip():
        return None
    try:
        result = Decimal(value.replace(",", ""))
        return result if result.is_finite() else None
    except InvalidOperation:
        return None


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--data", type=Path, default=Path(__file__).parent / "data")
    args = parser.parse_args()
    manifest = json.loads((args.data / "source_manifest.json").read_text(encoding="utf-8"))
    if manifest["status"] != "complete":
        raise ValueError("The acquisition manifest is incomplete.")
    counts = Counter()
    column_stats = defaultdict(Counter)
    authorities = defaultdict(lambda: {"rows": 0, "utc": set(), "local": set(), "dates": set(), "regions": set(), "offsets": set()})
    fuel_counts = Counter()
    raw_samples, anomalies, all_keys, schemas = [], [], set(), []
    reconciliation = Counter()
    for file in manifest["files"]:
        path = args.data / file["subset_file"]
        if sha256(path) != file["subset_sha256"]:
            raise ValueError(f"Source subset checksum does not match manifest: {path}")
        with path.open(encoding="utf-8", newline="") as stream:
            reader = csv.DictReader(stream)
            fuels = [c for c in reader.fieldnames if c.startswith("Net Generation (MW) from ") and not c.endswith("(Imputed)") and not c.endswith("(Adjusted)")]
            schemas.append({"file": path.name, "columns": reader.fieldnames, "fuel_columns": fuels})
            for row in reader:
                authority = row["Balancing Authority"]
                record = authorities[authority]
                utc = datetime.strptime(row["UTC Time at End of Hour"], STAMP_FORMAT)
                local = datetime.strptime(row["Local Time at End of Hour"], STAMP_FORMAT)
                operating_date = datetime.strptime(row["Data Date"], "%m/%d/%Y").date()
                key = (authority, utc)
                if key in all_keys:
                    counts["duplicate_authority_utc_keys"] += 1
                all_keys.add(key)
                record["rows"] += 1
                record["utc"].add(utc)
                record["local"].add(local)
                record["dates"].add(operating_date)
                record["regions"].add(row["Region"])
                record["offsets"].add(int((local - utc).total_seconds() / 60))
                counts["source_rows"] += 1
                if len(raw_samples) < 8:
                    raw_samples.append(row)
                values = {}
                for column in CORE + fuels:
                    raw = row[column]
                    value = number(raw)
                    values[column] = value
                    stats = column_stats[column]
                    stats["rows"] += 1
                    if not raw.strip():
                        stats["blank"] += 1
                    elif value is None:
                        stats["invalid_numeric"] += 1
                    else:
                        stats["numeric"] += 1
                        stats["zero"] += int(value == 0)
                        stats["negative"] += int(value < 0)
                        if column in fuels:
                            counts["numeric_fuel_cells"] += 1
                            fuel_counts[column] += 1
                        if value < 0 and len(anomalies) < 15:
                            anomalies.append({"authority": authority, "utc": utc.isoformat(), "column": column, "value": str(value), "source_file": row["_SourceFile"], "source_row": row["_SourceRow"]})
                demand, forecast = values[CORE[0]], values[CORE[1]]
                if demand is not None and forecast is not None and demand > 0 and forecast >= 0:
                    counts["eligible_forecast_pairs"] += 1
                available = [values[col] for col in fuels if values[col] is not None]
                if values[CORE[2]] is not None and available:
                    difference = sum(available) - values[CORE[2]]
                    reconciliation["hours_compared"] += 1
                    reconciliation["absolute_residual_over_1mw"] += int(abs(difference) > 1)
                    tolerance = max(Decimal("10"), abs(values[CORE[2]]) * Decimal("0.01"))
                    reconciliation["residual_over_10mw_or_1pct"] += int(abs(difference) > tolerance)
                    reconciliation["exact_matches"] += int(difference == 0)
    authority_rows = []
    for code, record in sorted(authorities.items()):
        first, last = min(record["utc"]), max(record["utc"])
        expected = int((last - first).total_seconds() / 3600) + 1
        missing = []
        current = first
        while current <= last:
            if current not in record["utc"]:
                missing.append(current.isoformat() + "Z")
            current += timedelta(hours=1)
        authority_rows.append({"code": code, "rows": record["rows"], "unique_utc_hours": len(record["utc"]),
                               "first_utc": first.isoformat() + "Z", "last_utc": last.isoformat() + "Z",
                               "expected_hours_within_observed_span": expected,
                               "missing_utc_hours": len(missing), "missing_examples": missing[:5],
                               "repeated_local_clock_labels": len(record["utc"]) - len(record["local"]),
                               "operating_dates": len(record["dates"]), "first_operating_date": str(min(record["dates"])),
                               "last_operating_date": str(max(record["dates"])), "region_codes": sorted(record["regions"]),
                               "observed_utc_offsets_minutes": sorted(record["offsets"])})
    result = {"scope": "Source profiling only. No warehouse tables loaded.", "counts": dict(counts),
              "authorities": authority_rows, "column_profiles": dict(column_stats),
              "fuel_numeric_counts": dict(fuel_counts), "generation_reconciliation": dict(reconciliation),
              "schemas": schemas, "negative_examples": anomalies, "raw_samples": raw_samples}
    (args.data / "profile.json").write_text(json.dumps(result, indent=2), encoding="utf-8")
    with (args.data / "sample_20_rows.csv").open("w", encoding="utf-8", newline="") as output:
        sample_fields = list(dict.fromkeys(column for schema in schemas for column in schema["columns"]))
        writer = csv.DictWriter(output, fieldnames=sample_fields)
        writer.writeheader()
        for item in manifest["files"]:
            with (args.data / item["subset_file"]).open(encoding="utf-8", newline="") as source:
                reader = csv.DictReader(source)
                for index, row in enumerate(reader):
                    if index == 5:
                        break
                    writer.writerow(row)
    print(json.dumps({"counts": dict(counts), "authorities": authority_rows,
                      "generation_reconciliation": dict(reconciliation),
                      "core_columns": {k: dict(column_stats[k]) for k in CORE}}, indent=2))


if __name__ == "__main__":
    main()
