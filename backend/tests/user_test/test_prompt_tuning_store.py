"""Unit tests for app.user.services.prompt_tuning_store.

Covers the full adjustment lifecycle (apply → trial → permanent / trash →
restore / delete), the v1→v2 schema migration, the audit trail, and the
graceful handling of corrupt files. The store is pointed at a tmp_path and the
Firestore audit mirror is stubbed, so nothing touches a real database.
"""

import json
from datetime import datetime, timedelta, timezone
from unittest.mock import patch

import pytest

from app.user.services import prompt_tuning_store as store

# Captured before the autouse fixture stubs it, so one test can exercise the
# real Firestore-mirroring path.
_REAL_MIRROR = store._mirror_audit

_CONFIG = {
    "min_sample_size": 20,
    "trial_period_days": 14,
    "trial_extension_days": 7,
    "trash_retention_days": 14,
}


@pytest.fixture(autouse=True)
def _tmp_store(tmp_path):
    """Isolate the store on disk and stub the Firestore audit mirror."""
    with patch.object(
        store, "TUNING_PATH", tmp_path / "prompt_tuning.json"
    ), patch.object(store, "_DATA_DIR", tmp_path), patch.object(
        store, "_LOCK_PATH", tmp_path / "prompt_tuning.lock"
    ), patch.object(
        store, "_mirror_audit"
    ), patch(
        "app.admin.services.system_config_service.get_prompt_tuning_config",
        return_value=_CONFIG,
    ):
        yield tmp_path / "prompt_tuning.json"


def _proposal(
    adj_id="language_complexity", metric="beginner_satisfaction_rate", baseline=0.45
):
    return {
        "id": adj_id,
        "dimension": "language_complexity",
        "trigger": "78% beginner users",
        "instruction": "Keep it simple.",
        "recommended": True,
        "validation_metric": metric,
        "baseline_value": baseline,
    }


def _apply(*proposals, actor="admin1", ids=None):
    proposals = list(proposals) or [_proposal()]
    ids = ids if ids is not None else [p["id"] for p in proposals]
    return store.apply_adjustments(proposals, ids, actor, _CONFIG)


# ── Load / save ───────────────────────────────────────────────────────────────


def test_load_missing_file_returns_empty_store():
    out = store.load()
    assert out["active"] == [] and out["trash"] == [] and out["audit_log"] == []


def test_load_corrupt_file_returns_empty_store(_tmp_store):
    _tmp_store.write_text("{not json")
    assert store.load()["active"] == []


def test_load_non_dict_file_returns_empty_store(_tmp_store):
    _tmp_store.write_text("[1, 2, 3]")
    assert store.load()["active"] == []


def test_load_coerces_non_list_sections(_tmp_store):
    _tmp_store.write_text(json.dumps({"version": 2, "active": "nope", "trash": None}))
    out = store.load()
    assert out["active"] == [] and out["trash"] == []


def test_save_is_atomic_and_leaves_no_tmp_files(_tmp_store, tmp_path):
    _apply()
    assert _tmp_store.exists()
    assert [p.name for p in tmp_path.glob("*.tmp")] == []


# ── v1 migration ──────────────────────────────────────────────────────────────


def test_v1_file_migrates_to_trial_without_a_clock(_tmp_store):
    """v1 adjustments have no baseline, so they can never be auto-validated —
    they must land as live trials awaiting a manual decision, not be promoted
    or removed on data we never captured."""
    _tmp_store.write_text(
        json.dumps(
            {
                "updated_at": "2026-07-01T00:00:00+00:00",
                "period_days": 7,
                "sample_size": 51,
                "adjustments": [{"id": "earnings_offer", "instruction": "x"}],
            }
        )
    )
    out = store.load()
    assert len(out["active"]) == 1
    adj = out["active"][0]
    assert adj["status"] == "trial"
    assert adj["trial_ends_at"] is None
    assert adj["applied_at"] == "2026-07-01T00:00:00+00:00"
    # Still live, so the chatbot keeps injecting it across the upgrade.
    assert store.live_adjustments(out) == [adj]


