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
        ("get", "/api/admin/gap-report"),
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


def test_non_admin_gets_403_on_gap_report(client, mock_valid_token, valid_auth_header):
    with patch("app.utils.firestore.get_user_role", return_value="user"):
        resp = client.get("/api/admin/gap-report", headers=valid_auth_header)
    assert resp.status_code == 403


def test_admin_gap_report_returns_200(client, mock_valid_token, valid_auth_header):
    fake = {"period": "last_7_days", "total_interactions": 5}
    with patch("app.utils.firestore.get_user_role", return_value="admin"), patch(
        "app.admin.services.gap_report_service.get_gap_report", return_value=fake
    ):
        resp = client.get("/api/admin/gap-report?days=7", headers=valid_auth_header)
    assert resp.status_code == 200
    assert resp.json()["total_interactions"] == 5


def test_non_admin_gets_403_on_rebuild_fewshot(
    client, mock_valid_token, valid_auth_header
):
    with patch("app.utils.firestore.get_user_role", return_value="user"):
        resp = client.get("/api/admin/rebuild-fewshot", headers=valid_auth_header)
    assert resp.status_code == 403


def test_admin_rebuild_fewshot_returns_count(
    client, mock_valid_token, valid_auth_header
):
    fake = {
        "examples": {
            "yield": [{"question": "q", "answer": "a"}],
            "price": [{"question": "q2", "answer": "a2"}],
        }
    }
    with patch("app.utils.firestore.get_user_role", return_value="admin"), patch(
        "app.user.services.fewshot_service.build_fewshot_examples", return_value=fake
    ), patch("app.user.services.chatbot_service._reload_fewshot_examples"):
        resp = client.get("/api/admin/rebuild-fewshot", headers=valid_auth_header)
    assert resp.status_code == 200
    assert resp.json() == {"status": "ok", "examples_count": 2}


# ═══════════════════════════════════════════════════════════════════════════
# Prompt tuning endpoints
# ═══════════════════════════════════════════════════════════════════════════
# Prompt tuning is superadmin-only — a plain admin must be rejected too.
@pytest.mark.parametrize("role", ["user", "admin"])
def test_non_superadmin_gets_403_on_analyze_prompt_tuning(
    client, mock_valid_token, valid_auth_header, role
):
    with patch("app.utils.firestore.get_user_role", return_value=role):
        resp = client.post(
            "/api/admin/analyze-prompt-tuning", headers=valid_auth_header
        )
    assert resp.status_code == 403


@pytest.mark.parametrize(
    "method,path",
    [
        ("get", "/api/admin/active-prompt-tuning"),
        ("delete", "/api/admin/clear-prompt-tuning"),
    ],
)
def test_admin_gets_403_on_prompt_tuning_read_write(
    client, mock_valid_token, valid_auth_header, method, path
):
    with patch("app.utils.firestore.get_user_role", return_value="admin"):
        resp = getattr(client, method)(path, headers=valid_auth_header)
    assert resp.status_code == 403


def test_admin_analyze_prompt_tuning_returns_proposal(
    client, mock_valid_token, valid_auth_header
):
    fake = {
        "updated_at": "t",
        "period_days": 7,
        "sample_size": 142,
        "adjustments": [
            {
                "id": "language_complexity",
                "dimension": "language_complexity",
                "trigger": "78% beginner users",
                "instruction": "Keep it simple.",
                "recommended": True,
            },
        ],
    }
    with patch("app.utils.firestore.get_user_role", return_value="superadmin"), patch(
        "app.user.services.prompt_tuning_service.analyze_and_generate_tuning",
        return_value=fake,
    ):
        resp = client.post(
            "/api/admin/analyze-prompt-tuning?days=7", headers=valid_auth_header
        )
    assert resp.status_code == 200
    body = resp.json()
    assert body["sample_size"] == 142
    assert body["proposed_adjustments"][0]["id"] == "language_complexity"


