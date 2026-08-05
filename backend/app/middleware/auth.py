"""Firebase JWT authentication middleware (Keshan — shift-left security)."""

import base64
import json
import logging
from typing import Optional

from fastapi.responses import JSONResponse
from starlette.middleware.base import BaseHTTPMiddleware
from starlette.requests import Request

# In-memory session cache — prevents duplicate session documents per container lifetime
_session_cache: set = set()
# In-memory cache of uids confirmed to have a Firestore user document —
# prevents re-reading (and, historically, re-writing photo_url on) the same
# document on every single authenticated request. Safe to cache for the
# container's lifetime: existence doesn't change, and role/ban status is
# never sourced from this call (roles.py always fetches those fresh).
_known_users: set = set()

logger = logging.getLogger(__name__)

# Paths that bypass JWT verification
_PUBLIC_PATHS = {"/api/health", "/docs", "/openapi.json", "/redoc"}

# Caps on what a *rejected* token may contribute to a security event. Firebase
# ID tokens sit well under 4 KB; anything larger is junk we refuse to parse,
# and individual claims are truncated so a crafted header cannot write an
# unbounded string into Firestore.
_MAX_TOKEN_BYTES = 4096
_MAX_CLAIM_CHARS = 254


class FirebaseAuthMiddleware(BaseHTTPMiddleware):
    """Verify a Firebase ID token on every request except public paths.

    On success: attaches uid to request.state.user_id and passes through.
    On failure: returns 401 JSON immediately — no route handler is called.
    Security assumption: firebase_admin is fully initialised before requests arrive.
    """

    async def dispatch(self, request: Request, call_next):
        if request.method == "OPTIONS":
            return await call_next(request)

        path = request.url.path

        if _is_public(path):
            return await call_next(request)

        token = _extract_bearer(request)
        if token is None:
            _record_failed_login(
                request, {"reason": "missing_or_malformed_authorization_header"}
            )
            return JSONResponse(
                status_code=401,
                content={"detail": "Authorization header missing or malformed"},
            )

        uid, failure = _verify(token)
        if uid is None:
            _record_failed_login(request, failure)
            return JSONResponse(
                status_code=401,
                content={"detail": "Token invalid or expired"},
            )

        _track_session(uid, request)

        request.state.user_id = uid
        return await call_next(request)


def _is_public(path: str) -> bool:
    """Return True if path is exempt from authentication."""
    return (
        path in _PUBLIC_PATHS or path.startswith("/docs") or path.startswith("/redoc")
    )


def _record_failed_login(request: Request, failure: dict) -> None:
    """Best-effort persistence of an authentication failure to security_events.

    `failure` is the dict from _verify: a reason, plus whatever identity the
    rejected token carried. Only a signature-verified identity (expired or
    revoked token) is promoted to the event's uid/email — those are the fields
    the admin dashboard treats as fact. An identity claimed by a token whose
    signature never checked out stays inside details as claimed_uid/
    claimed_email with identity_verified=False, because anyone can mint a JWT
    naming anyone; recording it is useful signal ("someone is presenting
    tokens claiming to be the admin"), trusting it would be a spoofing hole.

    Never raises — auth rejection must proceed regardless of Firestore state.
    Note: this runs on every rejected request, but SlowAPIMiddleware (outer)
    caps requests per IP before they reach here, bounding write amplification
    from a flood of invalid tokens.
    """
    try:
        from slowapi.util import get_remote_address

        from app.utils.security_logger import record_failed_login

        details = {"reason": failure.get("reason", "")}
        claimed_uid = failure.get("claimed_uid", "")
        claimed_email = failure.get("claimed_email", "")
        if claimed_uid or claimed_email:
            details["identity_verified"] = False
            if claimed_uid:
                details["claimed_uid"] = claimed_uid
            if claimed_email:
                details["claimed_email"] = claimed_email

        record_failed_login(
            endpoint=request.url.path,
            ip_address=get_remote_address(request),
            reason=failure.get("reason", ""),
            uid=failure.get("uid", ""),
            email=failure.get("email", ""),
            details=details,
        )
    except Exception as exc:
        logger.debug("failed_login event not recorded: %s", exc)


def _extract_bearer(request: Request) -> Optional[str]:
    """Return the raw token from 'Authorization: Bearer <token>'."""
    header = request.headers.get("Authorization", "")
    if header.startswith("Bearer "):
        return header[7:]
    return None


def _track_session(uid: str, request: Request) -> None:
    """Record login activity once per container lifetime per user.

    Uses an in-memory cache to avoid writing a new session document
    on every authenticated request — only fires on first request per UID.
    """
    if uid in _session_cache:
        return
    _session_cache.add(uid)
    try:
        from app.utils.firestore import create_session, update_last_login

        device_info = request.headers.get("User-Agent", "unknown")
        update_last_login(uid)
        create_session(uid, device_info)
    except Exception as exc:
        logger.warning("Session tracking failed for uid=%s: %s", uid, exc)


