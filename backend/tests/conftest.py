"""Shared pytest fixtures — test client, JWT mocks, environment setup."""

import os

# Set required env vars before any app module is imported
os.environ.setdefault(
    "FIREBASE_CREDENTIALS_JSON", '{"type":"service_account","project_id":"test"}'
)
os.environ.setdefault("FIREBASE_PROJECT_ID", "test-project")
os.environ.setdefault("GROQ_API_KEY", "test-groq-key")
os.environ.setdefault("ALLOWED_ORIGINS", "http://localhost:3000")
os.environ.setdefault("MODEL_DIR", "/tmp/models")

import pytest  # noqa: E402
from unittest.mock import MagicMock, patch  # noqa: E402
from fastapi.testclient import TestClient  # noqa: E402


@pytest.fixture(scope="session")
def app():
    """Create test app with all external I/O patched out."""
    with patch("firebase_admin.initialize_app"), patch(
        "firebase_admin._apps", new={"[DEFAULT]": MagicMock()}
    ), patch("app.utils.firestore.init_firestore"), patch(
        "app.utils.firestore.audit_log"
    ), patch(
        "app.models.loader.ModelLoader.load_all"
    ):
        from app.main import create_app

        return create_app()


@pytest.fixture(scope="session")
def client(app):
    """Session-scoped test client (startup/shutdown events fire once)."""
    with TestClient(app) as c:
        yield c


@pytest.fixture(autouse=True)
def reset_rate_limit(app):
    """Reset slowapi's in-memory counter before every test.

    Prevents rate-limit state from bleeding across tests when using a
    session-scoped client. The limiter stays active, so TestRateLimiting
    still makes 31 real requests and hits 429 correctly.
    """
    from app.middleware.rate_limit import limiter

    limiter._storage.reset()
    yield


@pytest.fixture
def valid_auth_header():
    """Authorization header carrying a mock valid token."""
    return {"Authorization": "Bearer valid-test-token"}


@pytest.fixture
def expired_auth_header():
    """Authorization header carrying a mock expired token."""
    return {"Authorization": "Bearer expired-test-token"}


@pytest.fixture
def mock_valid_token(monkeypatch):
    """Patch Firebase token verification to accept 'valid-test-token'."""

    def _verify(token, request, audience=None):
        if token == "valid-test-token":
            return {"uid": "test-user-123", "sub": "test-user-123"}
        raise Exception("Token invalid or expired")

    monkeypatch.setattr("firebase_admin.auth.verify_id_token", _verify)


@pytest.fixture
def mock_expired_token(monkeypatch):
    """Patch Firebase token verification to always raise (simulates expiry)."""

    def _verify(token, request, audience=None):
        raise Exception("Token has expired")

    monkeypatch.setattr("firebase_admin.auth.verify_id_token", _verify)
