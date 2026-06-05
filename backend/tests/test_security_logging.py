"""Tests for Security Logging & Monitoring."""

import logging
from app.utils.security_logger import (
    log_unauthorized_access,
    log_suspicious_input,
    log_rate_limit_exceeded,
    log_security_event,
)


def test_unauthorized_access_logging(caplog):
    """Unauthorized access must be logged as warning."""
    with caplog.at_level(logging.WARNING, logger="cropsphere.security"):
        log_unauthorized_access(
            endpoint="/api/health/admin/status",
            ip_address="127.0.0.1",
            reason="Missing token",
        )
    assert "UNAUTHORIZED_ACCESS" in caplog.text
    print("✅ Test 1 Passed — Unauthorized access logged")


def test_suspicious_input_logging(caplog):
    """Suspicious input must be logged as warning."""
    with caplog.at_level(logging.WARNING, logger="cropsphere.security"):
        log_suspicious_input(
            endpoint="/api/yield",
            input_data="<script>alert('hack')</script>",
            reason="XSS attempt",
        )
    assert "SUSPICIOUS_INPUT" in caplog.text
    print("✅ Test 2 Passed — Suspicious input logged")


def test_rate_limit_logging(caplog):
    """Rate limit exceeded must be logged."""
    with caplog.at_level(logging.WARNING, logger="cropsphere.security"):
        log_rate_limit_exceeded(
            endpoint="/api/health",
            ip_address="192.168.1.1",
        )
    assert "RATE_LIMIT_EXCEEDED" in caplog.text
    print("✅ Test 3 Passed — Rate limit exceeded logged")


def test_security_event_logging(caplog):
    """General security events must be logged."""
    with caplog.at_level(logging.INFO, logger="cropsphere.security"):
        log_security_event(
            event_type="LOGIN_ATTEMPT",
            details="Failed login for user farmer@example.com",
        )
    assert "SECURITY_EVENT" in caplog.text
    print("✅ Test 4 Passed — Security event logged")
