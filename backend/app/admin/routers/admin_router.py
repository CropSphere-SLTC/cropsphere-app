"""Admin endpoints — role-protected routes for user and system management.

Thin HTTP layer: request validation, auth dependencies, and rate limiting
only. All business logic lives in app.admin.services.admin_service.
"""

import logging
from typing import Optional

from fastapi import APIRouter, Depends, HTTPException, Request
from pydantic import BaseModel, Field

from app.admin.services import admin_service
from app.admin.services import gap_report_service
from app.middleware.rate_limit import limiter
from app.middleware.roles import (
    get_current_role,
    get_current_uid,
    require_admin,
    require_superadmin,
)

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/api/admin", tags=["admin"])


# ── Schemas ───────────────────────────────────────────────────────────────────


class RoleUpdate(BaseModel):
    role: str  # "user", "admin", "superadmin"


class BanUpdate(BaseModel):
    is_banned: bool


class ApprovedTuning(BaseModel):
    approved_ids: list[str]  # adjustment ids the admin approved to apply
    # Optional per-apply override of the configured trial length. Bounded so a
    # client can't start a 100-year trial; None = use the system config value.
    trial_period_days: Optional[int] = Field(None, ge=1, le=90)


class RemovalRequest(BaseModel):
    """Manual removal requires a reason — Step 5 makes the comment mandatory so
    the trash always carries the 'why' alongside the 'who'."""

    comment: str = Field(..., min_length=3, max_length=500)


class EmailPreferenceUpdate(BaseModel):
    email_notifications: bool


class PatternSelection(BaseModel):
    """One admin-approved pattern proposal, optionally with an edited phrase.

    `phrase` is bounded and character-checked again in
    pattern_override_store.validate_phrase before it can reach the chatbot's
    routing lists — this schema is the outer bound, not the only gate. Note
    there is deliberately no `category` field: the category is derived
    server-side from the proposal id, so a client cannot point a phrase at a
    predicate the analyzer never proposed it for.
    """

    id: str = Field(..., min_length=1, max_length=64)
    phrase: str = Field(..., min_length=3, max_length=50)
    edited: bool = False
    original_phrase: Optional[str] = Field(None, max_length=50)


class ApplyPatterns(BaseModel):
    patterns: list[PatternSelection] = Field(..., min_length=1, max_length=50)


class RevokeRequest(BaseModel):
    """Revoking requires a reason (Step 11) so the revoked list always carries
    the 'why' alongside the performance snapshot."""

    reason: str = Field(..., min_length=3, max_length=500)


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


# ── Access check ──────────────────────────────────────────────────────────────


@router.get("/access", dependencies=[Depends(require_admin)])
@limiter.limit("60/minute")
def admin_access(request: Request, actor: dict = Depends(get_current_role)):
    """Confirm the caller is admin/superadmin, and say which.

    Exists so the client's admin nav gate has something cheap to call. It used
    to poll /stats for this, which meant one role check consumed a slot in that
    endpoint's 10/min budget — and the gate re-runs on app boot, on every
    foreground resume, and on every Home tap, so it routinely starved the two
    pages that actually display stats. This does one role lookup: no psutil
    sampling, no Firestore scan.

    Inputs: none (uid comes from the verified JWT).
    Outputs: {"access": "granted", "role": "admin"|"superadmin"}.
    Security assumption: require_admin has already rejected regular, banned,
    and unauthenticated callers with 403/401 — reaching the body means access
    is granted, and the role returned is the server's resolved role, never a
    client-supplied one.
    """
    return {"access": "granted", "role": actor["role"]}


# ── System stats ──────────────────────────────────────────────────────────────


@router.get("/stats", dependencies=[Depends(require_admin)])
@limiter.limit("10/minute")
def system_stats(request: Request):
    """Return system stats — CPU, RAM, model status, request counts.

    Rate limited to 10/min: it samples CPU for a full second and reads audit
    logs. Callers that only need to know whether the user is an admin should
    use /access instead.
    """
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


# ── Gap report ────────────────────────────────────────────────────────────────


