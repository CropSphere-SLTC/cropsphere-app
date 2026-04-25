"""Consumer demand prediction service — per-crop XGBoost models."""
import logging
from typing import Dict, List

import numpy as np

from app.models.loader import model_loader
from app.models.schemas import (
    ConfidenceEnum,
    DemandPredictRequest,
    DemandPredictResponse,
    TrendEnum,
)

logger = logging.getLogger(__name__)

_CROP_KEY: Dict[str, str] = {
    "Carrot": "demand_Carrot",
    "Maize": "demand_Maize",
    "Green gram": "demand_Greengram",
    "Cowpea": "demand_Cowpea",
    "Finger millet": "demand_Fingermillet",
    "Groundnut": "demand_Groundnut",
}

# Derived from M4 LabelEncoder (same season ordering as M1)
_SEASON_ENC = {"Inter": 0, "Maha": 1, "Yala": 2}

# FEAT_COLS order (from M4_config.pkl):
# demand_index, consumer_pref_index, search_trend_index, retail_price_lkr_kg,
# farmgate_price_lkr_kg, inflation_index, supply_index, holiday_flag, festival_flag,
# week_of_year, demand_lag1..12, demand_roll4_mean, demand_roll4_std, demand_roll8_mean,
# price_change_pct, season_enc, district_enc


def predict_demand(req: DemandPredictRequest, user_id: str) -> DemandPredictResponse:
    """Predict consumer demand index and trend for the given crop.

    Inputs: DemandPredictRequest (Pydantic-validated).
    Outputs: DemandPredictResponse with demand index and rising/stable/falling trend.
    Security assumption: user_id verified by JWT middleware.
    Returns is_mock=True if XGBoost model file is absent.
    """
    key = _CROP_KEY[req.crop.value]

    if not model_loader.is_loaded(key):
        logger.warning("Demand model missing for %s — returning mock", req.crop.value)
        return DemandPredictResponse(
            crop=req.crop,
            predicted_demand_index=0.0,
            trend=TrendEnum.stable,
            confidence=ConfidenceEnum.low,
            is_mock=True,
        )

    try:
        features = _build_features(req)
        model = model_loader.get_model(key)
        prediction = float(model.predict([features])[0])
        trend = _infer_trend(prediction, req.demand_lag1)

        return DemandPredictResponse(
            crop=req.crop,
            predicted_demand_index=round(prediction, 2),
            trend=trend,
            confidence=ConfidenceEnum.medium,
        )
    except Exception as exc:
        logger.error("Demand prediction error crop=%s: %s", req.crop, exc)
        raise RuntimeError("Demand prediction unavailable") from exc


def _build_features(req: DemandPredictRequest) -> List[float]:
    """Build 22-feature vector matching the training pipeline (M4_config FEAT_COLS).

    Missing request fields are approximated with sensible defaults:
    - farmgate_price_lkr_kg ≈ 0.75 × retail_price (typical markup inverse)
    - supply_index: 100.0 (neutral)
    - demand_lag3: interpolated from lag2 and lag4
    - demand_lag8/12: approximated from lag4
    - district_enc: 0 (not in request schema)
    """
    lag1, lag2, lag4 = req.demand_lag1, req.demand_lag2, req.demand_lag4
    lag3 = (lag2 + lag4) / 2.0
    lag8  = lag4
    lag12 = lag4

    lags_4 = [lag1, lag2, lag3, lag4]
    roll4_mean = float(np.mean(lags_4))
    roll4_std  = float(np.std(lags_4))
    roll8_mean = roll4_mean  # approximation

    farmgate_approx = req.retail_price_lkr_kg * 0.75
    season_enc = _SEASON_ENC.get(req.season.value, 0)

    return [
        lag1,                          # 0  demand_index (use most recent lag as proxy)
        req.consumer_pref_index,       # 1  consumer_pref_index
        req.search_trend_index,        # 2  search_trend_index
        req.retail_price_lkr_kg,       # 3  retail_price_lkr_kg
        farmgate_approx,               # 4  farmgate_price_lkr_kg (approx)
        req.inflation_index,           # 5  inflation_index
        100.0,                         # 6  supply_index (default neutral)
        float(req.holiday_flag),       # 7  holiday_flag
        float(req.festival_flag),      # 8  festival_flag
        req.week_of_year,              # 9  week_of_year
        lag1,                          # 10 demand_lag1
        lag2,                          # 11 demand_lag2
        lag3,                          # 12 demand_lag3 (interpolated)
        lag4,                          # 13 demand_lag4
        lag8,                          # 14 demand_lag8 (approx)
        lag12,                         # 15 demand_lag12 (approx)
        roll4_mean,                    # 16 demand_roll4_mean
        roll4_std,                     # 17 demand_roll4_std
        roll8_mean,                    # 18 demand_roll8_mean
        0.0,                           # 19 price_change_pct (not available)
        season_enc,                    # 20 season_enc
        0,                             # 21 district_enc (not in request, default 0)
    ]


def _infer_trend(predicted: float, lag1: float) -> TrendEnum:
    """Classify demand movement relative to the most recent lag."""
    delta = predicted - lag1
    if delta > 5:
        return TrendEnum.rising
    if delta < -5:
        return TrendEnum.falling
    return TrendEnum.stable
