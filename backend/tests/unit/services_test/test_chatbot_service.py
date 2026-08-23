"""Unit tests for app.user.services.chatbot_service.

Calls the service functions directly (no HTTP layer). Groq, sentence_transformers
and model_loader are all mocked at the point of use, so no network, no real
encoder download, and no real model files are needed. Covers the deterministic
short-circuits (capability, near-miss, grounding refusal), the RAG retrieval
scoring/boost logic, the streaming generator, and every helper.
"""

from types import SimpleNamespace
from unittest.mock import MagicMock, patch

import numpy as np
import pytest

from app.models.schemas import (
    ChatRequest,
    ConversationTurn,
    CropEnum,
    DistrictEnum,
)
from app.user.services import chatbot_service as cs

SETTINGS = SimpleNamespace(GROQ_API_KEY="test-groq-key")

VALID_KWARGS = {
    "message": "How much carrot yield can I expect in Nuwara Eliya?",
    "conversation_history": [],
    "user_id": "user-1",
    "model": "accurate",
}


def _make_request(**overrides) -> ChatRequest:
    return ChatRequest(**{**VALID_KWARGS, **overrides})


@pytest.fixture(autouse=True)
def _reset_module_caches():
    """Clear the process-lifetime caches so tests don't bleed into each other."""
    cs._capabilities_cache = None
    cs._encoder = None
    yield
    cs._capabilities_cache = None
    cs._encoder = None


# Fake cosine-sim result shaped like util.cos_sim(...)[0].tolist()
class _FakeSims:
    def __init__(self, row):
        self._row = row

    def __getitem__(self, i):
        return SimpleNamespace(tolist=lambda: self._row)


def _fake_encoder():
    enc = MagicMock()

    def _encode(x, convert_to_tensor=False):
        if isinstance(x, list):
            return np.ones((len(x), 2))
        return np.ones(2)

    enc.encode.side_effect = _encode
    return enc


def _rag_dict(chunks, metadata):
    return {
        "knowledge_chunks": chunks,
        "chunk_metadata": metadata,
        "chunk_embeddings": object(),  # truthy; cos_sim is mocked
    }


# ═══════════════════════════════════════════════════════════════════════════
# _strip_html
# ═══════════════════════════════════════════════════════════════════════════


def test_strip_html_removes_tags():
    assert cs._strip_html("<b>hello</b> <script>x</script>world") == "hello xworld"


def test_strip_html_plain_text_unchanged():
    assert cs._strip_html("just text") == "just text"


# ═══════════════════════════════════════════════════════════════════════════
# _safe_audit
# ═══════════════════════════════════════════════════════════════════════════


def test_safe_audit_calls_audit_log():
    with patch("app.user.services.chatbot_service.audit_log") as mock_audit:
        cs._safe_audit("user-1", "hello")
    mock_audit.assert_called_once()


def test_safe_audit_swallows_exceptions():
    with patch(
        "app.user.services.chatbot_service.audit_log",
        side_effect=RuntimeError("firestore down"),
    ):
        # Must not raise
        cs._safe_audit("user-1", "hello")


# ═══════════════════════════════════════════════════════════════════════════
# _source_label
# ═══════════════════════════════════════════════════════════════════════════


def test_source_label_with_crop_and_district():
    label = cs._source_label({"crop": "Carrot", "district": "Badulla", "type": "yield"})
    assert "Carrot" in label and "Badulla" in label and "yield" in label


def test_source_label_falls_back_when_empty():
    assert cs._source_label({}) == "CropSphere agricultural dataset"


# ═══════════════════════════════════════════════════════════════════════════
# _dataset_capabilities
# ═══════════════════════════════════════════════════════════════════════════


def test_dataset_capabilities_from_rag_metadata():
    metadata = [
        {"crop": "Carrot", "district": "Nuwara Eliya"},
        {"crop": "Maize", "district": "Ampara"},
        {"crop": "all", "district": "all"},  # placeholders excluded
    ]
    with patch(
        "app.user.services.chatbot_service.model_loader.get_model",
        return_value=_rag_dict([], metadata),
    ):
        caps = cs._dataset_capabilities()

    assert "Carrot" in caps["crops"]
    assert "all" not in caps["crops"]
    assert "Nuwara Eliya" in caps["district_crops"]
    assert "Carrot" in caps["crop_districts"]


def test_dataset_capabilities_falls_back_to_enums():
    with patch(
        "app.user.services.chatbot_service.model_loader.get_model",
        return_value=None,
    ):
        caps = cs._dataset_capabilities()

    assert set(caps["crops"]) == {c.value for c in CropEnum}
    assert set(caps["districts"]) == {d.value for d in DistrictEnum}


def test_dataset_capabilities_is_cached():
    with patch(
        "app.user.services.chatbot_service.model_loader.get_model",
        return_value=None,
    ) as mock_get:
        cs._dataset_capabilities()
        cs._dataset_capabilities()
    # Second call should hit the cache, not model_loader again
    assert mock_get.call_count == 1


# ═══════════════════════════════════════════════════════════════════════════
# _near_miss
# ═══════════════════════════════════════════════════════════════════════════


def _enum_caps():
    return {
        "crops": [c.value for c in CropEnum],
        "districts": [d.value for d in DistrictEnum],
        "crop_districts": {},
        "district_crops": {},
    }


def test_near_miss_crop_only():
    assert cs._near_miss("tell me about carrot", _enum_caps()) == (
        "crop_match",
        "Carrot",
    )


def test_near_miss_district_only():
    assert cs._near_miss("what about badulla", _enum_caps()) == (
        "district_match",
        "Badulla",
    )


def test_near_miss_both_returns_none():
    assert cs._near_miss("carrot in badulla", _enum_caps()) is None


def test_near_miss_neither_returns_none():
    assert cs._near_miss("hello there", _enum_caps()) is None


# ═══════════════════════════════════════════════════════════════════════════
# _explicit_miss
# ═══════════════════════════════════════════════════════════════════════════


def test_explicit_miss_none_when_no_uncovered_term():
    with patch(
        "app.user.services.chatbot_service.model_loader.get_model",
        return_value=None,
    ):
        assert cs._explicit_miss("carrot yield in badulla") is None


def test_explicit_miss_district_match_uncovered_crop_covered_district():
    with patch(
        "app.user.services.chatbot_service.model_loader.get_model",
        return_value=None,
    ):
        # "rice" uncovered crop + "Jaffna" covered district
        assert cs._explicit_miss("rice yield in jaffna") == (
            "district_match",
            "Jaffna",
        )


def test_explicit_miss_crop_match_uncovered_district_covered_crop():
    with patch(
        "app.user.services.chatbot_service.model_loader.get_model",
        return_value=None,
    ):
        # "colombo" uncovered district + "carrot" covered crop
        assert cs._explicit_miss("carrot price in colombo") == (
            "crop_match",
            "Carrot",
        )


def test_explicit_miss_generic_when_nothing_covered():
    with patch(
        "app.user.services.chatbot_service.model_loader.get_model",
        return_value=None,
    ):
        assert cs._explicit_miss("rice price in colombo") == ("generic", "")


def test_explicit_miss_token_boundary_price_not_rice():
    """'price' must not trigger the 'rice' uncovered-crop token."""
    with patch(
        "app.user.services.chatbot_service.model_loader.get_model",
        return_value=None,
    ):
        assert cs._explicit_miss("carrot price in badulla") is None


# ═══════════════════════════════════════════════════════════════════════════
# _build_refusal
# ═══════════════════════════════════════════════════════════════════════════


def test_build_refusal_crop_match_points_to_districts():
    caps = {
        "crops": ["Carrot"],
        "districts": ["Badulla"],
        "crop_districts": {"Carrot": ["Nuwara Eliya", "Badulla"]},
        "district_crops": {},
    }
    with patch(
        "app.user.services.chatbot_service._dataset_capabilities",
        return_value=caps,
    ):
        msg = cs._build_refusal("x", near=("crop_match", "Carrot"))
    assert "Carrot" in msg and "Nuwara Eliya" in msg


def test_build_refusal_district_match_points_to_crops():
    caps = {
        "crops": ["Carrot"],
        "districts": ["Jaffna"],
        "crop_districts": {},
        "district_crops": {"Jaffna": ["Carrot", "Maize"]},
    }
    with patch(
        "app.user.services.chatbot_service._dataset_capabilities",
        return_value=caps,
    ):
        msg = cs._build_refusal("x", near=("district_match", "Jaffna"))
    assert "Jaffna" in msg and "Carrot" in msg


def test_build_refusal_generic_template():
    with patch(
        "app.user.services.chatbot_service.model_loader.get_model",
        return_value=None,
    ):
        msg = cs._build_refusal("something random", near=("generic", ""))
    assert isinstance(msg, str) and len(msg) > 0


