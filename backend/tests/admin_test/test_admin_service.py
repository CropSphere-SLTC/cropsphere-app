"""Unit tests for app.admin.services.admin_service — extracted admin business logic.

Calls the service functions directly (no HTTP layer). Firestore and psutil are
mocked so no real infrastructure is required.
"""

from datetime import datetime, timezone
from unittest.mock import MagicMock, patch

import pytest
from fastapi import HTTPException

from app.admin.services import admin_service

ADMIN_ACTOR = {"uid": "admin-uid", "role": "admin"}
SUPERADMIN_ACTOR = {"uid": "super-uid", "role": "superadmin"}


def _mock_doc(data: dict):
    """Build a fake Firestore document snapshot with .to_dict()."""
    doc = MagicMock()
    doc.to_dict.return_value = data
    return doc


# ═══════════════════════════════════════════════════════════════════════════
# list_users
# ═══════════════════════════════════════════════════════════════════════════


def test_list_users_admin_hides_superadmin_accounts():
    users_data = [
        {"uid": "u1", "email": "a@x.com", "role": "user", "is_banned": False},
        {"uid": "u2", "email": "b@x.com", "role": "admin", "is_banned": False},
        {"uid": "u3", "email": "c@x.com", "role": "superadmin", "is_banned": False},
    ]
    mock_db = MagicMock()
    mock_db.collection.return_value.stream.return_value = [
        _mock_doc(d) for d in users_data
    ]

    with patch("app.utils.firestore.get_db", return_value=mock_db):
        result = admin_service.list_users(ADMIN_ACTOR)

    uids = [u["uid"] for u in result["users"]]
    assert "u3" not in uids
    assert result["total"] == 2


def test_list_users_superadmin_sees_everyone():
    users_data = [
        {"uid": "u1", "role": "user"},
        {"uid": "u2", "role": "admin"},
        {"uid": "u3", "role": "superadmin"},
    ]
    mock_db = MagicMock()
    mock_db.collection.return_value.stream.return_value = [
        _mock_doc(d) for d in users_data
    ]

    with patch("app.utils.firestore.get_db", return_value=mock_db):
        result = admin_service.list_users(SUPERADMIN_ACTOR)

    assert result["total"] == 3


def test_list_users_firestore_failure_raises_500():
    with patch("app.utils.firestore.get_db", side_effect=RuntimeError("down")):
        with pytest.raises(HTTPException) as exc_info:
            admin_service.list_users(ADMIN_ACTOR)

    assert exc_info.value.status_code == 500


# ═══════════════════════════════════════════════════════════════════════════
# update_user_role
# ═══════════════════════════════════════════════════════════════════════════


def test_update_user_role_success():
    mock_db = MagicMock()

    with patch("app.utils.firestore.get_db", return_value=mock_db), patch(
        "app.utils.firestore.get_user_role", return_value="user"
    ), patch("app.utils.firestore.admin_audit_log") as mock_audit:
        result = admin_service.update_user_role("target-uid", "admin", ADMIN_ACTOR)

    assert result["uid"] == "target-uid"
    doc_mock = mock_db.collection.return_value.document.return_value
    doc_mock.update.assert_called_once_with({"role": "admin"})
    mock_audit.assert_called_once()


def test_update_user_role_blocks_self_modification():
    actor = {"uid": "same-uid", "role": "admin"}
    with pytest.raises(HTTPException) as exc_info:
        admin_service.update_user_role("same-uid", "admin", actor)
    assert exc_info.value.status_code == 400


def test_update_user_role_non_admin_actor_blocked():
    actor = {"uid": "regular-uid", "role": "user"}
    with pytest.raises(HTTPException) as exc_info:
        admin_service.update_user_role("target-uid", "admin", actor)
    assert exc_info.value.status_code == 403


def test_update_user_role_admin_cannot_assign_superadmin():
    with pytest.raises(HTTPException) as exc_info:
        admin_service.update_user_role("target-uid", "superadmin", ADMIN_ACTOR)
    assert exc_info.value.status_code == 403


