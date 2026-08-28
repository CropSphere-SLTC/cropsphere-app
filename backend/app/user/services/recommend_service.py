"""Crop recommendation service — auto-chains weather → yield → price → M5 ranking.

M5 IS A SINGLE MULTICLASS CLASSIFIER
------------------------------------
`M5_crop_recommendation_model.pkl` is a RandomForestClassifier over six
`recommended_crop` classes. Crop is NOT an input feature: one `predict_proba`
call on one feature row returns the probability of every crop at once, and a
given crop's score is `proba[index_of(crop)]`.

This module previously called it once per crop with a per-crop feature row and
took `.max()` — which returns the top class's probability regardless of which
crop was being scored — and built only 15 features against a model expecting
29, in a different order, with hand-written categorical index maps that did not
match the trained `LabelEncoder`s. Every call therefore raised ValueError, was
swallowed by a bare `except Exception`, and silently fell back to `_heuristic`
(gross revenue / 2.5M), so the M5 model never once ran in production. Hence:
the narrow logged handler in `_m5_probabilities`, and `assert_feature_contract`
wired into startup so this class of drift fails at boot instead of in silence.
"""

import logging
from datetime import date
from typing import Dict, List, Optional, Tuple

from app.models.loader import model_loader
from app.models.schemas import (
    CropEnum,
    CropRecommendation,
    PricePredictRequest,
    RecommendRequest,
    RecommendResponse,
    YieldPredictRequest,
)
from app.user.services import crop_suitability
from app.user.services.price_service import predict_price_internal
from app.user.services.weather_service import forecast_weather_internal

# Reused rather than re-derived: M1 and M5 were trained off the same dataset and
# share these conventions. Duplicating them is exactly how the encodings drifted
# out of sync the first time.
from app.user.services.yield_service import (
    _IRRIGATION_MAP,
    _safe_encode,
    _week_of_season,
    predict_yield,
)

logger = logging.getLogger(__name__)

_ALL_CROPS = list(CropEnum)

# RecommendRequest carries no management inputs — the farmer is asking what to
# plant, not describing a plan. Midpoints keep the row inside the trained range.
_DEFAULT_FERTILIZER_INDEX = 0.5
_DEFAULT_PESTICIDE_INDEX = 0.5
_DEFAULT_WIND_SPEED_KMH = 10.0
_DEFAULT_SOLAR_RADIATION_MJ = 15.0
# Training range is 100–190 (an index, not a multiplier). The old code passed
# 1.0 here, two orders of magnitude below anything the model ever saw.
_BASELINE_INFLATION_INDEX = 100.0
_BASELINE_DEMAND_INDEX = 100.0
_DEFAULT_PREV_CROP = "Unknown"