def test_build_refusal_no_near_uses_near_miss_detection():
    with patch(
        "app.user.services.chatbot_service.model_loader.get_model",
        return_value=None,
    ):
        # Covered crop, no district -> crop_match branch inside _near_miss
        msg = cs._build_refusal("tell me about carrot")
    assert "Carrot" in msg


# ═══════════════════════════════════════════════════════════════════════════
# _refusal_followups
# ═══════════════════════════════════════════════════════════════════════════


def test_refusal_followups_crop_match():
    caps = {
        "crops": ["Carrot"],
        "districts": ["Badulla"],
        "crop_districts": {"Carrot": ["Nuwara Eliya", "Badulla"]},
        "district_crops": {},
    }
    with patch(
        "app.user.services.chatbot_service._dataset_capabilities",
        return_value=caps,
    ):
        fu = cs._refusal_followups("x", near=("crop_match", "Carrot"))
    assert len(fu) == 3 and fu[-1] == "What crops do you cover?"


def test_refusal_followups_district_match():
    caps = {
        "crops": ["Carrot"],
        "districts": ["Jaffna"],
        "crop_districts": {},
        "district_crops": {"Jaffna": ["Carrot", "Maize"]},
    }
    with patch(
        "app.user.services.chatbot_service._dataset_capabilities",
        return_value=caps,
    ):
        fu = cs._refusal_followups("x", near=("district_match", "Jaffna"))
    assert len(fu) == 3 and "Jaffna" in fu[0]


def test_refusal_followups_generic():
    with patch(
        "app.user.services.chatbot_service.model_loader.get_model",
        return_value=None,
    ):
        fu = cs._refusal_followups("random", near=("generic", ""))
    assert len(fu) == 3 and fu[-1] == "What crops do you cover?"


# ═══════════════════════════════════════════════════════════════════════════
# _is_capability_question / _capability_reply / _is_non_topic_reply
# ═══════════════════════════════════════════════════════════════════════════


def test_is_capability_question_true():
    assert cs._is_capability_question("what crops do you cover?") is True


def test_is_capability_question_false():
    assert cs._is_capability_question("what can you tell me about carrots") is False


def test_capability_reply_shape():
    with patch(
        "app.user.services.chatbot_service.model_loader.get_model",
        return_value=None,
    ):
        reply, followups = cs._capability_reply()
    assert "I currently have data on" in reply
    assert len(followups) == 3


def test_is_non_topic_reply_matches_refusal_marker():
    assert cs._is_non_topic_reply(cs._OUT_OF_SCOPE_MARKER + " ...") is True


def test_is_non_topic_reply_false_for_normal_answer():
    assert cs._is_non_topic_reply("Carrots grow well in Nuwara Eliya.") is False


# ═══════════════════════════════════════════════════════════════════════════
# _confidence_label
# ═══════════════════════════════════════════════════════════════════════════


def test_confidence_label_out_of_scope_when_no_chunks():
    assert cs._confidence_label({"chunks": [], "score": 0.0}) == "Out of scope"


def test_confidence_label_high():
    assert cs._confidence_label({"chunks": [1], "score": 0.9}) == "High confidence"


def test_confidence_label_moderate():
    assert cs._confidence_label({"chunks": [1], "score": 0.6}) == "Moderate confidence"


def test_confidence_label_low():
    label = cs._confidence_label({"chunks": [1], "score": 0.3})
    assert label.startswith("Low confidence")


# ═══════════════════════════════════════════════════════════════════════════
# _system_prompt / _followups / _build_messages
# ═══════════════════════════════════════════════════════════════════════════


def test_system_prompt_includes_district_and_crop():
    req = _make_request(district="Badulla", crop="Carrot")
    prompt = cs._system_prompt(req)
    assert "Badulla" in prompt and "Carrot" in prompt


def test_system_prompt_without_district_or_crop():
    req = _make_request()
    prompt = cs._system_prompt(req)
    assert "CropSphere" in prompt


def test_followups_uses_crop_and_district():
    req = _make_request(district="Badulla", crop="Carrot")
    fu = cs._default_followups(req)
    assert len(fu) == 3 and "Carrot" in fu[0] and "Badulla" in fu[0]


def test_followups_defaults_when_missing():
    req = _make_request()
    fu = cs._default_followups(req)
    assert "crops" in fu[0] and "your area" in fu[0]


def test_build_messages_includes_context_and_trims_history():
    history = [ConversationTurn(role="user", content=f"msg {i}") for i in range(8)]
    req = _make_request(conversation_history=history)
    context = {
        "chunks": [{"text": "carrot data", "source": "src", "score": 0.9}],
        "sources": ["src"],
        "score": 0.9,
    }
    msgs = cs._build_messages("system prompt", context, req, "current msg")

    # system + context system + 6 trimmed history + current user = 9
    assert msgs[0]["role"] == "system"
    assert any("Relevant context" in m["content"] for m in msgs)
    assert msgs[-1] == {"role": "user", "content": "current msg"}
    history_msgs = [m for m in msgs if m["content"].startswith("msg ")]
    assert len(history_msgs) == cs._MAX_HISTORY_MESSAGES


def test_build_messages_no_context_chunks():
    req = _make_request()
    context = {"chunks": [], "sources": [], "score": 0.0}
    msgs = cs._build_messages("system", context, req, "hi")
    assert not any("Relevant context" in m["content"] for m in msgs)


# ═══════════════════════════════════════════════════════════════════════════
# prediction_context injection (ChatRequest.prediction_context)
# ═══════════════════════════════════════════════════════════════════════════

_EMPTY_CONTEXT = {"chunks": [], "sources": [], "score": 0.0}

_FULL_PREDICTION = {
    "crop": "Carrot",
    "district": "Badulla",
    "season": "Maha",
    "irrigation": "drip",
    "area_perches": 160.0,
    "area_hectares": 0.4047,
    "predicted_yield_kg_per_ha": 19612.0,
    "average_yield_kg_per_ha": 19961.0,
    "confidence": "high",
    "weather": {
        "rainfall_mm": 45.0,
        "temp_min_c": 12.0,
        "temp_max_c": 22.0,
        "humidity_pct": 78.0,
        "wind_speed_kmh": 12.0,
        "solar_radiation_mj": 16.0,
    },
}


def _prediction_msgs(**overrides):
    """_build_messages output for a request carrying a full prediction."""
    req = _make_request(prediction_context={**_FULL_PREDICTION, **overrides})
    return cs._build_messages("system", _EMPTY_CONTEXT, req, "Explain this prediction")


def test_prediction_context_defaults_to_none():
    assert _make_request().prediction_context is None


def test_build_messages_without_prediction_context_is_unchanged():
    """The additive field must not perturb existing requests at all."""
    req = _make_request()
    baseline = cs._build_messages("system", _EMPTY_CONTEXT, req, "hi")
    assert not any("yield prediction CropSphere just" in m["content"] for m in baseline)

    # Explicitly-null prediction_context produces the identical message list.
    req_null = _make_request(prediction_context=None)
    assert cs._build_messages("system", _EMPTY_CONTEXT, req_null, "hi") == baseline


def test_build_messages_injects_prediction_context():
    msgs = _prediction_msgs()
    block = [m for m in msgs if "yield prediction CropSphere just" in m["content"]]
    assert len(block) == 1
    body = block[0]["content"]
    assert block[0]["role"] == "system"
    assert "Carrot" in body and "Badulla" in body and "Maha" in body
    assert "drip" in body
    assert "19,612 kg/ha" in body
    assert "19,961 kg/ha" in body
    assert "160 perches" in body
    assert "Model confidence: high" in body
    assert "rainfall 45 mm" in body and "humidity 78%" in body


def test_prediction_context_states_the_gap():
    """The model is told not to calculate, so the delta is spelled out."""
    body = next(
        m["content"] for m in _prediction_msgs() if "Difference:" in m["content"]
    )
    assert "2% below the average" in body


def test_prediction_context_gap_above_average():
    body = next(
        m["content"]
        for m in _prediction_msgs(predicted_yield_kg_per_ha=25000.0)
        if "Difference:" in m["content"]
    )
    assert "25% above the average" in body


def test_build_messages_ordering_preserved_with_prediction_context():
    """Prediction context slots between RAG chunks and the formatting rules;
    everything downstream keeps its existing relative order."""
    history = [ConversationTurn(role="user", content="earlier turn")]
    req = _make_request(
        conversation_history=history, prediction_context=_FULL_PREDICTION
    )
    context = {
        "chunks": [{"text": "carrot data", "source": "src", "score": 0.9}],
        "sources": ["src"],
        "score": 0.9,
    }
    msgs = cs._build_messages("system prompt", context, req, "Explain this prediction")

    def idx(needle):
        return next(i for i, m in enumerate(msgs) if needle in m["content"])

    system_i = 0
    rag_i = idx("Relevant context")
    pred_i = idx("yield prediction CropSphere just")
    fmt_i = idx(cs._FORMATTING_RULES[:40])
    hist_i = idx("earlier turn")

    assert system_i < rag_i < pred_i < fmt_i < hist_i
    # Level instruction still sits between the formatting rules and history.
    level_i = next(
        i for i, m in enumerate(msgs) if m["content"] in cs._LEVEL_INSTRUCTIONS.values()
    )
    assert fmt_i < level_i < hist_i
    # The user message is still last, and still only the user's own text.
    assert msgs[-1] == {"role": "user", "content": "Explain this prediction"}


