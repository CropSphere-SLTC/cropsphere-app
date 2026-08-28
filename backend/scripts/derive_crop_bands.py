"""Derive the per-crop agronomic suitability bands from the training dataset.

WHY THIS EXISTS
---------------
The recommendation UI has always promised a per-crop verdict ("N of M
conditions are ideal"). The backend used to answer it with model-telemetry
flags (`yield_modelled`, `price_modelled`, `any_mock`), which describe model
health rather than the crop, are identical for all six crops, and made the
"Good match" branch mathematically unreachable. The real signal was in the
training data the whole time — this script extracts it.

`CropSphere_SL_Synthetic_Weekly.csv` carries eight per-crop threshold columns
(`crop_min_temp_c`, `crop_max_temp_c`, `crop_min_weekly_rain_mm`,
`crop_max_weekly_rain_mm`, `crop_min_humidity_pct`, `crop_max_humidity_pct`,
`crop_ph_min`, `crop_ph_max`) alongside the four boolean outcomes derived from
them (`temp_suitable_flag`, `rain_suitable_flag`, `humidity_suitable_flag`,
`ph_suitable_flag`) and their conjunction (`conditions_met_flag`).

The thresholds are constant per crop across the entire dataset, so they reduce
to a six-row lookup table. This script asserts that constancy rather than
assuming it, then re-derives the four boolean columns from the thresholds using
simple inclusive-range rules and checks them against the dataset's own values.

PROVENANCE
----------
Validated against every row of the dataset (4,978 weekly rows covering all six
crops and all eight districts). All four inclusive-range rules reproduce the
dataset's own flag columns exactly, and `temp & rain & humidity & ph`
reproduces `conditions_met_flag` exactly:

    temp rule matches column: 1.0
    rain rule matches column: 1.0
    hum  rule matches column: 1.0
    ph   rule matches column: 1.0
    all4 == conditions_met_flag: 1.0

The rules are inclusive on both ends:

    temp_suitable     = crop_min_temp_c <= temp_min_c and temp_max_c <= crop_max_temp_c
    rain_suitable     = crop_min_weekly_rain_mm <= rainfall_mm <= crop_max_weekly_rain_mm
    humidity_suitable = crop_min_humidity_pct <= humidity_pct <= crop_max_humidity_pct
    ph_suitable       = crop_ph_min <= soil_ph <= crop_ph_max

Note the temperature rule is NOT a midpoint check: it requires the *whole*
observed range to sit inside the crop's tolerance, so a crop fails if either
the cold night or the hot afternoon falls outside. That is what makes Carrot
(28 °C ceiling) fail in the low country while passing up in Nuwara Eliya.

USAGE
-----
    python -m scripts.derive_crop_bands            # verify only, prints report
    python -m scripts.derive_crop_bands --write    # regenerate the JSON

Re-run with --write only after the dataset itself changes. The generated file
is committed; this script is the audit trail for how those numbers arose.
"""

from __future__ import annotations

import argparse
import json
import sys
from datetime import date
from pathlib import Path

BACKEND = Path(__file__).resolve().parents[1]
CSV_PATH = BACKEND / "models" / "files" / "CropSphere_SL_Synthetic_Weekly.csv"
OUT_PATH = BACKEND / "data" / "crop_agronomic_bands.json"

# The CSV ships a two-row header (category banner, then real column names) and
# is latin-1 encoded — a stray 0xa1 byte makes a utf-8 read blow up.
CSV_HEADER_ROW = 1
CSV_ENCODING = "latin-1"

THRESHOLD_COLUMNS = [
    "crop_min_temp_c",
    "crop_max_temp_c",
    "crop_min_weekly_rain_mm",
    "crop_max_weekly_rain_mm",
    "crop_min_humidity_pct",
    "crop_max_humidity_pct",
    "crop_ph_min",
    "crop_ph_max",
]


def _rules(d):
    """Re-derive the four boolean columns from the threshold columns."""
    return {
        "temp": (d.temp_min_c >= d.crop_min_temp_c)
        & (d.temp_max_c <= d.crop_max_temp_c),
        "rain": (d.rainfall_mm >= d.crop_min_weekly_rain_mm)
        & (d.rainfall_mm <= d.crop_max_weekly_rain_mm),
        "humidity": (d.humidity_pct >= d.crop_min_humidity_pct)
        & (d.humidity_pct <= d.crop_max_humidity_pct),
        "ph": (d.soil_ph >= d.crop_ph_min) & (d.soil_ph <= d.crop_ph_max),
    }