def test_v1_migration_skips_entries_without_an_id(_tmp_store):
    _tmp_store.write_text(
        json.dumps({"adjustments": [{"instruction": "x"}, "junk", {"id": "ok"}]})
    )
    assert [a["id"] for a in store.load()["active"]] == ["ok"]


# ── Apply ─────────────────────────────────────────────────────────────────────


def test_apply_only_persists_approved_ids():
    result = _apply(
        _proposal("language_complexity"),
        _proposal("chip_high"),
        ids=["chip_high"],
    )
    assert result["applied"] == ["chip_high"]
    assert [a["id"] for a in store.load()["active"]] == ["chip_high"]


def test_apply_sets_trial_fields():
    _apply()
    adj = store.load()["active"][0]
    assert adj["status"] == "trial"
    assert adj["baseline_value"] == 0.45
    assert adj["extensions_used"] == 0
    assert adj["validated_at"] is None
    ends = store.parse_iso(adj["trial_ends_at"])
    applied = store.parse_iso(adj["applied_at"])
    assert (ends - applied).days == _CONFIG["trial_period_days"]


def test_apply_honours_trial_period_override():
    store.apply_adjustments(
        [_proposal()], ["language_complexity"], "admin1", _CONFIG, trial_period_days=3
    )
    adj = store.load()["active"][0]
    assert (
        store.parse_iso(adj["trial_ends_at"]) - store.parse_iso(adj["applied_at"])
    ).days == 3


@pytest.mark.parametrize(
    "metric,baseline",
    [(None, 0.4), ("refusal_rate", None), (None, None)],
)
def test_apply_without_a_measurable_metric_gets_no_clock(metric, baseline):
    """Step 10 — never auto-promote what the system can't measure."""
    _apply(_proposal("x", metric=metric, baseline=baseline))
    adj = store.load()["active"][0]
    assert adj["status"] == "trial" and adj["trial_ends_at"] is None


def test_apply_skips_already_active_id():
    _apply()
    result = _apply()
    assert result["applied"] == [] and result["skipped"] == ["language_complexity"]
    assert len(store.load()["active"]) == 1


def test_apply_writes_an_audit_entry():
    _apply()
    entries = store.adjustment_history(store.load(), "language_complexity")
    assert [e["action"] for e in entries] == ["applied"]
    assert entries[0]["performed_by"] == "admin1"
    assert entries[0]["details"]["after_status"] == "trial"


# ── Promote ───────────────────────────────────────────────────────────────────


def test_promote_marks_permanent_and_audits():
    _apply()
    result = store.promote("language_complexity", "super1")
    assert result["ok"]
    adj = store.load()["active"][0]
    assert adj["status"] == "permanent" and adj["validated_at"]
    assert "promoted" in [
        e["action"]
        for e in store.adjustment_history(store.load(), "language_complexity")
    ]


def test_promote_unknown_id_returns_not_found():
    assert store.promote("nope", "super1")["error"] == "not_found"


def test_promote_twice_reports_already_permanent():
    _apply()
    store.promote("language_complexity", "super1")
    assert (
        store.promote("language_complexity", "super1")["error"] == "already_permanent"
    )


def test_permanent_adjustments_stay_live():
    _apply()
    store.promote("language_complexity", "super1")
    assert [a["id"] for a in store.live_adjustments()] == ["language_complexity"]


# ── Trash ─────────────────────────────────────────────────────────────────────


def test_trash_moves_out_of_active_with_retention():
    _apply()
    result = store.trash(
        "language_complexity", "super1", "manual_removal", "not helping"
    )
    assert result["ok"]
    data = store.load()
    assert data["active"] == []
    item = data["trash"][0]
    assert item["reason"] == "manual_removal"
    assert item["comment"] == "not helping"
    assert item["trashed_by"] == "super1"
    assert item["can_restore"] is True
    days = (
        store.parse_iso(item["retention_until"]) - store.parse_iso(item["trashed_at"])
    ).days
    assert days == _CONFIG["trash_retention_days"]


def test_trashed_adjustment_is_not_live():
    _apply()
    store.trash("language_complexity", "super1", "manual_removal", "x")
    assert store.live_adjustments() == []


