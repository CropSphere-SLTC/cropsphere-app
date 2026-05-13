from fastapi.testclient import TestClient
from app.main import app

client = TestClient(app)


def test_rate_limit_allows_normal_requests():
    response = client.get("/api/health")
    assert response.status_code == 200
    print("✅ Test 1 Passed — Normal request allowed")


def test_rate_limit_middleware_is_active():
    # Verify limiter is attached to app state
    assert hasattr(app.state, "limiter")
    print("✅ Test 2 Passed — Rate limiting middleware is active")
