"""Market and farmgate price prediction service — per-crop LSTM models."""
import logging
from typing import Dict, List

import numpy as np

from app.models.loader import model_loader
from app.models.schemas import (
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
_DISTRICT_IDX = {
    "Nuwara Eliya": 0, "Badulla": 1, "Anuradhapura": 2, "Monaragala": 3,
    "Ampara": 4, "Hambantota": 5, "Batticaloa": 6, "Jaffna": 7,
}
_SEASON_IDX = {"Maha": 0, "Yala": 1, "Inter": 2}


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
            confidence=ConfidenceEnum.low,
            is_mock=True,
        )

    try:
        features = _build_features(req)
        model = model_loader.get_model(key)
        x = np.array([[features]], dtype=np.float32)
        pred = model.predict(x, verbose=0)[0]

        farmgate = round(float(pred[0]), 2)
        # Retail markup of 25 % if the model only outputs one value
        retail = round(float(pred[1]) if len(pred) > 1 else farmgate * 1.25, 2)

        return PricePredictResponse(
            crop=req.crop,
            district=req.district,
            predicted_farmgate_price_lkr_kg=farmgate,
            predicted_retail_price_lkr_kg=retail,
            confidence=ConfidenceEnum.medium,
        )
    except Exception as exc:
        logger.error("Price prediction error crop=%s: %s", req.crop, exc)
        raise RuntimeError("Price prediction unavailable") from exc


def predict_price_internal(req: PricePredictRequest) -> PricePredictResponse:
    """Internal call used by recommend_service — no user audit context needed."""
    return predict_price(req, user_id="system")


def _build_features(req: PricePredictRequest) -> List[float]:
    return [
        _DISTRICT_IDX[req.district.value],
        _SEASON_IDX[req.season.value],
        req.week_of_year,
        req.inflation_index,
        req.fuel_price_index,
        req.transport_cost_index,
        req.supply_index,
        req.demand_index,
        req.holiday_flag,
        req.festival_flag,
        req.farmgate_price_lag1,
        req.farmgate_price_lag2,
        req.farmgate_price_lag4,
    ]
