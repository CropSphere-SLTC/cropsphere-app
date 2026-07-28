"""Unit tests for app.user.services.pattern_override_store — the pattern
override file, its lifecycle transitions, retention sweep, and hit/feedback
ledger. The store is redirected at a tmp_path so no test touches data/."""

from datetime import datetime, timedelta, timezone
from pathlib import Path

import pytest

from app.user.services import pattern_override_store as store_mod


@pytest.fixture(autouse=True)
def _tmp_store(tmp_path, monkeypatch):
    """Point the store at a throwaway directory and silence the Firestore
    audit mirror (no DB in unit tests)."""
    monkeypatch.setattr(store_mod, "_DATA_DIR", Path(tmp_path))
    monkeypatch.setattr(
        store_mod, "OVERRIDES_PATH", tmp_path / "pattern_overrides.json"
    )
    monkeypatch.setattr(store_mod, "_LOCK_PATH", tmp_path / "pattern_overrides.lock")
    monkeypatch.setattr(store_mod, "_mirror_audit", lambda entry: None)
    yield


def _apply_one(pattern_id="reform_make_it_easier", phrase="make it easier", **kwargs):
    proposal = {
        "id": pattern_id,
        "category": "reformulation",
        "phrase": phrase,
        "original_proposed_phrase": kwargs.get("original", phrase),
        "edited": kwargs.get("edited", False),
        "evidence_count": kwargs.get("evidence_count", 8),
    }
    return store_mod.apply_patterns([proposal], "admin-uid")


# ── Phrase validation (Step 11) ───────────────────────────────────────────────


@pytest.mark.parametrize(
    "phrase",
    ["make it easier", "we grow", "what information"],
)
def test_validate_phrase_accepts_plain_phrases(phrase):
    ok, error = store_mod.validate_phrase(phrase)
    assert ok and error == ""


@pytest.mark.parametrize(
    "phrase,fragment",
    [
        ("", "empty"),
        ("   ", "empty"),
        ("ab", "at least"),
        ("x" * 51, "exceed"),
        ("grow.*", "cannot contain"),
        ("(easy|simple)", "cannot contain"),
        ("123 456", "must contain letters"),
        (None, "must be text"),
    ],
)
def test_validate_phrase_rejects_bad_input(phrase, fragment):
    ok, error = store_mod.validate_phrase(phrase)
    assert not ok
    assert fragment in error


def test_normalize_phrase_collapses_whitespace_and_case():
    assert store_mod.normalize_phrase("  Make   It  EASIER ") == "make it easier"


def test_category_for_id_derives_from_prefix():
    assert store_mod.category_for_id("reform_x") == "reformulation"
    assert store_mod.category_for_id("context_x") == "context_statement"
    assert store_mod.category_for_id("intent_x") == "agricultural_intent"
    assert store_mod.category_for_id("bogus_x") is None


# ── Load / save ───────────────────────────────────────────────────────────────


def test_load_missing_file_returns_empty_store():
    store = store_mod.load()
    assert store["active"] == []
    assert store["revoked"] == []
    assert store["version"] == store_mod.SCHEMA_VERSION


def test_load_corrupt_file_returns_empty_store():
    store_mod.OVERRIDES_PATH.write_text("{not json")
    assert store_mod.load()["active"] == []


# ── Apply ─────────────────────────────────────────────────────────────────────


def test_apply_adds_active_pattern_with_zeroed_counters():
    result = _apply_one()
    assert result["applied"] == ["reform_make_it_easier"]

    item = store_mod.find_active(store_mod.load(), "reform_make_it_easier")
    assert item["phrase"] == "make it easier"
    assert item["status"] == "active"
    assert item["hit_count"] == 0
    assert item["last_hit"] is None
    assert item["feedback"] == {"thumbs_up": 0, "thumbs_down": 0, "no_feedback": 0}
    assert item["edited"] is False


def test_apply_records_edit_in_audit():
    _apply_one(phrase="farming in", original="farming", edited=True)
    audit = store_mod.load()["audit"]
    assert audit[-1]["action"] == "approved_with_edit"
    assert audit[-1]["details"]["original"] == "farming"
    assert audit[-1]["details"]["edited_to"] == "farming in"


