"""HTTP tests for the superadmin prompt-tuning lifecycle endpoints.

Covers the config GET/PATCH, per-adjustment analytics, the manual overrides
(force-permanent / remove), and clear-trash. Every route is asserted to reject
non-superadmins, since these change what the live chatbot prompt contains.
Services are mocked — no Firestore, no tuning file.
"""

from unittest.mock import patch

import pytest

_CONFIG = {
    "min_sample_size": 20,
    "trial_period_days": 14,
    "trial_extension_days": 7,
    "trash_retention_days": 14,
}


def _as_role(role):
    return patch("app.utils.firestore.get_user_role", return_value=role)


# ── Role gating ───────────────────────────────────────────────────────────────

_GUARDED = [
    ("get", "/api/superadmin/prompt-tuning-config", None),
    ("patch", "/api/superadmin/prompt-tuning-config", {"min_sample_size": 25}),
    ("get", "/api/superadmin/adjustment-analytics/x", None),
    ("post", "/api/superadmin/force-permanent/x", None),
    ("post", "/api/superadmin/remove-adjustment/x", {"comment": "because"}),
    ("delete", "/api/superadmin/clear-trash", None),
]


def _call(client, method, path, body, headers=None):
    """TestClient.get/delete don't take a json kwarg, so only pass it when the
    route actually has a body."""
    kwargs = {}
    if headers:
        kwargs["headers"] = headers
    if body is not None:
        kwargs["json"] = body
    return getattr(client, method)(path, **kwargs)


@pytest.mark.parametrize("method,path,body", _GUARDED)
@pytest.mark.parametrize("role", ["user", "admin"])
def test_non_superadmin_is_rejected(
    client, mock_valid_token, valid_auth_header, method, path, body, role
):
    """A plain admin must not be able to change what the chatbot is told."""
    with _as_role(role):
        resp = _call(client, method, path, body, valid_auth_header)
    assert resp.status_code == 403


@pytest.mark.parametrize("method,path,body", _GUARDED)
def test_missing_jwt_is_rejected(client, mock_expired_token, method, path, body):
    resp = _call(client, method, path, body)
    assert resp.status_code == 401


# ── Config ────────────────────────────────────────────────────────────────────


def test_get_config_returns_values(client, mock_valid_token, valid_auth_header):
    with _as_role("superadmin"), patch(
        "app.admin.services.system_config_service.get_prompt_tuning_config",
        return_value=_CONFIG,
    ):
        resp = client.get(
            "/api/superadmin/prompt-tuning-config", headers=valid_auth_header
        )
    assert resp.status_code == 200
    assert resp.json() == _CONFIG


def test_patch_config_forwards_only_supplied_fields(
    client, mock_valid_token, valid_auth_header
):
    with _as_role("superadmin"), patch(
        "app.admin.services.system_config_service.update_prompt_tuning_config",
        return_value={**_CONFIG, "trial_period_days": 21},
    ) as update:
        resp = client.patch(
            "/api/superadmin/prompt-tuning-config",
            json={"trial_period_days": 21},
            headers=valid_auth_header,
        )
    assert resp.status_code == 200
    assert resp.json()["trial_period_days"] == 21
    # None-valued fields are stripped before the service sees them.
    assert update.call_args[0][0] == {"trial_period_days": 21}
    assert update.call_args.kwargs["actor_uid"] == "test-user-123"


@pytest.mark.parametrize(
    "body",
    [
        {"trial_period_days": 0},
        {"trial_period_days": 91},
        {"min_sample_size": -1},
        {"trash_retention_days": 400},
        {"trial_extension_days": 0},
    ],
)
def test_patch_config_rejects_out_of_range(
    client, mock_valid_token, valid_auth_header, body
):
    with _as_role("superadmin"):
        resp = client.patch(
            "/api/superadmin/prompt-tuning-config",
            json=body,
            headers=valid_auth_header,
        )
    assert resp.status_code == 422


# ── Adjustment analytics ──────────────────────────────────────────────────────


def test_adjustment_analytics_returns_payload(
    client, mock_valid_token, valid_auth_header
):
    payload = {"status": "trial", "verdict": "on_track_for_permanent"}
    with _as_role("superadmin"), patch(
        "app.admin.services.tuning_validation_service.get_adjustment_analytics",
        return_value=payload,
    ):
        resp = client.get(
            "/api/superadmin/adjustment-analytics/language_complexity",
            headers=valid_auth_header,
        )
    assert resp.status_code == 200
    assert resp.json()["verdict"] == "on_track_for_permanent"


def test_adjustment_analytics_unknown_id_returns_404(
    client, mock_valid_token, valid_auth_header
):
    with _as_role("superadmin"), patch(
        "app.admin.services.tuning_validation_service.get_adjustment_analytics",
        return_value=None,
    ):
        resp = client.get(
            "/api/superadmin/adjustment-analytics/nope", headers=valid_auth_header
        )
    assert resp.status_code == 404


