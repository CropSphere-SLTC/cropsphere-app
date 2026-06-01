from fastapi.testclient import TestClient
from app.main import app

client = TestClient(app)


def test_request_without_token_is_rejected():
    """No token — should be rejected."""
    response = client.get("/api/health/admin/status")
    assert response.status_code in [401, 403]
    print("✅ Test 1 Passed — Request without token rejected")


def test_request_with_invalid_token_is_rejected():
    """Fake/expired token — should be rejected."""
    headers = {"Authorization": "Bearer fake.expired.token"}
    response = client.get("/api/health/admin/status", headers=headers)
    assert response.status_code in [401, 403]
    print("✅ Test 2 Passed — Invalid token rejected")


def test_request_with_malformed_header_is_rejected():
    """Malformed Authorization header — should be rejected."""
    headers = {"Authorization": "InvalidHeader"}
    response = client.get("/api/health/admin/status", headers=headers)
    assert response.status_code in [401, 403]
    print("✅ Test 3 Passed — Malformed header rejected")


def test_public_endpoint_accessible_without_token():
    """Public endpoints should work without any token."""
    response = client.get("/api/health")
    assert response.status_code == 200
    print("✅ Test 4 Passed — Public endpoint accessible")
