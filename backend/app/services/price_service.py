"""Market and farmgate price prediction service — per-crop LSTM models."""
import logging
from typing import Dict

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

_LSTM_TIMESTEPS = 8  # historical timesteps the price LSTM expects
_RETAIL_MARKUP = 1.45  # approximate retail/farmgate ratio used during training


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
        model = model_loader.get_model(key)
        scalers = model_loader.get_model("price_scalers")
        crop_scaler = scalers.get(req.crop.value) if isinstance(scalers, dict) else None

        x = _build_sequence(req, crop_scaler)  # shape (1, 8, 9)
        pred = model.predict(x, verbose=0)[0]  # shape (2,): normalized farmgate, retail

        if crop_scaler is not None:
            # Inverse-transform: put predictions in positions 0 (farmgate) and 1 (retail)
            # Scaler order: farmgate, retail, transport, fuel,
            # supply, demand, inflation, holiday, festival
            dummy = np.zeros((1, crop_scaler.n_features_in_))
            dummy[0, 0] = float(pred[0])
            dummy[0, 1] = float(pred[1]) if len(pred) > 1 else float(pred[0])
            result = crop_scaler.inverse_transform(dummy)[0]
            farmgate = max(0.0, round(float(result[0]), 2))
            retail = max(0.0, round(float(result[1]), 2))
        else:
            logger.warning("price_scalers absent for %s — using raw model output", req.crop.value)
            farmgate = round(float(pred[0]), 2)
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


def _build_sequence(req: PricePredictRequest, crop_scaler) -> np.ndarray:
    """Build (1, 8, 9) input sequence for the price LSTM.

    Scaler feature order: farmgate, retail, transport, fuel,
    supply, demand, inflation, holiday, festival.
    Uses lag1/lag2/lag4 to approximate 8 weeks of farmgate history.
    """
    lag1, lag2, lag4 = req.farmgate_price_lag1, req.farmgate_price_lag2, req.farmgate_price_lag4

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
