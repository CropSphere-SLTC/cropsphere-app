"""CropSphere FastAPI application — entry point."""
import logging

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from slowapi import _rate_limit_exceeded_handler
from slowapi.errors import RateLimitExceeded

from app.config import get_settings
from app.middleware.auth import FirebaseAuthMiddleware
from app.middleware.rate_limit import limiter
from app.models.loader import model_loader
from app.routers import (
    chat_router,
    demand_router,
    health_router,
    price_router,
    recommend_router,
    weather_router,
    yield_router,
)
from app.utils.firestore import init_firestore
from app.utils.logger import setup_logging

setup_logging()
logger = logging.getLogger(__name__)


def create_app() -> FastAPI:
    """Construct and configure the FastAPI application."""
    settings = get_settings()

    app = FastAPI(
        title="CropSphere API",
        description="Agricultural intelligence API for Sri Lankan farmers",
        version="1.0.0",
    )

    # ── Rate limiter ──────────────────────────────────────────────────────────
    app.state.limiter = limiter
    app.add_exception_handler(RateLimitExceeded, _rate_limit_exceeded_handler)

    # ── CORS — origins from env only ──────────────────────────────────────────
    app.add_middleware(
        CORSMiddleware,
        allow_origins=settings.allowed_origins_list,
        allow_credentials=True,
        allow_methods=["*"],
        allow_headers=["*"],
    )

    # ── JWT auth — applied after CORS ─────────────────────────────────────────
    app.add_middleware(FirebaseAuthMiddleware)

    # ── Routers ───────────────────────────────────────────────────────────────
    app.include_router(health_router.router)
    app.include_router(yield_router.router)
    app.include_router(weather_router.router)
    app.include_router(price_router.router)
    app.include_router(demand_router.router)
    app.include_router(recommend_router.router)
    app.include_router(chat_router.router)

    # ── Startup ───────────────────────────────────────────────────────────────
    @app.on_event("startup")
    async def startup() -> None:
        logger.info("CropSphere starting — ENV=%s", settings.APP_ENV)
        try:
            init_firestore(settings.FIREBASE_CREDENTIALS_JSON, settings.FIREBASE_PROJECT_ID)
        except Exception as exc:
            logger.error("Firestore init failed (continuing without audit logging): %s", exc)
        model_loader.load_all(settings.MODEL_DIR)
        logger.info("Models: %s", model_loader.status_report())

    return app


app = create_app()
