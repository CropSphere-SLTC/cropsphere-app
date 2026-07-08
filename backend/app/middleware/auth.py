"""Firebase JWT authentication middleware (Keshan — shift-left security)."""

import logging
from typing import Optional

from fastapi.responses import JSONResponse
from starlette.middleware.base import BaseHTTPMiddleware
from starlette.requests import Request

# In-memory session cache — prevents duplicate session documents per container lifetime
_session_cache: set = set()

logger = logging.getLogger(__name__)

# Paths that bypass JWT verification
_PUBLIC_PATHS = {"/api/health", "/docs", "/openapi.json", "/redoc"}


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
            return JSONResponse(
                status_code=401,
                content={"detail": "Authorization header missing or malformed"},
            )

        uid = _verify(token)
        if uid is None:
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
        create_session(uid, device_info)
    except Exception as exc:
        logger.warning("Session tracking failed for uid=%s: %s", uid, exc)


def _verify(token: str) -> Optional[str]:
    """Verify a Firebase ID token using the Firebase Admin SDK.

    firebase-admin 5.0+ verifies tokens via Google's public certificate
    endpoint — no service-account private key is required for this operation.
    The project_id is used to validate the 'aud' claim.
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
        # Create user document in Firestore if first login
        try:
            from app.utils.firestore import get_or_create_user

            get_or_create_user(uid, email, photo_url)
        except Exception:
            pass  # Never block auth for Firestore failures
        return uid
    except Exception as exc:
        logger.warning(
            "JWT verification failed: %s — %s",
            type(exc).__name__,
            str(exc)[:200],
        )
        return None
