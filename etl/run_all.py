#!/usr/bin/env python3
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]

STEPS = [
    ("Staging load", ROOT / "etl" / "01_load_staging.py"),
    ("Dimension load", ROOT / "etl" / "02_load_dimensions.py"),
    ("Fact load", ROOT / "etl" / "03_load_facts.py"),
]

print("PowerPulse ETL pipeline")
print("=" * 40)

for name, script in STEPS:
    print(f"\nStarting: {name}")

    result = subprocess.run(
        [sys.executable, str(script)],
        cwd=ROOT
    )

    if result.returncode != 0:
        print(f"\nFAILED: {name}")
        sys.exit(result.returncode)

    print(f"SUCCESS: {name}")

print("\n" + "=" * 40)
print("DONE - full PowerPulse ETL pipeline completed.")