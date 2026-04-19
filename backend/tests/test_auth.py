"""Tests for JWT authentication middleware behaviour."""
<<<<<<< HEAD
from unittest.mock import patch
=======
>>>>>>> origin/main

YIELD_URL = "/api/yield/predict"
HEALTH_URL = "/api/health"

MINIMAL_YIELD_PAYLOAD = {
    "crop": "Carrot",
    "district": "Nuwara Eliya",
    "season": "Maha",
    "week_of_year": 10,
    "rainfall_mm": 100.0,
    "temp_min_c": 10.0,
    "temp_max_c": 22.0,
    "humidity_pct": 70.0,
    "wind_speed_kmh": 10.0,
    "solar_radiation_mj": 15.0,
    "soil_ph": 6.0,
    "soil_moisture_pct": 55.0,
    "cultivated_area_ha": 1.0,
    "seed_variety": "Standard",
    "fertilizer_index": 0.5,
    "pesticide_index": 0.5,
    "irrigation_type": "drip",
    "N_index": 0.5,
    "P_index": 0.5,
    "K_index": 0.5,
    "prev_crop": "none",
    "demand_index": 100.0,
    "inflation_index": 1.0,
    "holiday_flag": 0,
    "festival_flag": 0,
}


def test_health_endpoint_is_public(client):
    """Health endpoint must be reachable without any token."""
    resp = client.get(HEALTH_URL)
    assert resp.status_code == 200


def test_missing_token_returns_401(client, mock_expired_token):
    resp = client.post(YIELD_URL, json=MINIMAL_YIELD_PAYLOAD)
    assert resp.status_code == 401
<<<<<<< HEAD
    assert "Authorization" in resp.json()["detail"] or "missing" in resp.json()["detail"].lower()
=======
>>>>>>> origin/main


def test_invalid_token_returns_401(client, mock_expired_token):
    resp = client.post(
        YIELD_URL,
        json=MINIMAL_YIELD_PAYLOAD,
        headers={"Authorization": "Bearer totally-invalid"},
    )
    assert resp.status_code == 401


def test_expired_token_returns_401(client, mock_expired_token):
    resp = client.post(
        YIELD_URL,
        json=MINIMAL_YIELD_PAYLOAD,
        headers={"Authorization": "Bearer expired-test-token"},
    )
    assert resp.status_code == 401


def test_valid_token_passes_auth(client, mock_valid_token, valid_auth_header):
<<<<<<< HEAD
    """A valid token should reach the route (422 from missing body is fine here)."""
    resp = client.post(YIELD_URL, json={}, headers=valid_auth_header)
    # 422 means auth passed — Pydantic rejected the empty body
=======
    """A valid token should reach the route handler (422 means auth passed)."""
    resp = client.post(YIELD_URL, json={}, headers=valid_auth_header)
>>>>>>> origin/main
    assert resp.status_code == 422


def test_malformed_auth_header_returns_401(client, mock_expired_token):
    """'Token xyz' (not 'Bearer xyz') must be rejected."""
    resp = client.post(
        YIELD_URL,
        json=MINIMAL_YIELD_PAYLOAD,
        headers={"Authorization": "Token valid-test-token"},
    )
    assert resp.status_code == 401
