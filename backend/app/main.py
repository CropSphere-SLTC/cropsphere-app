"""CropSphere FastAPI application — entry point."""

import logging
import time
from datetime import date

from fastapi import FastAPI, Request
from fastapi.exceptions import RequestValidationError
from fastapi.encoders import jsonable_encoder
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
from slowapi.middleware import SlowAPIMiddleware
from slowapi.errors import RateLimitExceeded

from app.config import get_settings
from app.middleware.auth import FirebaseAuthMiddleware
from app.middleware.rate_limit import limiter, rate_limit_exceeded_handler
from app.middleware.security_headers import SecurityHeadersMiddleware
from app.models.loader import model_loader
from app.user.services.crop_suitability import assert_bands_available
from app.user.services.recommend_service import assert_feature_contract
from app.user.services.weather_service import assert_weather_seeds_in_range
from app.user.routers import (
    chat_history_router,
    chat_router,
    demand_router,
    health_router,
    price_router,
    profile_router,
    recommend_router,
    weather_router,
    yield_router,
)
from app.admin.routers import admin_router, security_router
from app.super_admin.routers import superadmin_router
from app.utils.firestore import init_firestore
from app.utils.logger import setup_logging

setup_logging()
logger = logging.getLogger(__name__)


def _warmup_models() -> None:
    """Run one real prediction per loaded ML model with realistic dummy
    inputs, so the first genuine user request never pays the "cold" cost
    (Keras graph tracing in particular is per model INSTANCE — warming
    price_Carrot's LSTM does nothing for price_Maize's, which is why every
    crop-specific model gets its own warm-up call, not just one per
    service). Each warm-up is fully independent: one model failing logs a
    warning and never blocks the rest or crashes startup.

    Dummy inputs are real, schema-valid values already proven in the test
    suite (tests/security/test_auth.py, tests/integration/test_price.py,
    test_demand.py, test_recommend.py) paired with real crop/district
    combinations from the CropSphere coverage matrix — not garbage.

    NOTE: these are throwaway calls with dummy data. If response caching
    is ever added to the prediction endpoints, these warm-up calls must be
    excluded from it — not an issue today, since no caching exists yet.
    """
    from app.models.schemas import (
        CropEnum,
        DemandPredictRequest,
        DistrictEnum,
        IrrigationEnum,
        PricePredictRequest,
        RecommendRequest,
        SeasonEnum,
        WeatherForecastRequest,
        YieldPredictRequest,
    )
    from app.user.services.demand_service import predict_demand
    from app.user.services.price_service import predict_price_internal
    from app.user.services.recommend_service import get_recommendations
    from app.user.services.weather_service import forecast_weather
    from app.user.services.chatbot_service import _get_encoder
    from app.user.services.yield_service import predict_yield

    def _run(name: str, fn) -> None:
        start = time.monotonic()
        try:
            fn()
            logger.info(
                f"[warmup] {name} model ready in {time.monotonic() - start:.2f}s"
            )
        except Exception as exc:
            logger.warning(f"[warmup] {name} failed: {exc}")

    total_start = time.monotonic()

    # crop -> a real, valid growing district (CropSphere coverage matrix)
    crop_district = {
        CropEnum.carrot: DistrictEnum.nuwara_eliya,
        CropEnum.maize: DistrictEnum.anuradhapura,
        CropEnum.green_gram: DistrictEnum.hambantota,
        CropEnum.cowpea: DistrictEnum.anuradhapura,
        CropEnum.finger_millet: DistrictEnum.anuradhapura,
        CropEnum.groundnut: DistrictEnum.batticaloa,
    }

    for crop, district in crop_district.items():
        _run(
            f"yield_{crop.value}",
            lambda crop=crop, district=district: predict_yield(
                YieldPredictRequest(
                    crop=crop,
                    district=district,
                    season=SeasonEnum.maha,
                    week_of_year=10,
                    rainfall_mm=100.0,
                    temp_min_c=10.0,
                    temp_max_c=22.0,
                    humidity_pct=70.0,
                    wind_speed_kmh=10.0,
                    solar_radiation_mj=15.0,
                    soil_ph=6.0,
                    soil_moisture_pct=55.0,
                    cultivated_area_ha=1.0,
                    seed_variety="Standard",
                    fertilizer_index=0.5,
                    pesticide_index=0.5,
                    irrigation_type=IrrigationEnum.drip,
                    N_index=0.5,
                    P_index=0.5,
                    K_index=0.5,
                    prev_crop="none",
                    demand_index=100.0,
                    inflation_index=1.0,
                    holiday_flag=0,
                    festival_flag=0,
                ),
                "system",
            ),
        )

    for crop, district in crop_district.items():
        _run(
            f"price_{crop.value}",
            lambda crop=crop, district=district: predict_price_internal(
                PricePredictRequest(
                    crop=crop,
                    district=district,
                    season=SeasonEnum.maha,
                    week_of_year=10,
                    inflation_index=1.2,
                    fuel_price_index=1.1,
                    transport_cost_index=1.0,
                    supply_index=100.0,
                    demand_index=110.0,
                    holiday_flag=0,
                    festival_flag=0,
                    farmgate_price_lag1=85.0,
                    farmgate_price_lag2=80.0,
                    farmgate_price_lag4=75.0,
                )
            ),
        )

    for crop in crop_district:
        _run(
            f"demand_{crop.value}",
            lambda crop=crop: predict_demand(
                DemandPredictRequest(
                    crop=crop,
                    season=SeasonEnum.maha,
                    week_of_year=10,
                    demand_lag1=95.0,
                    demand_lag2=90.0,
                    demand_lag4=85.0,
                    retail_price_lkr_kg=120.0,
                    inflation_index=1.2,
                    holiday_flag=0,
                    festival_flag=0,
                    consumer_pref_index=60.0,
                    search_trend_index=45.0,
                ),
                "system",
            ),
        )

    _run(
        "weather_lstm",
        lambda: forecast_weather(
            WeatherForecastRequest(
                district=DistrictEnum.nuwara_eliya,
                start_date=date.today().isoformat(),
                weeks_ahead=1,
            )
        ),
    )

    _run(
        "recommend_rf",
        lambda: get_recommendations(
            RecommendRequest(
                district=DistrictEnum.nuwara_eliya,
                season=SeasonEnum.maha,
                week_of_year=10,
                rainfall_mm=120.0,
                temp_min_c=10.0,
                temp_max_c=22.0,
                humidity_pct=75.0,
                soil_ph=6.0,
                soil_moisture_pct=60.0,
                N_index=0.5,
                P_index=0.4,
                K_index=0.6,
                irrigation_type=IrrigationEnum.drip,
            ),
            "system",
        ),
    )

    # RAG sentence encoder — loaded lazily on the first _rag_context() call,
    # which measured ~6.8s and was charged to the first farmer to chat after
    # every restart (once per uvicorn worker). Warming it here moves that cost
    # to startup: first chat drops from ~8.2s to ~1.3s.
    _run("rag_encoder", _get_encoder)

    logger.info(f"[warmup] all models ready in {time.monotonic() - total_start:.2f}s")


