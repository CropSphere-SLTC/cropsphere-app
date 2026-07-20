"""Unit tests for app.user.services.fewshot_service — few-shot collection,
merge, and file write. Firestore is mocked; no real infrastructure needed."""

import json
from unittest.mock import MagicMock, patch

from app.user.services import fewshot_service as svc


# ── _merge ─────────────────────────────────────────────────────────────────
def test_merge_manual_first_then_auto_capped_at_two():
    manual = {"yield": [{"question": "m q", "answer": "m a"}]}
    auto = {"yield": [
        {"question": "a1", "answer": "a1 ans"},
        {"question": "a2", "answer": "a2 ans"},
    ]}
    out = svc._merge(manual, auto)
    assert [e["question"] for e in out["yield"]] == ["m q", "a1"]  # manual first, cap 2
    assert out["price"] == []  # all types present


def test_merge_dedupes_by_question_case_insensitive():
    manual = {"price": [{"question": "Carrot Price", "answer": "manual"}]}
    auto = {"price": [{"question": "carrot price", "answer": "auto dup"}]}
    out = svc._merge(manual, auto)
    assert out["price"] == [{"question": "Carrot Price", "answer": "manual"}]


def test_merge_caps_total_at_ten():
    manual = {t: [{"question": f"{t} q", "answer": "a"}] for t in svc._TYPES}
    auto = {t: [{"question": f"{t} a1", "answer": "a"},
                {"question": f"{t} a2", "answer": "a"}] for t in svc._TYPES}
    out = svc._merge(manual, auto)
    assert sum(len(v) for v in out.values()) == 10  # 5 types * 2, hard cap


# ── _extract_pair ────────────────────────────────────────────────────────────
def _db_with_conversation(messages):
    db = MagicMock()
    snap = MagicMock()
    snap.exists = True
    snap.to_dict.return_value = {"messages": messages}
    db.collection.return_value.document.return_value.get.return_value = snap
    return db


def test_extract_pair_reads_answer_from_conversation():
    msgs = [{"role": "user", "content": "carrot yield?"},
            {"role": "assistant", "content": "The harvest is 19,517 kg/ha."}]
    db = _db_with_conversation(msgs)
    fb = {"conversation_id": "c1", "message_index": 1,
          "message_text": "carrot yield?"}
    assert svc._extract_pair(db, fb, {}) == (
        "carrot yield?", "The harvest is 19,517 kg/ha.")


def test_extract_pair_none_when_index_not_assistant():
    msgs = [{"role": "user", "content": "q"},
            {"role": "assistant", "content": "a"}]
    db = _db_with_conversation(msgs)
    # index 0 is the user turn, not an assistant answer → skip.
    assert svc._extract_pair(db, {"conversation_id": "c1", "message_index": 0,
                                  "message_text": "q"}, {}) is None


def test_extract_pair_none_when_conversation_missing():
    db = MagicMock()
    snap = MagicMock()
    snap.exists = False
    db.collection.return_value.document.return_value.get.return_value = snap
    assert svc._extract_pair(db, {"conversation_id": "gone", "message_index": 1,
                                  "message_text": "q"}, {}) is None


# ── _collect_auto ────────────────────────────────────────────────────────────
def test_collect_auto_groups_by_question_type():
    from datetime import datetime, timezone

    ts = datetime(2026, 1, 1, tzinfo=timezone.utc)
    up = MagicMock()
    up.to_dict.return_value = {
        "feedback": "up", "conversation_id": "c1", "message_index": 1,
        "message_text": "carrot yield?", "timestamp": ts,
    }
    db = MagicMock()
    db.collection.return_value.where.return_value.stream.return_value = [up]
    conv = MagicMock()
    conv.exists = True
    conv.to_dict.return_value = {"messages": [
        {"role": "user", "content": "carrot yield?"},
        {"role": "assistant", "content": "Reasoning: data.\n\nharvest is high"}]}
    db.collection.return_value.document.return_value.get.return_value = conv

    with patch("app.utils.firestore.get_db", return_value=db), patch(
        "app.user.services.chatbot_service._question_type", return_value="yield"
    ):
        buckets = svc._collect_auto()
    assert buckets["yield"] == [{"question": "carrot yield?",
                                 "answer": "Reasoning: data.\n\nharvest is high"}]


def test_collect_auto_skips_unstructured_single_paragraph_answers():
    """Up-votes predating the three-section rule must not merge back in —
    they teach the old merged format (see _is_structured)."""
    from datetime import datetime, timezone

    ts = datetime(2026, 1, 1, tzinfo=timezone.utc)
    up = MagicMock()
    up.to_dict.return_value = {
        "feedback": "up", "conversation_id": "c1", "message_index": 1,
        "message_text": "how much can I earn", "timestamp": ts,
    }
    db = MagicMock()
    db.collection.return_value.where.return_value.stream.return_value = [up]
    conv = MagicMock()
    conv.exists = True
    conv.to_dict.return_value = {"messages": [
        {"role": "user", "content": "how much can I earn"},
        {"role": "assistant", "content": (
            "Reasoning: CropSphere dataset: Groundnut — Batticaloa — Inter. "
            "You can harvest around 5,482 kg/acre of Groundnuts, and you can "
            "earn around 1,021,652 LKR/acre. Want me to give more details?")}]}
    db.collection.return_value.document.return_value.get.return_value = conv

    with patch("app.utils.firestore.get_db", return_value=db), patch(
        "app.user.services.chatbot_service._question_type", return_value="earnings"
    ):
        buckets = svc._collect_auto()
    assert buckets["earnings"] == []


def test_is_structured_requires_two_non_empty_sections():
    assert svc._is_structured("Reasoning: x.\n\nYou can expect 100 kg.")
    assert not svc._is_structured("Reasoning: x. You can expect 100 kg.")
    assert not svc._is_structured("Reasoning: x.\n\n   \n\n")


def test_collect_auto_returns_empty_without_firestore():
    with patch("app.utils.firestore.get_db", side_effect=RuntimeError("no db")):
        assert svc._collect_auto() == {}


# ── build_fewshot_examples ───────────────────────────────────────────────────
def test_build_writes_merged_file(tmp_path):
    out_path = tmp_path / "fewshot_examples.json"
    with patch.object(svc, "FEWSHOT_PATH", out_path), patch.object(
        svc, "_DATA_DIR", tmp_path
    ), patch.object(svc, "_collect_auto", return_value={}), patch.object(
        svc, "_load_manual",
        return_value={"yield": [{"question": "q", "answer": "a"}]},
    ):
        result = svc.build_fewshot_examples()

    assert out_path.exists()
    written = json.loads(out_path.read_text())
    assert "updated_at" in written
    assert written["examples"]["yield"] == [{"question": "q", "answer": "a"}]
    assert result["examples"]["yield"] == [{"question": "q", "answer": "a"}]
