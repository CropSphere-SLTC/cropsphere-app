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


def test_anonymize_uid_is_deterministic_and_hides_raw_uid():
    hashed = cb._anonymize_uid("firebase-uid-123")
    assert hashed == cb._anonymize_uid("firebase-uid-123")  # stable
    assert "firebase-uid-123" not in hashed
    assert len(hashed) == 16
