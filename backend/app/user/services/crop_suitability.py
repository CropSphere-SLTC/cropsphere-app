"""Per-crop agronomic suitability — the four flags the recommendation UI shows.

The UI renders "N of M conditions are ideal" per recommended crop. The four
conditions are temperature, weekly rainfall, humidity and soil pH, each checked
against a band specific to that crop.

Bands live in `backend/data/crop_agronomic_bands.json`, generated and validated
by `backend/scripts/derive_crop_bands.py` against every row of the training
dataset (4,978 weekly rows, all six crops). They are deliberately NOT inlined
here: the numbers are
derived from data, so they belong next to their derivation, and regenerating
them must not mean editing Python. See that script for full provenance.

Historical note — what this replaces: the service used to emit
`{yield_modelled, price_modelled, any_mock}`, which describe *model health*,
not the crop. Because `any_mock` is exactly `not (yield_modelled and
price_modelled)`, at most two of those three could ever be true, so the UI's
"Good match" branch (which needs >= 70% of flags true) was unreachable in all
four possible states and every crop always rendered "Fair match — only 2 of 3".
"""

from __future__ import annotations

import json
import logging
from pathlib import Path
from typing import Dict, Optional

logger = logging.getLogger(__name__)

_BANDS_PATH = Path(__file__).resolve().parents[3] / "data" / "crop_agronomic_bands.json"

# Flag order is the display order; the UI counts true values, so keep the most
# decisive condition first for readability in logs and API responses.
FLAG_NAMES = ("temp_suitable", "rain_suitable", "humidity_suitable", "ph_suitable")

_bands: Optional[Dict[str, Dict[str, float]]] = None


def load_bands() -> Dict[str, Dict[str, float]]:
    """Return {crop: band dict}, reading the JSON once and caching it."""
    global _bands
    if _bands is None:
        with _BANDS_PATH.open() as fh:
            _bands = json.load(fh)["bands"]
        logger.info("Loaded agronomic bands for %d crops", len(_bands))
    return _bands


def evaluate(
    crop: str,
    *,
    temp_min_c: float,
    temp_max_c: float,
    rainfall_mm: float,
    humidity_pct: float,
    soil_ph: float,
) -> Dict[str, bool]:
    """Return the four suitability flags for one crop under given conditions.

    Rules are inclusive on both ends and mirror the training dataset exactly
    (verified at 1.0 agreement against its own flag columns).

    Temperature is a containment check, not a midpoint one: the whole observed
    range must sit inside the crop's tolerance, so a crop fails if either the
    cold night or the hot afternoon falls outside it. This is what correctly
    rules Carrot (28 C ceiling) out of the low country while keeping it viable
    up in Nuwara Eliya.

    An unknown crop yields all-false rather than raising — a missing band must
    degrade the badge, never fail the whole recommendation request.
    """
    band = load_bands().get(crop)
    if band is None:
        logger.warning("No agronomic band for crop %r — flags default to false", crop)
        return {name: False for name in FLAG_NAMES}

    return {
        "temp_suitable": band["temp_min_c"] <= temp_min_c
        and temp_max_c <= band["temp_max_c"],
        "rain_suitable": band["rain_min_mm"] <= rainfall_mm <= band["rain_max_mm"],
        "humidity_suitable": band["humidity_min_pct"]
        <= humidity_pct
        <= band["humidity_max_pct"],
        "ph_suitable": band["ph_min"] <= soil_ph <= band["ph_max"],
    }


def assert_bands_available() -> None:
    """Fail loudly at boot if the bands file is missing or malformed.

    Without this the first `/api/recommend` call raises inside request handling
    and returns a 500 — or, worse, a future refactor makes it degrade to
    all-false flags and every crop silently reads "0 of 4". Same shift-left
    rationale as `recommend_service.assert_feature_contract`.
    """
    from app.models.schemas import CropEnum

    try:
        bands = load_bands()
    except (OSError, ValueError, KeyError) as exc:
        raise RuntimeError(
            f"Agronomic bands unreadable at {_BANDS_PATH}: {exc}. Regenerate "
            "with: python -m scripts.derive_crop_bands --write"
        ) from exc

    missing = sorted({c.value for c in CropEnum} - set(bands))
    if missing:
        raise RuntimeError(
            f"Agronomic bands missing for {missing}. The bands file is stale "
            "relative to CropEnum — regenerate with: "
            "python -m scripts.derive_crop_bands --write"
        )

    logger.info("Agronomic bands OK — %d crops", len(bands))