def test_prediction_context_never_touches_the_user_message():
    """chat_analytics.question is `message[:200]` — the injected context must
    stay out of it, or the gap report fills up with prompt boilerplate."""
    msgs = _prediction_msgs()
    user_msgs = [m for m in msgs if m["role"] == "user"]
    assert user_msgs == [{"role": "user", "content": "Explain this prediction"}]
    assert "19,612" not in user_msgs[0]["content"]
    assert "Carrot" not in user_msgs[0]["content"]


def test_format_prediction_context_none_and_empty():
    from app.models.schemas import PredictionContext

    assert cs._format_prediction_context(None) == ""
    # A context with nothing set has nothing worth injecting.
    assert cs._format_prediction_context(PredictionContext()) == ""


def test_analytics_logs_only_the_short_user_message_with_prediction_context():
    """END-TO-END on the analytics record itself, not just _build_messages.

    A starter-chip tap sends a 3-word question with the whole prediction
    riding along in prediction_context. chat_analytics.question must record
    ONLY those 3 words — if the injected block ever leaked into it, the gap
    report and conversation miner would fill with prompt boilerplate instead
    of real farmer phrasing.
    """
    req = _make_request(
        message="Explain this prediction",
        prediction_context=_FULL_PREDICTION,
    )
    with patch.object(cs, "log_chat_interaction") as logged:
        cs._run_analytics(
            req,
            "Explain this prediction",
            "answer",
            "High confidence",
            {"score": 0.7, "sources": ["src"]},
            None,
            120,
        )

    logged.assert_called_once()
    data = logged.call_args[0][0]
    assert data["question"] == "Explain this prediction"

    # Nothing from the prediction block may appear ANYWHERE in the record.
    blob = repr(data)
    for leak in (
        "19,612",
        "19612",
        "19,961",
        "District average yield",
        "yield prediction CropSphere just",
        "Model confidence: high",
        "rainfall 45 mm",
    ):
        assert leak not in blob, f"prediction context leaked into analytics: {leak}"


def test_format_prediction_context_partial_fields():
    """The client sends whatever the prediction produced; missing pieces are
    simply omitted rather than rendered as blanks."""
    from app.models.schemas import PredictionContext

    body = cs._format_prediction_context(
        PredictionContext(crop="Maize", predicted_yield_kg_per_ha=8000.0)
    )
    assert "Maize" in body
    assert "8,000 kg/ha" in body
    assert "District:" not in body
    assert "Difference:" not in body
    assert "Weather used:" not in body


# ═══════════════════════════════════════════════════════════════════════════
# _stream_error_code
# ═══════════════════════════════════════════════════════════════════════════


def test_stream_error_code_partial_is_interrupted():
    assert (
        cs._stream_error_code(Exception("x"), has_partial=True) == "stream_interrupted"
    )


def test_stream_error_code_generic_is_server_error():
    assert cs._stream_error_code(Exception("boom"), has_partial=False) == "server_error"


def test_stream_error_code_rate_limit():
    class _FakeRateLimit(Exception):
        pass

    with patch("groq.RateLimitError", _FakeRateLimit):
        assert (
            cs._stream_error_code(_FakeRateLimit(), has_partial=False) == "rate_limit"
        )


# ═══════════════════════════════════════════════════════════════════════════
# _get_encoder
# ═══════════════════════════════════════════════════════════════════════════


def test_get_encoder_loads_once_and_caches():
    fake_model = MagicMock()
    with patch(
        "sentence_transformers.SentenceTransformer", return_value=fake_model
    ) as mock_st, patch("os.makedirs"):
        first = cs._get_encoder()
        second = cs._get_encoder()
    assert first is second is fake_model
    mock_st.assert_called_once()


# ═══════════════════════════════════════════════════════════════════════════
# _rag_context
# ═══════════════════════════════════════════════════════════════════════════


def test_rag_context_returns_empty_when_rag_missing():
    with patch(
        "app.user.services.chatbot_service.model_loader.get_model",
        return_value=None,
    ):
        assert cs._rag_context("carrot") == {
            "chunks": [],
            "sources": [],
            "score": 0.0,
        }


def test_rag_context_returns_empty_when_no_chunks():
    with patch(
        "app.user.services.chatbot_service.model_loader.get_model",
        return_value={"knowledge_chunks": [], "chunk_embeddings": None},
    ):
        assert cs._rag_context("carrot")["chunks"] == []


def test_rag_context_retrieves_and_boosts_metadata_match():
    chunks = ["carrot chunk A", "carrot chunk B"]
    metadata = [
        {"crop": "Carrot", "district": "Badulla"},
        {"crop": "Carrot", "district": "Nuwara Eliya"},
    ]
    with patch(
        "app.user.services.chatbot_service.model_loader.get_model",
        return_value=_rag_dict(chunks, metadata),
    ), patch(
        "app.user.services.chatbot_service._get_encoder",
        return_value=_fake_encoder(),
    ), patch(
        "sentence_transformers.util.cos_sim",
        return_value=_FakeSims([0.5, 0.55]),
    ):
        # District filter boosts chunk 0 (Badulla) above chunk 1 despite lower raw
        result = cs._rag_context("carrot", district="Badulla", crop="Carrot")

    assert len(result["chunks"]) == 2
    assert result["chunks"][0]["text"] == "carrot chunk A"
    assert result["score"] == pytest.approx(0.55)


def test_rag_context_below_floor_returns_empty_with_best_raw():
    chunks = ["irrelevant chunk"]
    metadata = [{"crop": "Carrot", "district": "Badulla"}]
    with patch(
        "app.user.services.chatbot_service.model_loader.get_model",
        return_value=_rag_dict(chunks, metadata),
    ), patch(
        "app.user.services.chatbot_service._get_encoder",
        return_value=_fake_encoder(),
    ), patch(
        "sentence_transformers.util.cos_sim",
        return_value=_FakeSims([0.10]),
    ):
        result = cs._rag_context("weather on mars")

    assert result["chunks"] == []
    assert result["score"] == pytest.approx(0.10)


def test_rag_context_blends_history_context():
    chunks = ["carrot chunk"]
    metadata = [{"crop": "Carrot", "district": "Badulla"}]
    history = [
        ConversationTurn(role="user", content="carrot in badulla"),
        ConversationTurn(role="assistant", content="Carrots grow well there."),
        ConversationTurn(role="user", content="what about the yield"),
    ]
    with patch(
        "app.user.services.chatbot_service.model_loader.get_model",
        return_value=_rag_dict(chunks, metadata),
    ), patch(
        "app.user.services.chatbot_service._get_encoder",
        return_value=_fake_encoder(),
    ), patch(
        "sentence_transformers.util.cos_sim",
        return_value=_FakeSims([0.7]),
    ):
        result = cs._rag_context("how much can I earn", history=history)

    assert len(result["chunks"]) == 1


def test_rag_context_skips_refused_history_turn():
    chunks = ["carrot chunk"]
    metadata = [{"crop": "Carrot", "district": "Badulla"}]
    history = [
        ConversationTurn(role="user", content="rice price"),
        ConversationTurn(role="assistant", content=cs._OUT_OF_SCOPE_MARKER + " ..."),
    ]
    with patch(
        "app.user.services.chatbot_service.model_loader.get_model",
        return_value=_rag_dict(chunks, metadata),
    ), patch(
        "app.user.services.chatbot_service._get_encoder",
        return_value=_fake_encoder(),
    ), patch(
        "sentence_transformers.util.cos_sim",
        return_value=_FakeSims([0.7]),
    ):
        # The refused 'rice' turn must be skipped -> no history blend path used
        result = cs._rag_context("carrot yield", history=history)

    assert len(result["chunks"]) == 1


def test_rag_context_swallows_encoder_errors():
    chunks = ["carrot chunk"]
    metadata = [{"crop": "Carrot"}]
    encoder = MagicMock()
    encoder.encode.side_effect = RuntimeError("encoder blew up")
    with patch(
        "app.user.services.chatbot_service.model_loader.get_model",
        return_value=_rag_dict(chunks, metadata),
    ), patch(
        "app.user.services.chatbot_service._get_encoder",
        return_value=encoder,
    ):
        result = cs._rag_context("carrot")

    assert result == {"chunks": [], "sources": [], "score": 0.0}


