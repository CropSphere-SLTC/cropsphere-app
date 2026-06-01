"""Tests for POST /api/demand/predict."""

from unittest.mock import MagicMock, patch

URL = "/api/demand/predict"

VALID = {
    "crop": "Carrot",
    "season": "Maha",
    "week_of_year": 10,
    "demand_lag1": 95.0,
    "demand_lag2": 90.0,
    "demand_lag4": 85.0,
    "retail_price_lkr_kg": 120.0,
    "inflation_index": 1.2,
    "holiday_flag": 0,
    "festival_flag": 0,
    "consumer_pref_index": 60.0,
    "search_trend_index": 45.0,
}


def test_valid_input_returns_200(client, mock_valid_token, valid_auth_header):
    mock_model = MagicMock()
    mock_model.predict.return_value = [105.0]

    with patch("app.models.loader.model_loader.is_loaded", return_value=True), patch(
        "app.models.loader.model_loader.get_model", return_value=mock_model
    ), patch("app.utils.firestore.audit_log"):
        resp = client.post(URL, json=VALID, headers=valid_auth_header)

    assert resp.status_code == 200
    body = resp.json()
    assert "predicted_demand_index" in body
    assert body["is_mock"] is False


def test_missing_required_field_returns_422(
    client, mock_valid_token, valid_auth_header
):
    payload = {k: v for k, v in VALID.items() if k != "retail_price_lkr_kg"}
    resp = client.post(URL, json=payload, headers=valid_auth_header)
    assert resp.status_code == 422


def test_out_of_range_value_returns_422(client, mock_valid_token, valid_auth_header):
    resp = client.post(
        URL, json={**VALID, "demand_lag1": 500.0}, headers=valid_auth_header
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
