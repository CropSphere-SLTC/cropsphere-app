"""Superadmin endpoints — role-protected routes for superadmin-only actions.

Thin HTTP layer: request validation, auth dependencies, and rate limiting
only. All business logic lives in app.super_admin.services.superadmin_service.
"""

import logging
from typing import Optional

from fastapi import APIRouter, Depends, Request
from pydantic import BaseModel, Field

from app.middleware.rate_limit import limiter
from app.middleware.roles import require_superadmin
from app.super_admin.services import superadmin_service

logger = logging.getLogger(__name__)

# New superadmin-only endpoints.
router = APIRouter(prefix="/api/superadmin", tags=["superadmin"])

# The session-cleanup endpoint predates the admin/superadmin split and keeps
# its original /api/admin/* URL for backward compatibility — only its code
# location changed (moved out of app.admin into app.super_admin).
legacy_router = APIRouter(prefix="/api/admin", tags=["superadmin"])


# ── Schemas ───────────────────────────────────────────────────────────────────


class ConfigUpdate(BaseModel):
    admin_rate_limit_per_minute: Optional[int] = Field(None, ge=1, le=1000)
    superadmin_rate_limit_per_minute: Optional[int] = Field(None, ge=1, le=1000)


# ── Runtime config ───────────────────────────────────────────────────────────


@router.get("/config", dependencies=[Depends(require_superadmin)])
@limiter.limit("10/minute")
def get_config(request: Request):
    """Return current rate limits and the ENABLE_ADMIN_API setting."""
    return superadmin_service.get_config()


@router.patch("/config", dependencies=[Depends(require_superadmin)])
@limiter.limit("10/minute")
def update_config(request: Request, body: ConfigUpdate):
    """Update rate limits at runtime."""
    return superadmin_service.update_config(
        admin_rate_limit_per_minute=body.admin_rate_limit_per_minute,
        superadmin_rate_limit_per_minute=body.superadmin_rate_limit_per_minute,
    )


# ── Audit logs (unfiltered) ──────────────────────────────────────────────────


@router.get("/audit-logs", dependencies=[Depends(require_superadmin)])
@limiter.limit("10/minute")
def get_audit_logs(request: Request, limit: int = 50):
    """Return ALL admin audit logs, including superadmin actions — no filtering."""
    return superadmin_service.get_all_audit_logs(limit)


# ── Force logout ──────────────────────────────────────────────────────────────


@router.post("/security/force-logout/{uid}")
@limiter.limit("10/minute")
def force_logout(
    request: Request,
    uid: str,
    actor_uid: str = Depends(require_superadmin),
):
    """Force-logout a user by revoking their Firebase refresh tokens.

    Superadmin only — require_superadmin both gates the route (403 otherwise)
    and yields the acting superadmin's uid for the audit trail.
    """
    return superadmin_service.force_logout(uid, actor_uid)


# ── Session maintenance ───────────────────────────────────────────────────────


@legacy_router.delete(
    "/sessions/cleanup-old", dependencies=[Depends(require_superadmin)]
)
@limiter.limit("10/minute")
def cleanup_old_sessions(request: Request):
    """Delete session documents older than 30 days. Superadmin only."""
    return superadmin_service.cleanup_old_sessions()
