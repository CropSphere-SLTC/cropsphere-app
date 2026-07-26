"""Unit tests for app.admin.services.tuning_validation_service.

Firestore reads are replaced with hand-built document lists, so these cover the
metric maths, the direction-aware comparison, the promote/extend/remove
decision table, and the per-adjustment analytics payload — no database, no
network, no background threads left running.
"""

from datetime import datetime, timedelta, timezone
from unittest.mock import patch

import pytest

from app.admin.services import tuning_validation_service as tv
from app.user.services import prompt_tuning_store as store

_CONFIG = {
    "min_sample_size": 20,
    "trial_period_days": 14,
    "trial_extension_days": 7,
    "trash_retention_days": 14,
}

_NOW = datetime.now(timezone.utc)


@pytest.fixture(autouse=True)
def _tmp_store(tmp_path):
    """Isolate the store file, stub the config, and silence the Firestore
    audit mirror, notifications, and the chatbot cache reload."""
    with patch.object(
        store, "TUNING_PATH", tmp_path / "prompt_tuning.json"
    ), patch.object(store, "_DATA_DIR", tmp_path), patch.object(
        store, "_LOCK_PATH", tmp_path / "lock"
    ), patch.object(
        store, "_mirror_audit"
    ), patch(
        "app.admin.services.system_config_service.get_prompt_tuning_config",
        return_value=_CONFIG,
    ), patch.object(
        tv, "_notify"
    ), patch.object(
        tv, "_reload_chatbot_cache"
    ):
        yield tmp_path


@pytest.fixture(autouse=True)
def _reset_throttle():
    """maybe_run_validations throttles per module; reset between tests."""
    tv._last_run_at = 0.0
    tv._running = False
    yield
    tv._last_run_at = 0.0
    tv._running = False


def _apply(
    adj_id="language_complexity", metric="beginner_satisfaction_rate", baseline=0.45
):
    store.apply_adjustments(
        [
            {
                "id": adj_id,
                "dimension": "language_complexity",
                "trigger": "78% beginner",
                "instruction": "Keep it simple.",
                "recommended": True,
                "validation_metric": metric,
                "baseline_value": baseline,
            }
        ],
        [adj_id],
        "admin1",
        _CONFIG,
    )


def _expire_trial(adj_id: str, days_ago: int = 1):
    """Backdate an adjustment so its trial has ended."""
    data = store.load()
    adj = store.find_active(data, adj_id)
    adj["applied_at"] = (_NOW - timedelta(days=15)).isoformat()
    adj["trial_ends_at"] = (_NOW - timedelta(days=days_ago)).isoformat()
    store.save(data)


# ── Metric measurement ────────────────────────────────────────────────────────


def _fb(text, vote):
    return {"message_text": text, "feedback": vote}


def test_satisfaction_rate_by_question_type():
    docs = [_fb("what is the carrot price", "up")] * 6 + [
        _fb("what is the carrot price", "down")
    ] * 2
    with patch.object(tv, "_fetch", return_value=docs):
        out = tv.measure_metric("satisfaction_rate_price", None, _NOW)
    assert out == pytest.approx(6 / 8)


def test_satisfaction_rate_ignores_other_question_types():
    docs = [_fb("what is the carrot price", "up")] * 5 + [
        _fb("carrot yield in Badulla", "down")
    ] * 5
    with patch.object(tv, "_fetch", return_value=docs):
        assert tv.measure_metric("satisfaction_rate_price", None, _NOW) == 1.0


def test_metric_below_minimum_denominator_is_unmeasurable():
    """None means 'can't measure', never 'measured zero' — the caller extends
    the trial instead of judging it."""
    with patch.object(tv, "_fetch", return_value=[_fb("price?", "down")] * 2):
        assert tv.measure_metric("satisfaction_rate_price", None, _NOW) is None


def test_satisfaction_rate_by_knowledge_level():
    docs = [_fb("what is yield", "up")] * 5 + [_fb("what is yield", "down")] * 5
    with patch.object(tv, "_fetch", return_value=docs):
        out = tv.measure_metric("beginner_satisfaction_rate", None, _NOW)
    assert out == pytest.approx(0.5)


def test_votes_that_are_neither_up_nor_down_are_ignored():
    docs = [_fb("price?", "up")] * 5 + [_fb("price?", "maybe")] * 50
    with patch.object(tv, "_fetch", return_value=docs):
        assert tv.measure_metric("satisfaction_rate_price", None, _NOW) == 1.0


