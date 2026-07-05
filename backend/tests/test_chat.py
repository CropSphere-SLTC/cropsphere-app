"""Tests for POST /api/chat."""

from unittest.mock import patch

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
        "app.user.routers.chat_router.chat",
        return_value=_mock_chat_response(),
    ):
        resp = client.post(URL, json=VALID, headers=valid_auth_header)

    assert resp.status_code == 200
    body = resp.json()
    assert "reply" in body
    assert len(body["suggested_followups"]) == 3


def test_missing_required_field_returns_422(
    client, mock_valid_token, valid_auth_header
):
    payload = {k: v for k, v in VALID.items() if k != "user_id"}
    resp = client.post(URL, json=payload, headers=valid_auth_header)
    assert resp.status_code == 422


def test_out_of_range_value_returns_422(client, mock_valid_token, valid_auth_header):
    resp = client.post(
        URL, json={**VALID, "message": "x" * 501}, headers=valid_auth_header
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
    """Groq/RAG unavailable → service raises RuntimeError → 500."""
    with patch(
        "app.user.routers.chat_router.chat",
        side_effect=RuntimeError("Chatbot unavailable"),
    ):
        resp = client.post(URL, json=VALID, headers=valid_auth_header)

    assert resp.status_code == 500


# ── POST /api/chat/stream (SSE) ───────────────────────────────────────────────

STREAM_URL = "/api/chat/stream"


def _fake_stream_events(*args, **kwargs):
    """Stand-in for chatbot_service.chat_stream — happy path events."""
    yield {"type": "text", "content": "Plant "}
    yield {"type": "text", "content": "Carrot."}
    yield {
        "type": "metadata",
        "confidence": "High confidence",
        "sources": ["CropSphere dataset: Carrot — Nuwara Eliya — Maha (summary)"],
        "suggested_followups": ["When to plant?", "Fertiliser?", "Price?"],
        "conversation_id": "conv-1",
    }


def test_stream_valid_input_returns_sse(client, mock_valid_token, valid_auth_header):
    with patch(
        "app.user.routers.chat_router.chat_stream",
        side_effect=lambda *a, **k: _fake_stream_events(),
    ):
        resp = client.post(STREAM_URL, json=VALID, headers=valid_auth_header)

    assert resp.status_code == 200
    assert resp.headers["content-type"].startswith("text/event-stream")
    body = resp.text
    assert 'data: {"type": "text"' in body
    assert '"type": "metadata"' in body
    assert '"confidence": "High confidence"' in body
    assert body.rstrip().endswith("data: [DONE]")


def test_stream_error_event_still_terminates(
    client, mock_valid_token, valid_auth_header
):
    """Mid-stream service failure → error event + [DONE], never a 500."""

    def _broken(*args, **kwargs):
        yield {"type": "text", "content": "partial "}
        raise RuntimeError("groq died")

    with patch(
        "app.user.routers.chat_router.chat_stream",
        side_effect=lambda *a, **k: _broken(),
    ):
        resp = client.post(STREAM_URL, json=VALID, headers=valid_auth_header)

    assert resp.status_code == 200
    body = resp.text
    assert '"type": "error"' in body
    assert '"code": "server_error"' in body
    assert body.rstrip().endswith("data: [DONE]")


def test_stream_no_jwt_returns_401(client, mock_expired_token):
    resp = client.post(STREAM_URL, json=VALID)
    assert resp.status_code == 401