def test_auto_removal_uses_the_auto_removed_action_and_status():
    _apply()
    store.trash("language_complexity", "system", "auto_validation_failed", "declined")
    data = store.load()
    assert data["trash"][0]["adjustment"]["status"] == "auto_removed"
    assert "auto_removed" in [
        e["action"] for e in store.adjustment_history(data, "language_complexity")
    ]


def test_manual_removal_uses_the_manually_removed_action():
    _apply()
    store.trash("language_complexity", "super1", "manual_removal", "because")
    actions = [
        e["action"]
        for e in store.adjustment_history(store.load(), "language_complexity")
    ]
    assert "manually_removed" in actions


def test_trash_unknown_id_returns_not_found():
    assert store.trash("nope", "super1", "manual_removal", "x")["error"] == "not_found"


def test_clear_all_trashes_every_active_adjustment():
    _apply(_proposal("language_complexity"), _proposal("chip_high"))
    result = store.clear_all("super1")
    assert sorted(result["cleared"]) == ["chip_high", "language_complexity"]
    data = store.load()
    assert data["active"] == [] and len(data["trash"]) == 2


# ── Restore ───────────────────────────────────────────────────────────────────


def test_restore_returns_a_fresh_trial():
    _apply()
    store.promote("language_complexity", "super1")
    store.trash("language_complexity", "super1", "manual_removal", "oops")
    result = store.restore("language_complexity", "super1")
    assert result["ok"]
    adj = store.load()["active"][0]
    # Restored as trial, not back to permanent, with a brand-new clock.
    assert adj["status"] == "trial"
    assert adj["extensions_used"] == 0
    assert adj["validated_at"] is None
    assert adj["restored_at"]
    assert store.load()["trash"] == []


def test_restore_clears_the_needs_attention_flag():
    _apply()
    store.mark_needs_attention("language_complexity", "no data")
    store.trash("language_complexity", "super1", "manual_removal", "x")
    store.restore("language_complexity", "super1")
    adj = store.load()["active"][0]
    assert adj["needs_attention"] is False


def test_restore_unknown_id_returns_not_found():
    assert store.restore("nope", "super1")["error"] == "not_found"


def test_restore_conflicts_when_id_is_already_active():
    _apply()
    store.trash("language_complexity", "super1", "manual_removal", "x")
    _apply()  # re-applied from a fresh analysis while it sat in the trash
    assert store.restore("language_complexity", "super1")["error"] == "already_active"


def test_restore_audits():
    _apply()
    store.trash("language_complexity", "super1", "manual_removal", "x")
    store.restore("language_complexity", "super1")
    actions = [
        e["action"]
        for e in store.adjustment_history(store.load(), "language_complexity")
    ]
    assert "restored" in actions


# ── Retention purge ───────────────────────────────────────────────────────────


def _backdate_retention(adj_id: str, days_ago: int):
    """Rewrite a trash item's retention_until to the past."""
    data = store.load()
    item = store.find_trashed(data, adj_id)
    item["retention_until"] = (
        datetime.now(timezone.utc) - timedelta(days=days_ago)
    ).isoformat()
    store.save(data)


def test_purge_deletes_only_expired_items():
    _apply(_proposal("language_complexity"), _proposal("chip_high"))
    store.trash("language_complexity", "super1", "manual_removal", "x")
    store.trash("chip_high", "super1", "manual_removal", "y")
    _backdate_retention("language_complexity", 1)

    result = store.purge_expired_trash()
    assert result["deleted"] == ["language_complexity"]
    assert result["remaining"] == 1
    assert [t["adjustment"]["id"] for t in store.load()["trash"]] == ["chip_high"]


def test_purge_records_a_deleted_audit_entry_by_system():
    _apply()
    store.trash("language_complexity", "super1", "manual_removal", "x")
    _backdate_retention("language_complexity", 1)
    store.purge_expired_trash()
    entry = store.adjustment_history(store.load(), "language_complexity")[-1]
    assert entry["action"] == "deleted"
    assert entry["performed_by"] == "system"