@router.get("/gap-report", dependencies=[Depends(require_admin)])
@limiter.limit("10/minute")
def gap_report(request: Request, days: int = 7):
    """Aggregated chatbot analytics for the Gap Report dashboard.

    Admin-only. `days` (1..30, default 7) selects the look-back window; values
    outside the range are clamped. Reads chat_analytics and aggregates in
    Python (cached 5 min). See app.admin.services.gap_report_service.
    """
    return gap_report_service.get_gap_report(days)


@router.get("/rebuild-fewshot", dependencies=[Depends(require_admin)])
@limiter.limit("5/minute")
def rebuild_fewshot(request: Request):
    """Rebuild the few-shot examples file from thumbs-up feedback and reload
    the in-memory cache, so admins can refresh examples without a redeploy.

    Admin-only. Rate limited: 5 req/min. Returns the new example count.
    """
    from app.user.services.chatbot_service import _reload_fewshot_examples
    from app.user.services.fewshot_service import build_fewshot_examples

    out = build_fewshot_examples()
    _reload_fewshot_examples()
    count = sum(len(v) for v in out.get("examples", {}).values())
    return {"status": "ok", "examples_count": count}


# ── Prompt tuning (analytics-driven, review-gated) ────────────────────────────


@router.post("/analyze-prompt-tuning", dependencies=[Depends(require_superadmin)])
@limiter.limit("5/minute")
def analyze_prompt_tuning(request: Request, days: int = 7):
    """Analyze recent analytics + feedback and PROPOSE prompt tuning
    adjustments. Read-only — saves and applies nothing.

    Admin-only. Rate limited: 5 req/min. Returns the proposed adjustments plus
    the period and sample size the proposal was drawn from.
    """
    from app.user.services.prompt_tuning_service import (
        analyze_and_generate_tuning,
    )

    out = analyze_and_generate_tuning(days)
    return {
        "proposed_adjustments": out["adjustments"],
        "period_days": out["period_days"],
        "sample_size": out["sample_size"],
    }


@router.post("/apply-prompt-tuning", dependencies=[Depends(require_superadmin)])
@limiter.limit("5/minute")
def apply_prompt_tuning(
    request: Request,
    body: ApprovedTuning,
    days: int = 7,
    actor: dict = Depends(get_current_role),
):
    """Start a TRIAL for each admin-approved adjustment id and reload the cache.

    Re-runs the analysis server-side and keeps the approved subset, so the
    applied instructions always come from a trusted source (not a client body).
    Each applied adjustment captures its baseline metric at this moment and
    gets a trial_ends_at from the system config (or body.trial_period_days).
    Superadmin-only. Rate limited: 5 req/min.

    Returns applied/skipped id lists — `skipped` holds ids that were already
    active; ids that no longer trigger appear in neither.
    """
    from app.user.services.chatbot_service import _reload_prompt_tuning
    from app.user.services.prompt_tuning_service import apply_approved

    result = apply_approved(
        body.approved_ids,
        days,
        actor_uid=actor["uid"],
        trial_period_days=body.trial_period_days,
    )
    _reload_prompt_tuning()
    return {
        "status": "ok",
        "applied_count": len(result["applied"]),
        "applied_ids": result["applied"],
        "skipped_ids": result["skipped"],
    }


@router.get("/active-prompt-tuning", dependencies=[Depends(require_superadmin)])
@limiter.limit("10/minute")
def active_prompt_tuning(request: Request):
    """Return the live tuning adjustments (trial + permanent) — exactly what is
    in the prompt right now. Superadmin-only. Rate limited: 10 req/min.
    """
    from app.user.services.prompt_tuning_service import load_active_tuning

    active = load_active_tuning()
    adjustments = active.get("adjustments", [])
    return {
        "active_adjustments": adjustments,
        "count": len(adjustments),
        "trial_count": sum(1 for a in adjustments if a.get("status") == "trial"),
        "permanent_count": sum(
            1 for a in adjustments if a.get("status") == "permanent"
        ),
        "trash_count": active.get("trash_count", 0),
        "updated_at": active.get("updated_at"),
    }


