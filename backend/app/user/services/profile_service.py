"""User profile and preferences service — reads/writes the users collection."""

import logging

from app.models.schemas import (
    NotificationPreferences,
    UpdatePreferencesRequest,
    UpdateProfileRequest,
    UserPreferencesResponse,
    UserProfileResponse,
)
from app.utils.firestore import (
    get_active_sessions,
    get_user_preferences,
    get_user_profile,
    get_user_role,
    update_user_preferences,
    update_user_profile,
)

logger = logging.getLogger(__name__)


def get_profile(uid: str) -> UserProfileResponse:
    """Return the caller's profile — name, email, photo, role, last login,
    and current active-session count.
    """
    try:
        data = get_user_profile(uid)
        last_login = data.get("last_login")
        name = data.get("display_name") or data.get("email", "").split("@")[0] or uid

        return UserProfileResponse(
            name=name,
            email=data.get("email", ""),
            photo_url=data.get("photo_url"),
            role=get_user_role(uid),
            last_login=last_login.isoformat() if last_login else None,
            active_sessions=get_active_sessions(uid),
        )
    except Exception as exc:
        logger.error(f"get_profile failed uid={uid}: {exc}")
        raise RuntimeError("Failed to load profile") from exc


def update_profile(uid: str, body: UpdateProfileRequest) -> dict:
    """Update the caller's display name."""
    try:
        update_user_profile(uid, body.display_name)
        return {"message": "Profile updated", "display_name": body.display_name}
    except Exception as exc:
        logger.error(f"update_profile failed uid={uid}: {exc}")
        raise RuntimeError("Failed to update profile") from exc


def get_preferences(uid: str) -> UserPreferencesResponse:
    """Return the caller's saved preferences, defaulting when never set."""
    try:
        data = get_user_preferences(uid)
        return UserPreferencesResponse(
            language=data.get("language", "en"),
            notifications=NotificationPreferences(**data.get("notifications", {})),
            preferred_district=data.get("preferred_district"),
            preferred_crop=data.get("preferred_crop"),
        )
    except Exception as exc:
        logger.error(f"get_preferences failed uid={uid}: {exc}")
        raise RuntimeError("Failed to load preferences") from exc


def update_preferences(uid: str, body: UpdatePreferencesRequest) -> dict:
    """Save the caller's language and notification preferences."""
    try:
        update_user_preferences(
            uid,
            {
                "language": body.language,
                "notifications": body.notifications.model_dump(),
            },
        )
        return {
            "message": "Preferences updated",
            "language": body.language,
            "notifications": body.notifications,
        }
    except Exception as exc:
        logger.error(f"update_preferences failed uid={uid}: {exc}")
        raise RuntimeError("Failed to update preferences") from exc
