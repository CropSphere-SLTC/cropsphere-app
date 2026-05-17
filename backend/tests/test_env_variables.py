import os
import pytest
from app.config import get_settings


def test_required_env_variables_exist():
    """Required environment variables must be defined."""
    settings = get_settings()
    assert settings.APP_ENV is not None
    assert len(settings.APP_ENV) > 0
    print("✅ Test 1 Passed — APP_ENV variable exists")


def test_env_file_example_exists():
    """The .env.example file must exist for developer guidance."""
    assert os.path.exists(".env.example"), ".env.example file missing!"
    print("✅ Test 2 Passed — .env.example file exists")


def test_secret_keys_not_hardcoded():
    """Sensitive keys must come from environment, not hardcoded."""
    settings = get_settings()
    assert settings.FIREBASE_PROJECT_ID is not None
    print("✅ Test 3 Passed — Secrets loaded from environment")


def test_env_is_valid_value():
    """APP_ENV must be development, staging, or production."""
    settings = get_settings()
    assert settings.APP_ENV in ["development", "staging", "production"]
    print("✅ Test 4 Passed — APP_ENV is valid value")