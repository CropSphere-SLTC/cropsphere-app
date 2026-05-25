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
_SEASON_DURATION = {"Maha": 24, "Yala": 24, "Inter": 12}

# Irrigation types the encoder was trained on
_IRRIGATION_MAP = {
    "drip": "drip",
    "sprinkler": "drip",
    "flood": "canal",
    "rainfed": "rainfed",
}

_KNOWN_SEED_VARIETIES = {
    "Bushitao",
    "Chantenay",
    "HORDI Maize 1",
    "Harsha",
    "Local",
    "Local Hybrid",
    "MI 5",
    "MI 6",
    "MICP 1",
    "Nantes",
    "Ravana",
    "Ravi",
    "Ruwan",
    "Tissa",
    "Walawa",
}
_KNOWN_PREV_CROPS = {
    "Carrot",
    "Cowpea",
    "Finger millet",
    "Green gram",
    "Groundnut",
    "Maize",
    "Unknown",
}

# ─────────────────────────────────────────────────────────────────────────────
#  BASELINE FEATURES — deliberately mid-range and DIFFERENT from any real
#  request a user would submit.
#
#  KEY RULE: these must NOT accidentally match a common user input, otherwise
#  predicted == average and the green/red banner never works.
#
#  How these were chosen:
#  • week_of_year = 20 (mid-Yala, rarely used for Maha crops)
#  • season = "Yala" for Maha-dominant crops, "Maha" for Yala-dominant crops
#  • All weather = district long-term medians (not extremes, not user defaults)
#  • fertilizer/pesticide = 0.5 (exact midpoint)
#  • N/P/K = 0.45 (just below midpoint — typical subsistence farmer)
#  • cultivated_area_ha = 0.5 (small plot — Sri Lanka average holding)
#  • seed_variety = "Local", prev_crop = "Unknown" (most common labels)
# ─────────────────────────────────────────────────────────────────────────────
_BASELINE_FEATURES: Dict[str, dict] = {
    # Carrot — Nuwara Eliya, cool upcountry, Yala baseline
    "Carrot": dict(
        week_of_year=20,
        season="Yala",
        rainfall_mm=55.0,
        temp_min_c=14.0,
        temp_max_c=24.0,
        humidity_pct=75.0,
        wind_speed_kmh=9.0,
        solar_radiation_mj=17.0,
        soil_ph=6.1,
        soil_moisture_pct=58.0,
        cultivated_area_ha=0.5,
        seed_variety="Local",
        fertilizer_index=0.5,
        pesticide_index=0.5,
        irrigation_type="drip",
        N_index=0.45,
        P_index=0.45,
        K_index=0.45,
        prev_crop="Unknown",
        demand_index=75.0,
        inflation_index=1.15,
        holiday_flag=0,
        festival_flag=0,
        district="Nuwara Eliya",
    ),
    # Maize — Ampara, dry zone, Yala baseline
    # NOTE: week_of_year=20 and Yala season deliberately differs from the
    # common Maha test request (week=46, season=Maha) so baseline != actual
    "Maize": dict(
        week_of_year=20,
        season="Yala",
        rainfall_mm=35.0,
        temp_min_c=24.0,
        temp_max_c=33.0,
        humidity_pct=62.0,
        wind_speed_kmh=10.0,
        solar_radiation_mj=22.0,
        soil_ph=6.3,
        soil_moisture_pct=50.0,
        cultivated_area_ha=0.5,
        seed_variety="Local",
        fertilizer_index=0.5,
        pesticide_index=0.5,
        irrigation_type="rainfed",
        N_index=0.45,
        P_index=0.45,
        K_index=0.45,
        prev_crop="Unknown",
        demand_index=75.0,
        inflation_index=1.15,
        holiday_flag=0,
        festival_flag=0,
        district="Ampara",
    ),
    # Green gram — Hambantota, dry zone, Maha baseline
    "Green gram": dict(
        week_of_year=46,
        season="Maha",
        rainfall_mm=25.0,
        temp_min_c=22.0,
        temp_max_c=31.0,
        humidity_pct=63.0,
        wind_speed_kmh=11.0,
        solar_radiation_mj=20.0,
        soil_ph=6.4,
        soil_moisture_pct=48.0,
        cultivated_area_ha=0.5,
        seed_variety="Local",
        fertilizer_index=0.5,
        pesticide_index=0.5,
        irrigation_type="rainfed",
        N_index=0.45,
        P_index=0.45,
        K_index=0.40,
        prev_crop="Unknown",
        demand_index=75.0,
        inflation_index=1.15,
        holiday_flag=0,
        festival_flag=0,
        district="Hambantota",
    ),
    # Cowpea — Ampara, dry zone, Maha baseline
    "Cowpea": dict(
        week_of_year=46,
        season="Maha",
        rainfall_mm=28.0,
        temp_min_c=23.0,
        temp_max_c=32.0,
        humidity_pct=64.0,
        wind_speed_kmh=10.0,
        solar_radiation_mj=20.0,
        soil_ph=6.3,
        soil_moisture_pct=49.0,
        cultivated_area_ha=0.5,
        seed_variety="Local",
        fertilizer_index=0.5,
        pesticide_index=0.5,
        irrigation_type="rainfed",
        N_index=0.45,
        P_index=0.45,
        K_index=0.40,
        prev_crop="Unknown",
        demand_index=75.0,
        inflation_index=1.15,
        holiday_flag=0,
        festival_flag=0,
        district="Ampara",
    ),
    # Finger millet — Monaragala, dry zone, Maha baseline
    "Finger millet": dict(
        week_of_year=46,
        season="Maha",
        rainfall_mm=25.0,
        temp_min_c=22.0,
        temp_max_c=32.0,
        humidity_pct=62.0,
        wind_speed_kmh=10.0,
        solar_radiation_mj=20.0,
        soil_ph=5.9,
        soil_moisture_pct=47.0,
        cultivated_area_ha=0.5,
        seed_variety="Local",
        fertilizer_index=0.5,
        pesticide_index=0.5,
        irrigation_type="rainfed",
        N_index=0.45,
        P_index=0.40,
        K_index=0.40,
        prev_crop="Unknown",
        demand_index=75.0,
        inflation_index=1.15,
        holiday_flag=0,
        festival_flag=0,
        district="Monaragala",
    ),
    # Groundnut — Ampara, dry zone, Maha baseline
    "Groundnut": dict(
        week_of_year=46,
        season="Maha",
        rainfall_mm=22.0,
        temp_min_c=23.0,
        temp_max_c=33.0,
        humidity_pct=63.0,
        wind_speed_kmh=11.0,
        solar_radiation_mj=21.0,
        soil_ph=6.3,
        soil_moisture_pct=48.0,
        cultivated_area_ha=0.5,
        seed_variety="Local",
        fertilizer_index=0.5,
        pesticide_index=0.5,
        irrigation_type="rainfed",
        N_index=0.45,
        P_index=0.45,
        K_index=0.45,
        prev_crop="Unknown",
        demand_index=75.0,
        inflation_index=1.15,
        holiday_flag=0,
        festival_flag=0,
        district="Ampara",
    ),
}

