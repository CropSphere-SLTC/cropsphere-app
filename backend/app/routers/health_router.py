"""Health check endpoint — exempt from JWT auth and rate limiting."""

from fastapi import APIRouter

from app.config import get_settings
from app.models.loader import model_loader

router = APIRouter(prefix="/api/health", tags=["health"])


@router.get("")
def health_check():
    """Return app status and per-model load status.

    No authentication required. Used by Docker healthcheck and monitoring.
    """
    return {
        "status": "ok",
        "models_loaded": model_loader.status_report(),
        "environment": get_settings().APP_ENV,
    }
