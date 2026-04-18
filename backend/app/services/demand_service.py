"""Consumer demand prediction service — per-crop XGBoost models."""
import logging
from typing import Dict, List

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
_SEASON_IDX = {"Maha": 0, "Yala": 1, "Inter": 2}


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
    return [
        _SEASON_IDX[req.season.value],
        req.week_of_year,
        req.demand_lag1,
        req.demand_lag2,
        req.demand_lag4,
        req.retail_price_lkr_kg,
        req.inflation_index,
        req.holiday_flag,
        req.festival_flag,
        req.consumer_pref_index,
        req.search_trend_index,
    ]


def _infer_trend(predicted: float, lag1: float) -> TrendEnum:
    """Classify demand movement relative to the most recent lag."""
    delta = predicted - lag1
    if delta > 5:
        return TrendEnum.rising
    if delta < -5:
        return TrendEnum.falling
    return TrendEnum.stable