def test_refusal_rate_scoped_to_its_target():
    docs = [
        {"crop_mentioned": "Okra", "response_type": "refusal"},
        {"crop_mentioned": "Okra", "response_type": "refusal"},
        {"crop_mentioned": "Okra", "response_type": "answer"},
        {"crop_mentioned": "Okra", "response_type": "near_miss"},
        {"crop_mentioned": "Okra", "response_type": "answer"},
        {"crop_mentioned": "Carrot", "response_type": "refusal"},
    ]
    with patch.object(tv, "_fetch", return_value=docs):
        assert tv.measure_metric("refusal_rate", "Okra", _NOW) == pytest.approx(3 / 5)


def test_refusal_rate_matches_target_case_insensitively_on_district():
    docs = [{"district_mentioned": "Galle", "response_type": "refusal"}] * 5
    with patch.object(tv, "_fetch", return_value=docs):
        assert tv.measure_metric("refusal_rate", "galle", _NOW) == 1.0


def test_chip_tap_rate():
    docs = [{"followup_chip_tapped": True}] * 3 + [{"followup_chip_tapped": False}] * 7
    with patch.object(tv, "_fetch", return_value=docs):
        assert tv.measure_metric("chip_tap_rate", None, _NOW) == pytest.approx(0.3)


def test_avg_session_length():
    docs = [{"session_message_count": n} for n in (1, 2, 3, 4, 5)]
    with patch.object(tv, "_fetch", return_value=docs):
        assert tv.measure_metric("avg_session_length", None, _NOW) == 3.0


def test_earnings_followup_rate_uses_the_yield_price_proxy():
    docs = (
        [{"question_type": "yield"}] * 6
        + [{"question_type": "price"}] * 4
        + [{"question_type": "earnings"}] * 2
    )
    with patch.object(tv, "_fetch", return_value=docs):
        assert tv.measure_metric("earnings_followup_rate", None, _NOW) == pytest.approx(
            2 / 10
        )


def test_unknown_metric_returns_none():
    assert tv.measure_metric("made_up_metric", None, _NOW) is None


def test_measurement_never_raises_on_firestore_failure():
    with patch.object(tv, "_fetch", side_effect=RuntimeError("db down")):
        assert tv.measure_metric("chip_tap_rate", None, _NOW) is None


def test_count_interactions_returns_zero_on_failure():
    with patch.object(tv, "_fetch", side_effect=RuntimeError("db down")):
        assert tv.count_interactions(_NOW) == 0


# ── Comparison ────────────────────────────────────────────────────────────────


def test_higher_is_better_improvement():
    out = tv.compare("beginner_satisfaction_rate", 0.45, 0.68)
    assert out["trend"] == "improving" and out["relative_change"] > 0


def test_higher_is_better_decline():
    out = tv.compare("beginner_satisfaction_rate", 0.60, 0.40)
    assert out["trend"] == "worsened" and out["relative_change"] < 0


def test_small_movement_is_stable():
    out = tv.compare("beginner_satisfaction_rate", 0.50, 0.49)
    assert out["trend"] == "stable"


def test_refusal_rate_is_lower_is_better():
    """A refusal rate falling from 0.4 to 0.2 is an improvement, and
    relative_change is reported as positive so 'positive = better' holds."""
    out = tv.compare("refusal_rate", 0.4, 0.2)
    assert out["direction"] == "lower_is_better"
    assert out["trend"] == "improving" and out["relative_change"] > 0


def test_refusal_rate_rising_is_a_decline():
    assert tv.compare("refusal_rate", 0.2, 0.5)["trend"] == "worsened"


def test_zero_baseline_uses_absolute_movement():
    assert tv.compare("chip_tap_rate", 0.0, 0.0)["trend"] == "stable"
    assert tv.compare("chip_tap_rate", 0.0, 0.4)["trend"] == "improving"


def test_missing_values_are_unknown():
    assert tv.compare("chip_tap_rate", None, 0.4)["trend"] == "unknown"
    assert tv.compare("chip_tap_rate", 0.4, None)["trend"] == "unknown"


# ── Due detection ─────────────────────────────────────────────────────────────


def test_has_due_trials_true_when_past_end_date():
    _apply()
    _expire_trial("language_complexity")
    assert tv.has_due_trials(store.load()) is True


def test_has_due_trials_false_mid_trial():
    _apply()
    assert tv.has_due_trials(store.load()) is False


def test_has_due_trials_false_for_unmeasurable_adjustment():
    """trial_ends_at=None never comes due — it waits for an admin decision."""
    _apply(metric=None, baseline=None)
    assert tv.has_due_trials(store.load()) is False


def test_has_due_trials_ignores_permanent():
    _apply()
    _expire_trial("language_complexity")
    store.promote("language_complexity", "super1")
    assert tv.has_due_trials(store.load()) is False


def test_has_due_trials_tolerates_empty_and_none():
    assert tv.has_due_trials({}) is False
    assert tv.has_due_trials(None) is False


