"""Tests for POST /api/recommend."""
from unittest.mock import patch

URL = "/api/recommend"

VALID = {
    "district": "Nuwara Eliya",
    "season": "Maha",
    "week_of_year": 10,
    "rainfall_mm": 120.0,
    "temp_min_c": 10.0,
    "temp_max_c": 22.0,
    "humidity_pct": 75.0,
    "soil_ph": 6.0,
    "soil_moisture_pct": 60.0,
    "N_index": 0.5,
    "P_index": 0.4,
    "K_index": 0.6,
    "irrigation_type": "drip",
}


def _mock_recommend_response():
    from app.models.schemas import CropEnum, CropRecommendation, RecommendResponse
    return RecommendResponse(
        recommendations=[
            CropRecommendation(
                rank=1,
                crop=CropEnum.carrot,
                confidence_score=0.85,
                expected_yield_kg_per_ha=3500.0,
                expected_price_lkr_kg=90.0,
                suitability_flags={"yield_modelled": False, "any_mock": True},
            )
        ]
    )


def test_valid_input_returns_200(client, mock_valid_token, valid_auth_header):
    with patch(
        "app.services.recommend_service.get_recommendations",
        return_value=_mock_recommend_response(),
    ), patch("app.utils.firestore.audit_log"):
        resp = client.post(URL, json=VALID, headers=valid_auth_header)

    assert resp.status_code == 200
    body = resp.json()
    assert "recommendations" in body
    assert len(body["recommendations"]) >= 1


def test_missing_required_field_returns_422(client, mock_valid_token, valid_auth_header):
    payload = {k: v for k, v in VALID.items() if k != "district"}
    resp = client.post(URL, json=payload, headers=valid_auth_header)
    assert resp.status_code == 422


def test_out_of_range_value_returns_422(client, mock_valid_token, valid_auth_header):
    resp = client.post(URL, json={**VALID, "soil_ph": 15.0}, headers=valid_auth_header)
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
    body = resp.json()
    for rec in body["recommendations"]:
        assert rec["suitability_flags"]["any_mock"] is True
