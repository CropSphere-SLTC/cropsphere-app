"""Tests for POST /api/price/predict."""

from unittest.mock import MagicMock, patch
import numpy as np

URL = "/api/price/predict"

VALID = {
    "crop": "Carrot",
    "district": "Nuwara Eliya",
    "season": "Maha",
    "week_of_year": 10,
    "inflation_index": 1.2,
    "fuel_price_index": 1.1,
    "transport_cost_index": 1.0,
    "supply_index": 100.0,
    "demand_index": 110.0,
    "holiday_flag": 0,
    "festival_flag": 0,
    "farmgate_price_lag1": 85.0,
    "farmgate_price_lag2": 80.0,
    "farmgate_price_lag4": 75.0,
}


def test_valid_input_returns_200(client, mock_valid_token, valid_auth_header):
    mock_model = MagicMock()
    mock_model.predict.return_value = np.array([[88.0, 110.0]])

    with patch("app.models.loader.model_loader.is_loaded", return_value=True), patch(
        "app.models.loader.model_loader.get_model", return_value=mock_model
    ), patch("app.utils.firestore.audit_log"):
        resp = client.post(URL, json=VALID, headers=valid_auth_header)

    assert resp.status_code == 200
    body = resp.json()
    assert "predicted_farmgate_price_lkr_kg" in body
    assert body["is_mock"] is False


def test_missing_required_field_returns_422(
    client, mock_valid_token, valid_auth_header
):
    payload = {k: v for k, v in VALID.items() if k != "farmgate_price_lag1"}
    resp = client.post(URL, json=payload, headers=valid_auth_header)
    assert resp.status_code == 422


def test_out_of_range_value_returns_422(client, mock_valid_token, valid_auth_header):
    resp = client.post(
        URL, json={**VALID, "inflation_index": 99.0}, headers=valid_auth_header
    )
    assert resp.status_code == 422


def test_no_jwt_returns_401(client, mock_expired_token):
    resp = client.post(URL, json=VALID)
    assert resp.status_code == 401


def test_expired_jwt_returns_401(client, mock_expired_token, expired_auth_header):
    resp = client.post(URL, json=VALID, headers=expired_auth_header)
    assert resp.status_code == 401


def test_mock_response_when_model_not_loaded(
    client, mock_valid_token, valid_auth_header
):
    with patch("app.models.loader.model_loader.is_loaded", return_value=False), patch(
        "app.utils.firestore.audit_log"
    ):
        resp = client.post(URL, json=VALID, headers=valid_auth_header)

    assert resp.status_code == 200
    assert resp.json()["is_mock"] is True
