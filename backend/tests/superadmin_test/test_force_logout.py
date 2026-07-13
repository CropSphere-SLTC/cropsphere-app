"""Tests for superadmin force-logout — service unit tests plus HTTP integration.

force_logout revokes a user's Firebase refresh tokens and records an audit
entry. Firebase Admin SDK and Firestore are mocked throughout.
"""

from unittest.mock import patch

import pytest
from fastapi import HTTPException

from app.super_admin.services import superadmin_service

# ═══════════════════════════════════════════════════════════════════════════
# Service — force_logout
# ═══════════════════════════════════════════════════════════════════════════


def test_force_logout_revokes_tokens_and_audits():
    with patch("firebase_admin.auth.revoke_refresh_tokens") as mock_revoke, patch(
        "app.utils.firestore.admin_audit_log"
    ) as mock_audit:
        result = superadmin_service.force_logout("target-uid", "super-uid")

    mock_revoke.assert_called_once_with("target-uid")
    mock_audit.assert_called_once()
    kwargs = mock_audit.call_args.kwargs
    assert kwargs["action"] == "force_logout"
    assert kwargs["target_uid"] == "target-uid"
    assert kwargs["actor_uid"] == "super-uid"
    assert result["uid"] == "target-uid"


def test_force_logout_revoke_failure_raises_500():
    with patch(
        "firebase_admin.auth.revoke_refresh_tokens",
        side_effect=RuntimeError("firebase down"),
    ), patch("app.utils.firestore.admin_audit_log"):
        with pytest.raises(HTTPException) as exc_info:
            superadmin_service.force_logout("target-uid", "super-uid")
    assert exc_info.value.status_code == 500


# ═══════════════════════════════════════════════════════════════════════════
# HTTP — POST /api/superadmin/security/force-logout/{uid}
# ═══════════════════════════════════════════════════════════════════════════

_PATH = "/api/superadmin/security/force-logout/target-uid"


def test_force_logout_no_jwt_returns_401(client, mock_expired_token):
    resp = client.post(_PATH)
    assert resp.status_code == 401


def test_force_logout_admin_gets_403(client, mock_valid_token, valid_auth_header):
    """Admins are not superadmin — require_superadmin must reject with 403."""
    with patch("app.utils.firestore.get_user_role", return_value="admin"):
        resp = client.post(_PATH, headers=valid_auth_header)
    assert resp.status_code == 403


def test_force_logout_regular_user_gets_403(
    client, mock_valid_token, valid_auth_header
):
    with patch("app.utils.firestore.get_user_role", return_value="user"):
        resp = client.post(_PATH, headers=valid_auth_header)
    assert resp.status_code == 403


def test_force_logout_superadmin_returns_200(
    client, mock_valid_token, valid_auth_header
):
    with patch("app.utils.firestore.get_user_role", return_value="superadmin"), patch(
        "app.super_admin.services.superadmin_service.force_logout",
        return_value={"message": "User sessions revoked", "uid": "target-uid"},
    ) as mock_service:
        resp = client.post(_PATH, headers=valid_auth_header)

    assert resp.status_code == 200
    assert resp.json()["uid"] == "target-uid"
    # actor uid comes from the authenticated superadmin (conftest: test-user-123)
    mock_service.assert_called_once_with("target-uid", "test-user-123")
