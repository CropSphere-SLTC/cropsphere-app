"""Crop recommendation service — auto-chains weather → yield → price → RF ranking."""
import logging
from datetime import date
from typing import List, Tuple

from app.models.loader import model_loader
from app.models.schemas import (
    CropEnum,
    CropRecommendation,
    PricePredictRequest,
    RecommendRequest,
    RecommendResponse,
    YieldPredictRequest,
)
from app.services.price_service import predict_price_internal
from app.services.weather_service import forecast_weather_internal
from app.services.yield_service import predict_yield

logger = logging.getLogger(__name__)

_ALL_CROPS = list(CropEnum)
_DISTRICT_IDX = {
    "Nuwara Eliya": 0, "Badulla": 1, "Anuradhapura": 2, "Monaragala": 3,
    "Ampara": 4, "Hambantota": 5, "Batticaloa": 6, "Jaffna": 7,
}
_SEASON_IDX = {"Maha": 0, "Yala": 1, "Inter": 2}
_IRRIGATION_IDX = {"drip": 0, "sprinkler": 1, "flood": 2, "rainfed": 3}


def get_recommendations(req: RecommendRequest, user_id: str) -> RecommendResponse:
    """Return ranked crop recommendations via server-side chaining.

    Steps:
    1. WeatherService.forecast() for the district (1 week ahead).
    2. YieldService.predict() for each of the 6 crops using forecast weather.
    3. PriceService.predict() for market context per crop.
    4. RandomForest model (or heuristic fallback) to score and rank.

    Flutter calls this single endpoint; all chaining is server-side.
    Security assumption: user_id verified by JWT middleware.
    """
    try:
        weather_resp = forecast_weather_internal(
            district=req.district,
            start_date=str(date.today()),
        )
        weather = weather_resp.forecasts[0] if weather_resp.forecasts else None

        crop_results: List[Tuple] = []
        for crop in _ALL_CROPS:
            try:
                y_req = _yield_request(req, crop, weather)
                y_resp = predict_yield(y_req, user_id)
                p_req = _price_request(req, crop)
                p_resp = predict_price_internal(p_req)
                crop_results.append((crop, y_resp, p_resp))
            except Exception as exc:
                logger.warning("Skipping %s in recommendation chain: %s", crop.value, exc)

        return RecommendResponse(recommendations=_rank(req, crop_results))
    except Exception as exc:
        logger.error("Recommendation pipeline failed: %s", exc)
        raise RuntimeError("Recommendation unavailable") from exc


def _rank(req: RecommendRequest, results: list) -> List[CropRecommendation]:
    """Score crops using RF model when available, else a yield×price heuristic."""
    rf = model_loader.get_model("recommend_rf")
    scored = []

    for crop, y_resp, p_resp in results:
        if rf and not y_resp.is_mock:
            try:
                feats = _rf_features(req, y_resp, p_resp)
                score = float(rf.predict_proba([feats])[0].max())
            except Exception:
                score = _heuristic(y_resp, p_resp)
        else:
            score = _heuristic(y_resp, p_resp)

        scored.append((score, crop, y_resp, p_resp))

    scored.sort(key=lambda x: x[0], reverse=True)

    return [
        CropRecommendation(
            rank=rank,
            crop=crop,
            confidence_score=round(score, 4),
            expected_yield_kg_per_ha=y_resp.predicted_yield_kg_per_ha,
            expected_price_lkr_kg=p_resp.predicted_farmgate_price_lkr_kg,
            suitability_flags={
                "yield_modelled": not y_resp.is_mock,
                "price_modelled": not p_resp.is_mock,
                "any_mock": y_resp.is_mock or p_resp.is_mock,
            },
        )
        for rank, (score, crop, y_resp, p_resp) in enumerate(scored, 1)
    ]


def _heuristic(y_resp, p_resp) -> float:
    """Simple revenue-proxy score when RF model is unavailable."""
    return min(
        (y_resp.predicted_yield_kg_per_ha * p_resp.predicted_farmgate_price_lkr_kg)
        / (5000.0 * 500.0),
        1.0,
    )


def _yield_request(req: RecommendRequest, crop: CropEnum, weather) -> YieldPredictRequest:
    rain = weather.rainfall_mm if weather else req.rainfall_mm
    t_min = weather.temp_min_c if weather else req.temp_min_c
    t_max = weather.temp_max_c if weather else req.temp_max_c
    hum = weather.humidity_pct if weather else req.humidity_pct

    return YieldPredictRequest(
        crop=crop,
        district=req.district,
        season=req.season,
        week_of_year=req.week_of_year,
        rainfall_mm=rain,
        temp_min_c=t_min,
        temp_max_c=t_max,
        humidity_pct=hum,
        wind_speed_kmh=10.0,
        solar_radiation_mj=15.0,
        soil_ph=req.soil_ph,
        soil_moisture_pct=req.soil_moisture_pct,
        cultivated_area_ha=1.0,
        seed_variety="standard",
        fertilizer_index=0.5,
        pesticide_index=0.5,
        irrigation_type=req.irrigation_type,
        N_index=req.N_index,
        P_index=req.P_index,
        K_index=req.K_index,
        prev_crop="none",
        demand_index=req.demand_context or 100.0,
        inflation_index=1.0,
        holiday_flag=0,
        festival_flag=0,
    )


def _price_request(req: RecommendRequest, crop: CropEnum) -> PricePredictRequest:
    lag = req.farmgate_price_context or 100.0
    return PricePredictRequest(
        crop=crop,
        district=req.district,
        season=req.season,
        week_of_year=req.week_of_year,
        inflation_index=1.0,
        fuel_price_index=1.0,
        transport_cost_index=1.0,
        supply_index=100.0,
        demand_index=req.demand_context or 100.0,
        holiday_flag=0,
        festival_flag=0,
        farmgate_price_lag1=lag,
        farmgate_price_lag2=lag,
        farmgate_price_lag4=lag,
    )


def _rf_features(req: RecommendRequest, y_resp, p_resp) -> list:
    return [
        _DISTRICT_IDX[req.district.value],
        _SEASON_IDX[req.season.value],
        req.week_of_year,
        req.rainfall_mm,
        req.temp_min_c,
        req.temp_max_c,
        req.humidity_pct,
        req.soil_ph,
        req.soil_moisture_pct,
        req.N_index,
        req.P_index,
        req.K_index,
        _IRRIGATION_IDX[req.irrigation_type.value],
        y_resp.predicted_yield_kg_per_ha,
        p_resp.predicted_farmgate_price_lkr_kg,
    ]
