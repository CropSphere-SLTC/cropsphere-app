"""Security Logging & Monitoring for CropSphere."""

import logging
from datetime import datetime, timezone

# Security specific logger
security_logger = logging.getLogger("cropsphere.security")


def log_unauthorized_access(
    endpoint: str,
    ip_address: str,
    reason: str,
) -> None:
    """Log unauthorized access attempts."""
    security_logger.warning(
        "UNAUTHORIZED_ACCESS | endpoint=%s | ip=%s | reason=%s | time=%s",
        endpoint,
        ip_address,
        reason,
        datetime.now(timezone.utc).isoformat(),
    )


def log_suspicious_input(
    endpoint: str,
    input_data: str,
    reason: str,
) -> None:
    """Log suspicious/malicious input attempts."""
    security_logger.warning(
        "SUSPICIOUS_INPUT | endpoint=%s | input=%s | reason=%s | time=%s",
        endpoint,
        input_data,
        reason,
        datetime.now(timezone.utc).isoformat(),
    )


def log_rate_limit_exceeded(
    endpoint: str,
    ip_address: str,
) -> None:
    """Log rate limit exceeded events."""
    security_logger.warning(
        "RATE_LIMIT_EXCEEDED | endpoint=%s | ip=%s | time=%s",
        endpoint,
        ip_address,
        datetime.now(timezone.utc).isoformat(),
    )


def log_security_event(
    event_type: str,
    details: str,
) -> None:
    """Log general security events."""
    security_logger.info(
        "SECURITY_EVENT | type=%s | details=%s | time=%s",
        event_type,
        details,
        datetime.now(timezone.utc).isoformat(),
    )


# ── Persisted security events ─────────────────────────────────────────────────
#
# The record_* helpers below layer Firestore persistence (the security_events
# collection, surfaced in the admin Security dashboard) on top of the existing
# stdout logging. They are called from the request path — auth failures, 429s,
# banned-account access — so persistence is strictly best-effort: a Firestore
# failure is swallowed and never allowed to change the HTTP response.


def _persist_event(
    event_type: str,
    uid: str = "",
    email: str = "",
    ip_address: str = "",
    endpoint: str = "",
    details: dict = None,
) -> None:
    """Best-effort write of a security event to Firestore. Never raises."""
    try:
        from app.utils.firestore import write_security_event

        write_security_event(
            event_type=event_type,
            uid=uid,
            email=email,
            ip_address=ip_address,
            endpoint=endpoint,
            details=details or {},
        )
    except Exception as exc:  # pragma: no cover — defensive, write_* also guards
        security_logger.error(
            "security_events persist failed (type=%s): %s", event_type, exc
        )


def record_failed_login(
    endpoint: str,
    ip_address: str,
    reason: str,
    uid: str = "",
    email: str = "",
    details: dict = None,
) -> None:
    """Log + persist an authentication failure (missing/invalid/expired token).

    uid/email carry the attempting account only when the caller established it
    from a signature-verified token (expired or revoked); they stay empty when
    no trustworthy identity exists, which is the case for a missing header or
    an unverifiable token. `details` may carry extra context — including an
    identity merely *claimed* by an unverified token, which callers must keep
    out of uid/email. Defaults to just the reason.
    """
    log_unauthorized_access(endpoint=endpoint, ip_address=ip_address, reason=reason)
    _persist_event(
        "failed_login",
        uid=uid,
        email=email,
        ip_address=ip_address,
        endpoint=endpoint,
        details=details or {"reason": reason},
    )


def record_rate_limit_violation(
    endpoint: str,
    ip_address: str,
    uid: str = "",
    limit: str = "",
) -> None:
    """Log + persist a rate-limit violation (429 response)."""
    log_rate_limit_exceeded(endpoint=endpoint, ip_address=ip_address)
    _persist_event(
        "rate_limit_violation",
        uid=uid,
        ip_address=ip_address,
        endpoint=endpoint,
        details={"limit": limit} if limit else {},
    )


def record_banned_access_attempt(
    endpoint: str,
    ip_address: str,
    uid: str,
    email: str = "",
) -> None:
    """Log + persist a banned user's attempt to reach a protected endpoint."""
    log_unauthorized_access(
        endpoint=endpoint, ip_address=ip_address, reason="banned account"
    )
    _persist_event(
        "banned_access_attempt",
        uid=uid,
        email=email,
        ip_address=ip_address,
        endpoint=endpoint,
        details={},
    )
