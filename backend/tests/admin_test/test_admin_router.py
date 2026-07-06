"""Integration tests for /api/admin/* (app.admin.routers.admin_router).

Exercises the full HTTP stack — JWT auth, role gating, and the 10/minute
rate limit added for admin routes — with Firestore and psutil mocked out.
Reuses the client/app fixtures from tests/conftest.py.
"""

from unittest.mock import MagicMock, patch

import pytest


def _mock_doc(data: dict):
    doc = MagicMock()
    doc.to_dict.return_value = data
    return doc


def _empty_db():
    """Firestore double covering both access patterns admin_service uses:
    db.collection(...).stream() and db.collection(...).order_by(...).limit(...).stream()
    """
    mock_db = MagicMock()
    mock_db.collection.return_value.stream.return_value = []
    chain = mock_db.collection.return_value.order_by.return_value.limit.return_value
    chain.stream.return_value = []
    return mock_db


# ═══════════════════════════════════════════════════════════════════════════
# Auth / role gating
# ═══════════════════════════════════════════════════════════════════════════


@pytest.mark.parametrize(
    "method,path",
    [
        ("get", "/api/admin/users"),
        ("get", "/api/admin/stats"),
        ("get", "/api/admin/audit-logs"),
        ("get", "/api/admin/prediction-logs"),
        ("patch", "/api/admin/users/some-uid/role"),
        ("patch", "/api/admin/users/some-uid/ban"),
        ("delete", "/api/admin/users/some-uid"),
    ],
)
def test_no_jwt_returns_401(client, mock_expired_token, method, path):
    resp = getattr(client, method)(path)
    assert resp.status_code == 401


def test_expired_jwt_returns_401(client, mock_expired_token, expired_auth_header):
    resp = client.get("/api/admin/stats", headers=expired_auth_header)
    assert resp.status_code == 401


def test_non_admin_user_gets_403_on_stats(client, mock_valid_token, valid_auth_header):
    with patch("app.utils.firestore.get_user_role", return_value="user"):
        resp = client.get("/api/admin/stats", headers=valid_auth_header)
    assert resp.status_code == 403


def test_non_admin_user_gets_403_on_list_users(
    client, mock_valid_token, valid_auth_header
):
    with patch("app.utils.firestore.get_user_role", return_value="user"):
        resp = client.get("/api/admin/users", headers=valid_auth_header)
    assert resp.status_code == 403


def test_non_admin_user_gets_403_on_role_update(
    client, mock_valid_token, valid_auth_header
):
    """update_user_role has no `require_admin` dependency — the 403 must
    come from the manual role check inside admin_service."""
    with patch("app.utils.firestore.get_user_role", return_value="user"):
        resp = client.patch(
            "/api/admin/users/target-uid/role",
            json={"role": "admin"},
            headers=valid_auth_header,
        )
    assert resp.status_code == 403


# ═══════════════════════════════════════════════════════════════════════════
# Happy paths
# ═══════════════════════════════════════════════════════════════════════════


def test_admin_can_list_users(client, mock_valid_token, valid_auth_header):
    with patch("app.utils.firestore.get_db", return_value=_empty_db()), patch(
        "app.utils.firestore.get_user_role", return_value="admin"
    ):
        resp = client.get("/api/admin/users", headers=valid_auth_header)

    assert resp.status_code == 200
    assert resp.json() == {"users": [], "total": 0}


def test_admin_stats_returns_200(client, mock_valid_token, valid_auth_header):
    with patch("app.utils.firestore.get_db", return_value=_empty_db()), patch(
        "app.utils.firestore.get_user_role", return_value="admin"
    ), patch("app.models.loader.model_loader.get_model", return_value=None):
        resp = client.get("/api/admin/stats", headers=valid_auth_header)

    assert resp.status_code == 200
    body = resp.json()
    assert "cpu_percent" in body
    assert "models_loaded" in body


# mock_valid_token resolves the authenticated actor to uid "test-user-123"
# (see conftest.py). get_user_role is looked up twice per request — once for
# the acting user via get_current_role, once for the target uid inside the
# service — so it must discriminate by uid rather than return a flat value.
def _role_by_uid(actor_role):
    def _side_effect(uid):
        return actor_role if uid == "test-user-123" else "user"

    return _side_effect


