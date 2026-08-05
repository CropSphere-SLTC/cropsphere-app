"""Superadmin business logic — runtime config, unrestricted audit trail, and
session cleanup.

Extracted so app.super_admin.routers.superadmin_router stays a thin HTTP
layer, mirroring the app.admin split.
"""

import logging
from datetime import datetime, timedelta, timezone
from typing import Optional

from fastapi import HTTPException

from app.config import get_settings

logger = logging.getLogger(__name__)

# In-memory, runtime-adjustable rate limits.
#
# NOTE: these values are stored and returned here, but the @limiter.limit(...)
# decorators on the actual routes are still static strings evaluated at
# import time — updating this config does not yet retarget already-registered
# routes (that would require a dynamic key/limit resolver wired into
# slowapi). Treat this as the recorded desired configuration, not live
# enforcement, until that wiring exists.
_runtime_config = {
    "admin_rate_limit_per_minute": 10,
    "superadmin_rate_limit_per_minute": 10,
}


def get_config() -> dict:
    """Return current rate limits and the ENABLE_ADMIN_API setting."""
    settings = get_settings()
    return {
        **_runtime_config,
        "enable_admin_api": settings.ENABLE_ADMIN_API,
    }


def update_config(
    admin_rate_limit_per_minute: Optional[int] = None,
    superadmin_rate_limit_per_minute: Optional[int] = None,
) -> dict:
    """Update rate limits at runtime.

    See the _runtime_config docstring above for the current limitation —
    values are stored/returned here but not yet wired into enforcement.
    """
    if admin_rate_limit_per_minute is not None:
        _runtime_config["admin_rate_limit_per_minute"] = admin_rate_limit_per_minute
    if superadmin_rate_limit_per_minute is not None:
        _runtime_config["superadmin_rate_limit_per_minute"] = (
            superadmin_rate_limit_per_minute
        )
    return get_config()


def get_all_audit_logs(limit: int) -> dict:
    """Return ALL admin_audit_logs entries, including superadmin actions.

    Unlike app.admin.services.admin_service.get_audit_logs, nothing is
    filtered out here — superadmin sees the complete trail.

    Rows carry actor_email/target_email next to the UIDs, resolved at read time
    the same way the admin view does it, so the two audit screens name people
    identically.
    """
    try:
        from app.utils.firestore import emails_for_uids, get_db

        db = get_db()
        query = (
            db.collection("admin_audit_logs")
            .order_by("timestamp", direction="DESCENDING")
            .limit(limit)
        )
        logs = []
        for doc in query.stream():
            data = doc.to_dict()
            if "timestamp" in data:
                data["timestamp"] = data["timestamp"].isoformat()
            logs.append(data)

        emails = emails_for_uids(
            uid
            for log in logs
            for uid in (log.get("actor_uid"), log.get("target_uid"))
        )
        for log in logs:
            log["actor_email"] = emails.get(log.get("actor_uid", ""), "")
            log["target_email"] = emails.get(log.get("target_uid", ""), "")

        return {"logs": logs, "total": len(logs)}
    except Exception as exc:
        logger.error(f"get_all_audit_logs failed: {exc}")
        raise HTTPException(status_code=500, detail="Failed to fetch audit logs")


def force_logout(uid: str, actor_uid: str) -> dict:
    """Force-logout a user by revoking their Firebase refresh tokens.

    Superadmin only. Uses the Firebase Admin SDK's revoke_refresh_tokens, which
    invalidates all refresh tokens for the uid — the user cannot silently renew
    a session. Caveat: already-issued ID tokens remain valid until they expire
    (~1h) unless verify_id_token is called with check_revoked=True; the auth
    middleware does not currently do that (it would add a certs/Firestore round
    trip per request), so full revocation takes effect within the token TTL.

    The action is recorded in the admin audit trail.
    """
    from firebase_admin import auth as fb_auth

    from app.utils.firestore import admin_audit_log

    try:
        fb_auth.revoke_refresh_tokens(uid)
        admin_audit_log(
            actor_uid=actor_uid,
            actor_role="superadmin",
            action="force_logout",
            target_uid=uid,
        )
        return {"message": "User sessions revoked", "uid": uid}
    except Exception as exc:
        logger.error(f"force_logout failed for uid={uid}: {exc}")
        raise HTTPException(status_code=500, detail="Failed to force logout user")


def cleanup_old_sessions() -> dict:
    """Delete session documents older than 30 days. Superadmin only."""
    try:
        from app.utils.firestore import get_db

        db = get_db()
        cutoff = datetime.now(timezone.utc) - timedelta(days=30)
        docs = list(
            db.collection("sessions").where("last_active", "<", cutoff).stream()
        )
        for doc in docs:
            doc.reference.delete()
        return {"deleted": len(docs), "cutoff": cutoff.isoformat()}
    except Exception as exc:
        logger.error(f"cleanup_old_sessions failed: {exc}")
        raise HTTPException(status_code=500, detail="Failed to clean up sessions")
