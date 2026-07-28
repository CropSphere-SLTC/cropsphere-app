"""Unit tests for app.admin.services.pattern_analyzer_service — gap detection,
grouping/ranking, the apply path's server-side guards, and the read side.
Firestore is mocked; the override store is redirected at a tmp_path."""

from datetime import datetime, timedelta, timezone
from pathlib import Path
from unittest.mock import MagicMock, patch

import pytest

from app.admin.services import pattern_analyzer_service as svc
from app.user.services import pattern_override_store as store_mod


@pytest.fixture(autouse=True)
def _tmp_store(tmp_path, monkeypatch):
    """Isolate the overrides file and silence Firestore-backed side effects
    (audit mirror + notifications) that unit tests have no DB for."""
    monkeypatch.setattr(store_mod, "_DATA_DIR", Path(tmp_path))
    monkeypatch.setattr(
        store_mod, "OVERRIDES_PATH", tmp_path / "pattern_overrides.json"
    )
    monkeypatch.setattr(store_mod, "_LOCK_PATH", tmp_path / "pattern_overrides.lock")
    monkeypatch.setattr(store_mod, "_mirror_audit", lambda entry: None)
    monkeypatch.setattr(svc, "_notify_gaps", lambda proposals: None)
    monkeypatch.setattr(svc, "_notify_problematic", lambda patterns: None)
    svc._proposal_cache.clear()
    yield
    svc._proposal_cache.clear()


def _doc(question, response_type="refusal", **kwargs):
    """One chat_analytics document with the fields detection reads."""
    data = {
        "question": question,
        "response_type": response_type,
        "session_message_count": kwargs.get("session_message_count", 3),
        "crop_mentioned": kwargs.get("crop_mentioned"),
        "district_mentioned": kwargs.get("district_mentioned"),
    }
    return data


def _analyze(docs, days=14):
    with patch.object(svc, "_fetch_analytics", return_value=docs):
        return svc.analyze_pattern_gaps(days)


def _proposal(result, phrase):
    for p in result["proposed_patterns"]:
        if p["proposed_phrase"] == phrase:
            return p
    return None


# ── Detection ─────────────────────────────────────────────────────────────────


def test_detects_reformulation_misses():
    docs = [_doc("make it easier to understand") for _ in range(6)]
    result = _analyze(docs)
    phrases = [p["proposed_phrase"] for p in result["proposed_patterns"]]
    assert any("easier" in p for p in phrases)
    assert all(p["category"] == "reformulation" for p in result["proposed_patterns"])


def test_reformulation_ignores_first_turn_messages():
    """Nothing to rephrase on turn 1 — session_message_count gate."""
    docs = [_doc("make it easier", session_message_count=1) for _ in range(6)]
    assert _analyze(docs)["proposed_patterns"] == []


def test_reformulation_ignores_messages_naming_a_crop():
    docs = [
        _doc("make it easier to grow carrots", crop_mentioned="Carrot")
        for _ in range(6)
    ]
    assert not any(
        p["category"] == "reformulation" for p in _analyze(docs)["proposed_patterns"]
    )


def test_reformulation_ignores_long_messages():
    long_msg = "please make it easier " + " ".join(f"word{i}" for i in range(30))
    assert _analyze([_doc(long_msg) for _ in range(6)])["proposed_patterns"] == []


def test_skips_messages_the_live_predicate_already_catches():
    """'simplify' is already in _REFORMULATION_PHRASES — not a gap."""
    docs = [_doc("simplify that please, make it easier") for _ in range(6)]
    assert _analyze(docs)["proposed_patterns"] == []


def test_detects_context_statement_misses():
    docs = [_doc("we grow chillies", response_type="answer") for _ in range(5)]
    result = _analyze(docs)
    assert _proposal(result, "we grow chillies") or _proposal(result, "grow chillies")
    assert result["proposed_patterns"][0]["category"] == "context_statement"


def test_context_statement_ignores_questions():
    docs = [
        _doc("we grow chillies, what next?", response_type="answer") for _ in range(5)
    ]
    assert not any(
        p["category"] == "context_statement"
        for p in _analyze(docs)["proposed_patterns"]
    )


def test_detects_capability_misses():
    docs = [_doc("what information do you have") for _ in range(5)]
    result = _analyze(docs)
    assert result["proposed_patterns"]
    assert result["proposed_patterns"][0]["category"] == "capability"


def test_detects_agricultural_intent_misses_only_on_refusals():
    refused = [_doc("my soil is bad", response_type="refusal") for _ in range(5)]
    answered = [_doc("my soil is bad", response_type="answer") for _ in range(5)]
    assert any(
        p["category"] == "agricultural_intent"
        for p in _analyze(refused)["proposed_patterns"]
    )
    assert not any(
        p["category"] == "agricultural_intent"
        for p in _analyze(answered)["proposed_patterns"]
    )


