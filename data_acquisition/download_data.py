"""Download official EIA-930 bulk CSVs and preserve selected source rows.

Python 3.10+ standard library only. No API key is needed for bulk files.
This is source acquisition for Phase 1, not warehouse loading.
"""
import argparse
import csv
import hashlib
import json
import os
from pathlib import Path
import tempfile
import time
import zipfile
from datetime import datetime, timezone
from urllib.request import Request, urlopen

BASE_URL = "https://www.eia.gov/electricity/gridmonitor/sixMonthFiles/"
DEFAULT_AUTHORITIES = ["CISO", "ERCO", "ISNE", "NYIS", "PJM"]
REQUIRED_COLUMNS = {
    "Balancing Authority", "Data Date", "Hour Number",
    "Local Time at End of Hour", "UTC Time at End of Hour",
    "Demand Forecast (MW)", "Demand (MW)", "Net Generation (MW)", "Region",
}


def sha256(path):
    digest = hashlib.sha256()
    with path.open("rb") as source:
        for block in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def download(url, path, refresh=False, validate_csv=True):
    metadata_path = path.with_suffix(".download.json")
    if path.exists() and metadata_path.exists() and not refresh:
        metadata = json.loads(metadata_path.read_text(encoding="utf-8"))
        if metadata.get("sha256") == sha256(path):
            return metadata
        raise ValueError(f"Cached source checksum changed: {path}. Use --refresh.")
    for attempt in range(4):
        temporary = None
        try:
            request = Request(url, headers={"User-Agent": "PowerPulse-Academic-Data-Download/1.0"})
            with urlopen(request, timeout=90) as response:
                expected = response.headers.get("Content-Length")
                metadata = {
                    "url": url,
                    "retrieved_at_utc": datetime.now(timezone.utc).isoformat(),
                    "last_modified": response.headers.get("Last-Modified"),
                    "etag": response.headers.get("ETag"),
                }
                with tempfile.NamedTemporaryFile(dir=path.parent, delete=False) as target:
                    temporary = Path(target.name)
                    for block in iter(lambda: response.read(1024 * 1024), b""):
                        target.write(block)
            if expected and temporary.stat().st_size != int(expected):
                raise ValueError("Download length does not match the server response.")
            if validate_csv:
                with temporary.open(encoding="utf-8-sig", newline="") as source:
                    header = next(csv.reader(source))
                    if not REQUIRED_COLUMNS.issubset(header):
                        raise ValueError("Unexpected CSV schema. Inspect the publisher response.")
            elif not zipfile.is_zipfile(temporary):
                raise ValueError("The reference download is not an XLSX file.")
            metadata.update(bytes=temporary.stat().st_size, sha256=sha256(temporary))
            os.replace(temporary, path)
            metadata_path.write_text(json.dumps(metadata, indent=2), encoding="utf-8")
            return metadata
        except Exception:
            if temporary is not None:
                temporary.unlink(missing_ok=True)
            if attempt == 3:
                raise
            time.sleep(2 ** attempt)


def select_rows(source_path, output_path, authorities):
    counts = {authority: 0 for authority in authorities}
    total = 0
    with source_path.open(encoding="utf-8-sig", newline="") as source:
        reader = csv.DictReader(source)
        fields = reader.fieldnames
        if not REQUIRED_COLUMNS.issubset(fields):
            raise ValueError("Required EIA columns are missing.")
        with tempfile.NamedTemporaryFile(mode="w", encoding="utf-8", newline="",
                                         dir=output_path.parent, delete=False) as target:
            temporary = Path(target.name)
            writer = csv.DictWriter(target, fieldnames=fields + ["_SourceFile", "_SourceRow"])
            writer.writeheader()
            for row_number, row in enumerate(reader, 1):
                total += 1
                authority = row["Balancing Authority"]
                if authority in counts:
                    if None in row:
                        raise ValueError(f"Malformed CSV record {row_number}.")
                    writer.writerow({**row, "_SourceFile": source_path.name, "_SourceRow": row_number})
                    counts[authority] += 1
    if any(value == 0 for value in counts.values()):
        temporary.unlink(missing_ok=True)
        raise ValueError(f"Requested authority has no rows: {counts}")
    os.replace(temporary, output_path)
    return {"source_rows": total, "selected_rows": sum(counts.values()),
            "rows_by_authority": counts, "source_columns": fields,
            "subset_file": output_path.name, "subset_sha256": sha256(output_path)}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--years", nargs="+", type=int, default=[2024, 2025])
    parser.add_argument("--halves", nargs="+", choices=["Jan_Jun", "Jul_Dec"], default=["Jan_Jun", "Jul_Dec"])
    parser.add_argument("--authorities", nargs="+", default=DEFAULT_AUTHORITIES)
    parser.add_argument("--out", type=Path, default=Path(__file__).parent / "data")
    parser.add_argument("--cache", type=Path, default=Path(__file__).parent / "cache")
    parser.add_argument("--refresh", action="store_true", help="Re-fetch existing bulk files to detect source revisions.")
    args = parser.parse_args()
    if len(set(args.authorities)) != len(args.authorities):
        parser.error("Authority codes must be unique.")
    args.out.mkdir(parents=True, exist_ok=True)
    args.cache.mkdir(parents=True, exist_ok=True)
    manifest = {"status": "running", "authorities": args.authorities,
                "years": sorted(set(args.years)), "files": []}
    manifest_path = args.out / "source_manifest.json"
    for year in sorted(set(args.years)):
        for half in dict.fromkeys(args.halves):
            name = f"EIA930_BALANCE_{year}_{half}.csv"
            path = args.cache / name
            print(f"Acquiring {name}", flush=True)
            metadata = download(BASE_URL + name, path, args.refresh)
            metadata.update(select_rows(path, args.out / (name[:-4] + "_selected.csv"), args.authorities))
            manifest["files"].append(metadata)
            manifest_path.write_text(json.dumps(manifest, indent=2), encoding="utf-8")
            print(f"Selected {metadata['selected_rows']:,} of {metadata['source_rows']:,} rows", flush=True)
    reference_name = "EIA930_Reference_Tables.xlsx"
    reference = download("https://www.eia.gov/electricity/930-content/" + reference_name,
                         args.out / reference_name, args.refresh, validate_csv=False)
    manifest["reference_workbook"] = {**reference, "file": reference_name}
    manifest["status"] = "complete"
    manifest_path.write_text(json.dumps(manifest, indent=2), encoding="utf-8")
    print(f"Complete. Manifest saved to {manifest_path}", flush=True)


if __name__ == "__main__":
    main()
