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


def require_user(uid: str = Depends(get_current_uid)) -> str:
    """Allow any authenticated non-banned user."""
    from app.utils.firestore import is_user_banned
    try:
        if is_user_banned(uid):
            raise HTTPException(status_code=403, detail="Account banned")
    except HTTPException:
        raise
    except Exception:
        pass
    return uid


def require_admin(uid: str = Depends(get_current_uid)) -> str:
    """Allow admin and superadmin only. Returns 403 for regular users."""
    from app.utils.firestore import get_user_role
    role = get_user_role(uid)
    if role == "banned":
        raise HTTPException(status_code=403, detail="Account banned")
    if role not in ("admin", "superadmin"):
        raise HTTPException(status_code=403, detail="Admin access required")
    return uid


def require_superadmin(uid: str = Depends(get_current_uid)) -> str:
    """Allow superadmin only."""
    from app.utils.firestore import get_user_role
    role = get_user_role(uid)
    if role != "superadmin":
        raise HTTPException(status_code=403, detail="Superadmin access required")
    return uid


def get_current_role(uid: str = Depends(get_current_uid)) -> dict:
    """Return both uid and role for endpoints that need role-aware responses."""
    from app.utils.firestore import get_user_role
    role = get_user_role(uid)
    return {"uid": uid, "role": role}
