"""Market and farmgate price prediction service — per-crop LSTM models."""

import logging
from pathlib import Path
from typing import Dict, Optional, Tuple

import numpy as np
import pandas as pd

from app.config import get_settings
from app.models.loader import model_loader
from app.models.schemas import (
    AveragePriceSourceEnum,
    ConfidenceEnum,
    PricePredictRequest,
    PricePredictResponse,
)

logger = logging.getLogger(__name__)

_CROP_KEY: Dict[str, str] = {
    "Carrot": "price_Carrot",
    "Maize": "price_Maize",
    "Green gram": "price_Greengram",
    "Cowpea": "price_Cowpea",
    "Finger millet": "price_Fingermillet",
    "Groundnut": "price_Groundnut",
}

_LSTM_TIMESTEPS = 8  # historical timesteps the price LSTM expects
_RETAIL_MARKUP = 1.45  # approximate retail/farmgate ratio used during training

# ─────────────────────────────────────────────────────────────────────────
#  Average farmgate price — static per-crop baseline for the dashboard's
#  price-trend chart. Unlike yield's average (which re-runs the model
#  against a synthetic baseline input), this is a plain per-crop mean read
#  once from the static CSVs already shipped in MODEL_DIR — no model call.
#
#  Source picked per crop: the real dataset's `real_producer_price_lkr_kg`
#  (genuine market observations) when coverage clears
#  _REAL_COVERAGE_THRESHOLD; the synthetic dataset's `farmgate_price_lkr_kg`
#  otherwise. Note the real dataset ALSO has its own `farmgate_price_lkr_kg`
#  column, but that's a synthetic/matched reference value present on every
#  row (even where `real_producer_price_lkr_kg` is NaN) — not an
#  independent second real source — so it is never used as the fallback.
#
#  Coverage check (2026-08, n=4960 real-dataset rows, per crop):
#    Carrot          78.5% (615/783)   → real data used → LKR 224.09/kg
#    Cowpea          52.4% (410/783)   → below 70% bar  → synthetic → LKR 153.66/kg
#    Finger millet   47.5% (372/783)   → below 70% bar  → synthetic → LKR 111.74/kg
#    Green gram      58.1% (455/783)   → below 70% bar  → synthetic → LKR 141.82/kg
#    Groundnut       17.7% (185/1044)  → below 70% bar  → synthetic → LKR 188.02/kg
#    Maize           43.9% (344/783)   → below 70% bar  → synthetic → LKR 45.10/kg
#  Only Carrot cleared the threshold — every other crop falls back to the
#  synthetic mean. Worth flagging: real Carrot (224.09) is ~3.5x the
#  synthetic Carrot figure (64.34) for the same overlapping 2021-2025
#  period — plausibly real Sri Lankan carrot-price volatility the
#  synthetic data doesn't model, not a bug, but it means Carrot's baseline
#  sits on a different scale than the other five crops' synthetic-sourced
#  baselines. Re-run _load_average_farmgate_prices() (restart the server)
#  after any dataset refresh to recompute.
# ─────────────────────────────────────────────────────────────────────────
_REAL_COVERAGE_THRESHOLD = 0.70

# crop -> (average LKR/kg, which dataset it came from)
_avg_price_cache: Dict[str, Tuple[float, AveragePriceSourceEnum]] = {}
# Whether the CSV read has been attempted, regardless of whether it yielded
# anything. Emptiness alone cannot mean "not warmed yet": when the datasets
# are unreadable the cache stays empty forever, and every /api/price/predict
# would re-open both CSVs across four candidate encodings.
_avg_price_warmed = False

# Last-resort values if the CSVs are missing entirely in some environment —
# the coverage-checked figures above, frozen at the time this was written,
# each tagged with the source it was actually derived from so the reported
# provenance stays truthful even on this path.
_AVG_PRICE_FALLBACK: Dict[str, Tuple[float, AveragePriceSourceEnum]] = {
    "Carrot": (224.09, AveragePriceSourceEnum.real),
    "Maize": (45.10, AveragePriceSourceEnum.synthetic),
    "Green gram": (141.82, AveragePriceSourceEnum.synthetic),
    "Cowpea": (153.66, AveragePriceSourceEnum.synthetic),
    "Finger millet": (111.74, AveragePriceSourceEnum.synthetic),
    "Groundnut": (188.02, AveragePriceSourceEnum.synthetic),
}


