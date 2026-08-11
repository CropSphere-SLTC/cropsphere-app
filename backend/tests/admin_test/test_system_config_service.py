"""Unit tests for app.admin.services.system_config_service.

Firestore is mocked, so these cover the fallback-to-defaults behaviour, the
write-time bounds validation, and the read cache — no real database.
"""

from unittest.mock import MagicMock, patch

import pytest
from fastapi import HTTPException

from app.admin.services import system_config_service as cfg


@pytest.fixture(autouse=True)
def _clear_cache():
    """The module caches reads for 60s; a leaked cache would make later tests
    assert on an earlier test's stubbed document."""
    cfg.invalidate_cache()
    yield
    cfg.invalidate_cache()


def _mock_db(stored: dict | None, exists: bool = True):
    """A fake Firestore whose settings document returns `stored`."""
    snap = MagicMock()
    snap.exists = exists
    snap.to_dict.return_value = {"prompt_tuning": stored} if stored is not None else {}
    doc_ref = MagicMock()
    doc_ref.get.return_value = snap
    db = MagicMock()
    db.collection.return_value.document.return_value = doc_ref
    return db, doc_ref


# ── Reads ─────────────────────────────────────────────────────────────────────


def test_missing_document_returns_defaults():
    db, _ = _mock_db(None, exists=False)
    with patch("app.utils.firestore.get_db", return_value=db):
        assert cfg.get_prompt_tuning_config() == cfg._DEFAULTS


def test_firestore_failure_returns_defaults_and_never_raises():
    """This is read on the chat path — a DB outage must not surface there."""
    with patch("app.utils.firestore.get_db", side_effect=RuntimeError("no db")):
        assert cfg.get_prompt_tuning_config() == cfg._DEFAULTS


def test_stored_values_override_defaults():
    db, _ = _mock_db({"min_sample_size": 50, "trial_period_days": 21})
    with patch("app.utils.firestore.get_db", return_value=db):
        out = cfg.get_prompt_tuning_config()
    assert out["min_sample_size"] == 50
    assert out["trial_period_days"] == 21
    # Untouched keys still come from the defaults.
    assert out["trash_retention_days"] == cfg._DEFAULTS["trash_retention_days"]


def test_out_of_range_stored_value_falls_back_to_default():
    """The document could have been edited straight in the Firestore console,
    so reads re-validate rather than trusting what's stored."""
    db, _ = _mock_db({"trial_period_days": 9999, "min_sample_size": -3})
    with patch("app.utils.firestore.get_db", return_value=db):
        out = cfg.get_prompt_tuning_config()
    assert out["trial_period_days"] == cfg._DEFAULTS["trial_period_days"]
    assert out["min_sample_size"] == cfg._DEFAULTS["min_sample_size"]


def test_non_int_stored_value_ignored():
    db, _ = _mock_db({"min_sample_size": "20", "trial_period_days": True})
    with patch("app.utils.firestore.get_db", return_value=db):
        out = cfg.get_prompt_tuning_config()
    assert out["min_sample_size"] == cfg._DEFAULTS["min_sample_size"]
    assert out["trial_period_days"] == cfg._DEFAULTS["trial_period_days"]


def test_reads_are_cached():
    db, doc_ref = _mock_db({"min_sample_size": 33})
    with patch("app.utils.firestore.get_db", return_value=db):
        cfg.get_prompt_tuning_config()
        cfg.get_prompt_tuning_config()
    assert doc_ref.get.call_count == 1


# ── Writes ────────────────────────────────────────────────────────────────────


def test_update_merges_and_persists():
    db, doc_ref = _mock_db({"min_sample_size": 20})
    with patch("app.utils.firestore.get_db", return_value=db), patch(
        "app.utils.firestore.admin_audit_log"
    ):
        out = cfg.update_prompt_tuning_config({"trial_period_days": 30}, "super1")
    assert out["trial_period_days"] == 30
    assert out["min_sample_size"] == 20
    written = doc_ref.set.call_args[0][0]["prompt_tuning"]
    assert written["trial_period_days"] == 30


def test_update_ignores_none_values():
    """PATCH semantics: an absent field is 'don't change', not 'set to null'."""
    db, doc_ref = _mock_db({"trial_period_days": 14})
    with patch("app.utils.firestore.get_db", return_value=db), patch(
        "app.utils.firestore.admin_audit_log"
    ):
        out = cfg.update_prompt_tuning_config(
            {"trial_period_days": None, "min_sample_size": 25}, "super1"
        )
    assert out["trial_period_days"] == 14
    assert doc_ref.set.call_args[0][0]["prompt_tuning"]["min_sample_size"] == 25


def test_empty_update_does_not_write():
    db, doc_ref = _mock_db({"min_sample_size": 20})
    with patch("app.utils.firestore.get_db", return_value=db):
        cfg.update_prompt_tuning_config({}, "super1")
    doc_ref.set.assert_not_called()


@pytest.mark.parametrize(
    "updates",
    [
        {"trial_period_days": 0},
        {"trial_period_days": 91},
        {"min_sample_size": 0},
        {"trash_retention_days": 366},
        {"trial_extension_days": 31},
    ],
)
def test_out_of_bounds_update_rejected(updates):
    with pytest.raises(HTTPException) as exc:
        cfg.update_prompt_tuning_config(updates, "super1")
    assert exc.value.status_code == 400


def test_unknown_key_rejected():
    with pytest.raises(HTTPException) as exc:
        cfg.update_prompt_tuning_config({"delete_everything": 1}, "super1")
    assert exc.value.status_code == 400


def test_non_int_update_rejected():
    with pytest.raises(HTTPException) as exc:
        cfg.update_prompt_tuning_config({"min_sample_size": "20"}, "super1")
    assert exc.value.status_code == 400


def test_write_failure_raises_500():
    db, doc_ref = _mock_db({})
    doc_ref.set.side_effect = RuntimeError("write failed")
    with patch("app.utils.firestore.get_db", return_value=db):
        with pytest.raises(HTTPException) as exc:
            cfg.update_prompt_tuning_config({"min_sample_size": 25}, "super1")
    assert exc.value.status_code == 500


def test_update_invalidates_cache():
    db, doc_ref = _mock_db({"min_sample_size": 20})
    with patch("app.utils.firestore.get_db", return_value=db), patch(
        "app.utils.firestore.admin_audit_log"
    ):
        cfg.get_prompt_tuning_config()  # populates cache
        cfg.update_prompt_tuning_config({"min_sample_size": 25}, "super1")
        cfg.get_prompt_tuning_config()  # must re-read
    assert doc_ref.get.call_count >= 2


def test_update_is_audit_logged():
    db, _ = _mock_db({})
    with patch("app.utils.firestore.get_db", return_value=db), patch(
        "app.utils.firestore.admin_audit_log"
    ) as audit:
        cfg.update_prompt_tuning_config({"min_sample_size": 25}, "super1")
    assert audit.call_count == 1
    kwargs = audit.call_args.kwargs
    assert kwargs["actor_uid"] == "super1"
    assert kwargs["action"] == "prompt_tuning_config_updated"


def test_audit_failure_does_not_fail_the_update():
    db, _ = _mock_db({})
    with patch("app.utils.firestore.get_db", return_value=db), patch(
        "app.utils.firestore.admin_audit_log", side_effect=RuntimeError("boom")
    ):
        out = cfg.update_prompt_tuning_config({"min_sample_size": 25}, "super1")
    assert out["min_sample_size"] == 25
