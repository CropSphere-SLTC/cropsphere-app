"""Derive which districts M2's weather forecast cannot be trusted for.

WHY THIS EXISTS
---------------
M2 (weather) and the agronomic bands come from DIFFERENT datasets:

  * M2's scaler was fit on `Cropsphere_Real_Test_Dataset.csv` — verified by
    the scaler's per-feature ranges matching that file to the decimal on all
    six features.
  * The bands come from `CropSphere_SL_Synthetic_Weekly.csv` (see
    derive_crop_bands.py).

Both are weekly, and they agree on rainfall. They do NOT agree on temperature
for the hill country. `Cropsphere_Real_Test_Dataset.csv` records Nuwara Eliya
at a mean weekly maximum of 34.0 C — that is dry-zone weather attached to a
district at roughly 1,900 m, whose real maximum is around 19 C. Badulla is
wrong the same way, less severely.

The consequence is not a slightly-off forecast. `_DISTRICT_CLIMATE` seeds
Nuwara Eliya with a CORRECT 22 C maximum, which falls below the scaler's
fitted floor of 27.81 C, normalizes to -0.441, and drives the LSTM to a
rainfall output of 1.6mm against a training mean of 41.8mm. Sweeping temp_max
alone across the seed moves predicted rainfall from 1.58 to 68.28 — a 43x
swing driven entirely by a variable that is not rainfall.

So the seed is right and the training data is wrong, and no seed value fixes
it: raising the seed into range would mean asserting that Nuwara Eliya is hot.
The real fix is retraining M2 on corrected hill-country data. Until then the
affected districts are marked and disclosed rather than silently served.

WHY DISAGREEMENT AND NOT THE SCALER RANGE
-----------------------------------------
An out-of-range seed looks like the obvious trigger, but it does not identify
the right districts. Four of the eight breach the range; two of those
(Hambantota, Jaffna, both marginally below the humidity floor) produce the
most accurate forecasts of the set, landing within 3% of their training means.
Gating on the excursion would put a low-confidence badge on forecasts that
have earned the opposite, which devalues the badge everywhere it appears.

Dataset disagreement separates cleanly, and says what is actually wrong:

    Nuwara Eliya  34.0 vs 18.9   delta 15.1   <- untrusted
    Badulla       31.6 vs 26.0   delta  5.6   <- untrusted
    Monaragala    34.1 vs 33.0   delta  1.1
    everything else              delta <0.5

A 3 C threshold sits with a 5x margin below the smaller of the two offenders
and a 3x margin above the largest of the rest. The range check still runs, as
a loud diagnostic — see weather_service.assert_weather_seeds_in_range.

USAGE
-----
    python -m scripts.check_weather_trust        # verify the constant matches
    python -m scripts.check_weather_trust --list # print the derived set

Run this after either dataset changes. If it disagrees with
weather_service._UNTRUSTED_FORECAST_DISTRICTS, one of them is stale.
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

BACKEND = Path(__file__).resolve().parents[1]
M2_DATASET = BACKEND / "models" / "files" / "Cropsphere_Real_Test_Dataset.csv"
BAND_DATASET = BACKEND / "models" / "files" / "CropSphere_SL_Synthetic_Weekly.csv"

# Degrees C of mean weekly-maximum disagreement above which M2's view of a
# district is treated as wrong. See the module docstring for the margins.
DISAGREEMENT_THRESHOLD_C = 3.0


def derive() -> dict:
    import pandas as pd

    m2 = pd.read_csv(M2_DATASET, encoding="latin-1")
    bands = pd.read_csv(BAND_DATASET, encoding="latin-1", header=1)

    deltas = {}
    for district in sorted(set(m2.district.unique()) & set(bands.district.unique())):
        a = m2[m2.district == district].temp_max_c.mean()
        b = bands[bands.district == district].temp_max_c.mean()
        deltas[district] = (a, b, abs(a - b))
    return deltas


def main(list_only: bool) -> int:
    deltas = derive()
    untrusted = {d for d, (_, _, delta) in deltas.items() if delta > DISAGREEMENT_THRESHOLD_C}

    if list_only:
        print("\n".join(sorted(untrusted)))
        return 0

    print(f"mean weekly temp_max, M2 training vs agronomic-band dataset")
    print(f"{'district':14s} {'M2':>7s} {'bands':>7s} {'delta':>7s}")
    print("-" * 46)
    for district, (a, b, delta) in sorted(deltas.items(), key=lambda x: -x[1][2]):
        mark = "  <- UNTRUSTED" if delta > DISAGREEMENT_THRESHOLD_C else ""
        print(f"{district:14s} {a:7.1f} {b:7.1f} {delta:7.1f}{mark}")

    from app.user.services.weather_service import _UNTRUSTED_FORECAST_DISTRICTS

    print()
    if untrusted == _UNTRUSTED_FORECAST_DISTRICTS:
        print(f"OK: weather_service constant matches — {sorted(untrusted)}")
        return 0
    print(
        "FAIL: weather_service._UNTRUSTED_FORECAST_DISTRICTS is stale.\n"
        f"  derived from data: {sorted(untrusted)}\n"
        f"  in weather_service: {sorted(_UNTRUSTED_FORECAST_DISTRICTS)}",
        file=sys.stderr,
    )
    return 1


if __name__ == "__main__":
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--list", action="store_true", help="print the derived set only")
    sys.exit(main(p.parse_args().list))
