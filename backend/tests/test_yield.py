"""Tests for POST /api/yield/predict."""
from unittest.mock import MagicMock, patch

URL = "/api/yield/predict"

VALID = {
    "crop": "Carrot",
    "district": "Nuwara Eliya",
    "season": "Maha",
    "week_of_year": 10,
    "rainfall_mm": 120.0,
    "temp_min_c": 10.0,
    "temp_max_c": 22.0,
    "humidity_pct": 75.0,
    "wind_speed_kmh": 15.0,
    "solar_radiation_mj": 18.0,
    "soil_ph": 6.0,
    "soil_moisture_pct": 60.0,
    "cultivated_area_ha": 2.0,
    "seed_variety": "Ooty-1",
    "fertilizer_index": 0.6,
    "pesticide_index": 0.4,
    "irrigation_type": "drip",
    "N_index": 0.5,
    "P_index": 0.4,
    "K_index": 0.6,
    "prev_crop": "Potato",
    "demand_index": 100.0,
    "inflation_index": 1.2,
    "holiday_flag": 0,
    "festival_flag": 0,
}


def test_valid_input_returns_200(client, mock_valid_token, valid_auth_header):
    mock_model = MagicMock()
    mock_model.predict.return_value = [3500.0]
    mock_model.predict_proba = None

    with patch("app.models.loader.model_loader.is_loaded", return_value=True), \
         patch("app.models.loader.model_loader.get_model", return_value=mock_model), \
         patch("app.utils.firestore.audit_log"):
        resp = client.post(URL, json=VALID, headers=valid_auth_header)

    assert resp.status_code == 200
    body = resp.json()
    assert "predicted_yield_kg_per_ha" in body
    assert body["is_mock"] is False


def test_missing_required_field_returns_422(client, mock_valid_token, valid_auth_header):
    payload = {k: v for k, v in VALID.items() if k != "crop"}
    resp = client.post(URL, json=payload, headers=valid_auth_header)
    assert resp.status_code == 422


def test_out_of_range_value_returns_422(client, mock_valid_token, valid_auth_header):
    resp = client.post(URL, json={**VALID, "rainfall_mm": 9999.0}, headers=valid_auth_header)
    assert resp.status_code == 422


def test_no_jwt_returns_401(client, mock_expired_token):
    resp = client.post(URL, json=VALID)
    assert resp.status_code == 401


def test_expired_jwt_returns_401(client, mock_expired_token, expired_auth_header):
    resp = client.post(URL, json=VALID, headers=expired_auth_header)
    assert resp.status_code == 401


def test_mock_response_when_model_not_loaded(client, mock_valid_token, valid_auth_header):
    with patch("app.models.loader.model_loader.is_loaded", return_value=False), \
         patch("app.utils.firestore.audit_log"):
        resp = client.post(URL, json=VALID, headers=valid_auth_header)

    assert resp.status_code == 200
    assert resp.json()["is_mock"] is True