def _check_firestore(settings) -> None:
    """Lightweight Firestore connectivity check — lists collection IDs
    rather than reading any document data. Never blocks startup or raises:
    prediction models must keep working even if Firestore is unreachable
    (only chat history and user profiles depend on it).
    """
    try:
        from app.utils.firestore import get_db

        db = get_db()
        list(db.collections())  # materialize the iterator to force the RPC
        logger.info(
            "[startup] Firestore connection verified (project=%s, database=%s)",
            settings.FIREBASE_PROJECT_ID,
            "cropsphere-database",  # must stay in sync with init_firestore()
        )
    except Exception as exc:
        logger.warning(
            "[startup] Firestore connection failed: %s — chat history and "
            "user profiles will be unavailable",
            exc,
        )


def create_app() -> FastAPI:
    """Construct and configure the FastAPI application."""
    from contextlib import asynccontextmanager

    settings = get_settings()

    @asynccontextmanager
    async def lifespan(app: FastAPI):
        logger.info("CropSphere starting — ENV=%s", settings.APP_ENV)

        # Firestore audit logging — optional for dev
        try:
            init_firestore(
                settings.FIREBASE_CREDENTIALS_JSON, settings.FIREBASE_PROJECT_ID
            )
        except Exception as exc:
            logger.warning("Firestore audit logging disabled: %s", exc)

        # Load all ML models on startup (before yield = startup phase)
        model_loader.load_all(settings.MODEL_DIR)
        logger.info("Models loaded: %s", model_loader.status_report())

        # Shift-left, same spirit as the Dockerfile's torch/dist-info guards:
        # verify the recommendation feature vector still matches what M5 was
        # trained on. A mismatch makes every recommendation fall back to a
        # revenue heuristic while still returning 200 OK — invisible to health
        # checks, and it shipped that way once already. Fail the boot instead.
        assert_feature_contract()
        assert_bands_available()
        # Not an assertion despite the name shape: four districts breach
        # the M2 scaler's fitted range today and two of them forecast
        # fine, so this logs loudly rather than refusing to boot.
        assert_weather_seeds_in_range()

        # Warm the RAG sentence-encoder once, now, from the baked offline cache.
        # This moves the (previously per-request, network-bound) load to boot,
        # so a bad cache surfaces here instead of hanging the first chat request.
        try:
            from app.user.services.chatbot_service import _get_encoder

            _get_encoder()
            logger.info("RAG sentence-encoder preloaded")
        except Exception as exc:
            logger.warning("RAG encoder preload failed (chat will 500): %s", exc)

        # Prediction models — warm up all 20 individually loaded models
        # (RAG's own model, the sentence-encoder above, is separate).
        _warmup_models()

        # Average farmgate price per crop — a static per-crop mean read
        # once from the price CSVs, cached so /api/price/predict never
        # re-reads them per request. See price_service for source/coverage
        # details.
        try:
            from app.user.services.price_service import warm_average_farmgate_prices

            warm_average_farmgate_prices()
            logger.info("Average farmgate prices preloaded")
        except Exception as exc:
            logger.warning("Average farmgate price warm-up failed: %s", exc)

        # Firestore — verify connectivity, but never block startup on it.
        _check_firestore(settings)

        yield  # app runs here

    app = FastAPI(
        title="CropSphere API",
        description="Agricultural intelligence API for Sri Lankan farmers",
        version="1.0.0",
        lifespan=lifespan,
    )

    # ── Middleware ────────────────────────────────────────────────────────────
    # Starlette wraps middleware in reverse add_middleware order: the LAST call
    # added becomes the OUTERMOST wrapper (first to see requests, last to see
    # responses). Add FirebaseAuth first (innermost) and CORS last (outermost)
    # so CORS headers are present on every response — including 401 rejections —
    # which browsers require before they will show the response to JS clients.
    app.add_middleware(FirebaseAuthMiddleware)  # innermost — runs last on request
    app.add_middleware(SlowAPIMiddleware)
    app.add_middleware(SecurityHeadersMiddleware)
    app.add_middleware(
        CORSMiddleware,
        allow_origins=settings.allowed_origins_list,
        allow_origin_regex=(
            r"http://localhost(:\d+)?" if settings.APP_ENV == "development" else None
        ),
        allow_credentials=True,
        allow_methods=["*"],
        allow_headers=["*"],
    )  # outermost — injects CORS headers on every response

    # ── Rate limiter ──────────────────────────────────────────────────────────
    app.state.limiter = limiter
    app.add_exception_handler(RateLimitExceeded, rate_limit_exceeded_handler)

    # ── Validation-error diagnostics ─────────────────────────────────────────
    # Added while chasing a 422 the Flutter client was surfacing as "Couldn't
    # reach the server" (api_service.dart's _dioErrorCode maps any non-401/
    # 403/429/5xx status to the same 'network' code as a genuine connection
    # failure, so the real cause — PredictionWeatherWeek.week_number wrongly
    # bounded 1-4 instead of 1-53 — was invisible client-side; see that
    # field's doc comment in schemas.py). Logs which field(s) failed and why,
    # server-side only — the response body sent to the client is FastAPI's
    # normal 422 detail, unchanged. Kept permanently: cheap, and the next
    # silent 422 gets the same fast diagnosis this one did. Remove if this
    # turns out to be noisy in practice.
    @app.exception_handler(RequestValidationError)
    async def _log_validation_error(request: Request, exc: RequestValidationError):
        # jsonable_encoder, not exc.errors() raw: a validator that raises a
        # ValueError puts the exception object itself in the error's `ctx`,
        # which JSONResponse cannot serialise — turning the 422 this handler
        # exists to surface into an opaque 500.
        errors = jsonable_encoder(exc.errors())
        logger.warning("422 on %s %s: %s", request.method, request.url.path, errors)
        return JSONResponse(status_code=422, content={"detail": errors})

    # ── Routers ───────────────────────────────────────────────────────────────
    app.include_router(health_router.router)
    app.include_router(yield_router.router)
    app.include_router(weather_router.router)
    app.include_router(price_router.router)
    app.include_router(demand_router.router)
    app.include_router(recommend_router.router)
    app.include_router(chat_history_router.router)
    app.include_router(chat_router.router)
    app.include_router(profile_router.router)
    if settings.ENABLE_ADMIN_API:
        app.include_router(admin_router.router)
        app.include_router(security_router.router)
        app.include_router(superadmin_router.router)
        app.include_router(superadmin_router.legacy_router)

    return app


app = create_app()
