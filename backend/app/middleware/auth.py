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
    return path in _PUBLIC_PATHS or path.startswith("/docs") or path.startswith("/redoc")


def _extract_bearer(request: Request) -> Optional[str]:
    """Return the raw token from 'Authorization: Bearer <token>'."""
    header = request.headers.get("Authorization", "")
    if header.startswith("Bearer "):
        return header[7:]
    return None


def _verify(token: str) -> Optional[str]:
    """Verify a Firebase ID token using Google's public keys.

    Uses google.oauth2.id_token directly — no service-account credentials needed.
    Google's public key endpoint is public; only the project_id is required to
    validate the 'aud' claim.
    """
    try:
        from google.auth.transport import requests as google_requests
        from google.oauth2 import id_token
        from app.config import get_settings

        request = google_requests.Request()
        decoded = id_token.verify_firebase_token(
            token, request, audience=get_settings().FIREBASE_PROJECT_ID
        )
        return decoded.get("uid") or decoded.get("sub")
    except Exception as exc:
        logger.warning("JWT verification failed: %s", type(exc).__name__)
        return None