# ═══════════════════════════════════════════════════════════════════════════
# chat
# ═══════════════════════════════════════════════════════════════════════════


def _groq_reply(content):
    """Build a fake non-streaming Groq client returning `content`."""
    client = MagicMock()
    resp = MagicMock()
    resp.choices = [MagicMock()]
    resp.choices[0].message.content = content
    client.chat.completions.create.return_value = resp
    return client


def test_chat_capability_question_short_circuits():
    req = _make_request(message="what crops do you cover?")
    with patch("app.user.services.chatbot_service._safe_audit"), patch(
        "app.user.services.chatbot_service.model_loader.get_model",
        return_value=None,
    ):
        resp = cs.chat(req, SETTINGS)
    assert resp.confidence == "High confidence"
    assert resp.sources_used == []


def test_chat_explicit_miss_short_circuits():
    req = _make_request(message="rice yield in jaffna")
    with patch("app.user.services.chatbot_service._safe_audit"), patch(
        "app.user.services.chatbot_service.model_loader.get_model",
        return_value=None,
    ):
        resp = cs.chat(req, SETTINGS)
    assert resp.confidence == "Out of scope"


def test_chat_grounding_guard_refuses_when_no_chunks():
    req = _make_request()
    with patch("app.user.services.chatbot_service._safe_audit"), patch(
        "app.user.services.chatbot_service.model_loader.get_model",
        return_value=None,
    ), patch(
        "app.user.services.chatbot_service._explicit_miss", return_value=None
    ), patch(
        "app.user.services.chatbot_service._rag_context",
        return_value={"chunks": [], "sources": [], "score": 0.0},
    ):
        resp = cs.chat(req, SETTINGS)
    assert resp.sources_used == []
    assert resp.reply  # a refusal string


def test_chat_happy_path_calls_groq():
    req = _make_request(district="Nuwara Eliya", crop="Carrot")
    context = {
        "chunks": [{"text": "carrot data", "source": "src", "score": 0.9}],
        "sources": ["src"],
        "score": 0.9,
    }
    with patch("app.user.services.chatbot_service._safe_audit"), patch(
        "app.user.services.chatbot_service._explicit_miss", return_value=None
    ), patch(
        "app.user.services.chatbot_service._rag_context", return_value=context
    ), patch(
        "groq.Groq", return_value=_groq_reply("Reasoning: used src.\nCarrots do well.")
    ):
        resp = cs.chat(req, SETTINGS)
    assert "Carrots do well" in resp.reply
    assert resp.sources_used == ["src"]
    assert resp.confidence == "High confidence"


def test_chat_llm_refusal_marker_overrides_confidence():
    req = _make_request()
    context = {
        "chunks": [{"text": "carrot data", "source": "src", "score": 0.9}],
        "sources": ["src"],
        "score": 0.9,
    }
    refusal = cs._OUT_OF_SCOPE_MARKER + " to answer that."
    with patch("app.user.services.chatbot_service._safe_audit"), patch(
        "app.user.services.chatbot_service._explicit_miss", return_value=None
    ), patch(
        "app.user.services.chatbot_service._rag_context", return_value=context
    ), patch(
        "groq.Groq", return_value=_groq_reply(refusal)
    ):
        resp = cs.chat(req, SETTINGS)
    assert resp.confidence == "Out of scope"
    assert resp.sources_used == []


def test_chat_wraps_errors_in_runtime_error():
    req = _make_request()
    context = {
        "chunks": [{"text": "carrot data", "source": "src", "score": 0.9}],
        "sources": ["src"],
        "score": 0.9,
    }
    with patch("app.user.services.chatbot_service._safe_audit"), patch(
        "app.user.services.chatbot_service._explicit_miss", return_value=None
    ), patch(
        "app.user.services.chatbot_service._rag_context", return_value=context
    ), patch(
        "groq.Groq", side_effect=RuntimeError("groq down")
    ):
        with pytest.raises(RuntimeError):
            cs.chat(req, SETTINGS)


# ═══════════════════════════════════════════════════════════════════════════
# chat_stream
# ═══════════════════════════════════════════════════════════════════════════


def _groq_stream(deltas):
    """Build a fake streaming Groq client yielding the given text deltas."""
    client = MagicMock()

    def _make_chunk(text):
        chunk = MagicMock()
        chunk.choices = [MagicMock()]
        chunk.choices[0].delta.content = text
        return chunk

    client.chat.completions.create.return_value = [_make_chunk(d) for d in deltas]
    return client


def test_chat_stream_capability_question():
    req = _make_request(message="what crops do you cover?")
    with patch("app.user.services.chatbot_service._safe_audit"), patch(
        "app.user.services.chatbot_service.model_loader.get_model",
        return_value=None,
    ), patch(
        "app.user.services.chat_history_service.persist_chat_turn",
        return_value="conv-1",
    ):
        events = list(cs.chat_stream(req, SETTINGS, "uid-1"))
    assert events[0]["type"] == "text"
    assert events[-1]["type"] == "metadata"
    assert events[-1]["confidence"] == "High confidence"


def test_chat_stream_explicit_miss():
    req = _make_request(message="rice yield in jaffna")
    with patch("app.user.services.chatbot_service._safe_audit"), patch(
        "app.user.services.chatbot_service.model_loader.get_model",
        return_value=None,
    ), patch(
        "app.user.services.chat_history_service.persist_chat_turn",
        return_value="conv-1",
    ):
        events = list(cs.chat_stream(req, SETTINGS, "uid-1"))
    assert events[-1]["confidence"] == "Out of scope"


def test_chat_stream_grounding_refusal():
    req = _make_request()
    with patch("app.user.services.chatbot_service._safe_audit"), patch(
        "app.user.services.chatbot_service._explicit_miss", return_value=None
    ), patch(
        "app.user.services.chatbot_service._rag_context",
        return_value={"chunks": [], "sources": [], "score": 0.0},
    ), patch(
        "app.user.services.chatbot_service.model_loader.get_model",
        return_value=None,
    ), patch(
        "app.user.services.chat_history_service.persist_chat_turn",
        return_value="conv-1",
    ):
        events = list(cs.chat_stream(req, SETTINGS, "uid-1"))
    assert events[0]["type"] == "text"
    assert events[-1]["type"] == "metadata"


def test_chat_stream_happy_path_streams_text():
    req = _make_request()
    context = {
        "chunks": [{"text": "carrot data", "source": "src", "score": 0.9}],
        "sources": ["src"],
        "score": 0.9,
    }
    with patch("app.user.services.chatbot_service._safe_audit"), patch(
        "app.user.services.chatbot_service._explicit_miss", return_value=None
    ), patch(
        "app.user.services.chatbot_service._rag_context", return_value=context
    ), patch(
        "groq.Groq", return_value=_groq_stream(["Carrots ", "grow ", "well."])
    ), patch(
        "app.user.services.chat_history_service.persist_chat_turn",
        return_value="conv-9",
    ):
        events = list(cs.chat_stream(req, SETTINGS, "uid-1"))
    text = "".join(e["content"] for e in events if e["type"] == "text")
    assert text == "Carrots grow well."
    assert events[-1]["conversation_id"] == "conv-9"


def test_chat_stream_error_event_on_groq_failure():
    req = _make_request()
    context = {
        "chunks": [{"text": "carrot data", "source": "src", "score": 0.9}],
        "sources": ["src"],
        "score": 0.9,
    }
    with patch("app.user.services.chatbot_service._safe_audit"), patch(
        "app.user.services.chatbot_service._explicit_miss", return_value=None
    ), patch(
        "app.user.services.chatbot_service._rag_context", return_value=context
    ), patch(
        "groq.Groq", side_effect=RuntimeError("groq exploded")
    ):
        events = list(cs.chat_stream(req, SETTINGS, "uid-1"))
    assert events[-1]["type"] == "error"
    assert events[-1]["code"] == "server_error"


def test_chat_stream_empty_response_event():
    req = _make_request()
    context = {
        "chunks": [{"text": "carrot data", "source": "src", "score": 0.9}],
        "sources": ["src"],
        "score": 0.9,
    }
    with patch("app.user.services.chatbot_service._safe_audit"), patch(
        "app.user.services.chatbot_service._explicit_miss", return_value=None
    ), patch(
        "app.user.services.chatbot_service._rag_context", return_value=context
    ), patch(
        "groq.Groq", return_value=_groq_stream(["", None])
    ):
        events = list(cs.chat_stream(req, SETTINGS, "uid-1"))
    assert events[-1]["type"] == "error"
    assert events[-1]["code"] == "empty_response"