def test_empty_analytics_yields_no_proposals():
    result = _analyze([])
    assert result["total_analyzed"] == 0
    assert result["proposed_patterns"] == []


def test_days_is_clamped():
    with patch.object(svc, "_fetch_analytics", return_value=[]) as fetch:
        svc.analyze_pattern_gaps(500)
    assert fetch.call_args[0][0] == svc._MAX_DAYS


# ── Grouping and ranking ──────────────────────────────────────────────────────


def test_confidence_and_recommendation_follow_evidence_count():
    high = _analyze([_doc("make it easier") for _ in range(6)])["proposed_patterns"][0]
    assert high["evidence_count"] == 6
    assert high["confidence"] == "high"
    assert high["recommended"] is True

    medium = _analyze([_doc("make it easier") for _ in range(3)])["proposed_patterns"][
        0
    ]
    assert medium["confidence"] == "medium"
    assert medium["recommended"] is False

    low = _analyze([_doc("make it easier") for _ in range(2)])["proposed_patterns"][0]
    assert low["confidence"] == "low"


def test_example_messages_are_capped_at_five():
    docs = [_doc(f"make it easier {i}") for i in range(9)]
    assert len(_analyze(docs)["proposed_patterns"][0]["example_messages"]) == 5


def test_overlapping_ngrams_do_not_both_ship():
    """'make it easier' wins; the shorter 'it easier' must not ship too."""
    phrases = [
        p["proposed_phrase"]
        for p in _analyze([_doc("make it easier")] * 6)["proposed_patterns"]
    ]
    assert not any(a != b and (a in b or b in a) for a in phrases for b in phrases)


def test_already_applied_phrases_are_not_reproposed():
    docs = [_doc("make it easier") for _ in range(6)]
    first = _analyze(docs)["proposed_patterns"][0]
    store_mod.apply_patterns(
        [
            {
                "id": first["id"],
                "category": first["category"],
                "phrase": first["proposed_phrase"],
                "original_proposed_phrase": first["proposed_phrase"],
                "edited": False,
                "evidence_count": first["evidence_count"],
            }
        ],
        "admin-uid",
    )
    assert not any(
        p["proposed_phrase"] == first["proposed_phrase"]
        for p in _analyze(docs)["proposed_patterns"]
    )


def test_proposal_ids_are_stable_across_runs():
    docs = [_doc("make it easier") for _ in range(6)]
    assert [p["id"] for p in _analyze(docs)["proposed_patterns"]] == [
        p["id"] for p in _analyze(docs)["proposed_patterns"]
    ]


def test_proposal_ids_carry_the_category_prefix():
    for proposal in _analyze([_doc("make it easier")] * 6)["proposed_patterns"]:
        assert store_mod.category_for_id(proposal["id"]) == proposal["category"]


# ── Apply (server-side guards, Step 11) ───────────────────────────────────────


def test_apply_accepts_a_known_proposal():
    proposal = _analyze([_doc("make it easier")] * 6)["proposed_patterns"][0]
    result = svc.apply_proposals(
        [{"id": proposal["id"], "phrase": proposal["proposed_phrase"]}], "admin-uid"
    )
    assert result["applied"] == [proposal["id"]]
    item = store_mod.find_active(store_mod.load(), proposal["id"])
    assert item["category"] == proposal["category"]
    assert item["evidence_count"] == proposal["evidence_count"]


def test_apply_honours_an_edited_phrase():
    proposal = _analyze([_doc("make it easier")] * 6)["proposed_patterns"][0]
    svc.apply_proposals(
        [{"id": proposal["id"], "phrase": "  Make It  EASIER Please ", "edited": True}],
        "admin-uid",
    )
    item = store_mod.find_active(store_mod.load(), proposal["id"])
    assert item["phrase"] == "make it easier please"
    assert item["edited"] is True
    assert item["original_proposed_phrase"] == proposal["proposed_phrase"]


def test_apply_rejects_an_invalid_edited_phrase():
    proposal = _analyze([_doc("make it easier")] * 6)["proposed_patterns"][0]
    result = svc.apply_proposals(
        [{"id": proposal["id"], "phrase": "grow.*"}], "admin-uid"
    )
    assert result["applied"] == []
    assert "cannot contain" in result["skipped"][0]["reason"]


def test_apply_rejects_an_unknown_proposal_id():
    with patch.object(svc, "_fetch_analytics", return_value=[]):
        result = svc.apply_proposals(
            [{"id": "reform_invented", "phrase": "anything at all"}], "admin-uid"
        )
    assert result["applied"] == []
    assert result["skipped"] == [
        {"id": "reform_invented", "reason": "unknown_proposal"}
    ]


