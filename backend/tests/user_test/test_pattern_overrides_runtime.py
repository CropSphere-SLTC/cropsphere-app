"""Integration tests for the chatbot's pattern-override wiring — the runtime
half of the feature (Steps 4 and 5).

Covers the safety contract: overrides SUPPLEMENT the hardcoded lists and can
never suppress a match they already make, the context-statement question guards
still win over an override, and a match is attributed to the right pattern id
for hit tracking. The store is redirected at a tmp_path."""

from pathlib import Path

import pytest

from app.user.services import chatbot_service as chat_svc
from app.user.services import pattern_override_store as store_mod


@pytest.fixture(autouse=True)
def _tmp_store(tmp_path, monkeypatch):
    monkeypatch.setattr(store_mod, "_DATA_DIR", Path(tmp_path))
    monkeypatch.setattr(
        store_mod, "OVERRIDES_PATH", tmp_path / "pattern_overrides.json"
    )
    monkeypatch.setattr(store_mod, "_LOCK_PATH", tmp_path / "pattern_overrides.lock")
    monkeypatch.setattr(store_mod, "_mirror_audit", lambda entry: None)
    chat_svc._reset_override_match()
    chat_svc._pattern_overrides = None
    yield
    chat_svc._pattern_overrides = None
    chat_svc._reset_override_match()


def _add(pattern_id, category, phrase):
    store_mod.apply_patterns(
        [
            {
                "id": pattern_id,
                "category": category,
                "phrase": phrase,
                "original_proposed_phrase": phrase,
                "edited": False,
                "evidence_count": 5,
            }
        ],
        "admin-uid",
    )
    chat_svc._reload_pattern_overrides()


# ── Loader / cache ────────────────────────────────────────────────────────────


def test_load_returns_empty_when_no_file():
    assert chat_svc._load_pattern_overrides() == {
        c: {"phrases": [], "patterns": []} for c in store_mod.CATEGORIES
    }


def test_reload_picks_up_a_newly_applied_pattern():
    assert not chat_svc._is_reformulation_request("make it easier")
    _add("reform_make_it_easier", "reformulation", "make it easier")
    assert chat_svc._is_reformulation_request("make it easier")


def test_revoking_stops_the_match_after_reload():
    _add("reform_make_it_easier", "reformulation", "make it easier")
    store_mod.revoke_pattern("reform_make_it_easier", "admin-uid", "Too broad")
    chat_svc._reload_pattern_overrides()
    assert not chat_svc._is_reformulation_request("make it easier")


# ── Supplement, never replace (Step 11) ───────────────────────────────────────


@pytest.mark.parametrize(
    "message",
    ["please simplify that", "i don't understand", "explain that again", "rephrase it"],
)
def test_hardcoded_reformulation_phrases_still_match_with_overrides_present(message):
    _add("reform_make_it_easier", "reformulation", "make it easier")
    assert chat_svc._is_reformulation_request(message)


def test_hardcoded_capability_patterns_still_match():
    _add("capability_what_information", "capability", "what information")
    assert chat_svc._is_capability_question("what crops do you cover")
    assert chat_svc._is_capability_question("what information do you have")


def test_hardcoded_agricultural_intent_still_matches():
    _add("intent_my_soil", "agricultural_intent", "my soil")
    assert chat_svc._has_agricultural_intent("how much can i earn")
    assert chat_svc._has_agricultural_intent("my soil is poor")


def test_context_override_cannot_hijack_a_question():
    """The question guards run BEFORE overrides, so an override phrase inside a
    real question must not short-circuit it to a context ack."""
    _add("context_we_grow", "context_statement", "we grow")
    assert chat_svc._is_context_statement("we grow chillies here")
    assert not chat_svc._is_context_statement("we grow chillies, what next?")
    assert not chat_svc._is_context_statement("what should we grow")


def test_bare_simply_guard_still_applies_with_overrides_present():
    _add("reform_make_it_easier", "reformulation", "make it easier")
    assert chat_svc._is_reformulation_request("simply")
    assert not chat_svc._is_reformulation_request(
        "which crop simply grows best in Badulla district"
    )


def test_unrelated_message_still_matches_nothing():
    _add("reform_make_it_easier", "reformulation", "make it easier")
    assert not chat_svc._is_reformulation_request("what is the carrot price in Jaffna")
    assert chat_svc._current_override_match() is None


# ── Match attribution (Step 5) ────────────────────────────────────────────────


def test_override_match_records_the_pattern_id():
    _add("reform_make_it_easier", "reformulation", "make it easier")
    assert chat_svc._is_reformulation_request("can you make it easier")
    assert chat_svc._current_override_match() == {
        "category": "reformulation",
        "pattern_id": "reform_make_it_easier",
        "phrase": "make it easier",
    }


def test_hardcoded_match_records_nothing():
    """Only override matches are tracked — hardcoded ones need no attribution."""
    _add("reform_make_it_easier", "reformulation", "make it easier")
    assert chat_svc._is_reformulation_request("please simplify that")
    assert chat_svc._current_override_match() is None


def test_first_match_wins_across_predicates():
    _add("intent_my_soil", "agricultural_intent", "my soil")
    _add("reform_more_readable", "reformulation", "more readable")
    message = "my soil answer, make it more readable"
    assert chat_svc._has_agricultural_intent(message)
    assert chat_svc._is_reformulation_request(message)
    assert chat_svc._current_override_match()["pattern_id"] == "intent_my_soil"


def test_reset_clears_the_previous_turns_match():
    """FastAPI reuses threadpool threads, so a stale match must never leak."""
    _add("reform_make_it_easier", "reformulation", "make it easier")
    chat_svc._is_reformulation_request("make it easier")
    assert chat_svc._current_override_match() is not None
    chat_svc._reset_override_match()
    assert chat_svc._current_override_match() is None


def test_record_pattern_hit_persists_the_match():
    _add("reform_make_it_easier", "reformulation", "make it easier")
    chat_svc._is_reformulation_request("please make it easier")

    req = type("Req", (), {"conversation_id": "conv-1"})()
    chat_svc._record_pattern_hit(
        chat_svc._current_override_match(), req, "please make it easier"
    )

    item = store_mod.find_active(store_mod.load(), "reform_make_it_easier")
    assert item["hit_count"] == 1
    assert item["last_hit"] is not None


def test_record_pattern_hit_is_a_noop_without_a_match():
    _add("reform_make_it_easier", "reformulation", "make it easier")
    req = type("Req", (), {"conversation_id": "conv-1"})()
    chat_svc._record_pattern_hit(None, req, "anything")
    assert store_mod.load()["hits"] == []


def test_broken_override_file_does_not_break_routing(monkeypatch):
    """A corrupt file must degrade to hardcoded-only, never raise into chat()."""
    monkeypatch.setattr(
        store_mod, "compile_overrides", lambda: (_ for _ in ()).throw(OSError("boom"))
    )
    chat_svc._pattern_overrides = None
    assert chat_svc._is_reformulation_request("please simplify that")
    assert not chat_svc._is_reformulation_request("make it easier")
