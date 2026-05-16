"""FastAPI dependency functions shared across routers."""

from fastapi import Request


def get_user_id(request: Request) -> str:
    """Return user_id attached to request.state by FirebaseAuthMiddleware."""
    return request.state.user_id
