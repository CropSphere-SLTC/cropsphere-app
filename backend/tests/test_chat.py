"""Tests for POST /api/chat."""
from unittest.mock import MagicMock, patch

URL = "/api/chat"

VALID = {
    "message": "What crop should I plant this season?",
    "conversation_history": [],
    "user_id": "test-user-123",
    "district": "Nuwara Eliya",
    "crop": "Carrot",
}


def _mock_chat_response():
    from app.models.schemas import ChatResponse
    return ChatResponse(
        reply="You should consider planting Carrot this Maha season.",
        sources_used=["crop_guide_lk.pdf"],
        suggested_followups=["When to plant?", "What fertiliser?", "Market price?"],
    )


def test_valid_input_returns_200(client, mock_valid_token, valid_auth_header):
    with patch(
        "app.services.chatbot_service.chat",
        return_value=_mock_chat_response(),
    ):
        resp = client.post(URL, json=VALID, headers=valid_auth_header)

    assert resp.status_code == 200
    body = resp.json()
    assert "reply" in body
    assert len(body["suggested_followups"]) == 3


def test_missing_required_field_returns_422(client, mock_valid_token, valid_auth_header):
    payload = {k: v for k, v in VALID.items() if k != "user_id"}
    resp = client.post(URL, json=payload, headers=valid_auth_header)
    assert resp.status_code == 422


def test_out_of_range_value_returns_422(client, mock_valid_token, valid_auth_header):
    resp = client.post(URL, json={**VALID, "message": "x" * 501}, headers=valid_auth_header)
    assert resp.status_code == 422


def test_no_jwt_returns_401(client, mock_expired_token):
    resp = client.post(URL, json=VALID)
    assert resp.status_code == 401


def test_expired_jwt_returns_401(client, mock_expired_token, expired_auth_header):
    resp = client.post(URL, json=VALID, headers=expired_auth_header)
    assert resp.status_code == 401


def test_mock_response_when_model_not_loaded(client, mock_valid_token, valid_auth_header):
    """Groq unavailable → service raises → 500 is expected, not is_mock flag."""
    with patch(
        "app.services.chatbot_service.chat",
        side_effect=RuntimeError("Chatbot unavailable"),
    ):
        resp = client.post(URL, json=VALID, headers=valid_auth_header)

    assert resp.status_code == 500