def test_purge_keeps_items_with_an_unparseable_retention_date():
    """Losing an adjustment to a corrupt date is worse than keeping it."""
    _apply()
    store.trash("language_complexity", "super1", "manual_removal", "x")
    data = store.load()
    data["trash"][0]["retention_until"] = "not-a-date"
    store.save(data)
    assert store.purge_expired_trash()["deleted"] == []


def test_force_all_empties_the_trash_regardless_of_retention():
    _apply()
    store.trash("language_complexity", "super1", "manual_removal", "x")
    result = store.purge_expired_trash(actor_uid="super1", force_all=True)
    assert result["deleted"] == ["language_complexity"]
    assert store.load()["trash"] == []


# ── Trial updates (used by the validation pass) ───────────────────────────────


def test_update_trial_extends_the_clock_and_counts_extensions():
    _apply()
    before = store.parse_iso(store.load()["active"][0]["trial_ends_at"])
    store.update_trial("language_complexity", extend_days=7, note="thin sample")
    adj = store.load()["active"][0]
    assert (store.parse_iso(adj["trial_ends_at"]) - before).days == 7
    assert adj["extensions_used"] == 1


def test_update_trial_promotes_and_records_the_measurement():
    _apply()
    store.update_trial(
        "language_complexity", new_status="permanent", current_value=0.68, note="up"
    )
    adj = store.load()["active"][0]
    assert adj["status"] == "permanent"
    assert adj["last_measured_value"] == 0.68
    assert adj["validated_at"]


def test_update_trial_unknown_id_is_not_found():
    assert store.update_trial("nope")["error"] == "not_found"


def test_mark_needs_attention_keeps_it_live():
    _apply()
    store.mark_needs_attention("language_complexity", "no data after 2 extensions")
    adj = store.load()["active"][0]
    assert adj["needs_attention"] is True
    assert adj["attention_reason"] == "no data after 2 extensions"
    assert store.live_adjustments() == [adj]


# ── Audit log ─────────────────────────────────────────────────────────────────


def test_audit_log_is_capped():
    data = store.empty_store()
    data["audit_log"] = [
        {"action": "applied", "adjustment_id": f"a{i}"} for i in range(600)
    ]
    store.save(data)
    assert len(store.load()["audit_log"]) == store._AUDIT_CAP


def test_audit_comment_is_truncated():
    _apply()
    store.trash("language_complexity", "super1", "manual_removal", "x" * 900)
    entry = store.adjustment_history(store.load(), "language_complexity")[-1]
    assert len(entry["comment"]) == 500


def test_firestore_mirror_failure_does_not_break_a_transition():
    """The Firestore mirror is best-effort; the file stays the source of truth,
    so a DB outage must not stop an adjustment from being applied."""
    # Restore the real mirror (the fixture stubs it) and make Firestore fail.
    with patch.object(store, "_mirror_audit", _REAL_MIRROR), patch(
        "app.utils.firestore.admin_audit_log", side_effect=RuntimeError("db down")
    ):
        _apply()
    assert [a["id"] for a in store.load()["active"]] == ["language_complexity"]
    assert store.adjustment_history(store.load(), "language_complexity")


# ── Parsing helper ────────────────────────────────────────────────────────────


@pytest.mark.parametrize("value", [None, "", "not-a-date", 123, {}])
def test_parse_iso_rejects_junk(value):
    assert store.parse_iso(value) is None


def test_parse_iso_handles_z_suffix_and_naive_values():
    assert store.parse_iso("2026-07-14T10:00:00Z").tzinfo is not None
    assert store.parse_iso("2026-07-14T10:00:00").tzinfo == timezone.utc


# ── known_ids ─────────────────────────────────────────────────────────────────
#
# Feeds the analyzer's already_active flag, so a proposal the admin applied is
# not offered back as if it were a new finding.


def test_known_ids_empty_on_a_fresh_store():
    assert store.known_ids() == set()


def test_known_ids_reports_applied_adjustments():
    _apply()
    assert store.known_ids() == {"language_complexity"}


def test_known_ids_excludes_trashed_adjustments():
    """Removing an adjustment is how an admin retires it — if the condition
    starts triggering again that is a genuine new finding, not a repeat."""
    _apply()
    store.trash("language_complexity", "admin1", "manual_removal", "no longer needed")
    assert store.known_ids() == set()