def test_admin_can_update_user_role(client, mock_valid_token, valid_auth_header):
    with patch("app.utils.firestore.get_db", return_value=_empty_db()), patch(
        "app.utils.firestore.get_user_role", side_effect=_role_by_uid("admin")
    ), patch("app.utils.firestore.admin_audit_log"):
        resp = client.patch(
            "/api/admin/users/target-uid/role",
            json={"role": "admin"},
            headers=valid_auth_header,
        )

    assert resp.status_code == 200
    assert resp.json()["uid"] == "target-uid"


def test_admin_can_ban_user(client, mock_valid_token, valid_auth_header):
    with patch("app.utils.firestore.get_db", return_value=_empty_db()), patch(
        "app.utils.firestore.get_user_role", side_effect=_role_by_uid("admin")
    ), patch("app.utils.firestore.admin_audit_log"):
        resp = client.patch(
            "/api/admin/users/target-uid/ban",
            json={"is_banned": True},
            headers=valid_auth_header,
        )

    assert resp.status_code == 200
    assert "banned" in resp.json()["message"]


def test_admin_can_delete_user(client, mock_valid_token, valid_auth_header):
    with patch("app.utils.firestore.get_db", return_value=_empty_db()), patch(
        "app.utils.firestore.get_user_role", side_effect=_role_by_uid("admin")
    ), patch("app.utils.firestore.admin_audit_log"), patch(
        "app.config.get_settings"
    ) as mock_settings:
        mock_settings.return_value.SUPERADMIN_UID = "fixed-superadmin-uid"
        resp = client.delete("/api/admin/users/target-uid", headers=valid_auth_header)

    assert resp.status_code == 200


def test_audit_logs_returns_200(client, mock_valid_token, valid_auth_header):
    with patch("app.utils.firestore.get_db", return_value=_empty_db()), patch(
        "app.utils.firestore.get_user_role", return_value="admin"
    ):
        resp = client.get("/api/admin/audit-logs", headers=valid_auth_header)

    assert resp.status_code == 200
    assert resp.json() == {"logs": [], "total": 0}


def test_prediction_logs_returns_200(client, mock_valid_token, valid_auth_header):
    with patch("app.utils.firestore.get_db", return_value=_empty_db()), patch(
        "app.utils.firestore.get_user_role", return_value="admin"
    ):
        resp = client.get("/api/admin/prediction-logs", headers=valid_auth_header)

    assert resp.status_code == 200
    assert resp.json() == {"logs": [], "total": 0}


# ═══════════════════════════════════════════════════════════════════════════
# Rate limiting — admin routes are capped at 10/minute (vs 30/minute for the
# user-facing prediction routes), added as part of the user/admin split.
# ═══════════════════════════════════════════════════════════════════════════


class TestAdminRateLimiting:
    def test_11th_request_returns_429(
        self, client, mock_valid_token, valid_auth_header
    ):
        from app.middleware.rate_limit import limiter

        if getattr(limiter, "_disabled", False):
            pytest.skip("Rate limiter is disabled in test environment")

        with patch("app.utils.firestore.get_db", return_value=_empty_db()), patch(
            "app.utils.firestore.get_user_role", return_value="admin"
        ):
            responses = [
                client.get("/api/admin/users", headers=valid_auth_header)
                for _ in range(11)
            ]

        status_codes = [r.status_code for r in responses]
        assert (
            429 in status_codes
        ), f"Expected at least one 429 in 11 requests, got: {set(status_codes)}"


# ═══════════════════════════════════════════════════════════════════════════
# ENABLE_ADMIN_API toggle — a fresh app built with the flag off must not
# expose /api/admin/* at all.
# ═══════════════════════════════════════════════════════════════════════════


def test_admin_routes_return_404_when_disabled(monkeypatch, mock_valid_token):
    from fastapi.testclient import TestClient

    from app.config import get_settings

    monkeypatch.setenv("ENABLE_ADMIN_API", "false")
    get_settings.cache_clear()

    try:
        with patch("firebase_admin.initialize_app"), patch(
            "firebase_admin._apps", new={"[DEFAULT]": MagicMock()}
        ), patch("app.utils.firestore.init_firestore"), patch(
            "app.models.loader.ModelLoader.load_all"
        ):
            from app.main import create_app

            disabled_app = create_app()

            with TestClient(disabled_app) as disabled_client:
                resp = disabled_client.get(
                    "/api/admin/stats",
                    headers={"Authorization": "Bearer valid-test-token"},
                )
    finally:
        get_settings.cache_clear()

    assert resp.status_code == 404
