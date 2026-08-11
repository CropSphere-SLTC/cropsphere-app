"""Unit tests for chatbot analytics logging — the Firestore writer and the
metadata-extraction helpers. Firestore and the RAG loader are mocked, so no
real infrastructure is required."""

from unittest.mock import MagicMock, patch

from app.user.services import analytics_service as svc
from app.user.services import chatbot_service as cb

# ═══════════════════════════════════════════════════════════════════════════
# log_chat_interaction
# ═══════════════════════════════════════════════════════════════════════════


def test_log_chat_interaction_writes_to_chat_analytics():
    db = MagicMock()
    with patch("app.utils.firestore.get_db", return_value=db):
        svc.log_chat_interaction({"question": "hi", "response_type": "answer"})
    db.collection.assert_called_once_with("chat_analytics")
    written = db.collection.return_value.add.call_args[0][0]
    assert written["response_type"] == "answer"
    assert "timestamp" in written  # server timestamp injected when absent


def test_log_chat_interaction_truncates_question_to_200_chars():
    db = MagicMock()
    with patch("app.utils.firestore.get_db", return_value=db):
        svc.log_chat_interaction({"question": "x" * 500})
    assert len(db.collection.return_value.add.call_args[0][0]["question"]) == 200


def test_log_chat_interaction_never_raises_on_firestore_failure():
    with patch("app.utils.firestore.get_db", side_effect=RuntimeError("down")):
        svc.log_chat_interaction({"question": "hi"})  # must not raise


def test_log_chat_interaction_does_not_mutate_caller_dict():
    data = {"question": "hi"}
    with patch("app.utils.firestore.get_db", return_value=MagicMock()):
        svc.log_chat_interaction(data)
    assert "timestamp" not in data  # server timestamp added to a copy only


# ═══════════════════════════════════════════════════════════════════════════
# metadata-extraction helpers (chatbot_service)
# ═══════════════════════════════════════════════════════════════════════════


def test_detect_crop_mention_covered_uncovered_and_none():
    assert cb._detect_crop_mention("what is the yield for carrot") == "Carrot"
    assert cb._detect_crop_mention("tell me about rice") == "rice"
    # 'rice' is a whole-word check, so it must NOT match inside 'price'
    assert cb._detect_crop_mention("what is the price") is None
    assert cb._detect_crop_mention("hello there") is None


def test_detect_district_mention_covered_uncovered_and_none():
    assert cb._detect_district_mention("yield in Badulla") == "Badulla"
    assert cb._detect_district_mention("prices in Colombo") == "colombo"
    assert cb._detect_district_mention("no place named here") is None


def test_detect_if_chip_tapped():
    fu = ["Carrot price in Badulla", "Best season for Maize"]
    assert cb._detect_if_chip_tapped("Carrot price in Badulla", fu) is True
    assert cb._detect_if_chip_tapped("  carrot PRICE in badulla ", fu) is True
    assert cb._detect_if_chip_tapped("something else", fu) is False
    assert cb._detect_if_chip_tapped("anything", []) is False


def test_tapped_chip_reports_text_and_source():
    """Analytics records WHICH chip was tapped and how it was produced."""
    meta = {"source": "llm_generated", "generated": 3, "validated_count": 3}
    tapped = cb._tapped_chip(
        "Prevention methods for carrot pests",
        (["Prevention methods for carrot pests"], meta),
    )
    assert tapped["template"] == "Prevention methods for carrot pests"
    assert tapped["source"] == "llm_generated"


def test_tapped_chip_returns_none_for_a_typed_question():
    meta = {"source": "llm_generated"}
    assert cb._tapped_chip("something else entirely", (["Carrot price"], meta)) is None


def test_tapped_chip_without_meta_defaults_to_template_fallback():
    tapped = cb._tapped_chip("Carrot price in Jaffna", (["Carrot price in Jaffna"], {}))
    assert tapped["template"] == "Carrot price in Jaffna"
    assert tapped["source"] == "template_fallback"


# ═══════════════════════════════════════════════════════════════════════════
# Shown-chip memory — how a tap is detected now that chips are generated
# ═══════════════════════════════════════════════════════════════════════════


def _req(crop="Carrot", district="Jaffna"):
    from app.models.schemas import ChatRequest

    return ChatRequest(
        message="carrot yield in jaffna", user_id="u1", crop=crop, district=district
    )


def test_shown_chips_round_trip():
    req = _req()
    cb._remember_shown_chips(req, ["A", "B"], {"source": "llm_generated"})
    chips, meta = cb._recall_shown_chips(req)
    assert chips == ["A", "B"]
    assert meta["source"] == "llm_generated"


def test_shown_chips_miss_returns_empty():
    from app.models.schemas import ChatRequest

    other = ChatRequest(message="hi", user_id="nobody-else", conversation_id="zzz")
    assert cb._recall_shown_chips(other) == ([], {})


def test_shown_chips_cache_is_bounded():
    """A runaway cache would be a slow memory leak in a long-lived process."""
    from app.models.schemas import ChatRequest

    for i in range(cb._SHOWN_CHIPS_CAP + 50):
        cb._remember_shown_chips(
            ChatRequest(message="m", user_id=f"u{i}", conversation_id=f"c{i}"),
            ["x"],
            {},
        )
    assert len(cb._shown_chips) <= cb._SHOWN_CHIPS_CAP


def test_season_for_now_returns_a_valid_season():
    assert cb._season_for_now() in ("Maha", "Yala", "Inter")


def test_anonymize_uid_is_deterministic_and_hides_raw_uid():
    hashed = cb._anonymize_uid("firebase-uid-123")
    assert hashed == cb._anonymize_uid("firebase-uid-123")  # stable
    assert "firebase-uid-123" not in hashed
    assert len(hashed) == 16
