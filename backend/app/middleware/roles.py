"""Role-based access control dependencies for FastAPI endpoints."""

import logging
from fastapi import Depends, HTTPException, Request

logger = logging.getLogger(__name__)


def get_current_uid(request: Request) -> str:
    """Extract UID from request state (set by FirebaseAuthMiddleware)."""
    uid = getattr(request.state, "user_id", None)
    if not uid:
        raise HTTPException(status_code=401, detail="Not authenticated")
    return uid


def require_user(
    uid: str = Depends(get_current_uid), request: Request = None
) -> str:
    """Allow any authenticated non-banned user.

    On a banned denial, records a banned_access_attempt security event
    (best-effort) before returning 403. `request` is injected by FastAPI (by
    type annotation, regardless of position); it is None only when the
    dependency is unit-tested by direct call, in which case logging is skipped.
    """
    from app.utils.firestore import is_user_banned

    try:
        if is_user_banned(uid):
            if request is not None:
                _record_banned_access(request, uid)
            raise HTTPException(status_code=403, detail="Account banned")
    except HTTPException:
        raise
    except Exception:
        logger.exception("Ban-status check failed for uid=%s", uid)
        raise HTTPException(status_code=503, detail="Unable to verify account status")
    return uid


def _record_banned_access(request: Request, uid: str) -> None:
    """Best-effort persistence of a banned-access attempt to security_events."""
    try:
        from slowapi.util import get_remote_address

        from app.utils.security_logger import record_banned_access_attempt

        record_banned_access_attempt(
            endpoint=request.url.path,
            ip_address=get_remote_address(request),
            uid=uid,
        )
    except Exception as exc:
        logger.debug("banned_access_attempt event not recorded: %s", exc)


def require_admin(uid: str = Depends(get_current_uid)) -> str:
    """Allow admin and superadmin only. Returns 403 for regular users."""
    from app.utils.firestore import get_user_role

    role = get_user_role(uid)
    if role == "banned":
        logger.warning("require_admin denied uid=%s — account banned", uid)
        raise HTTPException(status_code=403, detail="Account banned")
    if role not in ("admin", "superadmin"):
        logger.warning("require_admin denied uid=%s — resolved role=%s", uid, role)
        raise HTTPException(status_code=403, detail="Admin access required")
    return uid


def require_superadmin(uid: str = Depends(get_current_uid)) -> str:
    """Allow superadmin only."""
    from app.utils.firestore import get_user_role

    role = get_user_role(uid)
    if role != "superadmin":
        logger.warning("require_superadmin denied uid=%s — resolved role=%s", uid, role)
        raise HTTPException(status_code=403, detail="Superadmin access required")
    return uid


def get_current_role(uid: str = Depends(get_current_uid)) -> dict:
    """Return both uid and role for endpoints that need role-aware responses."""
    from app.utils.firestore import get_user_role

    role = get_user_role(uid)
    return {"uid": uid, "role": role}