def test_maybe_run_does_nothing_when_nothing_is_due():
    _apply()
    with patch.object(tv, "run_due_validations") as run:
        assert tv.maybe_run_validations(store.load()) is False
    run.assert_not_called()


def test_maybe_run_is_throttled():
    _apply()
    _expire_trial("language_complexity")
    data = store.load()
    with patch.object(tv, "run_due_validations"):
        first = tv.maybe_run_validations(data)
        second = tv.maybe_run_validations(data)
    assert first is True and second is False


# ── The decision table ────────────────────────────────────────────────────────


def _run(sample: int, current):
    """Run the pass with a stubbed sample size and measured metric value."""
    with patch.object(tv, "count_interactions", return_value=sample), patch.object(
        tv, "measure_metric", return_value=current
    ):
        return tv.run_due_validations()


def test_improved_metric_is_promoted_to_permanent():
    _apply()
    _expire_trial("language_complexity")
    out = _run(sample=50, current=0.68)
    assert out["promoted"] == ["language_complexity"]
    assert store.load()["active"][0]["status"] == "permanent"


def test_stable_metric_is_also_promoted():
    """Step 4 treats 'stable within 5%' as a pass, not a failure."""
    _apply()
    _expire_trial("language_complexity")
    out = _run(sample=50, current=0.46)
    assert out["promoted"] == ["language_complexity"]


def test_declined_metric_is_auto_removed_to_trash():
    _apply()
    _expire_trial("language_complexity")
    out = _run(sample=50, current=0.20)
    assert out["removed"] == ["language_complexity"]
    data = store.load()
    assert data["active"] == []
    item = data["trash"][0]
    assert item["reason"] == "auto_validation_failed"
    assert item["trashed_by"] == "system"
    assert "declined from 0.45 to 0.20" in item["comment"]


def test_auto_removal_sends_a_notification():
    _apply()
    _expire_trial("language_complexity")
    with patch.object(tv, "_notify") as notify:
        _run(sample=50, current=0.20)
    assert notify.call_count == 1
    assert notify.call_args[0][1] == "auto_removed"
    assert "declined" in notify.call_args[0][2]


def test_thin_sample_extends_the_trial():
    _apply()
    _expire_trial("language_complexity")
    out = _run(sample=5, current=0.68)
    assert out["extended"] == ["language_complexity"]
    adj = store.load()["active"][0]
    assert adj["status"] == "trial" and adj["extensions_used"] == 1


def test_trial_is_flagged_after_max_extensions():
    _apply()
    for _ in range(store.MAX_EXTENSIONS):
        _expire_trial("language_complexity")
        _run(sample=5, current=0.68)
    _expire_trial("language_complexity")
    out = _run(sample=5, current=0.68)
    assert out["flagged"] == ["language_complexity"]
    adj = store.load()["active"][0]
    # Flagged, not removed — it stays live pending an admin decision.
    assert adj["status"] == "trial" and adj["needs_attention"] is True


def test_unmeasurable_metric_extends_then_flags_but_never_promotes():
    """Enough interactions overall, but the metric itself has no denominator."""
    _apply()
    _expire_trial("language_complexity")
    out = _run(sample=50, current=None)
    assert out["extended"] == ["language_complexity"]
    assert out["promoted"] == [] and out["removed"] == []


def test_adjustment_without_a_metric_is_never_auto_promoted():
    """Step 10 — belt and braces: even if a due date somehow appears on an
    unmeasurable adjustment, it is flagged rather than promoted."""
    _apply(metric=None, baseline=None)
    data = store.load()
    adj = store.find_active(data, "language_complexity")
    adj["applied_at"] = (_NOW - timedelta(days=15)).isoformat()
    adj["trial_ends_at"] = (_NOW - timedelta(days=1)).isoformat()
    store.save(data)

    out = _run(sample=50, current=0.9)
    assert out["flagged"] == ["language_complexity"]
    assert out["promoted"] == []
    assert store.load()["active"][0]["status"] == "trial"


def test_pass_purges_expired_trash_in_the_same_sweep():
    _apply()
    store.trash("language_complexity", "super1", "manual_removal", "x")
    data = store.load()
    data["trash"][0]["retention_until"] = (_NOW - timedelta(days=1)).isoformat()
    store.save(data)
    out = _run(sample=0, current=None)
    assert out["purged"] == ["language_complexity"]
    assert store.load()["trash"] == []


def test_pass_skips_trials_that_are_not_due():
    _apply()
    out = _run(sample=50, current=0.9)
    assert out["promoted"] == [] and out["extended"] == []
    assert store.load()["active"][0]["status"] == "trial"