def test_apply_skips_duplicate_id():
    _apply_one()
    result = _apply_one()
    assert result["applied"] == []
    assert result["skipped"] == [
        {"id": "reform_make_it_easier", "reason": "already_active"}
    ]


def test_apply_skips_duplicate_phrase_under_new_id():
    _apply_one()
    result = _apply_one(pattern_id="reform_other")
    assert result["skipped"] == [{"id": "reform_other", "reason": "duplicate_phrase"}]


# ── Compile (what the chatbot consumes) ───────────────────────────────────────


def test_compile_overrides_exposes_active_phrases_only():
    _apply_one()
    compiled = store_mod.compile_overrides()
    assert compiled["reformulation"]["phrases"] == [
        ("make it easier", "reform_make_it_easier")
    ]
    assert compiled["capability"]["phrases"] == []

    store_mod.revoke_pattern("reform_make_it_easier", "admin-uid", "too broad")
    assert store_mod.compile_overrides()["reformulation"]["phrases"] == []


# ── Revoke / restore / delete ─────────────────────────────────────────────────


def test_revoke_snapshots_performance_and_sets_retention():
    _apply_one()
    store_mod.record_hit(
        "reform_make_it_easier", "make it easier pls", "make it easier"
    )
    store_mod.record_feedback("", "make it easier pls", "down")

    result = store_mod.revoke_pattern(
        "reform_make_it_easier", "admin-uid", "Too broad", retention_days=14
    )
    assert result["ok"]
    item = result["item"]
    assert item["status"] == "revoked"
    assert item["revoke_reason"] == "Too broad"
    assert item["performance_at_revoke"] == {
        "hit_count": 1,
        "thumbs_up": 0,
        "thumbs_down": 1,
        "satisfaction": 0.0,
    }
    assert item["can_restore"] is True
    assert store_mod.parse_iso(item["retention_until"]) > datetime.now(timezone.utc)


def test_revoke_unknown_id_returns_not_found():
    assert store_mod.revoke_pattern("nope", "admin-uid", "x")["error"] == "not_found"


def test_restore_resets_counters_and_clears_ledger():
    _apply_one()
    store_mod.record_hit(
        "reform_make_it_easier", "make it easier pls", "make it easier"
    )
    store_mod.record_feedback("", "make it easier pls", "up")
    store_mod.revoke_pattern("reform_make_it_easier", "admin-uid", "Too broad")

    result = store_mod.restore_pattern("reform_make_it_easier", "admin-uid")
    assert result["ok"]
    item = result["item"]
    assert item["status"] == "active"
    assert item["hit_count"] == 0
    assert item["feedback"] == {"thumbs_up": 0, "thumbs_down": 0, "no_feedback": 0}
    assert "revoke_reason" not in item

    store = store_mod.load()
    assert store_mod.pattern_hits(store, "reform_make_it_easier") == []
    assert store_mod.find_revoked(store, "reform_make_it_easier") is None


def test_restore_conflicts_when_already_active():
    _apply_one()
    store_mod.revoke_pattern("reform_make_it_easier", "admin-uid", "Too broad")
    _apply_one()  # re-applied under the same id while still in revoked
    result = store_mod.restore_pattern("reform_make_it_easier", "admin-uid")
    assert result["error"] == "already_active"


def test_delete_only_touches_revoked():
    _apply_one()
    assert store_mod.delete_pattern("reform_make_it_easier", "admin-uid")["ok"] is False

    store_mod.revoke_pattern("reform_make_it_easier", "admin-uid", "Too broad")
    assert store_mod.delete_pattern("reform_make_it_easier", "admin-uid")["ok"] is True
    assert store_mod.load()["revoked"] == []


# ── Retention sweep (Step 7) ──────────────────────────────────────────────────


def test_load_auto_deletes_expired_revoked_and_audits_it():
    _apply_one()
    store_mod.revoke_pattern("reform_make_it_easier", "admin-uid", "Too broad")

    # Backdate the retention deadline the way real elapsed time would.
    store = store_mod._read()
    past = datetime.now(timezone.utc) - timedelta(days=1)
    store["revoked"][0]["retention_until"] = past.isoformat()
    store_mod.save(store)

    swept = store_mod.load()
    assert swept["revoked"] == []
    assert swept["audit"][-1]["action"] == "auto_deleted"
    assert swept["audit"][-1]["performed_by"] == "system"


