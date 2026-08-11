"""Tests for attributing a rejected login attempt to an account.

The admin Security dashboard used to show every failed_login as "unknown",
because nothing about the rejected token was recorded. These cover the rule
that decides what may be shown as fact: a token whose signature Firebase
verified (expired/revoked) yields a trustworthy uid/email, anything else
yields a *claimed* identity that must stay flagged as unverified — a forged
JWT naming the admin must never render as the admin.
"""

import base64
import json
from unittest.mock import MagicMock, patch

from firebase_admin import auth as fb_auth

from app.middleware import auth as auth_mw


def _token(claims: dict) -> str:
    """Build an unsigned JWT-shaped token carrying `claims`."""

    def seg(obj) -> str:
        raw = json.dumps(obj).encode()
        return base64.urlsafe_b64encode(raw).decode().rstrip("=")

    return f"{seg({'alg': 'RS256'})}.{seg(claims)}.signature-not-checked"


CLAIMS = {"user_id": "u1", "email": "farmer@x.com"}


# ═══════════════════════════════════════════════════════════════════════════
# _unverified_claims
# ═══════════════════════════════════════════════════════════════════════════


def test_unverified_claims_decodes_payload_without_a_valid_signature():
    assert auth_mw._unverified_claims(_token(CLAIMS)) == CLAIMS


def test_unverified_claims_rejects_oversized_token():
    """A junk Authorization header must not push a large blob into Firestore."""
    huge = _token({"user_id": "u1", "padding": "x" * auth_mw._MAX_TOKEN_BYTES})
    assert auth_mw._unverified_claims(huge) == {}


def test_unverified_claims_returns_empty_for_garbage():
    for junk in ("", "not-a-jwt", "a.b", "a.!!!.c"):
        assert auth_mw._unverified_claims(junk) == {}


def test_claimed_str_truncates_overlong_claim():
    long_email = "a" * 500
    claims = {"email": long_email}
    assert len(auth_mw._claimed_str(claims, "email")) == auth_mw._MAX_CLAIM_CHARS


# ═══════════════════════════════════════════════════════════════════════════
# _classify_failure — what may be presented as fact
# ═══════════════════════════════════════════════════════════════════════════


def test_expired_token_yields_a_trusted_identity():
    """Firebase only reports expiry after the signature checks out, so the
    claims came from a token it really issued to that account."""
    exc = fb_auth.ExpiredIdTokenError("expired", cause=None)
    failure = auth_mw._classify_failure(_token(CLAIMS), exc)

    assert failure["reason"] == "token_expired"
    assert failure["uid"] == "u1"
    assert failure["email"] == "farmer@x.com"
    assert "claimed_email" not in failure


def test_revoked_token_yields_a_trusted_identity():
    exc = fb_auth.RevokedIdTokenError("revoked")
    failure = auth_mw._classify_failure(_token(CLAIMS), exc)

    assert failure["reason"] == "token_revoked"
    assert failure["email"] == "farmer@x.com"


def test_unverifiable_token_identity_stays_a_claim():
    """The signature never verified — anyone could have written these claims."""
    exc = fb_auth.InvalidIdTokenError("bad signature")
    failure = auth_mw._classify_failure(_token(CLAIMS), exc)

    assert failure["reason"] == "token_invalid"
    assert failure["claimed_email"] == "farmer@x.com"
    assert failure["claimed_uid"] == "u1"
    # Must not leak into the fields the dashboard renders as fact.
    assert "uid" not in failure
    assert "email" not in failure


def test_unparseable_token_yields_no_identity_at_all():
    exc = fb_auth.InvalidIdTokenError("bad token")
    failure = auth_mw._classify_failure("garbage", exc)

    assert failure["reason"] == "token_invalid"
    assert failure["claimed_uid"] == ""
    assert failure["claimed_email"] == ""


# ═══════════════════════════════════════════════════════════════════════════
# _record_failed_login — how attribution reaches the event document
# ═══════════════════════════════════════════════════════════════════════════


def _request(path: str = "/api/yield/predict") -> MagicMock:
    request = MagicMock()
    request.url.path = path
    request.client.host = "1.2.3.4"
    request.headers = {}
    return request


def test_record_promotes_a_verified_identity_to_the_event():
    failure = {"reason": "token_expired", "uid": "u1", "email": "farmer@x.com"}
    with patch("app.utils.security_logger.record_failed_login") as mock_rec:
        auth_mw._record_failed_login(_request(), failure)

    kwargs = mock_rec.call_args.kwargs
    assert kwargs["uid"] == "u1"
    assert kwargs["email"] == "farmer@x.com"
    assert kwargs["details"]["reason"] == "token_expired"
    assert "identity_verified" not in kwargs["details"]


def test_record_keeps_a_claimed_identity_out_of_uid_and_email():
    """A crafted token must not be able to pin a failed login on a real user."""
    failure = {
        "reason": "token_invalid",
        "claimed_uid": "admin-uid",
        "claimed_email": "admin@x.com",
    }
    with patch("app.utils.security_logger.record_failed_login") as mock_rec:
        auth_mw._record_failed_login(_request(), failure)

    kwargs = mock_rec.call_args.kwargs
    assert kwargs["uid"] == ""
    assert kwargs["email"] == ""
    assert kwargs["details"]["identity_verified"] is False
    assert kwargs["details"]["claimed_email"] == "admin@x.com"


def test_record_marks_a_missing_header_as_having_no_identity():
    failure = {"reason": "missing_or_malformed_authorization_header"}
    with patch("app.utils.security_logger.record_failed_login") as mock_rec:
        auth_mw._record_failed_login(_request(), failure)

    kwargs = mock_rec.call_args.kwargs
    assert kwargs["uid"] == ""
    assert kwargs["email"] == ""
    assert "claimed_uid" not in kwargs["details"]


def test_record_never_raises_when_persistence_fails():
    """Attribution must not turn an auth rejection into a 500."""
    with patch(
        "app.utils.security_logger.record_failed_login",
        side_effect=RuntimeError("firestore down"),
    ):
        auth_mw._record_failed_login(_request(), {"reason": "token_invalid"})


# ═══════════════════════════════════════════════════════════════════════════
# _verify — contract used by the middleware
# ═══════════════════════════════════════════════════════════════════════════


def test_verify_returns_uid_and_no_failure_on_success(monkeypatch):
    monkeypatch.setattr(
        "firebase_admin.auth.verify_id_token",
        lambda token, **kw: {"uid": "u1", "email": "farmer@x.com"},
    )
    with patch("app.utils.firestore.get_or_create_user"):
        uid, failure = auth_mw._verify("any-token")

    assert uid == "u1"
    assert failure == {}


def test_verify_reports_expiry_with_the_account_that_expired(monkeypatch):
    def _raise(token, **kw):
        raise fb_auth.ExpiredIdTokenError("expired", cause=None)

    monkeypatch.setattr("firebase_admin.auth.verify_id_token", _raise)
    uid, failure = auth_mw._verify(_token(CLAIMS))

    assert uid is None
    assert failure["reason"] == "token_expired"
    assert failure["email"] == "farmer@x.com"
