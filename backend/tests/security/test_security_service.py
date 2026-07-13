"""Unit tests for app.admin.services.security_service.

Calls the service functions directly (no HTTP layer). The Firestore helpers in
app.utils.firestore that the service imports lazily are mocked, so no real
infrastructure is required.
"""

from unittest.mock import patch

import pytest
from fastapi import HTTPException

from app.admin.services import security_service

# ═══════════════════════════════════════════════════════════════════════════
# get_security_summary
# ═══════════════════════════════════════════════════════════════════════════


def test_summary_counts_events_by_type_and_reports_active_sessions():
    events = [
        {"type": "failed_login"},
        {"type": "failed_login"},
        {"type": "rate_limit_violation"},
        {"type": "banned_access_attempt"},
        {"type": "banned_access_attempt"},
        {"type": "banned_access_attempt"},
        {"type": "something_else"},  # ignored — not a tracked type
    ]
    with patch(
        "app.utils.firestore.get_security_events_since", return_value=events
    ), patch("app.utils.firestore.count_active_sessions", return_value=4):
        result = security_service.get_security_summary()

    assert result["failed_logins"] == 2
    assert result["rate_violations"] == 1
    assert result["banned_attempts"] == 3
    assert result["active_sessions"] == 4
    assert result["window_hours"] == 24
    assert "timestamp" in result


def test_summary_all_zero_when_no_events():
    with patch("app.utils.firestore.get_security_events_since", return_value=[]), patch(
        "app.utils.firestore.count_active_sessions", return_value=0
    ):
        result = security_service.get_security_summary()

    assert result["failed_logins"] == 0
    assert result["rate_violations"] == 0
    assert result["banned_attempts"] == 0
    assert result["active_sessions"] == 0


def test_summary_firestore_failure_raises_500():
    with patch(
        "app.utils.firestore.get_security_events_since",
        side_effect=RuntimeError("down"),
    ):
        with pytest.raises(HTTPException) as exc_info:
            security_service.get_security_summary()
    assert exc_info.value.status_code == 500


# ═══════════════════════════════════════════════════════════════════════════
# get_failed_logins / get_rate_violations / get_banned_attempts
# ═══════════════════════════════════════════════════════════════════════════


_MIXED_EVENTS = [
    {"id": "1", "type": "failed_login", "ip_address": "1.1.1.1"},
    {"id": "2", "type": "rate_limit_violation", "endpoint": "/api/chat"},
    {"id": "3", "type": "failed_login", "ip_address": "2.2.2.2"},
    {"id": "4", "type": "banned_access_attempt", "uid": "banned-1"},
]


def test_failed_logins_filters_to_that_type_only():
    with patch(
        "app.utils.firestore.query_recent_security_events", return_value=_MIXED_EVENTS
    ):
        result = security_service.get_failed_logins(limit=50)

    assert result["total"] == 2
    assert all(e["type"] == "failed_login" for e in result["events"])


def test_rate_violations_filters_to_that_type_only():
    with patch(
        "app.utils.firestore.query_recent_security_events", return_value=_MIXED_EVENTS
    ):
        result = security_service.get_rate_violations(limit=50)

    assert result["total"] == 1
    assert result["events"][0]["type"] == "rate_limit_violation"


def test_banned_attempts_filters_to_that_type_only():
    with patch(
        "app.utils.firestore.query_recent_security_events", return_value=_MIXED_EVENTS
    ):
        result = security_service.get_banned_attempts(limit=50)

    assert result["total"] == 1
    assert result["events"][0]["type"] == "banned_access_attempt"


def test_recent_by_type_respects_limit():
    many = [{"type": "failed_login", "id": str(i)} for i in range(10)]
    with patch("app.utils.firestore.query_recent_security_events", return_value=many):
        result = security_service.get_failed_logins(limit=3)

    assert result["total"] == 3
    assert len(result["events"]) == 3


def test_failed_logins_firestore_failure_raises_500():
    with patch(
        "app.utils.firestore.query_recent_security_events",
        side_effect=RuntimeError("down"),
    ):
        with pytest.raises(HTTPException) as exc_info:
            security_service.get_failed_logins()
    assert exc_info.value.status_code == 500


# ═══════════════════════════════════════════════════════════════════════════
# get_active_sessions
# ═══════════════════════════════════════════════════════════════════════════


def test_active_sessions_returns_list_and_total():
    sessions = [
        {"uid": "u1", "email": "a@x.com", "role": "user"},
        {"uid": "u2", "email": "b@x.com", "role": "admin"},
    ]
    with patch("app.utils.firestore.list_active_sessions", return_value=sessions):
        result = security_service.get_active_sessions(limit=100)

    assert result["total"] == 2
    assert result["sessions"] == sessions


def test_active_sessions_firestore_failure_raises_500():
    with patch(
        "app.utils.firestore.list_active_sessions", side_effect=RuntimeError("down")
    ):
        with pytest.raises(HTTPException) as exc_info:
            security_service.get_active_sessions()
    assert exc_info.value.status_code == 500