def test_chat_stream_llm_refusal_marker_overrides():
    req = _make_request()
    context = {
        "chunks": [{"text": "carrot data", "source": "src", "score": 0.9}],
        "sources": ["src"],
        "score": 0.9,
    }
    refusal = cs._OUT_OF_SCOPE_MARKER + " right now."
    with patch("app.user.services.chatbot_service._safe_audit"), patch(
        "app.user.services.chatbot_service._explicit_miss", return_value=None
    ), patch(
        "app.user.services.chatbot_service._rag_context", return_value=context
    ), patch(
        "groq.Groq", return_value=_groq_stream([refusal])
    ), patch(
        "app.user.services.chat_history_service.persist_chat_turn",
        return_value="conv-3",
    ):
        events = list(cs.chat_stream(req, SETTINGS, "uid-1"))
    meta = events[-1]
    assert meta["confidence"] == "Out of scope"
    assert meta["sources"] == []


def test_chat_stream_persistence_failure_is_swallowed():
    req = _make_request(message="what crops do you cover?")
    with patch("app.user.services.chatbot_service._safe_audit"), patch(
        "app.user.services.chatbot_service.model_loader.get_model",
        return_value=None,
    ), patch(
        "app.user.services.chat_history_service.persist_chat_turn",
        side_effect=RuntimeError("firestore down"),
    ):
        events = list(cs.chat_stream(req, SETTINGS, "uid-1"))
    # conv_id falls back to "" but stream still completes with metadata
    assert events[-1]["type"] == "metadata"
    assert events[-1]["conversation_id"] == ""


# ═══════════════════════════════════════════════════════════════════════════
# _detect_knowledge_level
# ═══════════════════════════════════════════════════════════════════════════


def test_detect_level_beginner_short_definition_first_message():
    assert cs._detect_knowledge_level("what is yield?", []) == "beginner"


def test_detect_level_advanced_comparison_technical():
    msg = "compare inter-season yields across upcountry districts for Maha"
    assert cs._detect_knowledge_level(msg, []) == "advanced"


def test_detect_level_intermediate_default():
    msg = "How much carrot yield can I expect in Nuwara Eliya?"
    assert cs._detect_knowledge_level(msg, []) == "intermediate"


def test_detect_level_never_downgrades_advanced_to_beginner():
    history = [
        ConversationTurn(
            role="user",
            content="compare inter-season farmgate prices, Maha vs Yala, per-hectare",
        ),
        ConversationTurn(role="assistant", content="Reasoning: ..."),
    ]
    # A bare beginner-style follow-up must not drop an expert to "beginner".
    assert cs._detect_knowledge_level("what is yield?", history) == "intermediate"


def test_detect_level_stabilises_to_advanced_after_consistent_history():
    history = [
        ConversationTurn(
            role="user", content="compare Maha vs Yala yields per-hectare"
        ),
        ConversationTurn(role="assistant", content="Reasoning: ..."),
        ConversationTurn(
            role="user", content="difference between farmgate and retail, kg/ha"
        ),
        ConversationTurn(role="assistant", content="Reasoning: ..."),
    ]
    # Ambiguous follow-up ("what about maize") stabilises up, not back to mid.
    assert cs._detect_knowledge_level("what about maize", history) == "advanced"


def test_build_messages_injects_level_instruction():
    req = _make_request(message="what is yield?", conversation_history=[])
    context = {"chunks": [], "sources": [], "score": 0.0}
    msgs = cs._build_messages("system", context, req, "what is yield?")
    assert any(m["content"] == cs._LEVEL_INSTRUCTIONS["beginner"] for m in msgs)


# ═══════════════════════════════════════════════════════════════════════════
# Saved-context confirmation
# ═══════════════════════════════════════════════════════════════════════════

_CTX_CAPS = {
    "crops": ["Carrot", "Maize", "Green gram", "Cowpea", "Finger millet", "Groundnut"],
    "districts": [
        "Nuwara Eliya",
        "Badulla",
        "Anuradhapura",
        "Monaragala",
        "Ampara",
        "Hambantota",
        "Batticaloa",
        "Jaffna",
    ],
    "crop_districts": {},
    "district_crops": {},
}


def test_extract_context_terms_finds_covered():
    with patch.object(cs, "_dataset_capabilities", return_value=_CTX_CAPS):
        assert cs._extract_context_terms("i grow carrot in badulla") == (
            "Carrot",
            "Badulla",
        )
        assert cs._extract_context_terms("hello there") == (None, None)


def test_confirm_when_message_crop_and_saved_district():
    req = _make_request(message="i want to plant carrot", conversation_history=[])
    with patch.object(cs, "_dataset_capabilities", return_value=_CTX_CAPS):
        assert (
            cs._should_confirm_saved_context(
                req, "i want to plant carrot", None, "Jaffna"
            )
            is True
        )
        reply, chips = cs._build_context_confirmation(
            req, "i want to plant carrot", None, "Jaffna"
        )
    assert "Carrot in Jaffna" in reply
    assert chips[0] == "Carrot in Jaffna"


def test_no_confirm_when_fully_specified():
    req = _make_request(message="carrot yield in badulla", conversation_history=[])
    with patch.object(cs, "_dataset_capabilities", return_value=_CTX_CAPS):
        # Message names both crop and district — nothing for saved context to fill.
        assert (
            cs._should_confirm_saved_context(
                req, "carrot yield in badulla", "Maize", "Jaffna"
            )
            is False
        )


def test_no_confirm_without_saved_context():
    req = _make_request(message="i want to plant carrot", conversation_history=[])
    with patch.object(cs, "_dataset_capabilities", return_value=_CTX_CAPS):
        assert (
            cs._should_confirm_saved_context(req, "i want to plant carrot", None, None)
            is False
        )


def test_dropdown_district_wins_over_saved():
    req = _make_request(
        message="i want to plant carrot",
        district=DistrictEnum("Badulla"),
        conversation_history=[],
    )
    with patch.object(cs, "_dataset_capabilities", return_value=_CTX_CAPS):
        # Dropdown already supplies the district → saved district must not fill it.
        assert (
            cs._should_confirm_saved_context(
                req, "i want to plant carrot", None, "Jaffna"
            )
            is False
        )


def test_no_confirm_on_non_agricultural_message():
    req = _make_request(message="hello", conversation_history=[])
    with patch.object(cs, "_dataset_capabilities", return_value=_CTX_CAPS):
        assert (
            cs._should_confirm_saved_context(req, "hello", "Carrot", "Jaffna") is False
        )


# ═══════════════════════════════════════════════════════════════════════════
# few-shot examples (loader + injection)
# ═══════════════════════════════════════════════════════════════════════════


def test_load_fewshot_examples_missing_file_returns_empty(tmp_path):
    cs._fewshot_examples = None
    with patch(
        "app.user.services.fewshot_service.FEWSHOT_PATH", tmp_path / "nope.json"
    ):
        assert cs._load_fewshot_examples() == {}
    cs._fewshot_examples = None


def test_load_fewshot_examples_reads_and_caches(tmp_path):
    f = tmp_path / "fewshot.json"
    f.write_text('{"examples": {"yield": [{"question": "q", "answer": "a"}]}}')
    cs._fewshot_examples = None
    with patch("app.user.services.fewshot_service.FEWSHOT_PATH", f):
        out = cs._load_fewshot_examples()
    assert out["examples"]["yield"][0]["question"] == "q"
    cs._fewshot_examples = None


def test_build_messages_injects_matching_fewshot():
    req = _make_request(message="carrot yield in Badulla", conversation_history=[])
    context = {"chunks": [], "sources": [], "score": 0.0}
    fake = {
        "examples": {
            "yield": [
                {
                    "question": "carrot yield in Badulla",
                    "answer": "harvest is 19,517 kg/ha",
                }
            ]
        }
    }
    with patch.object(cs, "_load_fewshot_examples", return_value=fake):
        msgs = cs._build_messages("sys", context, req, "carrot yield in Badulla")
    injected = [
        m["content"] for m in msgs if m["content"].startswith("Here are examples")
    ]
    assert injected and "harvest is 19,517 kg/ha" in injected[0]


def test_build_messages_no_fewshot_when_type_absent():
    req = _make_request(message="what soil is best?", conversation_history=[])
    context = {"chunks": [], "sources": [], "score": 0.0}
    # examples only for 'yield'; a 'general' question gets nothing injected.
    fake = {"examples": {"yield": [{"question": "q", "answer": "a"}]}}
    with patch.object(cs, "_load_fewshot_examples", return_value=fake):
        msgs = cs._build_messages("sys", context, req, "what soil is best?")
    assert not any(m["content"].startswith("Here are examples") for m in msgs)


# ═══════════════════════════════════════════════════════════════════════════
# reformulation detection ("simplify" family)
# ═══════════════════════════════════════════════════════════════════════════
@pytest.mark.parametrize(
    "message",
    [
        "simply explain",
        "simplify the answer",
        "simply",
        "explain simply",
        "tell me simply",
        "say simply",
        "put it simply",
        "say it simpler",
        "explain it simply",
    ],
)
def test_is_reformulation_request_detects_simplify_family(message):
    assert cs._is_reformulation_request(message) is True


