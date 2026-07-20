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
    with patch("app.user.services.fewshot_service.FEWSHOT_PATH",
               tmp_path / "nope.json"):
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
    fake = {"examples": {"yield": [
        {"question": "carrot yield in Badulla", "answer": "harvest is 19,517 kg/ha"}]}}
    with patch.object(cs, "_load_fewshot_examples", return_value=fake):
        msgs = cs._build_messages("sys", context, req, "carrot yield in Badulla")
    injected = [m["content"] for m in msgs
                if m["content"].startswith("Here are examples")]
    assert injected and "harvest is 19,517 kg/ha" in injected[0]


def test_build_messages_no_fewshot_when_type_absent():
    req = _make_request(message="what soil is best?", conversation_history=[])
    context = {"chunks": [], "sources": [], "score": 0.0}
    # examples only for 'yield'; a 'general' question gets nothing injected.
    fake = {"examples": {"yield": [{"question": "q", "answer": "a"}]}}
    with patch.object(cs, "_load_fewshot_examples", return_value=fake):
        msgs = cs._build_messages("sys", context, req, "what soil is best?")
    assert not any(m["content"].startswith("Here are examples") for m in msgs)
