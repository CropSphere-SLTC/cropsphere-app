"""Unit tests for app.middleware.roles — role-based access dependencies.

Calls the dependency functions directly (no HTTP layer). Firestore lookups
(is_user_banned, get_user_role) are patched at their point of use — the
functions import them locally from app.utils.firestore.
"""

from types import SimpleNamespace

import pytest
from fastapi import HTTPException

from app.middleware import roles


def _request(user_id=None):
    """Fake Request whose state carries the middleware-set user_id."""
    return SimpleNamespace(state=SimpleNamespace(user_id=user_id))


# ═══════════════════════════════════════════════════════════════════════════
# get_current_uid
# ═══════════════════════════════════════════════════════════════════════════


def test_get_current_uid_returns_uid_when_present():
    assert roles.get_current_uid(_request("uid-1")) == "uid-1"


def test_get_current_uid_raises_401_when_missing():
    with pytest.raises(HTTPException) as exc:
        roles.get_current_uid(_request(None))
    assert exc.value.status_code == 401


def test_get_current_uid_raises_401_when_state_has_no_user_id():
    req = SimpleNamespace(state=SimpleNamespace())
    with pytest.raises(HTTPException) as exc:
        roles.get_current_uid(req)
    assert exc.value.status_code == 401


# ═══════════════════════════════════════════════════════════════════════════
# require_user
# ═══════════════════════════════════════════════════════════════════════════


def test_require_user_allows_non_banned():
    with pytest.MonkeyPatch.context() as mp:
        mp.setattr("app.utils.firestore.is_user_banned", lambda uid: False)
        assert roles.require_user("uid-1") == "uid-1"


def test_require_user_raises_403_when_banned():
    with pytest.MonkeyPatch.context() as mp:
        mp.setattr("app.utils.firestore.is_user_banned", lambda uid: True)
        with pytest.raises(HTTPException) as exc:
            roles.require_user("uid-1")
    assert exc.value.status_code == 403


def test_require_user_swallows_lookup_errors_and_allows():
    def _boom(uid):
        raise RuntimeError("firestore down")

    with pytest.MonkeyPatch.context() as mp:
        mp.setattr("app.utils.firestore.is_user_banned", _boom)
        # Non-HTTPException errors are swallowed -> user allowed through
        assert roles.require_user("uid-1") == "uid-1"


# ═══════════════════════════════════════════════════════════════════════════
# require_admin
# ═══════════════════════════════════════════════════════════════════════════


def test_require_admin_allows_admin():
    with pytest.MonkeyPatch.context() as mp:
        mp.setattr("app.utils.firestore.get_user_role", lambda uid: "admin")
        assert roles.require_admin("uid-1") == "uid-1"


def test_require_admin_allows_superadmin():
    with pytest.MonkeyPatch.context() as mp:
        mp.setattr("app.utils.firestore.get_user_role", lambda uid: "superadmin")
        assert roles.require_admin("uid-1") == "uid-1"


def test_require_admin_rejects_regular_user():
    with pytest.MonkeyPatch.context() as mp:
        mp.setattr("app.utils.firestore.get_user_role", lambda uid: "user")
        with pytest.raises(HTTPException) as exc:
            roles.require_admin("uid-1")
    assert exc.value.status_code == 403
    assert "Admin access required" in exc.value.detail


def test_require_admin_rejects_banned():
    with pytest.MonkeyPatch.context() as mp:
        mp.setattr("app.utils.firestore.get_user_role", lambda uid: "banned")
        with pytest.raises(HTTPException) as exc:
            roles.require_admin("uid-1")
    assert exc.value.status_code == 403
    assert "banned" in exc.value.detail.lower()


# ═══════════════════════════════════════════════════════════════════════════
# require_superadmin
# ═══════════════════════════════════════════════════════════════════════════


def test_require_superadmin_allows_superadmin():
    with pytest.MonkeyPatch.context() as mp:
        mp.setattr("app.utils.firestore.get_user_role", lambda uid: "superadmin")
        assert roles.require_superadmin("uid-1") == "uid-1"


def test_require_superadmin_rejects_admin():
    with pytest.MonkeyPatch.context() as mp:
        mp.setattr("app.utils.firestore.get_user_role", lambda uid: "admin")
        with pytest.raises(HTTPException) as exc:
            roles.require_superadmin("uid-1")
    assert exc.value.status_code == 403
    assert "Superadmin access required" in exc.value.detail


# ═══════════════════════════════════════════════════════════════════════════
# get_current_role
# ═══════════════════════════════════════════════════════════════════════════


def test_get_current_role_returns_uid_and_role():
    with pytest.MonkeyPatch.context() as mp:
        mp.setattr("app.utils.firestore.get_user_role", lambda uid: "admin")
        result = roles.get_current_role("uid-1")
    assert result == {"uid": "uid-1", "role": "admin"}
