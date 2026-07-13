"""Security monitoring endpoints — read-only views for the admin dashboard.

Thin HTTP layer: auth dependencies and rate limiting only. All business logic
lives in app.admin.services.security_service. Both admin and superadmin may
read these views (require_admin); no action endpoints live here — force-logout
is superadmin-only and lives in the superadmin router.
"""

import logging

from fastapi import APIRouter, Depends, Request

from app.admin.services import security_service
from app.middleware.rate_limit import limiter
from app.middleware.roles import require_admin

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/api/admin/security", tags=["security"])


@router.get("/summary", dependencies=[Depends(require_admin)])
@limiter.limit("10/minute")
def security_summary(request: Request):
    """Return 24h counts of failed logins, rate violations, banned attempts,
    and the current active-session count."""
    return security_service.get_security_summary()


@router.get("/failed-logins", dependencies=[Depends(require_admin)])
@limiter.limit("10/minute")
def failed_logins(request: Request, limit: int = 50):
    """Return recent failed-login events."""
    return security_service.get_failed_logins(limit)


@router.get("/rate-violations", dependencies=[Depends(require_admin)])
@limiter.limit("10/minute")
def rate_violations(request: Request, limit: int = 50):
    """Return recent rate-limit-violation events."""
    return security_service.get_rate_violations(limit)


@router.get("/banned-attempts", dependencies=[Depends(require_admin)])
@limiter.limit("10/minute")
def banned_attempts(request: Request, limit: int = 50):
    """Return recent banned-user access attempts."""
    return security_service.get_banned_attempts(limit)


@router.get("/active-sessions", dependencies=[Depends(require_admin)])
@limiter.limit("10/minute")
def active_sessions(request: Request, limit: int = 100):
    """Return currently active sessions (last_active within 24h)."""
    return security_service.get_active_sessions(limit)