def get_recommendations(req: RecommendRequest, user_id: str) -> RecommendResponse:
    """Return ranked crop recommendations via server-side chaining.

    Steps:
    1. WeatherService.forecast() for the district (1 week ahead).
    2. YieldService.predict() for each of the 6 crops using forecast weather.
    3. PriceService.predict() for market context per crop.
    4. M5 RandomForest (or heuristic fallback) to score and rank.

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
                logger.warning(
                    "Skipping %s in recommendation chain: %s", crop.value, exc
                )

        any_mock = any(y.is_mock or p.is_mock for _, y, p in crop_results)
        return RecommendResponse(
            recommendations=_rank(req, crop_results, weather), is_mock=any_mock
        )
    except Exception as exc:
        logger.error("Recommendation pipeline failed: %s", exc)
        raise RuntimeError("Recommendation unavailable") from exc


# ── Ranking ─────────────────────────────────────────────────────────────────


def _rank(req: RecommendRequest, results: list, weather) -> List[CropRecommendation]:
    """Score crops with M5 when available, else a yield x price heuristic."""
    probabilities = _m5_probabilities(req, weather)
    valid_districts = model_loader.get_model("recommend_valid_pairs") or {}

    conditions = _observed_conditions(req)
    scored = []

    for crop, y_resp, p_resp in results:
        if probabilities is not None and crop.value in probabilities:
            score = probabilities[crop.value]
        else:
            score = _heuristic(y_resp, p_resp)

        # M5_valid_pairs records which districts each crop is actually grown in.
        # It is advisory, not a filter: all six crops still come back, but a crop
        # the district cannot support never outranks one it can — which is what
        # put Carrot (an up-country crop) at rank 1 for Monaragala.
        districts = valid_districts.get(crop.value)
        district_ok = True if districts is None else req.district.value in districts

        scored.append(
            (
                district_ok,
                score,
                crop,
                y_resp,
                p_resp,
                crop_suitability.evaluate(crop.value, **conditions),
            )
        )

    scored.sort(key=lambda x: (x[0], x[1]), reverse=True)

    return [
        CropRecommendation(
            rank=rank,
            crop=crop,
            confidence_score=round(score, 4),
            expected_yield_kg_per_ha=y_resp.predicted_yield_kg_per_ha,
            expected_price_lkr_kg=p_resp.predicted_farmgate_price_lkr_kg,
            district_suitable=district_ok,
            suitability_flags=flags,
        )
        for rank, (district_ok, score, crop, y_resp, p_resp, flags) in enumerate(
            scored, 1
        )
    ]


def _observed_conditions(req: RecommendRequest) -> Dict[str, float]:
    """The conditions the crop is judged against — the REQUEST, always.

    These are the numbers the farmer's own weather card showed them: the
    client fetches observed weather and sends it with the request. Judging a
    crop on anything else means showing one set of figures and grading on
    another, which is wrong regardless of which source is more accurate.

    This used to prefer the M2 forecast and fall back to the request. That
    silently substituted modelled values for observed ones — for Nuwara
    Eliya the card read 1.4mm / 13.6-20.7 C / 98% while the flags were
    computed on 1.6mm / 16.5-27.3 C / 91.9%. It also inherited M2's
    hill-country collapse (see weather_service._seed_excursions), so the
    worst-affected districts were exactly the ones being judged on the least
    trustworthy numbers.

    The forecast is still used where it belongs: as an INPUT to the M5
    feature row (_m5_features), which is a model consuming a model, not a
    farmer-facing claim.

    KNOWN, STILL OPEN: the client's rainfall is a mean of DAILY totals while
    the agronomic bands are weekly, and its humidity is a mean of daily
    MAXIMA while the bands expect a representative value. Both make their
    conditions fail far more often than they should. Tracked separately as
    the farm_context.dart unit fixes — NOT closed by this change.
    """
    return {
        "temp_min_c": req.temp_min_c,
        "temp_max_c": req.temp_max_c,
        "rainfall_mm": req.rainfall_mm,
        "humidity_pct": req.humidity_pct,
        "soil_ph": req.soil_ph,
    }


def _heuristic(y_resp, p_resp) -> float:
    """Simple revenue-proxy score when the M5 model is unavailable.

    Not a probability and not comparable to one — it is gross revenue per
    hectare against a nominal ceiling. Only ever reached when M5 fails to load.
    """
    return min(
        (y_resp.predicted_yield_kg_per_ha * p_resp.predicted_farmgate_price_lkr_kg)
        / (5000.0 * 500.0),
        1.0,
    )


# ── M5 inference ────────────────────────────────────────────────────────────


def _m5_probabilities(req: RecommendRequest, weather) -> Optional[Dict[str, float]]:
    """Return {crop_name: probability} from one M5 call, or None if unavailable.

    Returns None only when the model or its encoders are absent — callers then
    fall back to the heuristic. Any *other* failure is a contract break between
    this code and the trained artifacts, and is logged with the full traceback
    rather than swallowed: silent fallback here is precisely the bug that hid a
    15-vs-29 feature mismatch through every deploy.
    """
    model = model_loader.get_model("recommend_rf")
    encoders = model_loader.get_model("recommend_encoders")
    feature_order = model_loader.get_model("recommend_features")

    if model is None or not encoders or not feature_order:
        logger.warning(
            "M5 unavailable (model=%s encoders=%s features=%s) — "
            "falling back to the revenue heuristic",
            model is not None,
            bool(encoders),
            bool(feature_order),
        )
        return None

    try:
        row = _m5_features(req, weather, encoders, feature_order)
        proba = model.predict_proba([row])[0]
        labels = encoders["recommended_crop"].inverse_transform(model.classes_)
        return {str(label): float(p) for label, p in zip(labels, proba)}
    except (ValueError, KeyError, IndexError, AttributeError):
        logger.exception(
            "M5 inference failed — this is a CONTRACT BREAK between "
            "_m5_features() and the trained model, not a transient error. "
            "Model expects %s features in the order given by M5_features.pkl. "
            "Recommendations are falling back to the revenue heuristic and are "
            "NOT model-ranked until this is fixed.",
            getattr(model, "n_features_in_", "?"),
        )
        return None


def _m5_features(
    req: RecommendRequest, weather, encoders: dict, feature_order: List[str]
) -> List[float]:
    """Build the M5 feature row in the exact order M5_features.pkl declares.

    Built as a dict then projected through `feature_order`, so the pickled
    feature list stays the single source of truth for ordering — a reordered
    retrain cannot silently scramble the inputs.
    """
    rain = weather.rainfall_mm if weather else req.rainfall_mm
    t_min = weather.temp_min_c if weather else req.temp_min_c
    t_max = weather.temp_max_c if weather else req.temp_max_c
    hum = weather.humidity_pct if weather else req.humidity_pct

    irrigation = _IRRIGATION_MAP.get(req.irrigation_type.value, "drip")

    values: Dict[str, float] = {
        "week_of_year": req.week_of_year,
        "week_of_season": _week_of_season(req.week_of_year, req.season.value),
        "year": date.today().year,
        "district_enc": _safe_encode(encoders.get("district"), req.district.value),
        "season_enc": _safe_encode(encoders.get("season"), req.season.value),
        "rainfall_mm": rain,
        "temp_min_c": t_min,
        "temp_max_c": t_max,
        "humidity_pct": hum,
        "wind_speed_kmh": _DEFAULT_WIND_SPEED_KMH,
        "solar_radiation_mj": _DEFAULT_SOLAR_RADIATION_MJ,
        "temp_range": t_max - t_min,
        "heat_stress_flag": 1 if t_max > 35.0 else 0,
        "cold_stress_flag": 1 if t_min < 12.0 else 0,
        "soil_ph": req.soil_ph,
        "soil_moisture_pct": req.soil_moisture_pct,
        "N_index": req.N_index,
        "P_index": req.P_index,
        "K_index": req.K_index,
        "nutrient_score": (req.N_index + req.P_index + req.K_index) / 3.0,
        "fertilizer_index": _DEFAULT_FERTILIZER_INDEX,
        "pesticide_index": _DEFAULT_PESTICIDE_INDEX,
        "irrigation_type_enc": _safe_encode(
            encoders.get("irrigation_type"), irrigation
        ),
        "mgmt_score": (_DEFAULT_FERTILIZER_INDEX + _DEFAULT_PESTICIDE_INDEX) / 2.0,
        "prev_crop_enc": _safe_encode(encoders.get("prev_crop"), _DEFAULT_PREV_CROP),
        "demand_index": req.demand_context or _BASELINE_DEMAND_INDEX,
        "inflation_index": _BASELINE_INFLATION_INDEX,
        "holiday_flag": 0,
        "festival_flag": 0,
    }

    missing = [name for name in feature_order if name not in values]
    if missing:
        raise KeyError(
            f"M5_features.pkl asks for features this service does not build: "
            f"{missing}. The model was retrained with a changed schema."
        )
    return [float(values[name]) for name in feature_order]


def assert_feature_contract() -> None:
    """Fail loudly at boot if _m5_features() disagrees with the trained model.

    Mirrors the shift-left checks in the Dockerfile: a mismatch here means every
    recommendation silently degrades to the revenue heuristic, which is invisible
    in a health check and produced wrong rankings in production for months.
    Raises RuntimeError — startup should not survive it.

    A model that simply is not loaded is not a contract break; that path is
    already handled (and logged) by `_m5_probabilities`.
    """
    model = model_loader.get_model("recommend_rf")
    encoders = model_loader.get_model("recommend_encoders")
    feature_order = model_loader.get_model("recommend_features")

    if model is None or not encoders or not feature_order:
        logger.warning(
            "M5 artifacts not loaded — skipping feature-contract assertion. "
            "Recommendations will use the revenue heuristic."
        )
        return

    expected = getattr(model, "n_features_in_", None)
    declared = len(feature_order)

    if expected is not None and declared != expected:
        raise RuntimeError(
            f"M5 feature contract broken: M5_features.pkl declares {declared} "
            f"features but the model expects {expected}. The artifacts in "
            "models/files/ are inconsistent with each other."
        )

    probe = RecommendRequest(
        district="Monaragala",
        season="Yala",
        week_of_year=34,
        rainfall_mm=33.7,
        temp_min_c=19.6,
        temp_max_c=29.8,
        humidity_pct=78.2,
        soil_ph=6.5,
        soil_moisture_pct=40.0,
        N_index=0.5,
        P_index=0.5,
        K_index=0.5,
        irrigation_type="rainfed",
    )
    built = len(_m5_features(probe, None, encoders, feature_order))

    if built != declared:
        raise RuntimeError(
            f"M5 feature contract broken: _m5_features() built {built} features "
            f"but M5_features.pkl declares {declared}. Update _m5_features() to "
            "match the trained model before deploying."
        )

    logger.info("M5 feature contract OK — %d features", built)


# ── Chained sub-requests ────────────────────────────────────────────────────


def _yield_request(
    req: RecommendRequest, crop: CropEnum, weather
) -> YieldPredictRequest:
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
        wind_speed_kmh=_DEFAULT_WIND_SPEED_KMH,
        solar_radiation_mj=_DEFAULT_SOLAR_RADIATION_MJ,
        soil_ph=req.soil_ph,
        soil_moisture_pct=req.soil_moisture_pct,
        cultivated_area_ha=1.0,
        seed_variety="standard",
        fertilizer_index=_DEFAULT_FERTILIZER_INDEX,
        pesticide_index=_DEFAULT_PESTICIDE_INDEX,
        irrigation_type=req.irrigation_type,
        N_index=req.N_index,
        P_index=req.P_index,
        K_index=req.K_index,
        prev_crop="none",
        demand_index=req.demand_context or _BASELINE_DEMAND_INDEX,
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
        demand_index=req.demand_context or _BASELINE_DEMAND_INDEX,
        holiday_flag=0,
        festival_flag=0,
        farmgate_price_lag1=lag,
        farmgate_price_lag2=lag,
        farmgate_price_lag4=lag,
    )