def test_update_user_role_superadmin_can_assign_superadmin():
    mock_db = MagicMock()
    with patch("app.utils.firestore.get_db", return_value=mock_db), patch(
        "app.utils.firestore.get_user_role", return_value="admin"
    ), patch("app.utils.firestore.admin_audit_log"):
        result = admin_service.update_user_role(
            "target-uid", "superadmin", SUPERADMIN_ACTOR
        )

    assert "superadmin" in result["message"]


def test_update_user_role_admin_cannot_modify_admin_account():
    with patch("app.utils.firestore.get_user_role", return_value="admin"):
        with pytest.raises(HTTPException) as exc_info:
            admin_service.update_user_role("target-uid", "user", ADMIN_ACTOR)
    assert exc_info.value.status_code == 403


def test_update_user_role_firestore_failure_raises_500():
    with patch("app.utils.firestore.get_db", side_effect=RuntimeError("down")), patch(
        "app.utils.firestore.get_user_role", return_value="user"
    ):
        with pytest.raises(HTTPException) as exc_info:
            admin_service.update_user_role("target-uid", "admin", ADMIN_ACTOR)
    assert exc_info.value.status_code == 500


# ═══════════════════════════════════════════════════════════════════════════
# ban_user
# ═══════════════════════════════════════════════════════════════════════════


def test_ban_user_success():
    mock_db = MagicMock()
    with patch("app.utils.firestore.get_db", return_value=mock_db), patch(
        "app.utils.firestore.get_user_role", return_value="user"
    ), patch("app.utils.firestore.admin_audit_log") as mock_audit:
        result = admin_service.ban_user("target-uid", True, ADMIN_ACTOR)

    assert "banned" in result["message"]
    doc_mock = mock_db.collection.return_value.document.return_value
    doc_mock.update.assert_called_once_with({"is_banned": True})
    mock_audit.assert_called_once()


def test_ban_user_blocks_self_ban():
    actor = {"uid": "same-uid", "role": "admin"}
    with pytest.raises(HTTPException) as exc_info:
        admin_service.ban_user("same-uid", True, actor)
    assert exc_info.value.status_code == 400


def test_ban_user_non_admin_actor_blocked():
    actor = {"uid": "regular-uid", "role": "user"}
    with pytest.raises(HTTPException) as exc_info:
        admin_service.ban_user("target-uid", True, actor)
    assert exc_info.value.status_code == 403


def test_ban_user_admin_cannot_ban_admin():
    with patch("app.utils.firestore.get_user_role", return_value="admin"):
        with pytest.raises(HTTPException) as exc_info:
            admin_service.ban_user("target-uid", True, ADMIN_ACTOR)
    assert exc_info.value.status_code == 403


def test_ban_user_cannot_ban_superadmin_even_as_superadmin():
    with patch("app.utils.firestore.get_user_role", return_value="superadmin"):
        with pytest.raises(HTTPException) as exc_info:
            admin_service.ban_user("target-uid", True, SUPERADMIN_ACTOR)
    assert exc_info.value.status_code == 403


def test_ban_user_firestore_failure_raises_500():
    with patch("app.utils.firestore.get_db", side_effect=RuntimeError("down")), patch(
        "app.utils.firestore.get_user_role", return_value="user"
    ):
        with pytest.raises(HTTPException) as exc_info:
            admin_service.ban_user("target-uid", True, ADMIN_ACTOR)
    assert exc_info.value.status_code == 500


# ═══════════════════════════════════════════════════════════════════════════
# delete_user
# ═══════════════════════════════════════════════════════════════════════════


def test_delete_user_success():
    mock_db = MagicMock()
    with patch("app.utils.firestore.get_db", return_value=mock_db), patch(
        "app.utils.firestore.get_user_role", return_value="user"
    ), patch("app.utils.firestore.admin_audit_log") as mock_audit, patch(
        "app.config.get_settings"
    ) as mock_settings:
        mock_settings.return_value.SUPERADMIN_UID = "super-fixed-uid"
        result = admin_service.delete_user("target-uid", ADMIN_ACTOR)

    assert result["uid"] == "target-uid"
    mock_db.collection.return_value.document.return_value.delete.assert_called_once()
    mock_audit.assert_called_once()


