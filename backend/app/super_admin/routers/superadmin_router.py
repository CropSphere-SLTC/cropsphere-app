"""Superadmin endpoints — role-protected routes for superadmin-only actions.

Thin HTTP layer: request validation, auth dependencies, and rate limiting
only. All business logic lives in app.super_admin.services.superadmin_service.
"""

import logging
from typing import Optional

from fastapi import APIRouter, Depends, HTTPException, Request
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


class PromptTuningConfigUpdate(BaseModel):
    """PATCH body for the prompt-tuning lifecycle settings. Every field is
    optional — only the ones sent are changed. Bounds mirror
    system_config_service._BOUNDS so an invalid value is rejected as a 422
    before any service code runs."""

    min_sample_size: Optional[int] = Field(None, ge=1, le=10000)
    trial_period_days: Optional[int] = Field(None, ge=1, le=90)
    trial_extension_days: Optional[int] = Field(None, ge=1, le=30)
    trash_retention_days: Optional[int] = Field(None, ge=1, le=365)


class AdjustmentRemoval(BaseModel):
    """Removing an adjustment always records why (Step 5)."""

    comment: str = Field(..., min_length=3, max_length=500)


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


# ── Email test ────────────────────────────────────────────────────────────────


@router.post("/test-email")
@limiter.limit("5/minute")
def test_email(request: Request, actor_uid: str = Depends(require_superadmin)):
    """Send a test alert email to the requesting superadmin's own address.

    Verifies the SMTP configuration end-to-end. Sends only to the caller (never
    to other users). Delivery is backgrounded and best-effort, so a 200 means
    "queued for send", not "delivered" — check the inbox to confirm. Returns
    400 if the account has no email on file, and reports whether email is even
    enabled so a silent no-op (EMAIL_ENABLED=false) is obvious.
    """
    from app.admin.services.email_service import (
        render_notification_email,
        send_email,
    )
    from app.config import get_settings
    from app.utils.firestore import get_user_profile

    try:
        email = (get_user_profile(actor_uid).get("email") or "").strip()
    except Exception:
        email = ""
    if not email:
        raise HTTPException(status_code=400, detail="No email on file for your account")

    settings = get_settings()
    body = render_notification_email(
        "Test email",
        "This is a test alert from CropSphere. If you can read this, SMTP is "
        "configured correctly.",
        "info",
        dashboard_url=settings.dashboard_url,
    )
    send_email(email, "CropSphere: Test email", body)
    return {
        "status": "ok",
        "sent_to": email,
        "email_enabled": settings.EMAIL_ENABLED,
    }


# ── Prompt tuning config ─────────────────────────────────────────────────────


@router.get("/prompt-tuning-config", dependencies=[Depends(require_superadmin)])
@limiter.limit("10/minute")
def get_prompt_tuning_config(request: Request):
    """Return the current prompt-tuning lifecycle settings (min sample size,
    trial period, extension length, trash retention). Superadmin only."""
    from app.admin.services.system_config_service import (
        get_prompt_tuning_config as _get,
    )

    return _get()


@router.patch("/prompt-tuning-config", dependencies=[Depends(require_superadmin)])
@limiter.limit("10/minute")
def update_prompt_tuning_config(
    request: Request,
    body: PromptTuningConfigUpdate,
    actor_uid: str = Depends(require_superadmin),
):
    """Update one or more prompt-tuning lifecycle settings.

    Persisted to Firestore (unlike the in-memory rate limits above) because
    running trials depend on these values across restarts. Only the fields
    present in the body change. Superadmin only; the change is audit-logged.
    """
    from app.admin.services.system_config_service import update_prompt_tuning_config

    return update_prompt_tuning_config(
        body.model_dump(exclude_none=True), actor_uid=actor_uid
    )


# ── Prompt tuning: per-adjustment analytics & manual override ────────────────


@router.get(
    "/adjustment-analytics/{adjustment_id}", dependencies=[Depends(require_superadmin)]
)
@limiter.limit("20/minute")
def adjustment_analytics(request: Request, adjustment_id: str):
    """Before/after analytics for one adjustment — baseline vs current value of
    its validation metric, trial progress, sample size vs requirement, verdict,
    and its audit history. Superadmin only. 404 if the id is unknown.
    """
    from app.admin.services.tuning_validation_service import get_adjustment_analytics

    result = get_adjustment_analytics(adjustment_id)
    if result is None:
        raise HTTPException(status_code=404, detail="Adjustment not found")
    return result


@router.post("/force-permanent/{adjustment_id}")
@limiter.limit("10/minute")
def force_permanent(
    request: Request,
    adjustment_id: str,
    actor_uid: str = Depends(require_superadmin),
):
    """Force a trial adjustment to "permanent", bypassing auto-validation.

    Superadmin only — the intended flow is to review the adjustment analytics
    first. 404 if not active, 409 if already permanent. Audit-logged with
    reason "manual_override".
    """
    from app.user.services import prompt_tuning_store as store_mod
    from app.user.services.chatbot_service import _reload_prompt_tuning

    result = store_mod.promote(adjustment_id, actor_uid, reason="manual_override")
    if not result["ok"]:
        if result["error"] == "already_permanent":
            raise HTTPException(
                status_code=409, detail="Adjustment is already permanent"
            )
        raise HTTPException(status_code=404, detail="Adjustment not found")
    _reload_prompt_tuning()
    return {"status": "ok", "adjustment": result["adjustment"]}


@router.post("/remove-adjustment/{adjustment_id}")
@limiter.limit("10/minute")
def remove_adjustment(
    request: Request,
    adjustment_id: str,
    body: AdjustmentRemoval,
    actor_uid: str = Depends(require_superadmin),
):
    """Move an adjustment (trial or permanent) to the trash with a required
    comment. Reversible until trash_retention_days elapses. Superadmin only.
    404 if the id isn't active.
    """
    from app.user.services import prompt_tuning_store as store_mod
    from app.user.services.chatbot_service import _reload_prompt_tuning

    result = store_mod.trash(
        adjustment_id,
        actor_uid=actor_uid,
        reason="manual_removal",
        comment=body.comment,
    )
    if not result["ok"]:
        raise HTTPException(status_code=404, detail="Adjustment not found")
    _reload_prompt_tuning()
    return {"status": "ok", "item": result["item"]}


@router.delete("/clear-trash")
@limiter.limit("5/minute")
def clear_trash(
    request: Request,
    all_items: bool = False,
    actor_uid: str = Depends(require_superadmin),
):
    """Permanently delete trashed adjustments whose retention has expired.

    `all_items=true` empties the trash regardless of retention. Each deletion
    writes an audit entry with action="deleted". Superadmin only.
    """
    from app.user.services import prompt_tuning_store as store_mod

    result = store_mod.purge_expired_trash(actor_uid=actor_uid, force_all=all_items)
    return {
        "status": "ok",
        "deleted_count": len(result["deleted"]),
        "deleted_ids": result["deleted"],
        "remaining": result["remaining"],
    }


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