@router.delete("/clear-prompt-tuning", dependencies=[Depends(require_superadmin)])
@limiter.limit("5/minute")
def clear_prompt_tuning(request: Request, actor: dict = Depends(get_current_role)):
    """Move all active tuning to the trash — the chatbot reverts to its static
    prompt. Reversible until retention expires. Superadmin-only. 5 req/min.
    """
    from app.user.services.chatbot_service import _reload_prompt_tuning
    from app.user.services.prompt_tuning_service import clear_tuning

    result = clear_tuning(actor["uid"])
    _reload_prompt_tuning()
    return {"status": "ok", "cleared_count": len(result["cleared"])}


# ── Prompt tuning trash ───────────────────────────────────────────────────────


@router.get("/prompt-tuning-trash", dependencies=[Depends(require_superadmin)])
@limiter.limit("10/minute")
def prompt_tuning_trash(request: Request):
    """Return trashed adjustments, newest first, with their retention deadline
    and whether they can still be restored. Superadmin-only. 10 req/min."""
    from app.user.services import prompt_tuning_store as store_mod

    store = store_mod.load()
    items = sorted(
        store.get("trash", []),
        key=lambda t: t.get("trashed_at") or "",
        reverse=True,
    )
    return {"trash": items, "count": len(items)}


@router.post(
    "/restore-from-trash/{adjustment_id}", dependencies=[Depends(require_superadmin)]
)
@limiter.limit("5/minute")
def restore_from_trash(
    request: Request,
    adjustment_id: str,
    actor: dict = Depends(get_current_role),
):
    """Restore a trashed adjustment as a FRESH trial (new clock, extensions
    reset) and reload the live cache. Superadmin-only. 5 req/min.

    404 if the id isn't in the trash; 409 if an adjustment with that id is
    already active.
    """
    from app.user.services import prompt_tuning_store as store_mod
    from app.user.services.chatbot_service import _reload_prompt_tuning

    result = store_mod.restore(adjustment_id, actor["uid"])
    if not result["ok"]:
        if result["error"] == "already_active":
            raise HTTPException(status_code=409, detail="Adjustment is already active")
        raise HTTPException(status_code=404, detail="Adjustment not found in trash")
    _reload_prompt_tuning()
    return {"status": "ok", "adjustment": result["adjustment"]}


# ── Pattern overrides (analytics-driven routing gaps, review-gated) ───────────


@router.post("/analyze-patterns", dependencies=[Depends(require_superadmin)])
@limiter.limit("5/minute")
def analyze_patterns(request: Request, days: int = 14):
    """Analyze recent analytics for messages that SHOULD have matched a routing
    pattern but didn't, and PROPOSE new phrases. Read-only — saves nothing and
    changes no chatbot behaviour.

    Superadmin-only. Rate limited: 5 req/min. `days` (1..90, default 14) is
    clamped server-side. See app.admin.services.pattern_analyzer_service.
    """
    from app.admin.services import pattern_analyzer_service

    return pattern_analyzer_service.analyze_pattern_gaps(days)


@router.post("/apply-patterns", dependencies=[Depends(require_superadmin)])
@limiter.limit("5/minute")
def apply_patterns(
    request: Request,
    body: ApplyPatterns,
    days: int = 14,
    actor: dict = Depends(get_current_role),
):
    """Approve the selected pattern proposals (honouring admin edits) and
    reload the chatbot's override cache.

    Each phrase is re-validated server-side and each proposal's category comes
    from the server's own analysis, never from the body. Superadmin-only. Rate
    limited: 5 req/min.

    Returns applied ids plus `skipped` entries carrying the reason each one was
    rejected (unknown proposal, already active, duplicate phrase, or the
    validation error).
    """
    from app.admin.services import pattern_analyzer_service
    from app.user.services.chatbot_service import _reload_pattern_overrides

    selections = [
        {
            "id": p.id,
            "phrase": p.phrase,
            "edited": p.edited,
            "original_phrase": p.original_phrase,
        }
        for p in body.patterns
    ]
    result = pattern_analyzer_service.apply_proposals(
        selections, actor_uid=actor["uid"], days=days
    )
    _reload_pattern_overrides()
    return {
        "status": "ok",
        "applied_count": len(result["applied"]),
        "applied_ids": result["applied"],
        "skipped": result["skipped"],
    }