def predict_price(req: PricePredictRequest, user_id: str) -> PricePredictResponse:
    """Predict farmgate and retail prices for the given crop and district.

    Inputs: PricePredictRequest (Pydantic-validated).
    Outputs: PricePredictResponse with LKR/kg predictions.
    Security assumption: user_id verified by JWT middleware.
    Returns is_mock=True if LSTM model file is absent.
    """
    key = _CROP_KEY[req.crop.value]

    if not model_loader.is_loaded(key):
        logger.warning("Price model missing for %s — returning mock", req.crop.value)
        return PricePredictResponse(
            crop=req.crop,
            district=req.district,
            predicted_farmgate_price_lkr_kg=0.0,
            predicted_retail_price_lkr_kg=0.0,
            average_farmgate_price_lkr_kg=0.0,
            average_price_source=None,
            confidence=ConfidenceEnum.low,
            is_mock=True,
        )

    try:
        model = model_loader.get_model(key)
        scalers = model_loader.get_model("price_scalers")
        crop_scaler = scalers.get(req.crop.value) if isinstance(scalers, dict) else None

        x = _build_sequence(req, crop_scaler)  # shape (1, 8, 9)
        pred = model.predict(x, verbose=0)[0]  # shape (2,): normalized farmgate, retail

        if crop_scaler is not None:
            # Inverse-transform: farmgate at pos 0, retail at pos 1
            # Scaler order: farmgate, retail, transport, fuel,
            # supply, demand, inflation, holiday, festival
            dummy = np.zeros((1, crop_scaler.n_features_in_))
            dummy[0, 0] = float(pred[0])
            dummy[0, 1] = float(pred[1]) if len(pred) > 1 else float(pred[0])
            result = crop_scaler.inverse_transform(dummy)[0]
            farmgate = max(0.0, round(float(result[0]), 2))
            retail = max(0.0, round(float(result[1]), 2))
        else:
            logger.warning(
                "price_scalers absent for %s — using raw model output", req.crop.value
            )
            farmgate = round(float(pred[0]), 2)
            retail = round(float(pred[1]) if len(pred) > 1 else farmgate * 1.25, 2)

        average, average_source = _get_average_farmgate_price(req.crop.value)

        logger.info(
            "Price prediction: crop=%s district=%s predicted=%.2f average=%.2f (%s)",
            req.crop.value,
            req.district.value,
            farmgate,
            average,
            average_source.value if average_source else "unavailable",
        )

        return PricePredictResponse(
            crop=req.crop,
            district=req.district,
            predicted_farmgate_price_lkr_kg=farmgate,
            predicted_retail_price_lkr_kg=retail,
            average_farmgate_price_lkr_kg=average,
            average_price_source=average_source,
            confidence=ConfidenceEnum.medium,
        )
    except Exception as exc:
        logger.error("Price prediction error crop=%s: %s", req.crop, exc)
        raise RuntimeError("Price prediction unavailable") from exc


def predict_price_internal(req: PricePredictRequest) -> PricePredictResponse:
    """Internal call used by recommend_service — no user audit context needed."""
    return predict_price(req, user_id="system")


def _read_csv_safe(path: Path, **kwargs) -> pd.DataFrame:
    """Try known encodings — these CSVs were exported from Colab as Latin-1."""
    for enc in ("latin-1", "cp1252", "iso-8859-1", "utf-8"):
        try:
            return pd.read_csv(path, encoding=enc, **kwargs)
        except UnicodeDecodeError:
            continue
    raise ValueError(f"Cannot read {path} with any known encoding.")


