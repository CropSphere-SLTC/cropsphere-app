"""CropSphere FastAPI application — entry point."""

import logging

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from slowapi import _rate_limit_exceeded_handler
from slowapi.middleware import SlowAPIMiddleware
from slowapi.errors import RateLimitExceeded

from app.config import get_settings
from app.middleware.auth import FirebaseAuthMiddleware
from app.middleware.rate_limit import limiter
from app.middleware.security_headers import SecurityHeadersMiddleware
from app.models.loader import model_loader
from app.routers import (
    admin_router,
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
    app.add_exception_handler(RateLimitExceeded, _rate_limit_exceeded_handler)

    # ── Routers ───────────────────────────────────────────────────────────────
    app.include_router(health_router.router)
    app.include_router(yield_router.router)
    app.include_router(weather_router.router)
    app.include_router(price_router.router)
    app.include_router(demand_router.router)
    app.include_router(recommend_router.router)
    app.include_router(chat_router.router)
    app.include_router(admin_router.router)

    return app


app = create_app()