def test_one_bad_adjustment_does_not_stall_the_rest():
    _apply("language_complexity")
    _apply("chip_high", metric="chip_tap_rate", baseline=0.6)
    _expire_trial("language_complexity")
    _expire_trial("chip_high")

    calls = {"n": 0}

    def flaky(*_a, **_k):
        calls["n"] += 1
        if calls["n"] == 1:
            raise RuntimeError("boom")
        return 50

    with patch.object(tv, "count_interactions", side_effect=flaky), patch.object(
        tv, "measure_metric", return_value=0.9
    ):
        out = tv.run_due_validations()
    assert out["promoted"] == ["chip_high"]


# ── Per-adjustment analytics ──────────────────────────────────────────────────


def test_analytics_for_unknown_id_is_none():
    assert tv.get_adjustment_analytics("nope") is None


def test_analytics_reports_trial_progress_and_sample():
    _apply()
    with patch.object(tv, "count_interactions", return_value=45), patch.object(
        tv, "measure_metric", return_value=0.68
    ):
        out = tv.get_adjustment_analytics("language_complexity")
    assert out["status"] == "trial"
    assert out["trial_progress"] == "Day 1 of 14"
    assert out["interactions_during_trial"] == 45
    assert out["min_sample_required"] == 20
    assert out["sample_met"] is True
    assert out["baseline"]["value"] == 0.45
    assert out["baseline"]["metric_name"] == "beginner_satisfaction_rate"
    assert out["current"]["value"] == 0.68
    assert out["current"]["trend"] == "improving"
    assert out["verdict"] == "on_track_for_permanent"


def test_analytics_verdict_when_sample_is_short():
    _apply()
    with patch.object(tv, "count_interactions", return_value=3), patch.object(
        tv, "measure_metric", return_value=0.68
    ):
        out = tv.get_adjustment_analytics("language_complexity")
    assert out["sample_met"] is False
    assert out["verdict"] == "insufficient_data"


def test_analytics_verdict_when_at_risk():
    _apply()
    with patch.object(tv, "count_interactions", return_value=45), patch.object(
        tv, "measure_metric", return_value=0.10
    ):
        out = tv.get_adjustment_analytics("language_complexity")
    assert out["current"]["trend"] == "worsened"
    assert out["verdict"] == "at_risk_of_removal"


def test_analytics_for_unmeasurable_adjustment():
    _apply(metric=None, baseline=None)
    with patch.object(tv, "count_interactions", return_value=45):
        out = tv.get_adjustment_analytics("language_complexity")
    assert out["verdict"] == "not_measurable"
    assert out["current"]["value"] is None
    assert "awaiting manual decision" in out["trial_progress"]


def test_analytics_for_permanent_adjustment():
    _apply()
    store.promote("language_complexity", "super1")
    with patch.object(tv, "count_interactions", return_value=45), patch.object(
        tv, "measure_metric", return_value=0.68
    ):
        out = tv.get_adjustment_analytics("language_complexity")
    assert out["status"] == "permanent"
    assert out["verdict"] == "validated_permanent"
    assert out["trial_progress"] == "Permanent"


def test_analytics_for_a_trashed_adjustment_freezes_its_window():
    """Measuring 'now' on a removed adjustment would credit it with traffic it
    was never live for, so the window closes at trashed_at."""
    _apply()
    store.trash("language_complexity", "system", "auto_validation_failed", "declined")
    with patch.object(tv, "count_interactions", return_value=45) as count, patch.object(
        tv, "measure_metric", return_value=0.2
    ):
        out = tv.get_adjustment_analytics("language_complexity")
    assert out["status"] == "auto_removed"
    assert out["verdict"] == "removed"
    assert out["trashed"]["reason"] == "auto_validation_failed"
    assert out["trashed"]["can_restore"] is True
    trashed_at = store.parse_iso(out["trashed"]["trashed_at"])
    assert count.call_args[0][1] == trashed_at


def test_analytics_includes_the_audit_history():
    _apply()
    store.promote("language_complexity", "super1")
    with patch.object(tv, "count_interactions", return_value=45), patch.object(
        tv, "measure_metric", return_value=0.68
    ):
        out = tv.get_adjustment_analytics("language_complexity")
    assert [e["action"] for e in out["history"]] == ["applied", "promoted"]


def test_analytics_survives_an_unmeasurable_current_value():
    _apply()
    with patch.object(tv, "count_interactions", return_value=45), patch.object(
        tv, "measure_metric", return_value=None
    ):
        out = tv.get_adjustment_analytics("language_complexity")
    assert out["current"]["value"] is None
    assert out["current"]["trend"] == "unknown"
    assert out["verdict"] == "insufficient_data"