def _load_average_farmgate_prices() -> Dict[str, Tuple[float, AveragePriceSourceEnum]]:
    """Compute each crop's average farmgate price once, from the static CSVs.

    No model call — a plain per-crop mean. Prefers the real dataset's
    `real_producer_price_lkr_kg` when its non-NaN coverage for that crop
    clears _REAL_COVERAGE_THRESHOLD; falls back to the synthetic dataset's
    `farmgate_price_lkr_kg` otherwise. See the module-level comment above
    for the coverage numbers this was decided from.

    Returns crop -> (average, source) so callers can report which dataset
    each figure came from.
    """
    model_dir = Path(get_settings().MODEL_DIR)
    result: Dict[str, Tuple[float, AveragePriceSourceEnum]] = {}

    real_df: Optional[pd.DataFrame] = None
    try:
        real_df = _read_csv_safe(model_dir / "Cropsphere_Real_Test_Dataset.csv")
    except Exception as exc:
        logger.warning("Could not read real price dataset: %s", exc)

    synthetic_df: Optional[pd.DataFrame] = None
    try:
        # Two-row header (category names on row 0) — skip to the real
        # column-name row, same as the synthetic dataset elsewhere.
        synthetic_df = _read_csv_safe(
            model_dir / "CropSphere_SL_Synthetic_Weekly.csv", header=1
        )
    except Exception as exc:
        logger.warning("Could not read synthetic price dataset: %s", exc)

    for crop_name in _CROP_KEY:
        avg: Optional[float] = None
        source: Optional[AveragePriceSourceEnum] = None
        detail = ""

        if real_df is not None and "crop" in real_df.columns:
            rows = real_df.loc[
                real_df["crop"] == crop_name, "real_producer_price_lkr_kg"
            ]
            coverage = float(rows.notna().mean()) if len(rows) else 0.0
            if coverage >= _REAL_COVERAGE_THRESHOLD:
                avg = round(float(rows.mean()), 2)
                source = AveragePriceSourceEnum.real
                detail = f"real, {coverage:.1%} coverage"

        if avg is None and synthetic_df is not None and "crop" in synthetic_df.columns:
            rows = synthetic_df.loc[
                synthetic_df["crop"] == crop_name, "farmgate_price_lkr_kg"
            ]
            if len(rows):
                avg = round(float(rows.mean()), 2)
                source = AveragePriceSourceEnum.synthetic
                detail = "synthetic — real coverage below threshold"

        if avg is not None and source is not None:
            result[crop_name] = (avg, source)
            logger.info(
                "Average farmgate price cached: %s = %.2f LKR/kg (%s)",
                crop_name,
                avg,
                detail,
            )
        else:
            logger.warning(
                "No price data available for %s — average price unavailable", crop_name
            )

    return result


def warm_average_farmgate_prices() -> None:
    """Populate the average-price cache eagerly.

    Called once from the app's startup lifespan (see main.py) so the CSV
    read happens at boot, not on the first /api/price/predict request.
    """
    global _avg_price_warmed
    if _avg_price_warmed:
        return
    _avg_price_cache.update(_load_average_farmgate_prices())
    _avg_price_warmed = True


def _get_average_farmgate_price(
    crop_name: str,
) -> Tuple[float, Optional[AveragePriceSourceEnum]]:
    """Return the cached average farmgate price for a crop.

    Normally already warmed by warm_average_farmgate_prices() at startup;
    this lazily computes it if that warm-up was skipped (e.g. a test
    calling predict_price() directly, or startup warm-up itself failing).

    Returns (average, source); source is None only if the crop is absent
    from both the cache and the frozen fallback table.
    """
    if not _avg_price_warmed:
        warm_average_farmgate_prices()

    if crop_name in _avg_price_cache:
        return _avg_price_cache[crop_name]
    if crop_name in _AVG_PRICE_FALLBACK:
        return _AVG_PRICE_FALLBACK[crop_name]
    return 0.0, None


def _build_sequence(req: PricePredictRequest, crop_scaler) -> np.ndarray:
    """Build (1, 8, 9) input sequence for the price LSTM.

    Scaler feature order: farmgate, retail, transport, fuel,
    supply, demand, inflation, holiday, festival.
    Uses lag1/lag2/lag4 to approximate 8 weeks of farmgate history.
    """
    lag1, lag2, lag4 = (
        req.farmgate_price_lag1,
        req.farmgate_price_lag2,
        req.farmgate_price_lag4,
    )

    # 8 historical steps, oldest to newest
    farmgate_hist = [lag4, lag4, lag4, lag4, lag2, lag2, lag1, lag1]

    sequence = [
        [
            fg,
            fg * _RETAIL_MARKUP,
            req.transport_cost_index,
            req.fuel_price_index,
            req.supply_index,
            req.demand_index,
            req.inflation_index,
            float(req.holiday_flag),
            float(req.festival_flag),
        ]
        for fg in farmgate_hist
    ]

    seq_arr = np.array([sequence], dtype=np.float64)  # (1, 8, 9)

    if crop_scaler is not None:
        scaled = crop_scaler.transform(seq_arr.reshape(-1, 9))  # (8, 9)
        return scaled.reshape(1, _LSTM_TIMESTEPS, 9).astype(np.float32)

    return seq_arr.astype(np.float32)
