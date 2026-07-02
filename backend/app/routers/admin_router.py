"""Admin endpoints — role-protected routes for user and system management."""
import logging
import psutil
from datetime import datetime, timezone
from typing import Any, Dict, List, Optional

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel

from app.middleware.roles import require_admin, require_superadmin, get_current_role

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/api/admin", tags=["admin"])


# ── Schemas ───────────────────────────────────────────────────────────────────

class RoleUpdate(BaseModel):
    role: str  # "user", "admin", "superadmin"


class BanUpdate(BaseModel):
    is_banned: bool


# ── User management ───────────────────────────────────────────────────────────

@router.get("/users", dependencies=[Depends(require_admin)])
def list_users(actor: dict = Depends(get_current_role)):
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


@router.patch("/users/{uid}/role")
def update_user_role(
    uid: str,
    body: RoleUpdate,
    actor: dict = Depends(get_current_role),
):
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
    if body.role == "superadmin" and actor["role"] != "superadmin":
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
        db.collection("users").document(uid).update({"role": body.role})
        admin_audit_log(
            actor_uid=actor["uid"],
            actor_role=actor["role"],
            action="update_role",
            target_uid=uid,
            details={"new_role": body.role, "previous_role": target_role},
        )
        return {"message": f"Role updated to {body.role}", "uid": uid}
    except Exception as exc:
        logger.error(f"update_user_role failed: {exc}")
        raise HTTPException(status_code=500, detail="Failed to update role")


@router.patch("/users/{uid}/ban")
def ban_user(
    uid: str,
    body: BanUpdate,
    actor: dict = Depends(get_current_role),
):
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
        db.collection("users").document(uid).update({"is_banned": body.is_banned})
        action = "ban_user" if body.is_banned else "unban_user"
        admin_audit_log(
            actor_uid=actor["uid"],
            actor_role=actor["role"],
            action=action,
            target_uid=uid,
        )
        status = "banned" if body.is_banned else "unbanned"
        return {"message": f"User {status}", "uid": uid}
    except Exception as exc:
        logger.error(f"ban_user failed: {exc}")
        raise HTTPException(status_code=500, detail="Failed to update ban status")


@router.delete("/users/{uid}", dependencies=[Depends(require_admin)])
def delete_user(uid: str, actor: dict = Depends(get_current_role)):
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

@router.get("/stats", dependencies=[Depends(require_admin)])
def system_stats():
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
                "yield_Carrot", "yield_Maize", "weather_lstm",
                "price_Carrot", "demand_Carrot", "recommend_rf", "rag_artifacts"
            ]
        }

        # Request counts from audit logs
        db = get_db()
        logs = db.collection("audit_logs").stream()
        total_requests = 0
        endpoint_counts: Dict[str, int] = {}
        for log in logs:
            data = log.to_dict()
            total_requests += 1
            ep = data.get("endpoint", "unknown")
            endpoint_counts[ep] = endpoint_counts.get(ep, 0) + 1

        return {
            "cpu_percent": cpu_percent,
            "ram_total_gb": round(ram.total / (1024**3), 2),
            "ram_used_gb": round(ram.used / (1024**3), 2),
            "ram_percent": ram.percent,
            "models_loaded": models_loaded,
            "total_requests": total_requests,
            "requests_by_endpoint": endpoint_counts,
            "timestamp": datetime.now(timezone.utc).isoformat(),
        }
    except Exception as exc:
        logger.error(f"system_stats failed: {exc}")
        raise HTTPException(status_code=500, detail="Failed to fetch stats")


# ── Audit logs ────────────────────────────────────────────────────────────────

@router.get("/audit-logs", dependencies=[Depends(require_admin)])
def get_audit_logs(
    limit: int = 50,
    actor: dict = Depends(get_current_role),
):
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
            if (
                actor["role"] == "admin"
                and data.get("actor_role") == "superadmin"
            ):
                continue
            # Convert timestamp to string
            if "timestamp" in data:
                data["timestamp"] = data["timestamp"].isoformat()
            logs.append(data)
        return {"logs": logs, "total": len(logs)}
    except Exception as exc:
        logger.error(f"get_audit_logs failed: {exc}")
        raise HTTPException(status_code=500, detail="Failed to fetch audit logs")