def _unverified_claims(token: str) -> dict:
    """Decode a JWT payload WITHOUT verifying its signature.

    Inputs: a raw bearer token that failed verification.
    Outputs: the payload dict, or {} if it is not a decodable JWT.

    Security assumption: every value here is attacker-controlled — anyone can
    craft a token with any uid or email in it. The result is only ever shown
    to an admin as a *claimed* identity, never used for authentication,
    authorisation, or lookups. Oversized tokens are rejected outright so a
    junk Authorization header cannot push a large blob into Firestore.
    """
    if not token or len(token) > _MAX_TOKEN_BYTES:
        return {}
    try:
        payload = token.split(".")[1]
        payload += "=" * (-len(payload) % 4)  # restore base64url padding
        claims = json.loads(base64.urlsafe_b64decode(payload))
        return claims if isinstance(claims, dict) else {}
    except Exception:
        return {}


def _claimed_str(claims: dict, *keys: str) -> str:
    """First present string claim among `keys`, truncated for safe storage."""
    for key in keys:
        value = claims.get(key)
        if isinstance(value, str) and value:
            return value[:_MAX_CLAIM_CHARS]
    return ""


def _verify(token: str) -> tuple:
    """Verify a Firebase ID token using the Firebase Admin SDK.

    firebase-admin 5.0+ verifies tokens via Google's public certificate
    endpoint — no service-account private key is required for this operation.
    The project_id is used to validate the 'aud' claim.

    Returns (uid, failure): on success (uid, {}); on rejection (None, failure)
    where failure carries the reason plus whatever identity can be attributed
    to the attempt, for the security dashboard.

    Expiry and revocation are reported separately from a plain invalid token
    because firebase-admin only raises those two *after* the signature checks
    out — the token really was issued by Firebase to that account, so its uid
    and email are trustworthy. Anything else means the signature never
    verified, and the token's claims are recorded as claims, nothing more.
    """
    try:
        import firebase_admin
        from firebase_admin import auth as fb_auth
        from app.config import get_settings

        # Initialise a minimal Firebase app (project-id only) if none exists.
        # init_firestore() may have already done this with full credentials;
        # if it failed (e.g. empty credentials file) _apps will be empty.
        if not firebase_admin._apps:
            firebase_admin.initialize_app(
                options={"projectId": get_settings().FIREBASE_PROJECT_ID}
            )

        decoded = fb_auth.verify_id_token(token)
        uid = decoded.get("uid")
        email = decoded.get("email", "")
        photo_url = decoded.get("picture", "")
        # Create user document in Firestore if first login. Only needs to
        # run once per uid per container lifetime — every request after
        # that would otherwise re-read (and potentially re-write) this
        # document for no reason, which is what was driving Firestore 429s
        # under sustained traffic. Role/ban status is never sourced from
        # this call, so skipping it on repeat requests doesn't affect the
        # freshness of those checks (see app.middleware.roles).
        if uid not in _known_users:
            try:
                from app.utils.firestore import get_or_create_user

                get_or_create_user(uid, email, photo_url)
                _known_users.add(uid)
            except Exception:
                pass  # Never block auth for Firestore failures
        return uid, {}
    except Exception as exc:
        logger.warning(
            "JWT verification failed: %s — %s",
            type(exc).__name__,
            str(exc)[:200],
        )
        return None, _classify_failure(token, exc)


def _classify_failure(token: str, exc: Exception) -> dict:
    """Describe a rejected token for the security dashboard.

    Inputs: the raw token and the exception verification raised.
    Outputs: {"reason": ..., "uid"/"email": ...} when the identity is
    trustworthy, or {"reason": ..., "claimed_uid"/"claimed_email": ...} when it
    is only asserted by an unverified token. Never raises — attribution must
    not turn an auth rejection into a 500.
    """
    claims = _unverified_claims(token)
    uid = _claimed_str(claims, "user_id", "sub", "uid")
    email = _claimed_str(claims, "email")

    if _signature_verified(exc):
        # Firebase reached the expiry/revocation check, which it only does
        # once the signature, issuer and audience all check out — so these
        # claims came from a token Firebase really issued to this account.
        reason = "token_expired" if _is_expired(exc) else "token_revoked"
        return {"reason": reason, "uid": uid, "email": email}

    return {
        "reason": "token_invalid",
        "claimed_uid": uid,
        "claimed_email": email,
    }


def _is_expired(exc: Exception) -> bool:
    """True when verification failed specifically because the token aged out."""
    try:
        from firebase_admin import auth as fb_auth

        return isinstance(exc, fb_auth.ExpiredIdTokenError)
    except Exception:
        return False


def _signature_verified(exc: Exception) -> bool:
    """True when the failure is expiry or revocation — both raised only after
    firebase-admin has already verified the token's signature."""
    try:
        from firebase_admin import auth as fb_auth

        return isinstance(
            exc, (fb_auth.ExpiredIdTokenError, fb_auth.RevokedIdTokenError)
        )
    except Exception:
        return False
