"""Tests for POST /api/weather/forecast."""
from unittest.mock import MagicMock, patch
import numpy as np

URL = "/api/weather/forecast"

VALID = {
    "district": "Nuwara Eliya",
    "start_date": "2025-04-01",
    "weeks_ahead": 2,
}


def test_valid_input_returns_200(client, mock_valid_token, valid_auth_header):
    mock_model = MagicMock()
    mock_model.predict.return_value = np.array([[120.0, 10.0, 22.0, 75.0]])

    def _get_model(name):
        if name == "weather_lstm":
            return mock_model
        return None  # scaler absent — service uses raw output

    with patch("app.models.loader.model_loader.is_loaded", return_value=True), \
         patch("app.models.loader.model_loader.get_model", side_effect=_get_model), \
         patch("app.utils.firestore.audit_log"):
        resp = client.post(URL, json=VALID, headers=valid_auth_header)

    assert resp.status_code == 200
    body = resp.json()
    assert "forecasts" in body
    assert len(body["forecasts"]) == 2


def test_missing_required_field_returns_422(client, mock_valid_token, valid_auth_header):
    resp = client.post(URL, json={"district": "Badulla"}, headers=valid_auth_header)
    assert resp.status_code == 422


def test_out_of_range_value_returns_422(client, mock_valid_token, valid_auth_header):
    resp = client.post(URL, json={**VALID, "weeks_ahead": 99}, headers=valid_auth_header)
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