def test_admin_apply_prompt_tuning_saves_approved(
    client, mock_valid_token, valid_auth_header
):
    saved = {
        "applied": ["language_complexity"],
        "skipped": [],
        "adjustments": [{"id": "language_complexity", "instruction": "x"}],
    }
    with patch("app.utils.firestore.get_user_role", return_value="superadmin"), patch(
        "app.user.services.prompt_tuning_service.apply_approved", return_value=saved
    ), patch("app.user.services.chatbot_service._reload_prompt_tuning"):
        resp = client.post(
            "/api/admin/apply-prompt-tuning",
            json={"approved_ids": ["language_complexity"]},
            headers=valid_auth_header,
        )
    assert resp.status_code == 200
    assert resp.json() == {
        "status": "ok",
        "applied_count": 1,
        "applied_ids": ["language_complexity"],
        "skipped_ids": [],
    }


def test_apply_prompt_tuning_rejects_missing_body(
    client, mock_valid_token, valid_auth_header
):
    with patch("app.utils.firestore.get_user_role", return_value="superadmin"):
        resp = client.post("/api/admin/apply-prompt-tuning", headers=valid_auth_header)
    assert resp.status_code == 422


def test_admin_active_prompt_tuning_returns_live(
    client, mock_valid_token, valid_auth_header
):
    active = {"updated_at": "t", "adjustments": [{"id": "chip_high"}]}
    with patch("app.utils.firestore.get_user_role", return_value="superadmin"), patch(
        "app.user.services.prompt_tuning_service.load_active_tuning",
        return_value=active,
    ):
        resp = client.get("/api/admin/active-prompt-tuning", headers=valid_auth_header)
    assert resp.status_code == 200
    assert resp.json()["count"] == 1


def test_admin_clear_prompt_tuning(client, mock_valid_token, valid_auth_header):
    with patch("app.utils.firestore.get_user_role", return_value="superadmin"), patch(
        "app.user.services.prompt_tuning_service.clear_tuning",
        return_value={"cleared": ["language_complexity"]},
    ) as mock_clear, patch("app.user.services.chatbot_service._reload_prompt_tuning"):
        resp = client.delete(
            "/api/admin/clear-prompt-tuning", headers=valid_auth_header
        )
    assert resp.status_code == 200
    assert resp.json() == {"status": "ok", "cleared_count": 1}
    mock_clear.assert_called_once()


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


# ═══════════════════════════════════════════════════════════════════════════
# Prompt tuning trash & restore
# ═══════════════════════════════════════════════════════════════════════════


def test_prompt_tuning_trash_lists_newest_first(
    client, mock_valid_token, valid_auth_header
):
    store = {
        "trash": [
            {"adjustment": {"id": "old"}, "trashed_at": "2026-07-01T00:00:00+00:00"},
            {"adjustment": {"id": "new"}, "trashed_at": "2026-07-20T00:00:00+00:00"},
        ]
    }
    with patch("app.utils.firestore.get_user_role", return_value="superadmin"), patch(
        "app.user.services.prompt_tuning_store.load", return_value=store
    ):
        resp = client.get("/api/admin/prompt-tuning-trash", headers=valid_auth_header)
    assert resp.status_code == 200
    body = resp.json()
    assert body["count"] == 2
    assert [t["adjustment"]["id"] for t in body["trash"]] == ["new", "old"]


def test_prompt_tuning_trash_denied_for_plain_admin(
    client, mock_valid_token, valid_auth_header
):
    with patch("app.utils.firestore.get_user_role", return_value="admin"):
        resp = client.get("/api/admin/prompt-tuning-trash", headers=valid_auth_header)
    assert resp.status_code == 403


