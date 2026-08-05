"""Tests for force-logout enforcement in the auth middleware.

revoke_refresh_tokens only stops a client renewing its session — the ID token
already in the user's browser stays cryptographically valid for about an hour.
These cover the check that makes "Force Logout" actually end access: a token
issued before the revocation is refused, one issued after is not, and the
revocation list is read on a timer rather than on every request.
"""

from datetime import datetime, timedelta, timezone
from unittest.mock import patch

import pytest

from app.middleware import auth as auth_mw


@pytest.fixture(autouse=True)
def _clear_revocation_cache():
    """The cache is module state — reset it around every test."""
    auth_mw._revocations = {}
    auth_mw._revocations_loaded_at = 0.0
    yield
    auth_mw._revocations = {}
    auth_mw._revocations_loaded_at = 0.0


NOW = datetime.now(timezone.utc)
REVOKED_AT = NOW - timedelta(minutes=5)


def _token_claims(issued: datetime) -> dict:
    return {"auth_time": int(issued.timestamp())}


# ═══════════════════════════════════════════════════════════════════════════
# _session_revoked
# ═══════════════════════════════════════════════════════════════════════════


def test_token_issued_before_revocation_is_refused():
    with patch(
        "app.utils.firestore.list_token_revocations",
        return_value={"u1": REVOKED_AT},
    ):
        revoked = auth_mw._session_revoked(
            "u1", _token_claims(NOW - timedelta(minutes=30))
        )

    assert revoked is True


def test_token_issued_after_revocation_is_accepted():
    """The user logged back in — a past force-logout must not lock them out
    of the app permanently."""
    with patch(
        "app.utils.firestore.list_token_revocations",
        return_value={"u1": REVOKED_AT},
    ):
        revoked = auth_mw._session_revoked("u1", _token_claims(NOW))

    assert revoked is False


def test_never_revoked_user_is_unaffected():
    with patch(
        "app.utils.firestore.list_token_revocations",
        return_value={"someone-else": REVOKED_AT},
    ):
        revoked = auth_mw._session_revoked(
            "u1", _token_claims(NOW - timedelta(hours=2))
        )

    assert revoked is False


def test_token_without_a_usable_auth_time_is_refused():
    """Fail closed: an admin ended this session, so a token whose age we
    cannot establish is refused rather than waved through."""
    with patch(
        "app.utils.firestore.list_token_revocations",
        return_value={"u1": REVOKED_AT},
    ):
        assert auth_mw._session_revoked("u1", {}) is True
        assert auth_mw._session_revoked("u1", {"auth_time": "not-a-number"}) is True


def test_iat_is_used_when_auth_time_is_absent():
    with patch(
        "app.utils.firestore.list_token_revocations",
        return_value={"u1": REVOKED_AT},
    ):
        revoked = auth_mw._session_revoked(
            "u1", {"iat": int((NOW - timedelta(minutes=30)).timestamp())}
        )

    assert revoked is True


def test_firestore_failure_fails_open():
    """Locking every user out because one auxiliary read failed is worse than
    a revoked session lasting until its token expires."""
    with patch(
        "app.utils.firestore.list_token_revocations",
        side_effect=RuntimeError("firestore down"),
    ):
        revoked = auth_mw._session_revoked(
            "u1", _token_claims(NOW - timedelta(hours=2))
        )

    assert revoked is False


# ═══════════════════════════════════════════════════════════════════════════
# Refresh cadence — one read per interval, not one per request
# ═══════════════════════════════════════════════════════════════════════════


def test_revocation_list_is_not_reread_on_every_request():
    with patch(
        "app.utils.firestore.list_token_revocations",
        return_value={"u1": REVOKED_AT},
    ) as mock_list:
        for _ in range(20):
            auth_mw._session_revoked("u1", _token_claims(NOW))

    mock_list.assert_called_once()


def test_revocation_list_is_refreshed_after_the_interval():
    with patch(
        "app.utils.firestore.list_token_revocations",
        return_value={"u1": REVOKED_AT},
    ) as mock_list:
        auth_mw._session_revoked("u1", _token_claims(NOW))
        # Pretend the last refresh happened a full interval ago.
        auth_mw._revocations_loaded_at -= auth_mw._REVOCATION_REFRESH_SECONDS
        auth_mw._session_revoked("u1", _token_claims(NOW))

    assert mock_list.call_count == 2


def test_refresh_evicts_revoked_uid_from_the_session_cache():
    """Their next login must be recorded afresh in Active Sessions — every
    worker refreshes, so every worker evicts."""
    auth_mw._session_cache.add("u1")
    with patch(
        "app.utils.firestore.list_token_revocations",
        return_value={"u1": REVOKED_AT},
    ):
        auth_mw._session_revoked("u1", _token_claims(NOW))

    assert "u1" not in auth_mw._session_cache


# ═══════════════════════════════════════════════════════════════════════════
# _verify — a revoked session is reported as an attributable failure
# ═══════════════════════════════════════════════════════════════════════════


def test_verify_rejects_a_revoked_session_with_a_verified_identity(monkeypatch):
    monkeypatch.setattr(
        "firebase_admin.auth.verify_id_token",
        lambda token, **kw: {
            "uid": "u1",
            "email": "farmer@x.com",
            "auth_time": int((NOW - timedelta(minutes=30)).timestamp()),
        },
    )
    with patch(
        "app.utils.firestore.list_token_revocations",
        return_value={"u1": REVOKED_AT},
    ):
        uid, failure = auth_mw._verify("any-token")

    assert uid is None
    assert failure["reason"] == "session_revoked_by_admin"
    assert failure["uid"] == "u1"
    assert failure["email"] == "farmer@x.com"


def test_revoked_session_gets_its_own_401_message(client, monkeypatch):
    """The client needs to tell "sign in again" apart from "an admin ended
    this" — same status, different detail."""
    monkeypatch.setattr(
        "firebase_admin.auth.verify_id_token",
        lambda token, **kw: {
            "uid": "u1",
            "auth_time": int((NOW - timedelta(minutes=30)).timestamp()),
        },
    )
    with patch(
        "app.utils.firestore.list_token_revocations",
        return_value={"u1": REVOKED_AT},
    ), patch("app.utils.security_logger.record_failed_login"):
        resp = client.get(
            "/api/admin/stats", headers={"Authorization": "Bearer live-token"}
        )

    assert resp.status_code == 401
    assert resp.json()["detail"] == "Session ended by an administrator"