def test_delete_user_blocks_self_deletion():
    actor = {"uid": "same-uid", "role": "admin"}
    with patch("app.config.get_settings") as mock_settings:
        mock_settings.return_value.SUPERADMIN_UID = "super-fixed-uid"
        with pytest.raises(HTTPException) as exc_info:
            admin_service.delete_user("same-uid", actor)
    assert exc_info.value.status_code == 400


def test_delete_user_cannot_delete_superadmin_uid():
    with patch("app.config.get_settings") as mock_settings:
        mock_settings.return_value.SUPERADMIN_UID = "super-fixed-uid"
        with pytest.raises(HTTPException) as exc_info:
            admin_service.delete_user("super-fixed-uid", ADMIN_ACTOR)
    assert exc_info.value.status_code == 403


def test_delete_user_admin_cannot_delete_admin_account():
    with patch("app.config.get_settings") as mock_settings, patch(
        "app.utils.firestore.get_user_role", return_value="admin"
    ):
        mock_settings.return_value.SUPERADMIN_UID = "super-fixed-uid"
        with pytest.raises(HTTPException) as exc_info:
            admin_service.delete_user("target-uid", ADMIN_ACTOR)
    assert exc_info.value.status_code == 403


def test_delete_user_firestore_failure_raises_500():
    with patch("app.utils.firestore.get_db", side_effect=RuntimeError("down")), patch(
        "app.utils.firestore.get_user_role", return_value="user"
    ), patch("app.config.get_settings") as mock_settings:
        mock_settings.return_value.SUPERADMIN_UID = "super-fixed-uid"
        with pytest.raises(HTTPException) as exc_info:
            admin_service.delete_user("target-uid", ADMIN_ACTOR)
    assert exc_info.value.status_code == 500


# ═══════════════════════════════════════════════════════════════════════════
# get_system_stats
# ═══════════════════════════════════════════════════════════════════════════


def _stats_db(sample_docs, *, count=None):
    """Firestore double for get_system_stats: a bounded recent-logs query plus
    an optional count() aggregation. `count=None` simulates a backend where the
    aggregation is unavailable."""
    collection = MagicMock()
    collection.order_by.return_value.limit.return_value.stream.return_value = (
        sample_docs
    )
    if count is None:
        collection.count.side_effect = RuntimeError("aggregation unsupported")
    else:
        agg_result = MagicMock()
        agg_result.value = count
        collection.count.return_value.get.return_value = [[agg_result]]
    db = MagicMock()
    db.collection.return_value = collection
    return db, collection


def _patched_stats(mock_db):
    with patch("app.utils.firestore.get_db", return_value=mock_db), patch(
        "app.models.loader.model_loader.get_model", return_value=object()
    ), patch("psutil.cpu_percent", return_value=12.5), patch(
        "psutil.virtual_memory"
    ) as mock_vm:
        mock_vm.return_value.total = 16 * 1024**3
        mock_vm.return_value.used = 8 * 1024**3
        mock_vm.return_value.percent = 50.0
        return admin_service.get_system_stats()


SAMPLE_LOGS = [
    _mock_doc({"endpoint": "/api/yield/predict"}),
    _mock_doc({"endpoint": "/api/yield/predict"}),
    _mock_doc({"endpoint": "/api/price/predict"}),
]


def test_get_system_stats_returns_expected_shape():
    mock_db, _ = _stats_db(SAMPLE_LOGS, count=4213)
    result = _patched_stats(mock_db)

    assert result["cpu_percent"] == 12.5
    # Exact all-time total comes from the aggregation, not the bounded sample.
    assert result["total_requests"] == 4213
    assert result["requests_sampled"] == 3
    assert result["requests_by_endpoint"]["/api/yield/predict"] == 2
    assert all(result["models_loaded"].values())


def test_get_system_stats_never_scans_the_whole_collection():
    """audit_logs grows without bound (one doc per prediction AND per chat
    turn), so the breakdown must read a bounded, ordered slice — an unbounded
    .stream() is what made this endpoint time out."""
    mock_db, collection = _stats_db(SAMPLE_LOGS, count=10)
    _patched_stats(mock_db)

    collection.stream.assert_not_called()
    collection.order_by.assert_called_once_with("timestamp", direction="DESCENDING")
    collection.order_by.return_value.limit.assert_called_once_with(
        admin_service._ENDPOINT_SAMPLE_SIZE
    )


