"""Firebase JWT authentication middleware (Keshan — shift-left security)."""

import logging
from typing import Optional

from fastapi.responses import JSONResponse
from starlette.middleware.base import BaseHTTPMiddleware
from starlette.requests import Request

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
        return decoded.get("uid")
    except Exception as exc:
        logger.warning(
            "JWT verification failed: %s — %s",
            type(exc).__name__,
            str(exc)[:200],
        )
        return None
