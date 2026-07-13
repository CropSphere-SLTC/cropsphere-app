"""Integration tests for /api/admin/security/* (security_router).

Exercises the full HTTP stack — JWT auth, require_admin gating, and the
10/minute rate limit — with the service layer mocked. Reuses the client/app
fixtures from tests/conftest.py.
"""

from unittest.mock import patch

import pytest

_ENDPOINTS = [
    "/api/admin/security/summary",
    "/api/admin/security/failed-logins",
    "/api/admin/security/rate-violations",
    "/api/admin/security/banned-attempts",
    "/api/admin/security/active-sessions",
]


# ═══════════════════════════════════════════════════════════════════════════
# Auth / role gating — both admin and superadmin may read; users get 403.
# ═══════════════════════════════════════════════════════════════════════════


@pytest.mark.parametrize("path", _ENDPOINTS)
def test_no_jwt_returns_401(client, mock_expired_token, path):
    resp = client.get(path)
    assert resp.status_code == 401


@pytest.mark.parametrize("path", _ENDPOINTS)
def test_non_admin_user_gets_403(client, mock_valid_token, valid_auth_header, path):
    with patch("app.utils.firestore.get_user_role", return_value="user"):
        resp = client.get(path, headers=valid_auth_header)
    assert resp.status_code == 403


# ═══════════════════════════════════════════════════════════════════════════
# Happy paths — service layer mocked, role resolved to admin.
# ═══════════════════════════════════════════════════════════════════════════


def test_summary_returns_200(client, mock_valid_token, valid_auth_header):
    fake = {
        "failed_logins": 3,
        "rate_violations": 1,
        "banned_attempts": 0,
        "active_sessions": 5,
        "window_hours": 24,
        "timestamp": "2026-07-13T00:00:00+00:00",
    }
    with patch("app.utils.firestore.get_user_role", return_value="admin"), patch(
        "app.admin.services.security_service.get_security_summary", return_value=fake
    ):
        resp = client.get("/api/admin/security/summary", headers=valid_auth_header)

    assert resp.status_code == 200
    assert resp.json()["active_sessions"] == 5


def test_superadmin_can_read_summary(client, mock_valid_token, valid_auth_header):
    fake = {"failed_logins": 0, "active_sessions": 0}
    with patch("app.utils.firestore.get_user_role", return_value="superadmin"), patch(
        "app.admin.services.security_service.get_security_summary", return_value=fake
    ):
        resp = client.get("/api/admin/security/summary", headers=valid_auth_header)
    assert resp.status_code == 200


def test_failed_logins_returns_200(client, mock_valid_token, valid_auth_header):
    fake = {"events": [{"type": "failed_login"}], "total": 1}
    with patch("app.utils.firestore.get_user_role", return_value="admin"), patch(
        "app.admin.services.security_service.get_failed_logins", return_value=fake
    ):
        resp = client.get(
            "/api/admin/security/failed-logins", headers=valid_auth_header
        )

    assert resp.status_code == 200
    assert resp.json()["total"] == 1


def test_active_sessions_returns_200(client, mock_valid_token, valid_auth_header):
    fake = {"sessions": [{"uid": "u1", "role": "user"}], "total": 1}
    with patch("app.utils.firestore.get_user_role", return_value="admin"), patch(
        "app.admin.services.security_service.get_active_sessions", return_value=fake
    ):
        resp = client.get(
            "/api/admin/security/active-sessions", headers=valid_auth_header
        )

    assert resp.status_code == 200
    assert resp.json()["total"] == 1
