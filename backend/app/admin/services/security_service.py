"""Security monitoring business logic — read-only views over the
security_events collection plus the active-session list.

Mirrors the app.admin.services.admin_service split: the router stays a thin
HTTP layer, all Firestore access and shaping lives here. Every function
catches its own exceptions and re-raises as a safe HTTPException — no stack
traces reach the client (DevSecOps requirement).
"""

import logging
from datetime import datetime, timedelta, timezone

from fastapi import HTTPException

logger = logging.getLogger(__name__)

# Look-back window for the summary counts, in hours.
SUMMARY_WINDOW_HOURS = 24


def get_security_summary() -> dict:
    """Return 24h counts: failed_logins, rate_violations, banned_attempts,
    plus the current active-session count.
    """
    try:
        from app.utils.firestore import (
            count_active_sessions,
            get_security_events_since,
        )

        cutoff = datetime.now(timezone.utc) - timedelta(hours=SUMMARY_WINDOW_HOURS)
        events = get_security_events_since(cutoff)

        counts = {
            "failed_login": 0,
            "rate_limit_violation": 0,
            "banned_access_attempt": 0,
        }
        for event in events:
            event_type = event.get("type")
            if event_type in counts:
                counts[event_type] += 1

        return {
            "failed_logins": counts["failed_login"],
            "rate_violations": counts["rate_limit_violation"],
            "banned_attempts": counts["banned_access_attempt"],
            "active_sessions": count_active_sessions(hours=SUMMARY_WINDOW_HOURS),
            "window_hours": SUMMARY_WINDOW_HOURS,
            "timestamp": datetime.now(timezone.utc).isoformat(),
        }
    except Exception as exc:
        logger.error(f"get_security_summary failed: {exc}")
        raise HTTPException(status_code=500, detail="Failed to fetch security summary")


def _recent_by_type(event_type: str, limit: int) -> dict:
    """Return the `limit` most recent events of a single type, newest first.

    Fetches a slightly larger recent window ordered by timestamp (single-field
    index) and filters by type in Python — see query_recent_security_events for
    why we avoid a composite index here.
    """
    from app.utils.firestore import query_recent_security_events

    # Over-fetch so we still get `limit` of the target type when the recent
    # stream is dominated by other event types; capped to keep reads bounded.
    fetch = min(max(limit * 5, 200), 1000)
    events = query_recent_security_events(limit=fetch)
    filtered = [e for e in events if e.get("type") == event_type][:limit]
    return {"events": filtered, "total": len(filtered)}


def get_failed_logins(limit: int = 50) -> dict:
    """Return recent failed-login events from the security_events collection."""
    try:
        return _recent_by_type("failed_login", limit)
    except Exception as exc:
        logger.error(f"get_failed_logins failed: {exc}")
        raise HTTPException(status_code=500, detail="Failed to fetch failed logins")


def get_rate_violations(limit: int = 50) -> dict:
    """Return recent rate-limit-violation events."""
    try:
        return _recent_by_type("rate_limit_violation", limit)
    except Exception as exc:
        logger.error(f"get_rate_violations failed: {exc}")
        raise HTTPException(status_code=500, detail="Failed to fetch rate violations")


def get_banned_attempts(limit: int = 50) -> dict:
    """Return recent banned-user access attempts."""
    try:
        return _recent_by_type("banned_access_attempt", limit)
    except Exception as exc:
        logger.error(f"get_banned_attempts failed: {exc}")
        raise HTTPException(status_code=500, detail="Failed to fetch banned attempts")


def get_active_sessions(limit: int = 100) -> dict:
    """Return currently active sessions (last_active within 24h), enriched with
    each user's email/role.
    """
    try:
        from app.utils.firestore import list_active_sessions

        sessions = list_active_sessions(hours=SUMMARY_WINDOW_HOURS, limit=limit)
        return {"sessions": sessions, "total": len(sessions)}
    except Exception as exc:
        logger.error(f"get_active_sessions failed: {exc}")
        raise HTTPException(status_code=500, detail="Failed to fetch active sessions")
