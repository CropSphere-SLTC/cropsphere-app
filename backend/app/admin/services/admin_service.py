"""Admin business logic — user management, system stats, and audit trails.

Extracted from app.admin.routers.admin_router so the router stays a thin
HTTP layer; all Firestore/psutil access and role-permission rules live here.
"""

import logging
from datetime import datetime, timezone
from typing import Dict

import psutil
from fastapi import HTTPException

logger = logging.getLogger(__name__)

# How many of the most recent audit_logs documents the per-endpoint breakdown
# in get_system_stats is computed from. Bounded because audit_logs grows
# without limit (one document per prediction and per chat turn) — an unbounded
# scan there is what made /api/admin/stats time out. The all-time total is
# still exact; it comes from a count() aggregation, not from this sample.
_ENDPOINT_SAMPLE_SIZE = 1000


def _count_documents(collection) -> int | None:
    """Exact document count via Firestore's server-side count() aggregation.

    Inputs: a Firestore CollectionReference.
    Outputs: the count, or None when the aggregation is unavailable (older
    client, emulator without aggregation support, or a mock in tests) so the
    caller can fall back instead of failing the whole stats call.
    Security assumption: reads only aggregate metadata, no document contents.
    """
    try:
        result = collection.count().get()
        # Shape: [[AggregationResult(value=N)]]
        return int(result[0][0].value)
    except Exception as exc:
        logger.warning("audit_logs count() aggregation unavailable: %s", exc)
        return None


# ── User management ───────────────────────────────────────────────────────────


def list_users(actor: dict) -> dict:
    """List all users. Admins see users and admins. Superadmin sees everyone."""
    try:
        from app.utils.firestore import get_db

        db = get_db()
        docs = db.collection("users").stream()
        users = []
        for doc in docs:
            data = doc.to_dict()
            # Admins cannot see superadmin accounts
            if actor["role"] == "admin" and data.get("role") == "superadmin":
                continue
            users.append(data)
        return {"users": users, "total": len(users)}
    except Exception as exc:
        logger.error(f"list_users failed: {exc}")
        raise HTTPException(status_code=500, detail="Failed to fetch users")


def update_user_role(uid: str, new_role: str, actor: dict) -> dict:
    """Change a user's role.
    Admin can promote user→admin or demote admin→user.
    Superadmin can do everything including promote to superadmin.
    """
    from app.utils.firestore import get_db, get_user_role, admin_audit_log

    # Enforce role permissions
    if actor["role"] not in ("admin", "superadmin"):
        raise HTTPException(status_code=403, detail="Admin access required")

    # No self-modification
    if uid == actor["uid"]:
        raise HTTPException(status_code=400, detail="Cannot modify your own role")

    # Only superadmin can assign superadmin role
    if new_role == "superadmin" and actor["role"] != "superadmin":
        raise HTTPException(
            status_code=403, detail="Only superadmin can assign superadmin role"
        )

    # Admin cannot modify other admins or superadmins
    target_role = get_user_role(uid)
    if actor["role"] == "admin" and target_role in ("admin", "superadmin"):
        raise HTTPException(
            status_code=403, detail="Admin cannot modify admin or superadmin accounts"
        )

    try:
        db = get_db()
        db.collection("users").document(uid).update({"role": new_role})
        admin_audit_log(
            actor_uid=actor["uid"],
            actor_role=actor["role"],
            action="update_role",
            target_uid=uid,
            details={"new_role": new_role, "previous_role": target_role},
        )
        return {"message": f"Role updated to {new_role}", "uid": uid}
    except Exception as exc:
        logger.error(f"update_user_role failed: {exc}")
        raise HTTPException(status_code=500, detail="Failed to update role")


def ban_user(uid: str, is_banned: bool, actor: dict) -> dict:
    """Ban or unban a user.
    Admin can ban regular users only.
    Superadmin can ban anyone except other superadmins.
    """
    from app.utils.firestore import get_db, get_user_role, admin_audit_log

    if actor["role"] not in ("admin", "superadmin"):
        raise HTTPException(status_code=403, detail="Admin access required")

    # No self-ban
    if uid == actor["uid"]:
        raise HTTPException(status_code=400, detail="Cannot ban yourself")

    target_role = get_user_role(uid)

    # Admin cannot ban admins or superadmins
    if actor["role"] == "admin" and target_role in ("admin", "superadmin"):
        raise HTTPException(
            status_code=403, detail="Admin cannot ban admin or superadmin accounts"
        )

    # Superadmin cannot ban other superadmins
    if target_role == "superadmin":
        raise HTTPException(status_code=403, detail="Cannot ban a superadmin")

    try:
        db = get_db()
        db.collection("users").document(uid).update({"is_banned": is_banned})
        action = "ban_user" if is_banned else "unban_user"
        admin_audit_log(
            actor_uid=actor["uid"],
            actor_role=actor["role"],
            action=action,
            target_uid=uid,
        )
        status = "banned" if is_banned else "unbanned"
        return {"message": f"User {status}", "uid": uid}
    except Exception as exc:
        logger.error(f"ban_user failed: {exc}")
        raise HTTPException(status_code=500, detail="Failed to update ban status")


