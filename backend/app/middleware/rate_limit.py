"""Rate limiting configuration — 30 requests/minute per IP via slowapi."""

from slowapi import Limiter
from slowapi.util import get_remote_address

# Module-level limiter imported by every protected router
limiter = Limiter(
    key_func=get_remote_address,
    default_limits=["30/minute"],
)
