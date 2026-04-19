"""Yield prediction service — per-crop Random Forest models."""
import logging
from typing import Dict, List

from app.models.loader import model_loader
from app.models.schemas import (
    ConfidenceEnum,
    YieldPredictRequest,
    YieldPredictResponse,
)

logger = logging.getLogger(__name__)

_CROP_KEY: Dict[str, str] = {
    "Carrot": "yield_Carrot",
    "Maize": "yield_Maize",
    "Green gram": "yield_Greengram",
    "Cowpea": "yield_Cowpea",
    "Finger millet": "yield_Fingermillet",
    "Groundnut": "yield_Groundnut",
}
_DISTRICT_IDX = {
    "Nuwara Eliya": 0, "Badulla": 1, "Anuradhapura": 2, "Monaragala": 3,
    "Ampara": 4, "Hambantota": 5, "Batticaloa": 6, "Jaffna": 7,
}
_SEASON_IDX = {"Maha": 0, "Yala": 1, "Inter": 2}
_IRRIGATION_IDX = {"drip": 0, "sprinkler": 1, "flood": 2, "rainfed": 3}


def predict_yield(req: YieldPredictRequest, user_id: str) -> YieldPredictResponse:
    """Predict crop yield for the given agronomic and environmental inputs.

    Inputs: YieldPredictRequest (Pydantic-validated).
    Outputs: YieldPredictResponse with kg/ha prediction.
    Security assumption: user_id is already verified by JWT middleware.
    Returns is_mock=True (with zero values) if the model file is absent.
    """
    key = _CROP_KEY[req.crop.value]

    if not model_loader.is_loaded(key):
        logger.warning("Yield model missing for %s — returning mock", req.crop.value)
        return YieldPredictResponse(
            predicted_yield_kg_per_ha=0.0,
            crop=req.crop,
            district=req.district,
            confidence=ConfidenceEnum.low,
            model_used=key,
            is_mock=True,
        )

    try:
        features = _build_features(req)
        model = model_loader.get_model(key)
        prediction = float(model.predict([features])[0])
        confidence = _confidence_from_model(model, features)

        return YieldPredictResponse(
            predicted_yield_kg_per_ha=round(prediction, 2),
            crop=req.crop,
            district=req.district,
            confidence=confidence,
            model_used=key,
        )
    except Exception as exc:
        logger.error("Yield prediction error crop=%s district=%s: %s", req.crop, req.district, exc)
        raise RuntimeError("Yield prediction unavailable") from exc


def _build_features(req: YieldPredictRequest) -> List[float]:
    """Encode request fields into the numeric feature vector the model expects."""
    return [
        _DISTRICT_IDX[req.district.value],
        _SEASON_IDX[req.season.value],
        req.week_of_year,
        req.rainfall_mm,
        req.temp_min_c,
        req.temp_max_c,
        req.humidity_pct,
        req.wind_speed_kmh,
        req.solar_radiation_mj,
        req.soil_ph,
        req.soil_moisture_pct,
        req.cultivated_area_ha,
        req.fertilizer_index,
        req.pesticide_index,
        _IRRIGATION_IDX[req.irrigation_type.value],
        req.N_index,
        req.P_index,
        req.K_index,
        req.demand_index,
        req.inflation_index,
        req.holiday_flag,
        req.festival_flag,
    ]


def _confidence_from_model(model, features: list) -> ConfidenceEnum:
    """Map model confidence score to high/medium/low enum."""
    fn = getattr(model, "predict_proba", None)
    if fn is None:
        return ConfidenceEnum.medium
    try:
        prob = float(max(fn([features])[0]))
        if prob >= 0.75:
            return ConfidenceEnum.high
        if prob >= 0.5:
            return ConfidenceEnum.medium
        return ConfidenceEnum.low
    except Exception:
        return ConfidenceEnum.medium