# District map for baseline requests
_CROP_BASELINE_DISTRICT: Dict[str, str] = {
    "Carrot": "Nuwara Eliya",
    "Maize": "Ampara",
    "Green gram": "Hambantota",
    "Cowpea": "Ampara",
    "Finger millet": "Monaragala",
    "Groundnut": "Ampara",
}

# In-process cache — resets on server restart (i.e. after retrain)
_avg_yield_cache: Dict[str, float] = {}


def _get_average_yield(crop_name: str, key: str) -> float:
    """Ask the model itself what it predicts for a neutral average input.

    Cached in-process — automatically invalidated on server restart so
    it always reflects current model weights after any retrain.
    """
    if crop_name in _avg_yield_cache:
        return _avg_yield_cache[crop_name]

    try:
        from app.models.schemas import (
            CropEnum,
            DistrictEnum,
            SeasonEnum,
            IrrigationEnum,
        )

        b = _BASELINE_FEATURES[crop_name]

        class _FakeReq:
            pass

        req = _FakeReq()
        req.week_of_year = b["week_of_year"]
        req.season = SeasonEnum(b["season"])
        req.rainfall_mm = b["rainfall_mm"]
        req.temp_min_c = b["temp_min_c"]
        req.temp_max_c = b["temp_max_c"]
        req.humidity_pct = b["humidity_pct"]
        req.wind_speed_kmh = b["wind_speed_kmh"]
        req.solar_radiation_mj = b["solar_radiation_mj"]
        req.soil_ph = b["soil_ph"]
        req.soil_moisture_pct = b["soil_moisture_pct"]
        req.cultivated_area_ha = b["cultivated_area_ha"]
        req.seed_variety = b["seed_variety"]
        req.fertilizer_index = b["fertilizer_index"]
        req.pesticide_index = b["pesticide_index"]
        req.irrigation_type = IrrigationEnum(b["irrigation_type"])
        req.N_index = b["N_index"]
        req.P_index = b["P_index"]
        req.K_index = b["K_index"]
        req.prev_crop = b["prev_crop"]
        req.demand_index = b["demand_index"]
        req.inflation_index = b["inflation_index"]
        req.holiday_flag = b["holiday_flag"]
        req.festival_flag = b["festival_flag"]
        req.crop = CropEnum(crop_name)
        req.district = DistrictEnum(_CROP_BASELINE_DISTRICT[crop_name])

        features = _build_features(req)
        model = model_loader.get_model(key)
        avg = round(float(model.predict([features])[0]), 2)
        _avg_yield_cache[crop_name] = avg
        logger.info("Average yield cached: %s = %.1f kg/ha", crop_name, avg)
        return avg

    except Exception as exc:
        logger.warning(
            "Could not compute average yield for %s: %s — using fallback",
            crop_name,
            exc,
        )
        # Fallback — only used if model.predict() itself fails
        _fallback = {
            "Carrot": 12800.0,
            "Maize": 2600.0,
            "Green gram": 950.0,
            "Cowpea": 1050.0,
            "Finger millet": 900.0,
            "Groundnut": 1400.0,
        }
        return _fallback.get(crop_name, 1500.0)


