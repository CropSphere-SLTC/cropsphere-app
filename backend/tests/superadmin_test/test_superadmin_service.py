"""Unit tests for app.super_admin.services.superadmin_service.

Calls the service functions directly (no HTTP layer). Firestore and settings
are mocked so no real infrastructure is required.
"""

from datetime import datetime, timezone
from unittest.mock import MagicMock, patch

import pytest
from fastapi import HTTPException

from app.super_admin.services import superadmin_service


def _mock_doc(data: dict):
    """Build a fake Firestore document snapshot with .to_dict() and .reference."""
    doc = MagicMock()
    doc.to_dict.return_value = data
    return doc


@pytest.fixture(autouse=True)
def reset_runtime_config():
    """Reset the module-level _runtime_config before/after each test so
    tests don't leak state into each other."""
    original = dict(superadmin_service._runtime_config)
    yield
    superadmin_service._runtime_config.clear()
    superadmin_service._runtime_config.update(original)


# ═══════════════════════════════════════════════════════════════════════════
# get_config
# ═══════════════════════════════════════════════════════════════════════════


def test_get_config_returns_runtime_values_and_enable_flag():
    with patch(
        "app.super_admin.services.superadmin_service.get_settings"
    ) as mock_settings:
        mock_settings.return_value.ENABLE_ADMIN_API = True
        result = superadmin_service.get_config()

    assert result["admin_rate_limit_per_minute"] == 10
    assert result["superadmin_rate_limit_per_minute"] == 10
    assert result["enable_admin_api"] is True


def test_get_config_reflects_enable_admin_api_false():
    with patch(
        "app.super_admin.services.superadmin_service.get_settings"
    ) as mock_settings:
        mock_settings.return_value.ENABLE_ADMIN_API = False
        result = superadmin_service.get_config()

    assert result["enable_admin_api"] is False


# ═══════════════════════════════════════════════════════════════════════════
# update_config
# ═══════════════════════════════════════════════════════════════════════════


def test_update_config_updates_admin_limit_only():
    with patch(
        "app.super_admin.services.superadmin_service.get_settings"
    ) as mock_settings:
        mock_settings.return_value.ENABLE_ADMIN_API = True
        result = superadmin_service.update_config(
            admin_rate_limit_per_minute=25, superadmin_rate_limit_per_minute=None
        )

    assert result["admin_rate_limit_per_minute"] == 25
    assert result["superadmin_rate_limit_per_minute"] == 10  # unchanged default


def test_update_config_updates_superadmin_limit_only():
    with patch(
        "app.super_admin.services.superadmin_service.get_settings"
    ) as mock_settings:
        mock_settings.return_value.ENABLE_ADMIN_API = True
        result = superadmin_service.update_config(
            admin_rate_limit_per_minute=None, superadmin_rate_limit_per_minute=50
        )

    assert result["superadmin_rate_limit_per_minute"] == 50
    assert result["admin_rate_limit_per_minute"] == 10  # unchanged default


def test_update_config_updates_both_limits():
    with patch(
        "app.super_admin.services.superadmin_service.get_settings"
    ) as mock_settings:
        mock_settings.return_value.ENABLE_ADMIN_API = True
        result = superadmin_service.update_config(
            admin_rate_limit_per_minute=15, superadmin_rate_limit_per_minute=20
        )

    assert result["admin_rate_limit_per_minute"] == 15
    assert result["superadmin_rate_limit_per_minute"] == 20


def test_update_config_with_no_args_leaves_values_unchanged():
    with patch(
        "app.super_admin.services.superadmin_service.get_settings"
    ) as mock_settings:
        mock_settings.return_value.ENABLE_ADMIN_API = True
        result = superadmin_service.update_config()

    assert result["admin_rate_limit_per_minute"] == 10
    assert result["superadmin_rate_limit_per_minute"] == 10


# ═══════════════════════════════════════════════════════════════════════════
# get_all_audit_logs
# ═══════════════════════════════════════════════════════════════════════════


