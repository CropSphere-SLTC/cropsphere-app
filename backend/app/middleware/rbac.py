"""RBAC — Admin/User role checking."""
from enum import Enum
from fastapi import Depends, HTTPException, Request
from app.dependencies import get_user_id


class Role(str, Enum):
    user = "user"
    admin = "admin"


def get_role(request: Request) -> str:
    return getattr(request.state, "role", "user")


def require_role(required_role: Role):
    """Admin route ට user ගියොත් 403 දෙනවා."""
    def _check(
        user_id: str = Depends(get_user_id),
        role: str = Depends(get_role),
    ) -> str:
        if role != required_role.value:
            raise HTTPException(
                status_code=403,
                detail=f"Requires '{required_role.value}' role. Your role: '{role}'.",
            )
        return user_id
    return _check