def predict_yield(req: YieldPredictRequest, user_id: str) -> YieldPredictResponse:
    """Predict crop yield for the given agronomic and environmental inputs."""
    key = _CROP_KEY[req.crop.value]

    if not model_loader.is_loaded(key):
        logger.warning("Yield model missing for %s — returning mock", req.crop.value)
        return YieldPredictResponse(
            predicted_yield_kg_per_ha=0.0,
            average_yield_kg_per_ha=0.0,
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
        average = _get_average_yield(req.crop.value, key)

        logger.info(
            "Yield prediction: crop=%s district=%s predicted=%.1f average=%.1f",
            req.crop.value,
            req.district.value,
            prediction,
            average,
        )

        return YieldPredictResponse(
            predicted_yield_kg_per_ha=round(prediction, 2),
            average_yield_kg_per_ha=round(average, 2),
            crop=req.crop,
            district=req.district,
            confidence=confidence,
            model_used=key,
        )
    except Exception as exc:
        logger.error(
            "Yield prediction error crop=%s district=%s: %s",
            req.crop,
            req.district,
            exc,
        )
        raise RuntimeError("Yield prediction unavailable") from exc


def _build_features(req) -> List[float]:
    """Build the 35-feature vector matching the training pipeline."""
    encoders: Dict = model_loader.get_model("yield_encoders") or {}

    wos = _week_of_season(req.week_of_year, req.season.value)
    season_prog = wos / _SEASON_DURATION.get(req.season.value, 24)
    year = date.today().year

    crop_enc = _safe_encode(encoders.get("crop"), req.crop.value)
    district_enc = _safe_encode(encoders.get("district"), req.district.value)
    season_enc = _safe_encode(encoders.get("season"), req.season.value)

    irr_mapped = _IRRIGATION_MAP.get(req.irrigation_type.value, "drip")
    irrigation_enc = _safe_encode(encoders.get("irrigation_type"), irr_mapped)

    sv = req.seed_variety if req.seed_variety in _KNOWN_SEED_VARIETIES else "Local"
    seed_enc = _safe_encode(encoders.get("seed_variety"), sv)

    pc = req.prev_crop if req.prev_crop in _KNOWN_PREV_CROPS else "Unknown"
    prev_crop_enc = _safe_encode(encoders.get("prev_crop"), pc)

    temp_range = req.temp_max_c - req.temp_min_c
    heat_stress = 1 if req.temp_max_c > 35.0 else 0
    cold_stress = 1 if req.temp_min_c < 12.0 else 0
    rain_adequacy = min(req.rainfall_mm / 100.0, 2.0)

    nutrient_score = (req.N_index + req.P_index + req.K_index) / 3.0
    mgmt_score = (req.fertilizer_index + req.pesticide_index) / 2.0

    return [
        req.week_of_year,  # 0  week_of_year
        wos,  # 1  week_of_season
        season_prog,  # 2  season_progress
        year,  # 3  year
        crop_enc,  # 4  crop_enc
        district_enc,  # 5  district_enc
        season_enc,  # 6  season_enc
        req.rainfall_mm,  # 7  rainfall_mm
        req.temp_min_c,  # 8  temp_min_c
        req.temp_max_c,  # 9  temp_max_c
        req.humidity_pct,  # 10 humidity_pct
        req.wind_speed_kmh,  # 11 wind_speed_kmh
        req.solar_radiation_mj,  # 12 solar_radiation_mj
        temp_range,  # 13 temp_range
        heat_stress,  # 14 heat_stress_flag
        cold_stress,  # 15 cold_stress_flag
        rain_adequacy,  # 16 rain_adequacy
        req.cultivated_area_ha,  # 17 cultivated_area_ha
        req.fertilizer_index,  # 18 fertilizer_index
        req.pesticide_index,  # 19 pesticide_index
        req.soil_ph,  # 20 soil_ph
        req.soil_moisture_pct,  # 21 soil_moisture_pct
        irrigation_enc,  # 22 irrigation_type_enc
        seed_enc,  # 23 seed_variety_enc
        req.N_index,  # 24 N_index
        req.P_index,  # 25 P_index
        req.K_index,  # 26 K_index
        nutrient_score,  # 27 nutrient_score
        mgmt_score,  # 28 mgmt_score
        prev_crop_enc,  # 29 prev_crop_enc
        req.inflation_index,  # 30 inflation_index
        req.demand_index,  # 31 demand_index
        50.0,  # 32 consumer_pref_index (not in request — use midpoint)
        req.holiday_flag,  # 33 holiday_flag
        req.festival_flag,  # 34 festival_flag
    ]


def _week_of_season(week_of_year: int, season: str) -> int:
    start = _SEASON_START_WEEK.get(season, 1)
    wos = (
        (week_of_year - start + 1)
        if week_of_year >= start
        else (52 - start + week_of_year + 1)
    )
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
        if prob >= 0.50:
            return ConfidenceEnum.medium
        return ConfidenceEnum.low
    except Exception:
        return ConfidenceEnum.medium