def test_get_all_audit_logs_returns_unfiltered_logs():
    logs_data = [
        {"actor_role": "admin", "action": "ban_user"},
        {"actor_role": "superadmin", "action": "delete_user"},
    ]
    mock_query = MagicMock()
    mock_query.stream.return_value = [_mock_doc(d) for d in logs_data]
    mock_db = MagicMock()
    mock_db.collection.return_value.order_by.return_value.limit.return_value = (
        mock_query
    )

    with patch("app.utils.firestore.get_db", return_value=mock_db):
        result = superadmin_service.get_all_audit_logs(50)

    # No filtering — both admin and superadmin actions are present
    actor_roles = [log["actor_role"] for log in result["logs"]]
    assert "admin" in actor_roles
    assert "superadmin" in actor_roles
    assert result["total"] == 2


def test_get_all_audit_logs_converts_timestamp_to_isoformat_string():
    ts = datetime(2026, 1, 15, 10, 30, tzinfo=timezone.utc)
    mock_query = MagicMock()
    mock_query.stream.return_value = [
        _mock_doc(
            {"actor_role": "superadmin", "action": "delete_user", "timestamp": ts}
        )
    ]
    mock_db = MagicMock()
    mock_db.collection.return_value.order_by.return_value.limit.return_value = (
        mock_query
    )

    with patch("app.utils.firestore.get_db", return_value=mock_db):
        result = superadmin_service.get_all_audit_logs(50)

    assert result["logs"][0]["timestamp"] == ts.isoformat()


def test_get_all_audit_logs_firestore_failure_raises_500():
    with patch("app.utils.firestore.get_db", side_effect=RuntimeError("down")):
        with pytest.raises(HTTPException) as exc_info:
            superadmin_service.get_all_audit_logs(50)
    assert exc_info.value.status_code == 500


def test_get_all_audit_logs_includes_actor_and_target_emails():
    """The superadmin trail must name people the same way the admin one does —
    both screens render the same AuditLog model."""
    mock_query = MagicMock()
    mock_query.stream.return_value = [
        _mock_doc(
            {
                "actor_uid": "s1",
                "actor_role": "superadmin",
                "action": "delete_user",
                "target_uid": "u1",
            }
        )
    ]
    mock_db = MagicMock()
    mock_db.collection.return_value.order_by.return_value.limit.return_value = (
        mock_query
    )

    def _document(uid):
        ref = MagicMock()
        ref.uid = uid
        return ref

    users = {
        "s1": {"uid": "s1", "email": "root@x.com"},
        "u1": {"uid": "u1", "email": "farmer@x.com"},
    }

    def _snapshot(uid):
        snap = MagicMock()
        snap.id = uid
        snap.to_dict.return_value = users.get(uid)
        return snap

    mock_db.collection.return_value.document.side_effect = _document
    mock_db.get_all.side_effect = lambda refs: [_snapshot(r.uid) for r in refs]

    with patch("app.utils.firestore.get_db", return_value=mock_db):
        result = superadmin_service.get_all_audit_logs(50)

    assert result["logs"][0]["actor_email"] == "root@x.com"
    assert result["logs"][0]["target_email"] == "farmer@x.com"


# ═══════════════════════════════════════════════════════════════════════════
# cleanup_old_sessions
# ═══════════════════════════════════════════════════════════════════════════


def test_cleanup_old_sessions_deletes_stale_sessions():
    stale_docs = [_mock_doc({}), _mock_doc({})]
    mock_where = MagicMock()
    mock_where.stream.return_value = stale_docs
    mock_db = MagicMock()
    mock_db.collection.return_value.where.return_value = mock_where

    with patch("app.utils.firestore.get_db", return_value=mock_db):
        result = superadmin_service.cleanup_old_sessions()

    assert result["deleted"] == 2
    assert "cutoff" in result
    for doc in stale_docs:
        doc.reference.delete.assert_called_once()


def test_cleanup_old_sessions_no_stale_sessions_returns_zero():
    mock_where = MagicMock()
    mock_where.stream.return_value = []
    mock_db = MagicMock()
    mock_db.collection.return_value.where.return_value = mock_where

    with patch("app.utils.firestore.get_db", return_value=mock_db):
        result = superadmin_service.cleanup_old_sessions()

    assert result["deleted"] == 0


def test_cleanup_old_sessions_firestore_failure_raises_500():
    with patch("app.utils.firestore.get_db", side_effect=RuntimeError("down")):
        with pytest.raises(HTTPException) as exc_info:
            superadmin_service.cleanup_old_sessions()
    assert exc_info.value.status_code == 500
