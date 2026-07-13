"""Tests for the security_events persistence layer.

Covers:
- app.utils.firestore.write_security_event (shape + best-effort behaviour)
- app.utils.security_logger.record_* (stdout log + Firestore persist)
- middleware wiring: an unauthenticated request records a failed_login
"""

import logging
from unittest.mock import MagicMock, patch

from app.utils.firestore import write_security_event
from app.utils.security_logger import (
    record_banned_access_attempt,
    record_failed_login,
    record_rate_limit_violation,
)


# ═══════════════════════════════════════════════════════════════════════════
# write_security_event
# ═══════════════════════════════════════════════════════════════════════════


def test_write_security_event_writes_expected_document():
    mock_db = MagicMock()
    with patch("app.utils.firestore.get_db", return_value=mock_db):
        write_security_event(
            "failed_login",
            uid="u1",
            ip_address="1.2.3.4",
            endpoint="/api/x",
            details={"reason": "missing"},
        )

    mock_db.collection.assert_called_once_with("security_events")
    doc = mock_db.collection.return_value.add.call_args.args[0]
    assert doc["type"] == "failed_login"
    assert doc["uid"] == "u1"
    assert doc["ip_address"] == "1.2.3.4"
    assert doc["endpoint"] == "/api/x"
    assert doc["details"] == {"reason": "missing"}
    assert "timestamp" in doc


def test_write_security_event_normalises_empty_strings_to_none():
    mock_db = MagicMock()
    with patch("app.utils.firestore.get_db", return_value=mock_db):
        write_security_event("rate_limit_violation", ip_address="9.9.9.9")

    doc = mock_db.collection.return_value.add.call_args.args[0]
    assert doc["uid"] is None
    assert doc["email"] is None
    assert doc["endpoint"] is None
    assert doc["details"] == {}


def test_write_security_event_swallows_firestore_errors():
    """Best-effort: an uninitialised/failing Firestore must not raise."""
    with patch("app.utils.firestore.get_db", side_effect=RuntimeError("no db")):
        # Must not raise.
        write_security_event("failed_login", ip_address="1.2.3.4")


# ═══════════════════════════════════════════════════════════════════════════
# record_* — stdout log + persistence
# ═══════════════════════════════════════════════════════════════════════════


def test_record_failed_login_logs_and_persists(caplog):
    with patch("app.utils.firestore.write_security_event") as mock_write:
        with caplog.at_level(logging.WARNING, logger="cropsphere.security"):
            record_failed_login(
                endpoint="/api/x", ip_address="1.2.3.4", reason="missing"
            )

    assert "UNAUTHORIZED_ACCESS" in caplog.text
    mock_write.assert_called_once()
    assert mock_write.call_args.kwargs["event_type"] == "failed_login"
    assert mock_write.call_args.kwargs["details"] == {"reason": "missing"}


def test_record_rate_limit_violation_logs_and_persists(caplog):
    with patch("app.utils.firestore.write_security_event") as mock_write:
        with caplog.at_level(logging.WARNING, logger="cropsphere.security"):
            record_rate_limit_violation(
                endpoint="/api/chat", ip_address="1.2.3.4", limit="10/minute"
            )

    assert "RATE_LIMIT_EXCEEDED" in caplog.text
    assert mock_write.call_args.kwargs["event_type"] == "rate_limit_violation"
    assert mock_write.call_args.kwargs["details"] == {"limit": "10/minute"}


def test_record_banned_access_attempt_logs_and_persists(caplog):
    with patch("app.utils.firestore.write_security_event") as mock_write:
        with caplog.at_level(logging.WARNING, logger="cropsphere.security"):
            record_banned_access_attempt(
                endpoint="/api/chat", ip_address="1.2.3.4", uid="banned-1"
            )

    assert "UNAUTHORIZED_ACCESS" in caplog.text
    assert mock_write.call_args.kwargs["event_type"] == "banned_access_attempt"
    assert mock_write.call_args.kwargs["uid"] == "banned-1"


def test_persist_never_raises_when_write_fails():
    """record_* must not propagate a persistence failure to the request path."""
    with patch(
        "app.utils.firestore.write_security_event",
        side_effect=RuntimeError("boom"),
    ):
        # Must not raise.
        record_failed_login(endpoint="/api/x", ip_address="1.2.3.4", reason="missing")


# ═══════════════════════════════════════════════════════════════════════════
# Middleware wiring — an unauthenticated request emits a failed_login event
# ═══════════════════════════════════════════════════════════════════════════


def test_unauthenticated_request_records_failed_login(client):
    with patch("app.utils.security_logger.record_failed_login") as mock_rec:
        resp = client.get("/api/admin/stats")  # no Authorization header

    assert resp.status_code == 401
    assert mock_rec.called