def test_apply_reruns_analysis_when_this_worker_has_no_cache():
    """Two uvicorn workers: apply can land where analyze never ran."""
    docs = [_doc("make it easier")] * 6
    proposal = _analyze(docs)["proposed_patterns"][0]
    svc._proposal_cache.clear()

    with patch.object(svc, "_fetch_analytics", return_value=docs):
        result = svc.apply_proposals(
            [{"id": proposal["id"], "phrase": proposal["proposed_phrase"]}], "admin-uid"
        )
    assert result["applied"] == [proposal["id"]]


# ── Read side ─────────────────────────────────────────────────────────────────


def _seed_active(pattern_id="reform_x", phrase="make it easier"):
    store_mod.apply_patterns(
        [
            {
                "id": pattern_id,
                "category": "reformulation",
                "phrase": phrase,
                "original_proposed_phrase": phrase,
                "edited": False,
                "evidence_count": 8,
            }
        ],
        "admin-uid",
    )


def test_active_patterns_groups_by_category():
    _seed_active()
    out = svc.get_active_patterns()
    assert out["count"] == 1
    assert len(out["by_category"]["reformulation"]) == 1
    assert out["by_category"]["capability"] == []


@pytest.mark.parametrize(
    "hits,up,down,expected",
    [
        (2, 1, 0, "insufficient_data"),  # too few hits
        (10, 0, 0, "insufficient_data"),  # plenty of hits, never rated
        (10, 8, 2, "working_well"),
        (10, 6, 4, "needs_review"),  # 0.6 satisfaction
        (10, 7, 3, "needs_review"),  # 0.7 but 3 downvotes
        (10, 2, 8, "likely_problematic"),
    ],
)
def test_verdict_thresholds(hits, up, down, expected):
    rated = up + down
    satisfaction = round(up / rated, 2) if rated else 0.0
    assert svc._verdict(hits, rated, satisfaction, down) == expected


def test_pattern_analytics_reports_hits_and_false_positives():
    _seed_active()
    store_mod.record_hit("reform_x", "make it easier please", "make it easier", "c1")
    store_mod.record_hit(
        "reform_x", "make it easier to grow carrots in Badulla", "make it easier", "c2"
    )
    store_mod.record_feedback("c1", "make it easier please", "up")
    store_mod.record_feedback("c2", "make it easier to grow carrots in Badulla", "down")

    detail = svc.get_pattern_analytics("reform_x")
    assert detail["hit_count"] == 2
    assert detail["feedback"] == {"thumbs_up": 1, "thumbs_down": 1, "no_feedback": 0}
    assert detail["satisfaction_rate"] == 0.5
    assert detail["verdict"] == "insufficient_data"  # only 2 hits
    assert len(detail["example_hits"]) == 2
    assert detail["false_positive_candidates"] == [
        {
            "message": "make it easier to grow carrots in Badulla",
            "feedback": "down",
            "timestamp": detail["false_positive_candidates"][0]["timestamp"],
        }
    ]


def test_pattern_analytics_unknown_id_returns_none():
    assert svc.get_pattern_analytics("nope") is None


def test_pattern_analytics_covers_revoked_patterns():
    _seed_active()
    store_mod.revoke_pattern("reform_x", "admin-uid", "Too broad")
    assert svc.get_pattern_analytics("reform_x")["pattern"]["status"] == "revoked"


def test_pattern_health_counts_period_hits_only():
    _seed_active()
    store_mod.record_hit("reform_x", "recent hit", "make it easier")
    store = store_mod._read()
    old = datetime.now(timezone.utc) - timedelta(days=40)
    store["hits"].append(
        {
            "pattern_id": "reform_x",
            "key": "old hit",
            "message": "old hit",
            "matched_phrase": "make it easier",
            "conversation_id": "",
            "timestamp": old.isoformat(),
            "feedback": None,
        }
    )
    store_mod.save(store)

    health = svc.get_pattern_health(days=7)
    assert health["active_count"] == 1
    assert health["hits_this_period"] == 1
    assert health["total_hits"] == 1  # counter only bumped by record_hit


def test_pattern_health_survives_a_broken_store(monkeypatch):
    monkeypatch.setattr(
        store_mod, "load", MagicMock(side_effect=RuntimeError("disk gone"))
    )
    assert svc.get_pattern_health(7)["active_count"] == 0


def test_revoked_patterns_expose_retention_countdown():
    _seed_active()
    store_mod.revoke_pattern("reform_x", "admin-uid", "Too broad", retention_days=14)
    out = svc.get_revoked_patterns()
    assert out["count"] == 1
    assert out["revoked"][0]["revoke_reason"] == "Too broad"
    assert 12 <= out["revoked"][0]["days_remaining"] <= 14