@router.get("/active-patterns", dependencies=[Depends(require_admin)])
@limiter.limit("10/minute")
def active_patterns(request: Request):
    """Active pattern overrides with hit counts, feedback and verdicts —
    exactly what supplements the chatbot's routing lists right now. Grouped by
    category for the management screen. Admin-readable. 10 req/min."""
    from app.admin.services import pattern_analyzer_service

    return pattern_analyzer_service.get_active_patterns()


@router.get("/revoked-patterns", dependencies=[Depends(require_admin)])
@limiter.limit("10/minute")
def revoked_patterns(request: Request):
    """Revoked overrides, newest first, with revoke reason, the performance
    snapshot taken at revoke time, and days_remaining before auto-deletion.
    Admin-readable. 10 req/min."""
    from app.admin.services import pattern_analyzer_service

    return pattern_analyzer_service.get_revoked_patterns()


@router.get("/pattern-analytics/{pattern_id}", dependencies=[Depends(require_admin)])
@limiter.limit("20/minute")
def pattern_analytics(request: Request, pattern_id: str):
    """Per-pattern detail: hit count, feedback breakdown, daily hit rate,
    example hits, thumbs-down false-positive candidates, and a verdict.

    404 when the id is neither active nor revoked. Admin-readable. 20 req/min.
    """
    from app.admin.services import pattern_analyzer_service

    detail = pattern_analyzer_service.get_pattern_analytics(pattern_id)
    if detail is None:
        raise HTTPException(status_code=404, detail="Pattern not found")
    return detail


@router.post("/revoke-pattern/{pattern_id}", dependencies=[Depends(require_superadmin)])
@limiter.limit("10/minute")
def revoke_pattern(
    request: Request,
    pattern_id: str,
    body: RevokeRequest,
    actor: dict = Depends(get_current_role),
):
    """Retire an active override, snapshotting its performance and starting the
    retention clock, then reload the cache so it stops matching immediately.

    Reversible until retention expires. A reason is mandatory. 404 if the id
    isn't active. Superadmin-only. 10 req/min.
    """
    from app.admin.services.system_config_service import get_prompt_tuning_config
    from app.user.services import pattern_override_store as store_mod
    from app.user.services.chatbot_service import _reload_pattern_overrides

    retention = get_prompt_tuning_config().get(
        "trash_retention_days", store_mod.DEFAULT_RETENTION_DAYS
    )
    result = store_mod.revoke_pattern(
        pattern_id, actor["uid"], body.reason, retention_days=retention
    )
    if not result["ok"]:
        raise HTTPException(status_code=404, detail="Active pattern not found")
    _reload_pattern_overrides()
    return {"status": "ok", "pattern": result["item"]}


@router.post(
    "/restore-pattern/{pattern_id}", dependencies=[Depends(require_superadmin)]
)
@limiter.limit("10/minute")
def restore_pattern(
    request: Request,
    pattern_id: str,
    actor: dict = Depends(get_current_role),
):
    """Restore a revoked override with FRESH counters (hits and feedback reset
    to zero) and reload the cache.

    404 if the id isn't in the revoked list; 409 if it is already active.
    Superadmin-only. 10 req/min.
    """
    from app.user.services import pattern_override_store as store_mod
    from app.user.services.chatbot_service import _reload_pattern_overrides

    result = store_mod.restore_pattern(pattern_id, actor["uid"])
    if not result["ok"]:
        if result["error"] == "already_active":
            raise HTTPException(status_code=409, detail="Pattern is already active")
        raise HTTPException(status_code=404, detail="Pattern not found in revoked list")
    _reload_pattern_overrides()
    return {"status": "ok", "pattern": result["item"]}


@router.delete(
    "/delete-pattern/{pattern_id}", dependencies=[Depends(require_superadmin)]
)
@limiter.limit("10/minute")
def delete_pattern(
    request: Request,
    pattern_id: str,
    actor: dict = Depends(get_current_role),
):
    """Permanently delete a revoked override and its hit ledger. Irreversible.

    404 if the id isn't in the revoked list — an active pattern must be revoked
    first, so this can never silently remove something the chatbot is still
    using. Superadmin-only. 10 req/min.
    """
    from app.user.services import pattern_override_store as store_mod

    result = store_mod.delete_pattern(pattern_id, actor["uid"])
    if not result["ok"]:
        raise HTTPException(status_code=404, detail="Pattern not found in revoked list")
    return {"status": "ok", "deleted_id": pattern_id}


