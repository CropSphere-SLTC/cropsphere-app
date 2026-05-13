"""Rate limiting configuration — 30 requests/minute per IP via slowapi."""

from fastapi import Request
from fastapi.responses import JSONResponse
from slowapi import Limiter
from slowapi.errors import RateLimitExceeded
from slowapi.util import get_remote_address

# Module-level limiter imported by every protected router
limiter = Limiter(
    key_func=get_remote_address,
    default_limits=["30/minute"],
)


def rate_limit_exceeded_handler(request: Request, exc: RateLimitExceeded) -> JSONResponse:
    """Return a 429 JSON response when the rate limit is exceeded."""
    return JSONResponse(
        status_code=429,
        content={
            "error": "Rate limit exceeded",
            "detail": "Too many requests. Try again later.",
        },
    )
