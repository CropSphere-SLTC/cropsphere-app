"""Unit tests for app.admin.services.conversation_miner_service — conversation
reconstruction (including orphan first turns), season tagging, drop-off
analysis, conversation health (flows, per-type drop-off, chip tap trend) and
the abandonment notification. Firestore is mocked throughout.

The chip-generation half of this module is gone: follow-up chips are now
generated per reply by the LLM and validated against RAG (see
chatbot_service._resolve_followup_chips), so there are no transitions, chip
templates, confidence ladder or dual-window shifts left to test.
"""

from datetime import datetime, timedelta, timezone
from unittest.mock import patch

import pytest

from app.admin.services import conversation_miner_service as svc

NOW = datetime(2026, 7, 29, 12, 0, tzinfo=timezone.utc)


@pytest.fixture(autouse=True)
def _silence_notifications(monkeypatch):
    """No Firestore in these tests — notifications are a side effect, not the
    subject (one test asserts on them via its own patch)."""
    monkeypatch.setattr(svc, "_notify", lambda *a, **k: None)


def _doc(qtype, index, conv="c1", days_ago=1, user="u1", **kwargs):
    """One chat_analytics document as the analyser reads it."""
    doc = {
        "conversation_id": conv,
        "user_id": user,
        "question_type": qtype,
        "session_message_count": index,
        "timestamp": NOW - timedelta(days=days_ago),
        "response_type": kwargs.get("response_type", "answer"),
        "confidence": kwargs.get("confidence", "High confidence"),
        "crop_mentioned": kwargs.get("crop"),
        "district_mentioned": kwargs.get("district"),
    }
    for key in ("followup_chip_tapped", "season", "followup_source"):
        if key in kwargs:
            doc[key] = kwargs[key]
    return doc


def _conversation(types, conv="c1", days_ago=1, crop=None, district=None):
    """Docs for one conversation from a list of question types."""
    return [
        _doc(qtype, i + 1, conv=conv, days_ago=days_ago, crop=crop, district=district)
        for i, qtype in enumerate(types)
    ]


def _analyze(docs, days=30):
    with patch.object(svc, "_fetch_analytics", return_value=docs), patch.object(
        svc, "_now", return_value=NOW
    ):
        return svc.mine_conversation_patterns(days)


# ── Conversation reconstruction ───────────────────────────────────────────────


def test_groups_by_conversation_id_and_orders_by_message_count():
    docs = [
        _doc("price", 2, conv="c1"),
        _doc("yield", 1, conv="c1"),
        _doc("season", 1, conv="c2"),
    ]
    convs = svc.reconstruct_conversations(docs)
    assert len(convs) == 2
    by_id = {c["id"]: c for c in convs}
    assert [t["type"] for t in by_id["c1"]["turns"]] == ["yield", "price"]


def test_orphan_first_turn_is_stitched_onto_its_conversation():
    """A conversation's first turn has no id — the server mints it afterwards."""
    orphan = _doc("yield", 1, conv=None)
    orphan["conversation_id"] = None
    docs = [orphan, _doc("price", 2, conv="c1")]
    convs = svc.reconstruct_conversations(docs)
    assert len(convs) == 1
    assert [t["type"] for t in convs[0]["turns"]] == ["yield", "price"]


def test_orphan_beyond_session_gap_stays_its_own_conversation():
    orphan = _doc("yield", 1, conv=None, days_ago=5)
    orphan["conversation_id"] = None
    docs = [orphan, _doc("price", 2, conv="c1", days_ago=1)]
    assert len(svc.reconstruct_conversations(docs)) == 2


def test_conversation_inherits_first_named_crop_and_district():
    docs = [
        _doc("yield", 1, crop="Carrot", district="Jaffna"),
        _doc("price", 2),
    ]
    conv = svc.reconstruct_conversations(docs)[0]
    assert conv["crop"] == "Carrot"
    assert conv["district"] == "Jaffna"


def test_season_tagged_from_timestamp_when_absent():
    # NOW is 29 July -> Yala (Apr 1 - Aug 31).
    conv = svc.reconstruct_conversations([_doc("yield", 1)])[0]
    assert conv["season"] == "Yala"


def test_stored_season_wins_over_derived():
    conv = svc.reconstruct_conversations([_doc("yield", 1, season="Maha")])[0]
    assert conv["season"] == "Maha"


@pytest.mark.parametrize(
    "month,expected",
    [(11, "Maha"), (1, "Maha"), (3, "Maha"), (4, "Yala"), (8, "Yala"), (9, "Inter")],
)
def test_season_boundaries(month, expected):
    when = datetime(2026, month, 15, tzinfo=timezone.utc)
    assert svc._season_for(when) == expected


# ── Drop-off analysis ─────────────────────────────────────────────────────────