@pytest.mark.parametrize(
    "message",
    [
        # "simply" as an adverb inside a real question — must reach retrieval.
        "which crop simply grows best in Badulla",
        "what is the yield for carrots in Badulla",
        "best season for carrot in Nuwara Eliya",
        "how much can I earn from 2 acres",
    ],
)
def test_is_reformulation_request_ignores_real_questions(message):
    assert cs._is_reformulation_request(message) is False


def test_bare_simply_guarded_by_message_length():
    """Bare "simply" only counts in a message short enough to be nothing but
    the request — the length guard is what keeps the adverb usage out."""
    assert cs._is_reformulation_request("simply") is True
    assert len("simply") < cs._BARE_SIMPLY_MAX_LEN
    long_msg = "simply " + "x" * cs._BARE_SIMPLY_MAX_LEN
    assert cs._is_reformulation_request(long_msg) is False


def test_simplify_family_classified_as_simplify_not_math():
    for m in ("simply", "simply explain", "put it simply"):
        assert cs._reformulation_type(m) == "simplify"


# ═══════════════════════════════════════════════════════════════════════════
# reformulation message assembly (instruction vs. formatting-rule ordering)
# ═══════════════════════════════════════════════════════════════════════════
def _reform_msgs(rtype):
    req = _make_request(message="simply", conversation_history=[])
    return cs._build_reformulation_messages("SYS", "PREV", req, "simply", rtype)


def test_simplify_instruction_comes_after_formatting_rules():
    """Simplify must contradict Part B (three sections, all units, earnings
    offer), so it has to be the LAST system message to win."""
    msgs = _reform_msgs("simplify")
    systems = [m["content"] for m in msgs if m["role"] == "system"]
    assert systems[-1].startswith("The user wants a much simpler")
    rules_at = next(
        i for i, s in enumerate(systems) if s.startswith("FORMATTING RULES")
    )
    assert rules_at < len(systems) - 1


@pytest.mark.parametrize("rtype", ["math", "formal_math"])
def test_math_instructions_keep_original_ordering(rtype):
    """Math rules don't conflict with Part B — their position is unchanged."""
    msgs = _reform_msgs(rtype)
    systems = [m["content"] for m in msgs if m["role"] == "system"]
    assert systems[-1].startswith("FORMATTING RULES")


def test_simplify_instruction_names_the_rules_it_overrides():
    systems = [m["content"] for m in _reform_msgs("simplify") if m["role"] == "system"]
    instruction = systems[-1]
    assert "OVERRIDE" in instruction
    for dropped in ("three-section", "show-all-three-units", "earnings offer"):
        assert dropped in instruction
    assert "always use acres" in instruction
    assert "PREV" in instruction  # previous answer is carried in


def test_simplify_instruction_offers_varied_styles():
    """A single example acts as a template — the model copies its shape.
    Four styles plus an anti-default nudge is what breaks the flat pattern."""
    systems = [m["content"] for m in _reform_msgs("simplify") if m["role"] == "system"]
    instruction = systems[-1]
    for style in ("Style 1", "Style 2", "Style 3", "Style 4"):
        assert style in instruction
    assert "Do not default to Style 1" in instruction
    # the old single flat example must not come back
    assert "Yala season is the best time to plant" not in instruction
    # "Before:" stays — it shows what to strip out
    assert "Before:" in instruction


def test_simplify_instruction_guards_against_false_encouragement():
    systems = [m["content"] for m in _reform_msgs("simplify") if m["role"] == "system"]
    assert "never call a poor yield good news" in systems[-1]


def test_simplify_instruction_states_sentence_cap_once():
    """Two copies of the limit would make the model over-weight it."""
    systems = [m["content"] for m in _reform_msgs("simplify") if m["role"] == "system"]
    assert systems[-1].count("2-3") == 1


# ═══════════════════════════════════════════════════════════════════════════
# prompt tuning injection into _build_messages
# ═══════════════════════════════════════════════════════════════════════════
def test_prompt_tuning_injected_after_fewshot_before_history():
    req = _make_request(message="carrot yield in Badulla", conversation_history=[])
    context = {"chunks": [], "sources": [], "score": 0.0}
    tuning = {
        "active": [
            {
                "id": "language_complexity",
                "instruction": "Keep it simple.",
                "status": "trial",
            },
            {
                "id": "chip_high",
                "instruction": "Lead into the suggestions.",
                "status": "permanent",
            },
        ]
    }
    with patch.object(cs, "_load_fewshot_examples", return_value={}), patch.object(
        cs, "_load_prompt_tuning", return_value=tuning
    ):
        msgs = cs._build_messages("sys", context, req, "carrot yield in Badulla")
    tuned = [
        m["content"] for m in msgs if m["content"].startswith("SYSTEM ADJUSTMENTS")
    ]
    assert tuned, "tuning message not injected"
    assert "- Keep it simple." in tuned[0]
    assert "- Lead into the suggestions." in tuned[0]
    # must sit before the current user message (i.e. among the system messages)
    assert msgs[-1]["role"] == "user"
    assert msgs.index({"role": "system", "content": tuned[0]}) < len(msgs) - 1


def test_no_prompt_tuning_message_when_empty():
    req = _make_request(message="carrot yield in Badulla", conversation_history=[])
    context = {"chunks": [], "sources": [], "score": 0.0}
    with patch.object(cs, "_load_fewshot_examples", return_value={}), patch.object(
        cs, "_load_prompt_tuning", return_value={"active": []}
    ):
        msgs = cs._build_messages("sys", context, req, "carrot yield in Badulla")
    assert not any(m["content"].startswith("SYSTEM ADJUSTMENTS") for m in msgs)


def test_format_prompt_tuning_injection_skips_malformed():
    tuning = {
        "active": [
            {"id": "ok", "instruction": "Good one.", "status": "trial"},
            {"id": "bad", "status": "trial"},  # no instruction
            "not-a-dict",  # wrong type
            {"id": "bad2", "instruction": 123, "status": "trial"},  # non-string
        ]
    }
    with patch.object(cs, "_load_prompt_tuning", return_value=tuning):
        out = cs._format_prompt_tuning_injection()
    assert out == "SYSTEM ADJUSTMENTS (based on recent usage patterns):\n- Good one."


def test_format_prompt_tuning_injection_skips_non_live_statuses():
    """Only trial + permanent reach the prompt — anything auto-removed or
    otherwise not live must be invisible to the chatbot."""
    tuning = {
        "active": [
            {"id": "live", "instruction": "Live one.", "status": "permanent"},
            {"id": "gone", "instruction": "Removed one.", "status": "auto_removed"},
            {"id": "nostatus", "instruction": "No status."},
        ]
    }
    with patch.object(cs, "_load_prompt_tuning", return_value=tuning):
        out = cs._format_prompt_tuning_injection()
    assert "Live one." in out
    assert "Removed one." not in out
    assert "No status." not in out


# ═══════════════════════════════════════════════════════════════════════════
# Follow-up continuation — _looks_like_followup / _is_followup /
# _followup_context / _reformulate_query / _retrieval_query
# ═══════════════════════════════════════════════════════════════════════════


@pytest.fixture
def _caps(monkeypatch):
    """Pin the dataset capabilities so follow-up detection doesn't depend on
    whether rag_artifacts is loaded in this environment."""
    monkeypatch.setattr(cs, "_capabilities_cache", _enum_caps())
    return _enum_caps()


REFUSAL_REPLY = cs._OUT_OF_SCOPE_REPLY
ANSWER_REPLY = (
    "Reasoning: CropSphere data for Carrot in Badulla, Inter season.\n\n"
    "You can expect around 20,169 kg from one hectare."
)


def _turns(*pairs):
    return [ConversationTurn(role=r, content=c) for r, c in pairs]


@pytest.mark.parametrize(
    "message",
    [
        "yes",
        "Yes!",
        "yes explain",
        "sure",
        "ok",
        "tell me more",
        "go on",
        "continue",
        "yes please",
        "explain that",
        "show me",
        "what about that?",
        "how does it work?",
        "why is that?",
        "can you explain it?",
        "why?",
        "and the price?",
        "what about weather?",
        "for Maize?",
    ],
)
def test_looks_like_followup_true(_caps, message):
    assert cs._looks_like_followup(message) is True


@pytest.mark.parametrize(
    "message",
    [
        "What is the best planting season for Maize in Jaffna?",
        "Cowpea price in Ampara",
        "how much can I earn from 2 acres of groundnut",
        "what crops do you cover?",
        "Compare carrot yield in Badulla with Nuwara Eliya for the Maha season",
        "",
    ],
)
def test_looks_like_followup_false(_caps, message):
    assert cs._looks_like_followup(message) is False


