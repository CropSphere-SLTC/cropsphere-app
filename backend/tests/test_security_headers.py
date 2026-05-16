import pytest
from fastapi.testclient import TestClient
from app.main import app

client = TestClient(app)


def test_security_headers_present():
    """Security headers must be present in every response."""
    response = client.get("/api/health")
    assert response.status_code == 200
    assert "x-frame-options" in response.headers
    assert "x-content-type-options" in response.headers
    assert "referrer-policy" in response.headers
    print("✅ Test 1 Passed — Security headers present")


def test_clickjacking_header_is_deny():
    """X-Frame-Options must be DENY to prevent clickjacking."""
    response = client.get("/api/health")
    assert response.headers.get("x-frame-options") == "DENY"
    print("✅ Test 2 Passed — Clickjacking header correct")