def test_drop_off_after_refusal_counts_leaves_and_rephrases():
    left = [_doc("yield", 1, conv="a", response_type="refusal")]
    rephrased = [
        _doc("yield", 1, conv="b", response_type="refusal"),
        _doc("yield", 2, conv="b"),
    ]
    result = _analyze(left + rephrased)["drop_off_analysis"]["after_refusal"]
    assert result["sample_size"] == 2
    assert result["leave_rate"] == 0.5
    assert result["rephrase_rate"] == 0.5


def test_drop_off_after_clarification_tracks_answer_rate():
    docs = [
        _doc("yield", 1, conv="a", response_type="clarification"),
        _doc("yield", 2, conv="a", response_type="answer"),
    ]
    result = _analyze(docs)["drop_off_analysis"]["after_clarification"]
    assert result["sample_size"] == 1
    assert result["answer_rate"] == 1.0
    assert result["leave_rate"] == 0.0


def test_drop_off_after_low_confidence():
    docs = [_doc("yield", 1, conv="a", confidence="Low confidence — limited data")]
    result = _analyze(docs)["drop_off_analysis"]["after_low_confidence"]
    assert result["sample_size"] == 1
    assert result["leave_rate"] == 1.0


# ── Conversation health ───────────────────────────────────────────────────────


def test_health_reports_average_length_and_single_turn_rate():
    docs = _conversation(["yield", "price"], conv="a") + _conversation(
        ["season"], conv="b"
    )
    health = _analyze(docs)["conversation_health"]
    assert health["total_conversations"] == 2
    assert health["avg_conversation_length"] == 1.5
    assert health["single_turn_rate"] == 0.5


def test_top_flows_ranks_common_paths():
    docs = (
        _conversation(["yield", "price"], conv="a")
        + _conversation(["yield", "price"], conv="b")
        + _conversation(["season", "yield"], conv="c")
    )
    flows = _analyze(docs)["conversation_health"]["top_flows"]
    assert flows[0]["flow"] == "yield → price"
    assert flows[0]["count"] == 2


def test_problem_flows_capture_conversations_ending_in_refusal():
    docs = [
        _doc("yield", 1, conv="a"),
        _doc("price", 2, conv="a", response_type="refusal"),
    ]
    problems = _analyze(docs)["conversation_health"]["problem_flows"]
    assert problems and problems[0]["flow"].endswith("leave")


def test_drop_off_by_question_type_is_ordered_by_volume():
    docs = _conversation(["yield", "yield"], conv="a") + _conversation(
        ["price"], conv="b"
    )
    rows = _analyze(docs)["conversation_health"]["drop_off_by_question_type"]
    assert rows[0]["question_type"] == "yield"
    assert rows[0]["turns"] == 2


def test_chip_tap_trend_compares_this_week_to_last():
    docs = [
        _doc("yield", 1, conv="a", days_ago=1, followup_chip_tapped=True),
        _doc("yield", 1, conv="b", days_ago=2, followup_chip_tapped=False),
        _doc("yield", 1, conv="c", days_ago=9, followup_chip_tapped=False),
        _doc("yield", 1, conv="d", days_ago=10, followup_chip_tapped=False),
    ]
    trend = _analyze(docs)["conversation_health"]["chip_tap_trend"]
    assert trend["this_week"] == 0.5
    assert trend["last_week"] == 0.0
    assert trend["change"] == 0.5


# ── Report shape and failure modes ────────────────────────────────────────────


def test_empty_input_gives_wellformed_zeroed_report():
    result = _analyze([])
    assert result["total_conversations"] == 0
    assert result["drop_off_analysis"]["after_refusal"]["sample_size"] == 0
    assert result["conversation_health"]["top_flows"] == []
    assert "chip_patterns" not in result  # chip mining is gone


def test_firestore_failure_yields_empty_report():
    with patch.object(svc, "_fetch_analytics", return_value=[]):
        assert svc.mine_conversation_patterns(30)["total_conversations"] == 0


def test_days_is_clamped_to_max():
    with patch.object(svc, "_fetch_analytics", return_value=[]) as fetch:
        svc.mine_conversation_patterns(9999)
    assert fetch.call_args[0][0] == svc._MAX_DAYS


def test_high_abandonment_raises_a_notification(monkeypatch):
    """Above the sample floor and the 70% leave rate, an admin is told."""
    sent = []
    monkeypatch.setattr(svc, "_notify", lambda *a, **k: sent.append(a))
    docs = [_doc("yield", 1, conv=f"c{i}", response_type="refusal") for i in range(8)]
    _analyze(docs)
    assert sent and sent[0][0] == "high_abandonment"


def test_no_notification_below_sample_floor(monkeypatch):
    sent = []
    monkeypatch.setattr(svc, "_notify", lambda *a, **k: sent.append(a))
    docs = [_doc("yield", 1, conv="c1", response_type="refusal")]
    _analyze(docs)
    assert sent == []