# ── Conversation analytics ────────────────────────────────────────────────────
# Read-only insight into how conversations actually go. Follow-up chips are
# generated per reply by the LLM and validated against RAG, so there is no chip
# configuration to review or write here — this endpoint only reports.


@router.post("/mine-patterns", dependencies=[Depends(require_admin)])
@limiter.limit("3/minute")
def mine_patterns(request: Request, days: int = 30):
    """Analyse conversations from the last `days` days. Read-only.

    Reconstructs conversations from chat_analytics and returns drop-off rates,
    the most common and worst-abandoning flows, per-question-type drop-off and
    the chip tap trend. Nothing is written — this is reporting only. `days` is
    clamped to 1..90 in the service. Rate limited hard (3/min): a run scans the
    window's analytics documents.
    """
    from app.admin.services.conversation_miner_service import mine_conversation_patterns

    try:
        return mine_conversation_patterns(days=days)
    except Exception as exc:
        logger.error("conversation analysis failed: %s", exc)
        raise HTTPException(status_code=500, detail="Analysis failed")


# ── Admin notifications (the bell) ────────────────────────────────────────────


@router.get("/notifications", dependencies=[Depends(require_admin)])
@limiter.limit("30/minute")
def list_notifications(request: Request, limit: int = 20, unread_only: bool = False):
    """Recent admin notifications, newest first. Admin-readable.

    `limit` is clamped to 1..100 server-side; `unread_only` filters to unread.
    Rate limit 30/min leaves headroom for the bell's 60s poll plus manual
    refreshes. See app.admin.services.notification_service.
    """
    from app.admin.services.notification_service import get_notifications

    items = get_notifications(limit=limit, unread_only=unread_only)
    return {"notifications": items, "total": len(items)}


@router.get("/notifications/unread-count", dependencies=[Depends(require_admin)])
@limiter.limit("60/minute")
def notifications_unread_count(request: Request):
    """Unread notification count for the bell badge. Admin-readable.

    Higher rate limit (60/min) because this is the endpoint the badge polls
    every 60 seconds; the count is capped server-side (the UI shows '9+').
    """
    from app.admin.services.notification_service import get_unread_count

    return {"count": get_unread_count()}


@router.post(
    "/notifications/{notification_id}/read", dependencies=[Depends(require_admin)]
)
@limiter.limit("60/minute")
def notification_mark_read(request: Request, notification_id: str):
    """Mark one notification read (tapping a card). Admin-readable. Idempotent —
    an unknown id is a no-op, not an error."""
    from app.admin.services.notification_service import mark_read

    mark_read(notification_id)
    return {"status": "ok"}


@router.post("/notifications/read-all", dependencies=[Depends(require_admin)])
@limiter.limit("20/minute")
def notifications_mark_all_read(request: Request):
    """Mark every notification read ('Mark all read'). Admin-readable."""
    from app.admin.services.notification_service import mark_all_read

    mark_all_read()
    return {"status": "ok"}


# ── Email alert preference (per admin) ────────────────────────────────────────


@router.get("/email-preferences", dependencies=[Depends(require_admin)])
@limiter.limit("20/minute")
def get_email_preferences(request: Request, uid: str = Depends(get_current_uid)):
    """Whether the calling admin receives email alerts (default True)."""
    from app.admin.services.notification_service import get_email_preference

    return {"email_notifications": get_email_preference(uid)}


@router.patch("/email-preferences", dependencies=[Depends(require_admin)])
@limiter.limit("20/minute")
def update_email_preferences(
    request: Request,
    body: EmailPreferenceUpdate,
    uid: str = Depends(get_current_uid),
):
    """Turn the calling admin's email alerts on or off. Merges into their
    existing preferences (never clobbers other keys)."""
    from app.admin.services.notification_service import set_email_preference

    value = set_email_preference(uid, body.email_notifications)
    return {"email_notifications": value}