# ── Force permanent ───────────────────────────────────────────────────────────


def test_force_permanent_promotes_and_reloads_cache(
    client, mock_valid_token, valid_auth_header
):
    with _as_role("superadmin"), patch(
        "app.user.services.prompt_tuning_store.promote",
        return_value={"ok": True, "error": None, "adjustment": {"id": "x"}},
    ) as promote, patch(
        "app.user.services.chatbot_service._reload_prompt_tuning"
    ) as reload:
        resp = client.post(
            "/api/superadmin/force-permanent/x", headers=valid_auth_header
        )
    assert resp.status_code == 200
    promote.assert_called_once_with("x", "test-user-123", reason="manual_override")
    reload.assert_called_once()


def test_force_permanent_unknown_id_returns_404(
    client, mock_valid_token, valid_auth_header
):
    with _as_role("superadmin"), patch(
        "app.user.services.prompt_tuning_store.promote",
        return_value={"ok": False, "error": "not_found", "adjustment": None},
    ):
        resp = client.post(
            "/api/superadmin/force-permanent/x", headers=valid_auth_header
        )
    assert resp.status_code == 404


def test_force_permanent_already_permanent_returns_409(
    client, mock_valid_token, valid_auth_header
):
    with _as_role("superadmin"), patch(
        "app.user.services.prompt_tuning_store.promote",
        return_value={"ok": False, "error": "already_permanent", "adjustment": {}},
    ):
        resp = client.post(
            "/api/superadmin/force-permanent/x", headers=valid_auth_header
        )
    assert resp.status_code == 409


# ── Remove adjustment ─────────────────────────────────────────────────────────


def test_remove_adjustment_requires_a_comment(
    client, mock_valid_token, valid_auth_header
):
    """Step 5: manual removal always records why."""
    with _as_role("superadmin"):
        resp = client.post(
            "/api/superadmin/remove-adjustment/x", headers=valid_auth_header, json={}
        )
    assert resp.status_code == 422


def test_remove_adjustment_rejects_a_trivial_comment(
    client, mock_valid_token, valid_auth_header
):
    with _as_role("superadmin"):
        resp = client.post(
            "/api/superadmin/remove-adjustment/x",
            headers=valid_auth_header,
            json={"comment": "x"},
        )
    assert resp.status_code == 422


def test_remove_adjustment_trashes_with_the_comment(
    client, mock_valid_token, valid_auth_header
):
    with _as_role("superadmin"), patch(
        "app.user.services.prompt_tuning_store.trash",
        return_value={"ok": True, "error": None, "item": {"reason": "manual_removal"}},
    ) as trash, patch("app.user.services.chatbot_service._reload_prompt_tuning"):
        resp = client.post(
            "/api/superadmin/remove-adjustment/x",
            headers=valid_auth_header,
            json={"comment": "made answers worse"},
        )
    assert resp.status_code == 200
    kwargs = trash.call_args.kwargs
    assert kwargs["actor_uid"] == "test-user-123"
    assert kwargs["reason"] == "manual_removal"
    assert kwargs["comment"] == "made answers worse"


def test_remove_adjustment_unknown_id_returns_404(
    client, mock_valid_token, valid_auth_header
):
    with _as_role("superadmin"), patch(
        "app.user.services.prompt_tuning_store.trash",
        return_value={"ok": False, "error": "not_found", "item": None},
    ):
        resp = client.post(
            "/api/superadmin/remove-adjustment/x",
            headers=valid_auth_header,
            json={"comment": "because"},
        )
    assert resp.status_code == 404


# ── Clear trash ───────────────────────────────────────────────────────────────


def test_clear_trash_purges_expired_only_by_default(
    client, mock_valid_token, valid_auth_header
):
    with _as_role("superadmin"), patch(
        "app.user.services.prompt_tuning_store.purge_expired_trash",
        return_value={"deleted": ["a"], "remaining": 2},
    ) as purge:
        resp = client.delete("/api/superadmin/clear-trash", headers=valid_auth_header)
    assert resp.status_code == 200
    assert resp.json() == {
        "status": "ok",
        "deleted_count": 1,
        "deleted_ids": ["a"],
        "remaining": 2,
    }
    assert purge.call_args.kwargs["force_all"] is False


def test_clear_trash_all_items_forces_the_purge(
    client, mock_valid_token, valid_auth_header
):
    with _as_role("superadmin"), patch(
        "app.user.services.prompt_tuning_store.purge_expired_trash",
        return_value={"deleted": ["a", "b"], "remaining": 0},
    ) as purge:
        resp = client.delete(
            "/api/superadmin/clear-trash?all_items=true", headers=valid_auth_header
        )
    assert resp.status_code == 200
    assert purge.call_args.kwargs["force_all"] is True