def test_get_system_stats_falls_back_when_count_unavailable():
    """No count() support (older emulator, restricted permissions) must not
    fail the whole call — report what the sample actually saw."""
    mock_db, _ = _stats_db(SAMPLE_LOGS, count=None)
    result = _patched_stats(mock_db)

    assert result["total_requests"] == 3
    assert result["requests_sampled"] == 3


def test_get_system_stats_firestore_failure_raises_500():
    with patch("app.utils.firestore.get_db", side_effect=RuntimeError("down")):
        with pytest.raises(HTTPException) as exc_info:
            admin_service.get_system_stats()
    assert exc_info.value.status_code == 500


# ═══════════════════════════════════════════════════════════════════════════
# get_audit_logs / get_prediction_logs
# ═══════════════════════════════════════════════════════════════════════════


def test_get_audit_logs_hides_superadmin_actions_from_admin():
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
        result = admin_service.get_audit_logs(50, ADMIN_ACTOR)

    actor_roles = [log["actor_role"] for log in result["logs"]]
    assert "superadmin" not in actor_roles
    assert result["total"] == 1


def test_get_audit_logs_superadmin_sees_all():
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
        result = admin_service.get_audit_logs(50, SUPERADMIN_ACTOR)

    assert result["total"] == 2


def test_get_audit_logs_converts_timestamp_to_isoformat_string():
    """Firestore returns a datetime — the API response must serialize it
    as an ISO-8601 string, not a raw datetime object."""
    ts = datetime(2026, 1, 15, 10, 30, tzinfo=timezone.utc)
    mock_query = MagicMock()
    mock_query.stream.return_value = [
        _mock_doc({"actor_role": "admin", "action": "ban_user", "timestamp": ts})
    ]
    mock_db = MagicMock()
    mock_db.collection.return_value.order_by.return_value.limit.return_value = (
        mock_query
    )

    with patch("app.utils.firestore.get_db", return_value=mock_db):
        result = admin_service.get_audit_logs(50, SUPERADMIN_ACTOR)

    assert result["logs"][0]["timestamp"] == ts.isoformat()


def test_get_audit_logs_firestore_failure_raises_500():
    with patch("app.utils.firestore.get_db", side_effect=RuntimeError("down")):
        with pytest.raises(HTTPException) as exc_info:
            admin_service.get_audit_logs(50, ADMIN_ACTOR)
    assert exc_info.value.status_code == 500


def test_get_prediction_logs_returns_logs():
    logs_data = [{"user_id": "u1", "endpoint": "/api/yield/predict"}]
    mock_query = MagicMock()
    mock_query.stream.return_value = [_mock_doc(d) for d in logs_data]
    mock_db = MagicMock()
    mock_db.collection.return_value.order_by.return_value.limit.return_value = (
        mock_query
    )

    with patch("app.utils.firestore.get_db", return_value=mock_db):
        result = admin_service.get_prediction_logs(50)

    assert result["total"] == 1
    assert result["logs"][0]["user_id"] == "u1"


def test_get_prediction_logs_converts_timestamp_to_isoformat_string():
    ts = datetime(2026, 1, 15, 10, 30, tzinfo=timezone.utc)
    mock_query = MagicMock()
    mock_query.stream.return_value = [
        _mock_doc({"user_id": "u1", "endpoint": "/api/yield/predict", "timestamp": ts})
    ]
    mock_db = MagicMock()
    mock_db.collection.return_value.order_by.return_value.limit.return_value = (
        mock_query
    )

    with patch("app.utils.firestore.get_db", return_value=mock_db):
        result = admin_service.get_prediction_logs(50)

    assert result["logs"][0]["timestamp"] == ts.isoformat()


def test_get_prediction_logs_firestore_failure_raises_500():
    with patch("app.utils.firestore.get_db", side_effect=RuntimeError("down")):
        with pytest.raises(HTTPException) as exc_info:
            admin_service.get_prediction_logs(50)
    assert exc_info.value.status_code == 500