def test_load_keeps_revoked_with_unparseable_retention():
    _apply_one()
    store_mod.revoke_pattern("reform_make_it_easier", "admin-uid", "Too broad")
    store = store_mod._read()
    store["revoked"][0]["retention_until"] = "not-a-date"
    store_mod.save(store)
    assert len(store_mod.load()["revoked"]) == 1


# ── Hit + feedback ledger (Step 5) ────────────────────────────────────────────


def test_record_hit_increments_counters_and_appends_ledger():
    _apply_one()
    store_mod.record_hit(
        "reform_make_it_easier", "Make It Easier please", "make it easier", "conv-1"
    )
    store = store_mod.load()
    item = store_mod.find_active(store, "reform_make_it_easier")
    assert item["hit_count"] == 1
    assert item["last_hit"] is not None
    assert item["feedback"]["no_feedback"] == 1

    hits = store_mod.pattern_hits(store, "reform_make_it_easier")
    assert hits[0]["message"] == "Make It Easier please"
    assert hits[0]["matched_phrase"] == "make it easier"
    assert hits[0]["feedback"] is None


def test_record_hit_for_inactive_pattern_is_dropped():
    store_mod.record_hit("ghost", "anything", "x")
    assert store_mod.load()["hits"] == []


def test_record_feedback_attributes_vote_to_pattern():
    _apply_one()
    store_mod.record_hit(
        "reform_make_it_easier", "make it easier please", "make it easier", "conv-1"
    )
    assert (
        store_mod.record_feedback("conv-1", "make it easier please", "up")
        == "reform_make_it_easier"
    )
    item = store_mod.find_active(store_mod.load(), "reform_make_it_easier")
    assert item["feedback"]["thumbs_up"] == 1
    assert item["feedback"]["no_feedback"] == 0


def test_record_feedback_matches_when_conversation_id_absent_on_first_turn():
    """The server mints conversation_id after the turn, so a hit recorded with
    none must still attribute the vote that arrives with one."""
    _apply_one()
    store_mod.record_hit(
        "reform_make_it_easier", "make it easier please", "make it easier", None
    )
    assert (
        store_mod.record_feedback("conv-9", "make it easier please", "up")
        == "reform_make_it_easier"
    )


def test_record_feedback_revote_swaps_counters():
    _apply_one()
    store_mod.record_hit(
        "reform_make_it_easier", "make it easier please", "make it easier", "conv-1"
    )
    store_mod.record_feedback("conv-1", "make it easier please", "up")
    store_mod.record_feedback("conv-1", "make it easier please", "down")

    fb = store_mod.find_active(store_mod.load(), "reform_make_it_easier")["feedback"]
    assert fb == {"thumbs_up": 0, "thumbs_down": 1, "no_feedback": 0}


def test_record_feedback_is_idempotent_for_same_vote():
    _apply_one()
    store_mod.record_hit(
        "reform_make_it_easier", "make it easier please", "make it easier", "conv-1"
    )
    store_mod.record_feedback("conv-1", "make it easier please", "up")
    store_mod.record_feedback("conv-1", "make it easier please", "up")
    fb = store_mod.find_active(store_mod.load(), "reform_make_it_easier")["feedback"]
    assert fb["thumbs_up"] == 1


def test_record_feedback_without_matching_hit_writes_nothing():
    _apply_one()
    before = store_mod.OVERRIDES_PATH.read_text()
    assert store_mod.record_feedback("conv-1", "unrelated question", "down") is None
    assert store_mod.OVERRIDES_PATH.read_text() == before


def test_record_feedback_ignores_invalid_vote():
    _apply_one()
    store_mod.record_hit("reform_make_it_easier", "make it easier", "make it easier")
    assert store_mod.record_feedback("", "make it easier", "sideways") is None


def test_hit_ledger_is_capped(monkeypatch):
    monkeypatch.setattr(store_mod, "_HIT_CAP", 5)
    _apply_one()
    for i in range(9):
        store_mod.record_hit("reform_make_it_easier", f"msg {i}", "make it easier")
    assert len(store_mod.load()["hits"]) == 5
