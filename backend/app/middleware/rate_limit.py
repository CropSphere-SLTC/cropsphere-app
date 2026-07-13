"""Rate limiting configuration — 30 requests/minute per IP via slowapi."""

from fastapi import Request
from fastapi.responses import Response
from slowapi import Limiter
from slowapi import _rate_limit_exceeded_handler as _slowapi_handler
from slowapi.errors import RateLimitExceeded
from slowapi.util import get_remote_address

# Module-level limiter imported by every protected router
limiter = Limiter(
    key_func=get_remote_address,
    default_limits=["200/minute"],
)


def rate_limit_exceeded_handler(request: Request, exc: RateLimitExceeded) -> Response:
    """Persist a rate_limit_violation security event, then return slowapi's
    standard 429 response.

    Delegating to slowapi's built-in handler preserves the Retry-After header
    that AdminService.checkAdminAccess in the Flutter client depends on. The
    event write is strictly best-effort and never alters the response. The
    acting uid is read from request.state when available (per-route limits are
    evaluated after auth); it is absent for the global default limit, which is
    enforced before auth runs.
    """
    try:
        from app.utils.security_logger import record_rate_limit_violation

        record_rate_limit_violation(
            endpoint=request.url.path,
            ip_address=get_remote_address(request),
            uid=getattr(request.state, "user_id", "") or "",
            limit=str(getattr(exc, "detail", "") or ""),
        )
    except Exception:
        pass
    return _slowapi_handler(request, exc)