def delete_user(uid: str, actor: dict) -> dict:
    """Delete a user account.
    Admin can delete regular users only.
    Superadmin can delete users and admins.
    """
    from app.utils.firestore import get_db, get_user_role, admin_audit_log
    from app.config import get_settings

    # No self-deletion
    if uid == actor["uid"]:
        raise HTTPException(status_code=400, detail="Cannot delete your own account")

    # Cannot delete superadmin
    if uid == get_settings().SUPERADMIN_UID:
        raise HTTPException(status_code=403, detail="Cannot delete superadmin account")

    target_role = get_user_role(uid)

    # Admin cannot delete admins or superadmins
    if actor["role"] == "admin" and target_role in ("admin", "superadmin"):
        raise HTTPException(
            status_code=403, detail="Admin cannot delete admin or superadmin accounts"
        )

    try:
        db = get_db()
        db.collection("users").document(uid).delete()
        admin_audit_log(
            actor_uid=actor["uid"],
            actor_role=actor["role"],
            action="delete_user",
            target_uid=uid,
            details={"deleted_role": target_role},
        )
        return {"message": "User deleted", "uid": uid}
    except Exception as exc:
        logger.error(f"delete_user failed: {exc}")
        raise HTTPException(status_code=500, detail="Failed to delete user")


# ── System stats ──────────────────────────────────────────────────────────────


def get_system_stats() -> dict:
    """Return system stats — CPU, RAM, model status, request counts."""
    try:
        from app.models.loader import model_loader
        from app.utils.firestore import get_db

        # CPU and RAM
        cpu_percent = psutil.cpu_percent(interval=1)
        ram = psutil.virtual_memory()

        # Model status
        models_loaded = {
            name: model_loader.get_model(name) is not None
            for name in [
                "yield_Carrot",
                "yield_Maize",
                "weather_lstm",
                "price_Carrot",
                "demand_Carrot",
                "recommend_rf",
                "rag_artifacts",
            ]
        }

        # Request counts from audit logs. audit_logs grows by one document per
        # prediction AND per chat turn, without bound — streaming the whole
        # collection to count it got slower every day and eventually timed out
        # the client (30s), which is what took this endpoint down.
        db = get_db()
        collection = db.collection("audit_logs")
        # Exact total via the server-side count() aggregation: one RPC, no
        # documents transferred, cost independent of collection size.
        total_requests = _count_documents(collection)
        # The per-endpoint breakdown genuinely has to read documents to group
        # them, so it is bounded to the most recent _ENDPOINT_SAMPLE_SIZE. The
        # sample size is returned alongside it so the UI can say what the
        # breakdown actually covers instead of implying it is all-time.
        endpoint_counts: Dict[str, int] = {}
        sampled = 0
        recent = (
            collection.order_by("timestamp", direction="DESCENDING")
            .limit(_ENDPOINT_SAMPLE_SIZE)
            .stream()
        )
        for log in recent:
            data = log.to_dict() or {}
            sampled += 1
            ep = data.get("endpoint", "unknown")
            endpoint_counts[ep] = endpoint_counts.get(ep, 0) + 1

        # count() unavailable (older emulator, permission shape) — the sample
        # is the only number we actually have, so report it rather than 0.
        if total_requests is None:
            total_requests = sampled

        return {
            "cpu_percent": cpu_percent,
            "ram_total_gb": round(ram.total / (1024**3), 2),
            "ram_used_gb": round(ram.used / (1024**3), 2),
            "ram_percent": ram.percent,
            "models_loaded": models_loaded,
            "total_requests": total_requests,
            "requests_by_endpoint": endpoint_counts,
            # How many documents the breakdown above was computed from, so the
            # client can label it honestly ("last 1,000 requests").
            "requests_sampled": sampled,
            "timestamp": datetime.now(timezone.utc).isoformat(),
        }
    except Exception as exc:
        logger.error(f"system_stats failed: {exc}")
        raise HTTPException(status_code=500, detail="Failed to fetch stats")


# ── Audit logs ────────────────────────────────────────────────────────────────


def get_audit_logs(limit: int, actor: dict) -> dict:
    """Return admin audit logs.
    Admin sees only admin-level actions (not superadmin actions).
    Superadmin sees all actions.
    """
    try:
        from app.utils.firestore import get_db

        db = get_db()
        query = (
            db.collection("admin_audit_logs")
            .order_by("timestamp", direction="DESCENDING")
            .limit(limit)
        )
        logs = []
        for doc in query.stream():
            data = doc.to_dict()
            # Hide superadmin actions from admins
            if actor["role"] == "admin" and data.get("actor_role") == "superadmin":
                continue
            # Convert timestamp to string
            if "timestamp" in data:
                data["timestamp"] = data["timestamp"].isoformat()
            logs.append(data)
        return {"logs": logs, "total": len(logs)}
    except Exception as exc:
        logger.error(f"get_audit_logs failed: {exc}")
        raise HTTPException(status_code=500, detail="Failed to fetch audit logs")


def get_prediction_logs(limit: int) -> dict:
    """Return prediction audit logs from audit_logs collection."""
    try:
        from app.utils.firestore import get_db

        db = get_db()
        query = (
            db.collection("audit_logs")
            .order_by("timestamp", direction="DESCENDING")
            .limit(limit)
        )
        logs = []
        for doc in query.stream():
            data = doc.to_dict()
            if "timestamp" in data:
                data["timestamp"] = data["timestamp"].isoformat()
            logs.append(data)
        return {"logs": logs, "total": len(logs)}
    except Exception as exc:
        logger.error(f"get_prediction_logs failed: {exc}")
        raise HTTPException(status_code=500, detail="Failed to fetch prediction logs")
