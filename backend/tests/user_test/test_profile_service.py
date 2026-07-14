"""Unit tests for app.user.services.profile_service.

Calls the service functions directly (no HTTP layer). Firestore helpers in
app.utils.firestore are mocked so no real infrastructure is required.
"""

from datetime import datetime, timezone
from unittest.mock import patch

import pytest

from app.models.schemas import (
    NotificationPreferences,
    UpdatePreferencesRequest,
    UpdateProfileRequest,
)
from app.user.services import profile_service

UID = "test-user-123"


# ═══════════════════════════════════════════════════════════════════════════
# get_profile
# ═══════════════════════════════════════════════════════════════════════════


def test_get_profile_returns_expected_shape():
    last_login = datetime(2026, 1, 15, 10, 30, tzinfo=timezone.utc)
    profile_data = {
        "display_name": "Nimal Perera",
        "email": "nimal@example.com",
        "photo_url": "https://example.com/photo.jpg",
        "last_login": last_login,
    }

    with patch(
        "app.user.services.profile_service.get_user_profile",
        return_value=profile_data,
    ), patch(
        "app.user.services.profile_service.get_user_role", return_value="user"
    ), patch(
        "app.user.services.profile_service.get_active_sessions", return_value=2
    ):
        result = profile_service.get_profile(UID)

    assert result.name == "Nimal Perera"
    assert result.email == "nimal@example.com"
    assert result.photo_url == "https://example.com/photo.jpg"
    assert result.role == "user"
    assert result.last_login == last_login.isoformat()
    assert result.active_sessions == 2


def test_get_profile_falls_back_to_email_prefix_when_no_display_name():
    profile_data = {"email": "farmer99@example.com", "last_login": None}

    with patch(
        "app.user.services.profile_service.get_user_profile",
        return_value=profile_data,
    ), patch(
        "app.user.services.profile_service.get_user_role", return_value="user"
    ), patch(
        "app.user.services.profile_service.get_active_sessions", return_value=1
    ):
        result = profile_service.get_profile(UID)

    assert result.name == "farmer99"


def test_get_profile_falls_back_to_uid_when_no_name_or_email():
    profile_data = {"last_login": None}

    with patch(
        "app.user.services.profile_service.get_user_profile",
        return_value=profile_data,
    ), patch(
        "app.user.services.profile_service.get_user_role", return_value="user"
    ), patch(
        "app.user.services.profile_service.get_active_sessions", return_value=0
    ):
        result = profile_service.get_profile(UID)

    assert result.name == UID


def test_get_profile_handles_missing_last_login():
    profile_data = {"display_name": "Nimal", "email": "n@x.com", "last_login": None}

    with patch(
        "app.user.services.profile_service.get_user_profile",
        return_value=profile_data,
    ), patch(
        "app.user.services.profile_service.get_user_role", return_value="user"
    ), patch(
        "app.user.services.profile_service.get_active_sessions", return_value=0
    ):
        result = profile_service.get_profile(UID)

    assert result.last_login is None


def test_get_profile_firestore_failure_raises_runtime_error():
    with patch(
        "app.user.services.profile_service.get_user_profile",
        side_effect=RuntimeError("firestore down"),
    ):
        with pytest.raises(RuntimeError):
            profile_service.get_profile(UID)


# ═══════════════════════════════════════════════════════════════════════════
# update_profile
# ═══════════════════════════════════════════════════════════════════════════


def test_update_profile_success():
    body = UpdateProfileRequest(display_name="New Name")

    with patch("app.user.services.profile_service.update_user_profile") as mock_update:
        result = profile_service.update_profile(UID, body)

    mock_update.assert_called_once_with(UID, "New Name")
    assert result["message"] == "Profile updated"
    assert result["display_name"] == "New Name"


def test_update_profile_firestore_failure_raises_runtime_error():
    body = UpdateProfileRequest(display_name="New Name")

    with patch(
        "app.user.services.profile_service.update_user_profile",
        side_effect=RuntimeError("firestore down"),
    ):
        with pytest.raises(RuntimeError):
            profile_service.update_profile(UID, body)


# ═══════════════════════════════════════════════════════════════════════════
# get_preferences
# ═══════════════════════════════════════════════════════════════════════════


def test_get_preferences_returns_saved_values():
    prefs_data = {
        "language": "si",
        "notifications": {
            "price_alerts": True,
            "weather_alerts": False,
            "yield_recommendations": True,
        },
    }

    with patch(
        "app.user.services.profile_service.get_user_preferences",
        return_value=prefs_data,
    ):
        result = profile_service.get_preferences(UID)

    assert result.language == "si"
    assert result.notifications.price_alerts is True
    assert result.notifications.weather_alerts is False
    assert result.notifications.yield_recommendations is True


def test_get_preferences_defaults_when_never_set():
    with patch(
        "app.user.services.profile_service.get_user_preferences", return_value={}
    ):
        result = profile_service.get_preferences(UID)

    assert result.language == "en"
    assert result.preferred_district is None
    assert result.preferred_crop is None


def test_get_preferences_includes_saved_context():
    with patch(
        "app.user.services.profile_service.get_user_preferences",
        return_value={"preferred_district": "Jaffna", "preferred_crop": "Carrot"},
    ):
        result = profile_service.get_preferences(UID)

    assert result.preferred_district == "Jaffna"
    assert result.preferred_crop == "Carrot"
    assert isinstance(result.notifications, NotificationPreferences)


def test_get_preferences_firestore_failure_raises_runtime_error():
    with patch(
        "app.user.services.profile_service.get_user_preferences",
        side_effect=RuntimeError("firestore down"),
    ):
        with pytest.raises(RuntimeError):
            profile_service.get_preferences(UID)


# ═══════════════════════════════════════════════════════════════════════════
# update_preferences
# ═══════════════════════════════════════════════════════════════════════════


def test_update_preferences_success():
    body = UpdatePreferencesRequest(
        language="ta",
        notifications=NotificationPreferences(
            price_alerts=False, weather_alerts=True, yield_recommendations=False
        ),
    )

    with patch(
        "app.user.services.profile_service.update_user_preferences"
    ) as mock_update:
        result = profile_service.update_preferences(UID, body)

    mock_update.assert_called_once_with(
        UID,
        {
            "language": "ta",
            "notifications": {
                "price_alerts": False,
                "weather_alerts": True,
                "yield_recommendations": False,
            },
        },
    )
    assert result["message"] == "Preferences updated"
    assert result["language"] == "ta"


def test_update_preferences_firestore_failure_raises_runtime_error():
    body = UpdatePreferencesRequest(
        language="en",
        notifications=NotificationPreferences(
            price_alerts=True, weather_alerts=True, yield_recommendations=True
        ),
    )

    with patch(
        "app.user.services.profile_service.update_user_preferences",
        side_effect=RuntimeError("firestore down"),
    ):
        with pytest.raises(RuntimeError):
            profile_service.update_preferences(UID, body)