def test_is_followup_needs_a_previous_assistant_turn(_caps):
    """A follow-up shape on the conversation's first turn is just a vague
    question — there is nothing to continue."""
    assert cs._is_followup("yes explain", []) is False
    assert cs._is_followup("yes explain", _turns(("user", "how to test soil"))) is False
    history = _turns(("user", "how to test soil"), ("assistant", ANSWER_REPLY))
    assert cs._is_followup("yes explain", history) is True


def test_followup_context_reads_topic_from_last_exchange(_caps):
    history = _turns(("user", "how to test soil"), ("assistant", ANSWER_REPLY))
    question, crop, district = cs._followup_context(history)
    assert question == "how to test soil"
    assert (crop, district) == ("Carrot", "Badulla")


def test_followup_context_skips_refused_turn_and_reaches_back(_caps):
    """The repeated-out-of-scope case: the refused turn must not become the
    topic, so the walk continues to the question that actually worked."""
    history = _turns(
        ("user", "carrot yield in Badulla"),
        ("assistant", ANSWER_REPLY),
        ("user", "what about the moon"),
        ("assistant", REFUSAL_REPLY),
    )
    question, crop, district = cs._followup_context(history)
    assert question == "carrot yield in Badulla"
    assert (crop, district) == ("Carrot", "Badulla")


def test_followup_context_skips_earlier_followups(_caps):
    """ "yes explain" is not a topic — the walk keeps going past it."""
    history = _turns(
        ("user", "how to test soil"),
        ("assistant", ANSWER_REPLY),
        ("user", "yes explain"),
        ("assistant", "Reasoning: more soil detail.\n\nUse a pH kit."),
    )
    assert cs._followup_context(history)[0] == "how to test soil"


def test_followup_context_newest_topic_wins(_caps):
    """A mid-conversation topic switch must not be overridden by the older
    question underneath it."""
    history = _turns(
        ("user", "Maize in Jaffna"),
        ("assistant", "Reasoning: CropSphere data for Maize in Jaffna."),
        ("user", "and Cowpea?"),
        ("assistant", "Reasoning: CropSphere data for Cowpea in Jaffna."),
    )
    _question, crop, district = cs._followup_context(history)
    assert (crop, district) == ("Cowpea", "Jaffna")


def test_followup_context_empty_history(_caps):
    assert cs._followup_context([]) == ("", None, None)


def test_reformulate_query_prepends_topic(_caps):
    """The bug: "yes explain" alone matches no chunk. It must carry the
    previous question and its crop/district into retrieval."""
    history = _turns(("user", "how to test soil"), ("assistant", ANSWER_REPLY))
    query = cs._reformulate_query("yes explain", history)
    assert query.startswith("how to test soil")
    assert "Carrot" in query and "Badulla" in query
    assert query.endswith("yes explain")


def test_reformulate_query_partial_followup_keeps_previous_topic(_caps):
    history = _turns(
        ("user", "best crop for Nuwara Eliya"),
        ("assistant", "Reasoning: CropSphere data for Carrot in Nuwara Eliya."),
    )
    query = cs._reformulate_query("what about price?", history)
    assert "Nuwara Eliya" in query
    assert "Carrot" in query
    assert query.endswith("what about price?")


def test_reformulate_query_own_crop_replaces_inherited_one(_caps):
    """ "and Cowpea?" after a Maize answer must retrieve Cowpea — the inherited
    crop is dropped from the carried-over question, not stacked on top of it."""
    history = _turns(
        ("user", "tell me about Maize"),
        ("assistant", "Reasoning: CropSphere data for Maize in Anuradhapura."),
    )
    query = cs._reformulate_query("and Cowpea?", history)
    assert "Maize" not in query
    assert "Cowpea" in query
    assert "Anuradhapura" in query


def test_reformulate_query_leaves_real_questions_alone(_caps):
    history = _turns(("user", "how to test soil"), ("assistant", ANSWER_REPLY))
    msg = "What is the best planting season for Maize in Jaffna?"
    assert cs._reformulate_query(msg, history) == msg


def test_reformulate_query_without_topic_returns_message(_caps):
    """Nothing topical in history (only a refusal) — leave the query alone
    rather than prepending noise."""
    history = _turns(("user", "weather on Mars"), ("assistant", REFUSAL_REPLY))
    assert cs._reformulate_query("yes explain", history) == "yes explain"


def test_reformulate_query_caps_the_inherited_topic(_caps):
    """A long previous question must not swamp the follow-up's own wording in
    the blended embedding."""
    long_question = ("carrot yield in Badulla " * 20)[:480]
    history = _turns(("user", long_question), ("assistant", ANSWER_REPLY))
    query = cs._reformulate_query("yes explain", history)
    assert len(query) <= cs._MAX_LEN
    assert len(query) < len(long_question)
    assert query.endswith("yes explain")


def test_retrieval_query_unit_reply_still_wins(_caps):
    """A bare land-unit reply keeps its own (more specific) expansion — the
    follow-up rebuild must not shadow _expand_clarifying_reply."""
    history = _turns(
        ("user", "carrot yield in Badulla"),
        (
            "assistant",
            "Would you like me to work out how much you could earn? "
            "Just tell me your land size in acres or perches.",
        ),
    )
    assert cs._retrieval_query("2 acres", history) == "carrot yield in Badulla 2 acres"


def test_retrieval_query_falls_through_to_followup_rebuild(_caps):
    history = _turns(("user", "how to test soil"), ("assistant", ANSWER_REPLY))
    assert cs._retrieval_query("yes explain", history) != "yes explain"


# ═══════════════════════════════════════════════════════════════════════════
# Repeated "Out of scope" loop
# ═══════════════════════════════════════════════════════════════════════════


def test_should_retry_after_refusal_only_after_a_refusal(_caps):
    answered = _turns(("user", "carrot yield in Badulla"), ("assistant", ANSWER_REPLY))
    refused = _turns(("user", "weather on Mars"), ("assistant", REFUSAL_REPLY))
    assert cs._should_retry_after_refusal("yes explain", answered) is False
    assert cs._should_retry_after_refusal("yes explain", refused) is True


def test_should_retry_after_refusal_covers_agricultural_rephrase(_caps):
    """Not only follow-up shapes — a farming question asked again in different
    words must not hit the same refusal twice. "Farming" here is
    _has_agricultural_intent's existing definition, unchanged by this path."""
    refused = _turns(("user", "what should I plant"), ("assistant", REFUSAL_REPLY))
    assert cs._should_retry_after_refusal("which crop grows best?", refused) is True


def test_should_retry_after_refusal_ignores_unrelated_questions(_caps):
    """Junk still gets refused, twice if asked twice — the grounding guard is
    the primary defence and must not be talked out of it."""
    refused = _turns(("user", "weather on Mars"), ("assistant", REFUSAL_REPLY))
    assert cs._should_retry_after_refusal("tell me a joke", refused) is False


def test_chat_does_not_repeat_out_of_scope_for_followup(_caps):
    """End to end: after a refusal, another short follow-up that still
    retrieves nothing gets a clarifying question, not a second refusal."""
    history = _turns(
        ("user", "carrot yield in Badulla"),
        ("assistant", ANSWER_REPLY),
        ("user", "what about the moon"),
        ("assistant", REFUSAL_REPLY),
    )
    req = _make_request(message="yes explain", conversation_history=history)
    with patch("app.user.services.chatbot_service._safe_audit"), patch(
        "app.user.services.chatbot_service._explicit_miss", return_value=None
    ), patch(
        "app.user.services.chatbot_service._rag_context",
        return_value={"chunks": [], "sources": [], "score": 0.0},
    ):
        resp = cs.chat(req, SETTINGS)
    assert resp.confidence != "Out of scope"
    assert cs._OUT_OF_SCOPE_MARKER not in resp.reply
    assert cs._CLARIFICATION_MARKER in resp.reply


def test_chat_still_refuses_unrelated_question_after_refusal(_caps):
    history = _turns(
        ("user", "weather on Mars"),
        ("assistant", REFUSAL_REPLY),
    )
    req = _make_request(message="tell me a joke", conversation_history=history)
    with patch("app.user.services.chatbot_service._safe_audit"), patch(
        "app.user.services.chatbot_service._explicit_miss", return_value=None
    ), patch(
        "app.user.services.chatbot_service._rag_context",
        return_value={"chunks": [], "sources": [], "score": 0.0},
    ):
        resp = cs.chat(req, SETTINGS)
    assert resp.confidence == "Out of scope"


