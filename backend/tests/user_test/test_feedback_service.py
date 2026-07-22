"""Unit tests for app.user.services.feedback_service — chat_feedback logging
and read-back. Firestore is mocked; no real infrastructure required."""

from unittest.mock import MagicMock, patch

from app.user.services import feedback_service as svc


def _written(db):
    """The document payload passed to .document(id).set(payload)."""
    return db.collection.return_value.document.return_value.set.call_args[0][0]


def test_log_feedback_upserts_to_chat_feedback():
    db = MagicMock()
    with patch("app.utils.firestore.get_db", return_value=db):
        svc.log_feedback("uid-1", "conv-1", 3, "up", "carrot yield in badulla")
    db.collection.assert_called_once_with("chat_feedback")
    # Upsert by deterministic id (not add()) so re-votes overwrite.
    db.collection.return_value.document.return_value.set.assert_called_once()
    written = _written(db)
    assert written["feedback"] == "up"
    assert written["conversation_id"] == "conv-1"
    assert written["message_index"] == 3
    assert written["message_text"] == "carrot yield in badulla"
    assert "timestamp" in written


def test_log_feedback_same_message_reuses_doc_id():
    db = MagicMock()
    with patch("app.utils.firestore.get_db", return_value=db):
        svc.log_feedback("uid-1", "conv-1", 3, "up", "q")
        svc.log_feedback("uid-1", "conv-1", 3, "down", "q")  # changed vote
    ids = [c.args[0] for c in db.collection.return_value.document.call_args_list]
    assert ids[0] == ids[1]  # same (user, conv, index) → same doc → overwrite


def test_log_feedback_anonymises_uid():
    db = MagicMock()
    with patch("app.utils.firestore.get_db", return_value=db):
        svc.log_feedback("firebase-uid-999", "c", 0, "down", "q")
    written = _written(db)
    assert written["user_id"] != "firebase-uid-999"
    assert len(written["user_id"]) == 16


def test_log_feedback_truncates_message_text():
    db = MagicMock()
    with patch("app.utils.firestore.get_db", return_value=db):
        svc.log_feedback("uid", "c", 0, "down", "x" * 900)
    assert len(_written(db)["message_text"]) == 500


def test_log_feedback_never_raises_on_firestore_failure():
    with patch("app.utils.firestore.get_db", side_effect=RuntimeError("down")):
        svc.log_feedback("uid", "c", 0, "up", "q")  # must not raise


def _doc(data):
    d = MagicMock()
    d.to_dict.return_value = data
    return d


def test_get_conversation_feedback_returns_callers_votes():
    anon = svc._anonymize_uid("uid-1")
    docs = [
        _doc({"user_id": anon, "message_index": 1, "feedback": "up"}),
        _doc({"user_id": anon, "message_index": 3, "feedback": "down"}),
        _doc({"user_id": "someone-else", "message_index": 5, "feedback": "up"}),
    ]
    db = MagicMock()
    db.collection.return_value.where.return_value.stream.return_value = docs
    with patch("app.utils.firestore.get_db", return_value=db):
        votes = svc.get_conversation_feedback("uid-1", "conv-1")
    assert votes == {1: "up", 3: "down"}  # other user's vote excluded


def test_get_conversation_feedback_swallows_errors():
    with patch("app.utils.firestore.get_db", side_effect=RuntimeError("down")):
        assert svc.get_conversation_feedback("uid", "c") == {}
