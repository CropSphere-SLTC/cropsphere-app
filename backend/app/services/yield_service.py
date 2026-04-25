"""Yield prediction service — per-crop Random Forest models."""
import logging
from datetime import date
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

# Maha: ~Oct(wk40)–Mar(wk12); Yala: ~Apr(wk14)–Sep(wk39); Inter: rest
_SEASON_START_WEEK = {"Maha": 40, "Yala": 14, "Inter": 1}
_SEASON_DURATION   = {"Maha": 24, "Yala": 24, "Inter": 12}

# Irrigation types the encoder was trained on; map unseen values to nearest
_IRRIGATION_MAP = {"drip": "drip", "sprinkler": "drip", "flood": "canal", "rainfed": "rainfed"}

# Seed varieties and prev-crop labels known to the encoder
_KNOWN_SEED_VARIETIES = {
    "Bushitao", "Chantenay", "HORDI Maize 1", "Harsha", "Local", "Local Hybrid",
    "MI 5", "MI 6", "MICP 1", "Nantes", "Ravana", "Ravi", "Ruwan", "Tissa", "Walawa",
}
_KNOWN_PREV_CROPS = {"Carrot", "Cowpea", "Finger millet", "Green gram", "Groundnut", "Maize", "Unknown"}


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
    """Build the 35-feature vector matching the training pipeline.

    Feature order (from M1_features.pkl):
    week_of_year, week_of_season, season_progress, year,
    crop_enc, district_enc, season_enc,
    rainfall_mm, temp_min_c, temp_max_c, humidity_pct, wind_speed_kmh, solar_radiation_mj,
    temp_range, heat_stress_flag, cold_stress_flag, rain_adequacy,
    cultivated_area_ha, fertilizer_index, pesticide_index, soil_ph, soil_moisture_pct,
    irrigation_type_enc, seed_variety_enc,
    N_index, P_index, K_index, nutrient_score, mgmt_score,
    prev_crop_enc, inflation_index, demand_index, consumer_pref_index,
    holiday_flag, festival_flag
    """
    encoders: Dict = model_loader.get_model("yield_encoders") or {}

    # Time features
    wos = _week_of_season(req.week_of_year, req.season.value)
    season_prog = wos / _SEASON_DURATION.get(req.season.value, 24)
    year = date.today().year

    # Label-encoded categoricals — fall back to 0 for unseen labels
    crop_enc = _safe_encode(encoders.get("crop"), req.crop.value)
    district_enc = _safe_encode(encoders.get("district"), req.district.value)
    season_enc = _safe_encode(encoders.get("season"), req.season.value)

    irr_mapped = _IRRIGATION_MAP.get(req.irrigation_type.value, "drip")
    irrigation_enc = _safe_encode(encoders.get("irrigation_type"), irr_mapped)

    sv = req.seed_variety if req.seed_variety in _KNOWN_SEED_VARIETIES else "Local"
    seed_enc = _safe_encode(encoders.get("seed_variety"), sv)

    pc = req.prev_crop if req.prev_crop in _KNOWN_PREV_CROPS else "Unknown"
    prev_crop_enc = _safe_encode(encoders.get("prev_crop"), pc)

    # Derived weather features
    temp_range = req.temp_max_c - req.temp_min_c
    heat_stress = 1 if req.temp_max_c > 35.0 else 0
    cold_stress = 1 if req.temp_min_c < 12.0 else 0
    rain_adequacy = min(req.rainfall_mm / 100.0, 2.0)

    # Derived management scores
    nutrient_score = (req.N_index + req.P_index + req.K_index) / 3.0
    mgmt_score = (req.fertilizer_index + req.pesticide_index) / 2.0

    return [
        req.week_of_year,          # 0  week_of_year
        wos,                        # 1  week_of_season
        season_prog,                # 2  season_progress
        year,                       # 3  year
        crop_enc,                   # 4  crop_enc
        district_enc,               # 5  district_enc
        season_enc,                 # 6  season_enc
        req.rainfall_mm,            # 7  rainfall_mm
        req.temp_min_c,             # 8  temp_min_c
        req.temp_max_c,             # 9  temp_max_c
        req.humidity_pct,           # 10 humidity_pct
        req.wind_speed_kmh,         # 11 wind_speed_kmh
        req.solar_radiation_mj,     # 12 solar_radiation_mj
        temp_range,                 # 13 temp_range
        heat_stress,                # 14 heat_stress_flag
        cold_stress,                # 15 cold_stress_flag
        rain_adequacy,              # 16 rain_adequacy
        req.cultivated_area_ha,     # 17 cultivated_area_ha
        req.fertilizer_index,       # 18 fertilizer_index
        req.pesticide_index,        # 19 pesticide_index
        req.soil_ph,                # 20 soil_ph
        req.soil_moisture_pct,      # 21 soil_moisture_pct
        irrigation_enc,             # 22 irrigation_type_enc
        seed_enc,                   # 23 seed_variety_enc
        req.N_index,                # 24 N_index
        req.P_index,                # 25 P_index
        req.K_index,                # 26 K_index
        nutrient_score,             # 27 nutrient_score
        mgmt_score,                 # 28 mgmt_score
        prev_crop_enc,              # 29 prev_crop_enc
        req.inflation_index,        # 30 inflation_index
        req.demand_index,           # 31 demand_index
        50.0,                       # 32 consumer_pref_index (not in request — use midpoint)
        req.holiday_flag,           # 33 holiday_flag
        req.festival_flag,          # 34 festival_flag
    ]


def _week_of_season(week_of_year: int, season: str) -> int:
    start = _SEASON_START_WEEK.get(season, 1)
    if week_of_year >= start:
        wos = week_of_year - start + 1
    else:
        wos = (52 - start) + week_of_year + 1
    return max(1, min(wos, _SEASON_DURATION.get(season, 24)))


def _safe_encode(encoder, value: str, default: int = 0) -> int:
    if encoder is None:
        return default
    try:
        return int(encoder.transform([value])[0])
    except Exception:
        return default


def _confidence_from_model(model, features: list) -> ConfidenceEnum:
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