def test_restore_from_trash_returns_a_fresh_trial(
    client, mock_valid_token, valid_auth_header
):
    restored = {"id": "chip_high", "status": "trial"}
    with patch("app.utils.firestore.get_user_role", return_value="superadmin"), patch(
        "app.user.services.prompt_tuning_store.restore",
        return_value={"ok": True, "error": None, "adjustment": restored},
    ) as mock_restore, patch(
        "app.user.services.chatbot_service._reload_prompt_tuning"
    ) as mock_reload:
        resp = client.post(
            "/api/admin/restore-from-trash/chip_high", headers=valid_auth_header
        )
    assert resp.status_code == 200
    assert resp.json()["adjustment"]["status"] == "trial"
    mock_restore.assert_called_once_with("chip_high", "test-user-123")
    mock_reload.assert_called_once()


def test_restore_from_trash_unknown_id_returns_404(
    client, mock_valid_token, valid_auth_header
):
    with patch("app.utils.firestore.get_user_role", return_value="superadmin"), patch(
        "app.user.services.prompt_tuning_store.restore",
        return_value={"ok": False, "error": "not_found", "adjustment": None},
    ):
        resp = client.post(
            "/api/admin/restore-from-trash/nope", headers=valid_auth_header
        )
    assert resp.status_code == 404


def test_restore_from_trash_conflict_returns_409(
    client, mock_valid_token, valid_auth_header
):
    with patch("app.utils.firestore.get_user_role", return_value="superadmin"), patch(
        "app.user.services.prompt_tuning_store.restore",
        return_value={"ok": False, "error": "already_active", "adjustment": None},
    ):
        resp = client.post(
            "/api/admin/restore-from-trash/chip_high", headers=valid_auth_header
        )
    assert resp.status_code == 409


def test_active_prompt_tuning_reports_status_counts(
    client, mock_valid_token, valid_auth_header
):
    active = {
        "updated_at": "2026-07-23T10:00:00+00:00",
        "trash_count": 3,
        "adjustments": [
            {"id": "a", "status": "trial"},
            {"id": "b", "status": "permanent"},
            {"id": "c", "status": "permanent"},
        ],
    }
    with patch("app.utils.firestore.get_user_role", return_value="superadmin"), patch(
        "app.user.services.prompt_tuning_service.load_active_tuning",
        return_value=active,
    ):
        resp = client.get("/api/admin/active-prompt-tuning", headers=valid_auth_header)
    assert resp.status_code == 200
    body = resp.json()
    assert body["count"] == 3
    assert body["trial_count"] == 1
    assert body["permanent_count"] == 2
    assert body["trash_count"] == 3


def test_apply_prompt_tuning_rejects_out_of_range_trial_period(
    client, mock_valid_token, valid_auth_header
):
    with patch("app.utils.firestore.get_user_role", return_value="superadmin"):
        resp = client.post(
            "/api/admin/apply-prompt-tuning",
            json={"approved_ids": ["x"], "trial_period_days": 500},
            headers=valid_auth_header,
        )
    assert resp.status_code == 422


# ═══════════════════════════════════════════════════════════════════════════
# Admin notifications (the bell)
# ═══════════════════════════════════════════════════════════════════════════


@pytest.mark.parametrize(
    "method,path",
    [
        ("get", "/api/admin/notifications"),
        ("get", "/api/admin/notifications/unread-count"),
        ("post", "/api/admin/notifications/abc/read"),
        ("post", "/api/admin/notifications/read-all"),
    ],
)
def test_notifications_require_admin(
    client, mock_valid_token, valid_auth_header, method, path
):
    with patch("app.utils.firestore.get_user_role", return_value="user"):
        resp = getattr(client, method)(path, headers=valid_auth_header)
    assert resp.status_code == 403


def test_list_notifications_returns_items(client, mock_valid_token, valid_auth_header):
    items = [
        {"id": "a", "type": "adjustment_promoted", "read": False},
        {"id": "b", "type": "high_refusal_rate", "read": True},
    ]
    with patch("app.utils.firestore.get_user_role", return_value="admin"), patch(
        "app.admin.services.notification_service.get_notifications",
        return_value=items,
    ) as get:
        resp = client.get(
            "/api/admin/notifications?limit=20&unread_only=true",
            headers=valid_auth_header,
        )
    assert resp.status_code == 200
    body = resp.json()
    assert body["total"] == 2
    assert body["notifications"][0]["id"] == "a"
    assert get.call_args.kwargs == {"limit": 20, "unread_only": True}


