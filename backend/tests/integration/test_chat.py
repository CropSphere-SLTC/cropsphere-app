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


# ── Friendly refusal / capability helpers (no Groq) ───────────────────────────

_CAPS = {
    "crops": ["Carrot", "Maize"],
    "districts": ["Badulla", "Nuwara Eliya"],
    "crop_districts": {"Carrot": ["Badulla", "Nuwara Eliya"]},
    "district_crops": {"Badulla": ["Carrot", "Maize"]},
}


def test_near_miss_crop_district_none():
    from app.user.services.chatbot_service import _near_miss

    # Covered crop, uncovered district → crop_match
    assert _near_miss("carrot price in galle", _CAPS) == ("crop_match", "Carrot")
    # Covered district, uncovered crop → district_match
    assert _near_miss("rice yield in badulla", _CAPS) == (
        "district_match",
        "Badulla",
    )
    # Neither → None
    assert _near_miss("weather on mars", _CAPS) is None
    # Both covered → None (that's the retrieval path's job)
    assert _near_miss("carrot in badulla", _CAPS) is None


def test_capability_question_detection():
    from app.user.services.chatbot_service import _is_capability_question

    assert _is_capability_question("what crops do you cover?")
    assert _is_capability_question("which districts are supported")
    # Must NOT hijack a real question that happens to contain "what can you"
    assert not _is_capability_question("what can you tell me about carrots")


def test_build_refusal_and_followups_use_real_coverage():
    import app.user.services.chatbot_service as svc

    # Force the enum-fallback capabilities and a clean cache.
    svc._capabilities_cache = None
    reply = svc._build_refusal("how do I grow rice in kurunegala")
    assert reply and len(reply) < 400
    followups = svc._refusal_followups("carrot price in galle")
    assert len(followups) == 3
    assert followups[-1] == "What crops do you cover?"
    # Near-miss crop match surfaces the covered crop in the suggestions.
    assert any("Carrot" in f for f in followups)
    svc._capabilities_cache = None  # avoid leaking into other tests


def test_explicit_miss_gazetteer():
    import app.user.services.chatbot_service as svc

    svc._capabilities_cache = None
    # Covered crop + uncovered district → crop_match
    assert svc._explicit_miss("carrot price in Galle") == ("crop_match", "Carrot")
    # Covered district + uncovered crop → district_match
    assert svc._explicit_miss("potato in Nuwara Eliya") == (
        "district_match",
        "Nuwara Eliya",
    )
    # Both uncovered → generic
    assert svc._explicit_miss("rice price in Kurunegala") == ("generic", "")
    # No uncovered term → None (normal retrieval path)
    assert svc._explicit_miss("carrot yield in Badulla") is None
    # Substring trap: "rice" must NOT match inside "price"
    assert svc._explicit_miss("carrot price in Badulla") is None
    svc._capabilities_cache = None


def test_generic_refusal_has_no_empty_placeholders():
    import app.user.services.chatbot_service as svc

    svc._capabilities_cache = None
    # ("generic", "") must render a generic template, not a district_match
    # template with an empty name ("I have data for , but not that crop").
    reply = svc._build_refusal("rice price in Kurunegala", near=("generic", ""))
    assert "data for ," not in reply
    assert "In  I can help" not in reply
    svc._capabilities_cache = None


# ── POST /api/chat/feedback ───────────────────────────────────────────────────

FEEDBACK_URL = "/api/chat/feedback"
FEEDBACK_VALID = {
    "conversation_id": "conv-1",
    "message_index": 2,
    "feedback": "up",
    "message_text": "carrot yield in badulla",
}


def test_feedback_valid_returns_200(client, mock_valid_token, valid_auth_header):
    with patch("app.user.routers.chat_router.log_feedback") as mock_log:
        resp = client.post(
            FEEDBACK_URL, json=FEEDBACK_VALID, headers=valid_auth_header
        )
    assert resp.status_code == 200
    assert resp.json() == {"status": "ok"}
    mock_log.assert_called_once()


def test_feedback_invalid_value_returns_422(
    client, mock_valid_token, valid_auth_header
):
    resp = client.post(
        FEEDBACK_URL,
        json={**FEEDBACK_VALID, "feedback": "maybe"},
        headers=valid_auth_header,
    )
    assert resp.status_code == 422


def test_feedback_no_jwt_returns_401(client, mock_expired_token):
    resp = client.post(FEEDBACK_URL, json=FEEDBACK_VALID)
    assert resp.status_code == 401


def test_get_feedback_returns_votes(client, mock_valid_token, valid_auth_header):
    with patch(
        "app.user.routers.chat_router.get_conversation_feedback",
        return_value={1: "up", 3: "down"},
    ):
        resp = client.get("/api/chat/feedback/conv-1", headers=valid_auth_header)
    assert resp.status_code == 200
    # JSON object keys are strings on the wire.
    assert resp.json() == {"votes": {"1": "up", "3": "down"}}


def test_get_feedback_no_jwt_returns_401(client, mock_expired_token):
    resp = client.get("/api/chat/feedback/conv-1")
    assert resp.status_code == 401
