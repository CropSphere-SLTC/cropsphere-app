"""Security Logging & Monitoring for CropSphere."""
import logging
from datetime import datetime, timezone
from typing import Optional

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