def derive(write: bool) -> int:
    import pandas as pd

    if not CSV_PATH.exists():
        print(f"FAIL: dataset not found at {CSV_PATH}", file=sys.stderr)
        return 1

    d = pd.read_csv(CSV_PATH, encoding=CSV_ENCODING, header=CSV_HEADER_ROW)
    print(f"loaded {len(d):,} rows from {CSV_PATH.name}")

    # 1. The thresholds must be constant per crop, or a lookup table is wrong.
    spread = d.groupby("crop")[THRESHOLD_COLUMNS].nunique()
    if (spread != 1).any().any():
        offenders = spread[(spread != 1).any(axis=1)]
        print(
            "FAIL: threshold columns vary within a crop — these are not "
            f"constants and cannot be reduced to a lookup table:\n{offenders}",
            file=sys.stderr,
        )
        return 1
    print("OK: all 8 threshold columns are constant per crop")

    # 2. The inclusive-range rules must reproduce the dataset's own flags.
    derived = _rules(d)
    checks = {
        "temp": "temp_suitable_flag",
        "rain": "rain_suitable_flag",
        "humidity": "humidity_suitable_flag",
        "ph": "ph_suitable_flag",
    }
    ok = True
    for key, column in checks.items():
        match = (derived[key].astype(int) == d[column]).mean()
        print(f"  {key:9s} rule reproduces {column:24s}: {match:.6f}")
        if match != 1.0:
            ok = False

    conjunction = (
        derived["temp"] & derived["rain"] & derived["humidity"] & derived["ph"]
    ).astype(int)
    met = (conjunction == d["conditions_met_flag"]).mean()
    print(f"  all four AND-ed reproduces conditions_met_flag  : {met:.6f}")
    if met != 1.0:
        ok = False

    if not ok:
        print(
            "FAIL: the inclusive-range rules no longer reproduce the dataset's "
            "own flag columns. The dataset's suitability semantics changed — "
            "do not regenerate the bands until you understand how.",
            file=sys.stderr,
        )
        return 1
    print("OK: rules reproduce every flag column exactly")

    # 3. Build the lookup table.
    first = d.groupby("crop")[THRESHOLD_COLUMNS].first()
    bands = {
        crop: {
            "temp_min_c": float(row.crop_min_temp_c),
            "temp_max_c": float(row.crop_max_temp_c),
            "rain_min_mm": float(row.crop_min_weekly_rain_mm),
            "rain_max_mm": float(row.crop_max_weekly_rain_mm),
            "humidity_min_pct": float(row.crop_min_humidity_pct),
            "humidity_max_pct": float(row.crop_max_humidity_pct),
            "ph_min": float(row.crop_ph_min),
            "ph_max": float(row.crop_ph_max),
        }
        for crop, row in first.iterrows()
    }

    payload = {
        "_comment": (
            "Per-crop agronomic suitability bands. GENERATED — do not hand-edit. "
            "Regenerate with: python -m scripts.derive_crop_bands --write. "
            "See backend/scripts/derive_crop_bands.py for the derivation and "
            "its validation against the full training dataset."
        ),
        "source_dataset": CSV_PATH.name,
        "source_rows": int(len(d)),
        "derived_on": str(date.today()),
        "rules": {
            "temp": "crop.temp_min_c <= temp_min_c and temp_max_c <= crop.temp_max_c",
            "rain": "crop.rain_min_mm <= rainfall_mm <= crop.rain_max_mm",
            "humidity": "crop.humidity_min_pct <= humidity_pct <= crop.humidity_max_pct",
            "ph": "crop.ph_min <= soil_ph <= crop.ph_max",
        },
        "bands": bands,
    }

    print()
    print(json.dumps(bands, indent=2, sort_keys=True))

    if write:
        OUT_PATH.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n")
        print(f"\nwrote {OUT_PATH}")
    else:
        print("\n(verify only — pass --write to regenerate the JSON)")
    return 0


if __name__ == "__main__":
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--write", action="store_true", help="regenerate the JSON file")
    sys.exit(derive(p.parse_args().write))
