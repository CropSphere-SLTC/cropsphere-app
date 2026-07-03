"""Admin endpoints — role-protected routes for user and system management.

Thin HTTP layer: request validation, auth dependencies, and rate limiting
only. All business logic lives in app.admin.services.admin_service.
"""
import logging

from fastapi import APIRouter, Depends, Request
from pydantic import BaseModel

from app.admin.services import admin_service
from app.middleware.rate_limit import limiter
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
@limiter.limit("10/minute")
def list_users(request: Request, actor: dict = Depends(get_current_role)):
    """List all users. Admins see users and admins. Superadmin sees everyone."""
    return admin_service.list_users(actor)


@router.patch("/users/{uid}/role")
@limiter.limit("10/minute")
def update_user_role(
    request: Request,
    uid: str,
    body: RoleUpdate,
    actor: dict = Depends(get_current_role),
):
    """Change a user's role.
    Admin can promote user→admin or demote admin→user.
    Superadmin can do everything including promote to superadmin.
    """
    return admin_service.update_user_role(uid, body.role, actor)


@router.patch("/users/{uid}/ban")
@limiter.limit("10/minute")
def ban_user(
    request: Request,
    uid: str,
    body: BanUpdate,
    actor: dict = Depends(get_current_role),
):
    """Ban or unban a user.
    Admin can ban regular users only.
    Superadmin can ban anyone except other superadmins.
    """
    return admin_service.ban_user(uid, body.is_banned, actor)


@router.delete("/users/{uid}", dependencies=[Depends(require_admin)])
@limiter.limit("10/minute")
def delete_user(request: Request, uid: str, actor: dict = Depends(get_current_role)):
    """Delete a user account.
    Admin can delete regular users only.
    Superadmin can delete users and admins.
    """
    return admin_service.delete_user(uid, actor)


# ── System stats ──────────────────────────────────────────────────────────────

@router.get("/stats", dependencies=[Depends(require_admin)])
@limiter.limit("10/minute")
def system_stats(request: Request):
    """Return system stats — CPU, RAM, model status, request counts."""
    return admin_service.get_system_stats()


# ── Audit logs ────────────────────────────────────────────────────────────────

@router.get("/audit-logs", dependencies=[Depends(require_admin)])
@limiter.limit("10/minute")
def get_audit_logs(
    request: Request,
    limit: int = 50,
    actor: dict = Depends(get_current_role),
):
    """Return admin audit logs.
    Admin sees only admin-level actions (not superadmin actions).
    Superadmin sees all actions.
    """
    return admin_service.get_audit_logs(limit, actor)


@router.get("/prediction-logs", dependencies=[Depends(require_admin)])
@limiter.limit("10/minute")
def get_prediction_logs(
    request: Request,
    limit: int = 50,
    actor: dict = Depends(get_current_role),
):
    """Return prediction audit logs from audit_logs collection."""
    return admin_service.get_prediction_logs(limit)


# Clean Old Sessions
@router.delete("/sessions/cleanup-old", dependencies=[Depends(require_superadmin)])
def cleanup_old_sessions():
    """Delete session documents older than 30 days. Superadmin only."""
    from datetime import datetime, timezone, timedelta
    from app.utils.firestore import get_db
    db = get_db()
    cutoff = datetime.now(timezone.utc) - timedelta(days=30)
    docs = list(db.collection("sessions")
                .where("last_active", "<", cutoff)
                .stream())
    for doc in docs:
        doc.reference.delete()
    return {"deleted": len(docs), "cutoff": cutoff.isoformat()}