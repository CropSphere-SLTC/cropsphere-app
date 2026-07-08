"""FastAPI dependency functions shared across routers."""

from fastapi import HTTPException, Request


def get_user_id(request: Request) -> str:
    """Return user_id attached to request.state by FirebaseAuthMiddleware."""
    uid = getattr(request.state, "user_id", None)
    if not uid:
        raise HTTPException(status_code=401, detail="Not authenticated")
    return uid
