"""User profile and preferences router."""

from fastapi import APIRouter, Depends, HTTPException, Request

from app.dependencies import get_user_id
from app.middleware.rate_limit import limiter
from app.models.schemas import (
    UpdatePreferencesRequest,
    UpdateProfileRequest,
    UserPreferencesResponse,
    UserProfileResponse,
)
from app.user.services.profile_service import (
    get_preferences,
    get_profile,
    update_preferences,
    update_profile,
)

router = APIRouter(prefix="/api/user", tags=["profile"])


@router.get("/profile", response_model=UserProfileResponse)
@limiter.limit("30/minute")
async def profile_get(
    request: Request,
    user_id: str = Depends(get_user_id),
) -> UserProfileResponse:
    """Return the caller's profile.

    Requires valid Firebase JWT.  Rate limited: 30 req/min per IP.
    """
    try:
        return get_profile(user_id)
    except RuntimeError as exc:
        raise HTTPException(status_code=500, detail=str(exc))


@router.patch("/profile")
@limiter.limit("30/minute")
async def profile_update(
    request: Request,
    body: UpdateProfileRequest,
    user_id: str = Depends(get_user_id),
):
    """Update the caller's display name.

    Requires valid Firebase JWT.  Rate limited: 30 req/min per IP.
    """
    try:
        return update_profile(user_id, body)
    except RuntimeError as exc:
        raise HTTPException(status_code=500, detail=str(exc))


@router.get("/preferences", response_model=UserPreferencesResponse)
@limiter.limit("30/minute")
async def preferences_get(
    request: Request,
    user_id: str = Depends(get_user_id),
) -> UserPreferencesResponse:
    """Return the caller's language and notification preferences.

    Requires valid Firebase JWT.  Rate limited: 30 req/min per IP.
    """
    try:
        return get_preferences(user_id)
    except RuntimeError as exc:
        raise HTTPException(status_code=500, detail=str(exc))


@router.patch("/preferences")
@limiter.limit("30/minute")
async def preferences_update(
    request: Request,
    body: UpdatePreferencesRequest,
    user_id: str = Depends(get_user_id),
):
    """Save the caller's language and notification preferences.

    Requires valid Firebase JWT.  Rate limited: 30 req/min per IP.
    """
    try:
        return update_preferences(user_id, body)
    except RuntimeError as exc:
        raise HTTPException(status_code=500, detail=str(exc))