def test_unread_count_endpoint(client, mock_valid_token, valid_auth_header):
    with patch("app.utils.firestore.get_user_role", return_value="admin"), patch(
        "app.admin.services.notification_service.get_unread_count", return_value=7
    ):
        resp = client.get(
            "/api/admin/notifications/unread-count", headers=valid_auth_header
        )
    assert resp.status_code == 200
    assert resp.json() == {"count": 7}


def test_mark_one_read_endpoint(client, mock_valid_token, valid_auth_header):
    with patch("app.utils.firestore.get_user_role", return_value="admin"), patch(
        "app.admin.services.notification_service.mark_read"
    ) as mark:
        resp = client.post(
            "/api/admin/notifications/abc123/read", headers=valid_auth_header
        )
    assert resp.status_code == 200
    mark.assert_called_once_with("abc123")


def test_mark_all_read_endpoint(client, mock_valid_token, valid_auth_header):
    with patch("app.utils.firestore.get_user_role", return_value="admin"), patch(
        "app.admin.services.notification_service.mark_all_read"
    ) as mark:
        resp = client.post(
            "/api/admin/notifications/read-all", headers=valid_auth_header
        )
    assert resp.status_code == 200
    mark.assert_called_once()


def test_superadmin_can_also_read_notifications(
    client, mock_valid_token, valid_auth_header
):
    with patch("app.utils.firestore.get_user_role", return_value="superadmin"), patch(
        "app.admin.services.notification_service.get_unread_count", return_value=0
    ):
        resp = client.get(
            "/api/admin/notifications/unread-count", headers=valid_auth_header
        )
    assert resp.status_code == 200
    assert resp.json() == {"count": 0}


# ═══════════════════════════════════════════════════════════════════════════
# Email preferences (per admin)
# ═══════════════════════════════════════════════════════════════════════════


@pytest.mark.parametrize("method", ["get", "patch"])
def test_email_preferences_require_admin(
    client, mock_valid_token, valid_auth_header, method
):
    kwargs = {"headers": valid_auth_header}
    if method == "patch":
        kwargs["json"] = {"email_notifications": False}
    with patch("app.utils.firestore.get_user_role", return_value="user"):
        resp = getattr(client, method)("/api/admin/email-preferences", **kwargs)
    assert resp.status_code == 403


def test_get_email_preferences_returns_current_value(
    client, mock_valid_token, valid_auth_header
):
    with patch("app.utils.firestore.get_user_role", return_value="admin"), patch(
        "app.admin.services.notification_service.get_email_preference",
        return_value=True,
    ) as get:
        resp = client.get("/api/admin/email-preferences", headers=valid_auth_header)
    assert resp.status_code == 200
    assert resp.json() == {"email_notifications": True}
    # Reads the preference for the authenticated caller (conftest uid).
    get.assert_called_once_with("test-user-123")


def test_patch_email_preferences_updates_value(
    client, mock_valid_token, valid_auth_header
):
    with patch("app.utils.firestore.get_user_role", return_value="admin"), patch(
        "app.admin.services.notification_service.set_email_preference",
        return_value=False,
    ) as set_pref:
        resp = client.patch(
            "/api/admin/email-preferences",
            json={"email_notifications": False},
            headers=valid_auth_header,
        )
    assert resp.status_code == 200
    assert resp.json() == {"email_notifications": False}
    set_pref.assert_called_once_with("test-user-123", False)


def test_patch_email_preferences_rejects_missing_body(
    client, mock_valid_token, valid_auth_header
):
    with patch("app.utils.firestore.get_user_role", return_value="admin"):
        resp = client.patch("/api/admin/email-preferences", headers=valid_auth_header)
    assert resp.status_code == 422
