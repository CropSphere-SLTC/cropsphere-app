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

    # CORS — comma-separated list of allowed frontend origins
    ALLOWED_ORIGINS: str = "http://localhost:3000"

    # slowapi rate limit
    RATE_LIMIT_PER_MINUTE: int = 30

    # ML model files directory (mounted in Docker)
    MODEL_DIR: str = "/app/models/files"

    @property
    def allowed_origins_list(self) -> List[str]:
        """Split ALLOWED_ORIGINS into a list."""
        return [o.strip() for o in self.ALLOWED_ORIGINS.split(",")]


@lru_cache()
def get_settings() -> Settings:
    """Return cached singleton Settings instance."""
    return Settings()
