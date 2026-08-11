"""Application configuration — all values sourced from environment variables."""

from functools import lru_cache
from typing import List

from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    """All secrets and config loaded from environment only.

    Raises a clear ValidationError on startup if any required field is missing.
    """

    model_config = SettingsConfigDict(env_file=".env", extra="ignore")

    APP_ENV: str = "development"

    # Firebase — required; startup fails fast if absent
    FIREBASE_CREDENTIALS_JSON: str
    FIREBASE_PROJECT_ID: str

    # Groq API — required for chatbot
    GROQ_API_KEY: str

    # Superadmin — hardcoded UID, cannot be changed via Firestore
    SUPERADMIN_UID: str = ""

    # Admin API — set False to disable /api/admin/* routes without a redeploy
    ENABLE_ADMIN_API: bool = True

    # CORS — comma-separated list of allowed frontend origins
    ALLOWED_ORIGINS: str = "http://localhost:3000"

    # slowapi rate limit
    RATE_LIMIT_PER_MINUTE: int = 30

    # ML model files directory (mounted in Docker)
    MODEL_DIR: str = "/app/models/files"

    # ── Email alerts (admin notifications) ──────────────────────────────────
    # OFF by default — emails only go out once SMTP is configured, so dev and
    # test never send real mail. Gmail SMTP (App Password) is the intended
    # setup; see email_service. Password is a secret — env only, never in code.
    EMAIL_ENABLED: bool = False
    EMAIL_FROM: str = ""
    EMAIL_SMTP_HOST: str = "smtp.gmail.com"
    EMAIL_SMTP_PORT: int = 587
    EMAIL_SMTP_USER: str = ""
    EMAIL_SMTP_PASSWORD: str = ""
    # Absolute URL the "View in Dashboard" button links to. Falls back to the
    # first allowed origin when unset.
    DASHBOARD_URL: str = ""

    @property
    def allowed_origins_list(self) -> List[str]:
        """Split ALLOWED_ORIGINS into a list."""
        return [o.strip() for o in self.ALLOWED_ORIGINS.split(",")]

    @property
    def dashboard_url(self) -> str:
        """The admin dashboard URL for email links — DASHBOARD_URL, else the
        first configured origin."""
        if self.DASHBOARD_URL:
            return self.DASHBOARD_URL.rstrip("/")
        origins = self.allowed_origins_list
        return origins[0].rstrip("/") if origins and origins[0] else ""


@lru_cache()
def get_settings() -> Settings:
    """Return cached singleton Settings instance."""
    return Settings()