def test_chat_retrieves_with_the_reformulated_query(_caps):
    """The rebuilt query goes to retrieval; the ORIGINAL message is what
    reaches Groq."""
    history = _turns(("user", "how to test soil"), ("assistant", ANSWER_REPLY))
    req = _make_request(message="yes explain", conversation_history=history)
    context = {
        "chunks": [{"text": "soil data", "source": "src", "score": 0.9}],
        "sources": ["src"],
        "score": 0.9,
    }
    groq = _groq_reply("Reasoning: used src.\n\nHere is more on soil testing.")
    with patch("app.user.services.chatbot_service._safe_audit"), patch(
        "app.user.services.chatbot_service._explicit_miss", return_value=None
    ), patch(
        "app.user.services.chatbot_service._rag_context", return_value=context
    ) as mock_rag, patch(
        "groq.Groq", return_value=groq
    ):
        resp = cs.chat(req, SETTINGS)
    assert "how to test soil" in mock_rag.call_args.args[0]
    sent = groq.chat.completions.create.call_args.kwargs["messages"]
    assert sent[-1] == {"role": "user", "content": "yes explain"}
    assert resp.confidence == "High confidence"


def test_chat_stream_does_not_repeat_out_of_scope_for_followup(_caps):
    history = _turns(
        ("user", "carrot yield in Badulla"),
        ("assistant", ANSWER_REPLY),
        ("user", "what about the moon"),
        ("assistant", REFUSAL_REPLY),
    )
    req = _make_request(message="yes explain", conversation_history=history)
    with patch("app.user.services.chatbot_service._safe_audit"), patch(
        "app.user.services.chatbot_service._explicit_miss", return_value=None
    ), patch(
        "app.user.services.chatbot_service._rag_context",
        return_value={"chunks": [], "sources": [], "score": 0.0},
    ), patch(
        "app.user.services.chat_history_service.persist_chat_turn",
        return_value="conv-1",
    ):
        events = list(cs.chat_stream(req, SETTINGS, "uid-1"))
    text = "".join(e["content"] for e in events if e["type"] == "text")
    meta = next(e for e in events if e["type"] == "metadata")
    assert cs._OUT_OF_SCOPE_MARKER not in text
    assert meta["confidence"] == "Moderate confidence"


# ═══════════════════════════════════════════════════════════════════════════
# Follow-ups are not "vague" or "ambiguous" — the topic is already known
# ═══════════════════════════════════════════════════════════════════════════


def test_vague_query_check_skips_resolved_followup(_caps):
    """ "what about price?" names no crop or district, but the previous turn
    did — asking the farmer to repeat it would be a worse answer."""
    history = _turns(("user", "carrot yield in Badulla"), ("assistant", ANSWER_REPLY))
    context = {"chunks": [], "sources": [], "score": 0.4}
    assert (
        cs._is_vague_agricultural_query("what about price?", context, history) is False
    )
    assert cs._is_vague_agricultural_query("what about price?", context, []) is True


def test_ambiguous_query_check_skips_resolved_followup(_caps):
    history = _turns(("user", "carrot yield in Badulla"), ("assistant", ANSWER_REPLY))
    context = {
        "chunks": [
            {"crop": "Carrot", "district": "Badulla"},
            {"crop": "Maize", "district": "Jaffna"},
        ],
        "sources": [],
        "score": 0.4,
    }
    assert cs._is_ambiguous_query("what about price?", context, history) is False
    assert cs._is_ambiguous_query("what about price?", context, []) is True


def test_system_prompt_tells_llama_to_continue_followups():
    prompt = cs._system_prompt(_make_request())
    assert "short follow-up" in prompt
    assert "continue explaining the topic from your previous response" in prompt


# ═══════════════════════════════════════════════════════════════════════════
# LLM-generated follow-up chips
# ═══════════════════════════════════════════════════════════════════════════


def test_parse_followups_strips_marker_lines_from_the_reply():
    raw = (
        "Reasoning: CropSphere data.\n\nYou can expect 20,169 kg.\n\n"
        "FOLLOWUP: Prevention methods for carrot pests\n"
        "FOLLOWUP: How do these pests spread\n"
        "FOLLOWUP: More about carrot diseases"
    )
    clean, followups = cs._parse_followups_from_response(raw)
    assert "FOLLOWUP" not in clean
    assert clean.endswith("20,169 kg.")
    assert followups == [
        "Prevention methods for carrot pests",
        "How do these pests spread",
        "More about carrot diseases",
    ]


def test_parse_followups_returns_reply_unchanged_when_none_present():
    reply = "Just an answer with no suggestions."
    assert cs._parse_followups_from_response(reply) == (reply, [])


def test_parse_followups_caps_at_three_but_still_strips_extras():
    raw = "Answer.\n" + "\n".join(f"FOLLOWUP: q{i}" for i in range(6))
    clean, followups = cs._parse_followups_from_response(raw)
    assert len(followups) == 3
    assert "FOLLOWUP" not in clean  # surplus lines never reach the farmer


def test_parse_followups_drops_blank_and_overlong_suggestions():
    raw = "Answer.\nFOLLOWUP:   \nFOLLOWUP: " + ("x" * 200) + "\nFOLLOWUP: fine one"
    clean, followups = cs._parse_followups_from_response(raw)
    assert followups == ["fine one"]
    assert "FOLLOWUP" not in clean


def test_parse_followups_handles_empty_reply():
    assert cs._parse_followups_from_response("") == ("", [])


# ── Bot-question detection ────────────────────────────────────────────────────


def test_earnings_offer_is_not_treated_as_a_bot_question():
    """The earnings offer is a soft suggestion — contextual chips must win."""
    reply = (
        "You can expect around 20,169 kg per hectare.\n\n"
        "Would you like me to work out how much you could earn? "
        "Just tell me your land size in acres or perches."
    )
    assert cs._extract_bot_question_options(reply) is None


def test_unit_clarification_yields_every_option():
    reply = "Thanks!\n\nIs that 3 acres, 3 hectares, or 3 perches?"
    assert cs._extract_bot_question_options(reply) == [
        "3 acres",
        "3 hectares",
        "3 perches",
    ]


def test_crop_selection_question_drops_the_lead_in():
    reply = (
        "Happy to help.\n\nWhich crop are you asking about — Carrot, Maize, or Cowpea?"
    )
    assert cs._extract_bot_question_options(reply) == ["Carrot", "Maize", "Cowpea"]


def test_bulleted_options_become_chips():
    reply = (
        "I can cover these:\n\n- Carrot\n- Maize\n- Cowpea\n\nWhich one shall I use?"
    )
    assert cs._extract_bot_question_options(reply) == ["Carrot", "Maize", "Cowpea"]


def test_genuine_yes_no_question_gets_yes_no_chips():
    reply = "Prices move weekly.\n\nShall I compare Badulla with Jaffna?"
    assert cs._extract_bot_question_options(reply) == ["Yes please", "No thanks"]


def test_plain_answer_has_no_bot_question():
    assert (
        cs._extract_bot_question_options("Carrots yield 20,169 kg in Badulla.") is None
    )


# ── Priority resolution ───────────────────────────────────────────────────────


def _req():
    from app.models.schemas import ChatRequest

    return ChatRequest(message="carrot yield in jaffna", user_id="u1")


def test_bot_question_beats_llm_suggestions():
    reply = "Sure.\n\nIs that 3 acres, 3 hectares, or 3 perches?"
    chips, meta = cs._resolve_followup_chips(
        reply, ["something else"], {"chunks": []}, "3", _req()
    )
    assert meta["source"] == "bot_question"
    assert chips[0] == "3 acres"


def test_validated_llm_suggestions_are_used(monkeypatch):
    monkeypatch.setattr(cs, "_validate_followup_chips", lambda f: f)
    chips, meta = cs._resolve_followup_chips(
        "An answer.", ["a", "b"], {"chunks": []}, "q", _req()
    )
    assert chips == ["a", "b"]
    assert meta["source"] == "llm_generated"
    assert meta["generated"] == 2 and meta["validated_count"] == 2


def test_falls_back_to_templates_when_every_suggestion_fails_validation(monkeypatch):
    monkeypatch.setattr(cs, "_validate_followup_chips", lambda f: [])
    chips, meta = cs._resolve_followup_chips(
        "An answer.", ["ungrounded"], {"chunks": []}, "q", _req()
    )
    assert meta["source"] == "template_fallback"
    assert chips  # the safety net always produces something


def test_falls_back_to_templates_when_model_suggested_nothing():
    chips, meta = cs._resolve_followup_chips(
        "An answer.", [], {"chunks": []}, "q", _req()
    )
    assert meta["source"] == "template_fallback"
    assert meta["generated"] == 0


def test_validation_fails_open_without_rag(monkeypatch):
    """Losing every chip to a missing model is worse than an imperfect chip."""
    monkeypatch.setattr(cs.model_loader, "get_model", lambda name: None)
    assert cs._validate_followup_chips(["a", "b"]) == ["a", "b"]


def test_validation_of_empty_list_is_empty():
    assert cs._validate_followup_chips([]) == []
