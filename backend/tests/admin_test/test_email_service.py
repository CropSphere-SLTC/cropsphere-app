"""Unit tests for app.admin.services.email_service.

SMTP is mocked — no real mail is ever sent. Covers the EMAIL_ENABLED gate, the
background-thread hand-off, the SMTP dialog, the never-raise guarantee, and the
per-severity HTML template (including escaping).
"""

import re
from types import SimpleNamespace
from unittest.mock import MagicMock, patch

from app.admin.services import email_service as es


def _settings(**over):
    base = {
        "EMAIL_ENABLED": True,
        "EMAIL_FROM": "alerts@cropsphere.app",
        "EMAIL_SMTP_HOST": "smtp.gmail.com",
        "EMAIL_SMTP_PORT": 587,
        "EMAIL_SMTP_USER": "alerts@cropsphere.app",
        "EMAIL_SMTP_PASSWORD": "app-password",
    }
    base.update(over)
    return SimpleNamespace(**base)


# ── The enabled/disabled gate + threading ─────────────────────────────────────


def test_disabled_is_a_no_op():
    with patch("app.config.get_settings", return_value=_settings(EMAIL_ENABLED=False)):
        with patch.object(es.threading, "Thread") as thread:
            es.send_email_to(["a@b.com"], "subj", "<p>hi</p>")
    thread.assert_not_called()


def test_empty_recipients_is_a_no_op():
    with patch("app.config.get_settings", return_value=_settings()):
        with patch.object(es.threading, "Thread") as thread:
            es.send_email_to([], "subj", "<p>hi</p>")
            es.send_email_to(["", "  "], "subj", "<p>hi</p>")
    thread.assert_not_called()


def test_enabled_dispatches_on_a_background_thread():
    with patch("app.config.get_settings", return_value=_settings()):
        with patch.object(es.threading, "Thread") as thread:
            es.send_email_to(["a@b.com", "c@d.com"], "subj", "<p>hi</p>")
    thread.assert_called_once()
    assert thread.call_args.kwargs["target"] is es._deliver
    assert thread.call_args.kwargs["daemon"] is True
    thread.return_value.start.assert_called_once()


def test_send_email_wraps_single_recipient():
    with patch.object(es, "send_email_to") as bulk:
        es.send_email("solo@x.com", "s", "<p>b</p>")
    bulk.assert_called_once_with(["solo@x.com"], "s", "<p>b</p>")


# ── The SMTP dialog (_deliver runs on the worker thread) ──────────────────────


def _cfg():
    return {
        "host": "smtp.gmail.com",
        "port": 587,
        "user": "alerts@cropsphere.app",
        "password": "app-password",
        "sender": "alerts@cropsphere.app",
    }


def test_deliver_performs_starttls_login_and_send():
    server = MagicMock()
    smtp_cm = MagicMock()
    smtp_cm.__enter__.return_value = server
    with patch.object(es.smtplib, "SMTP", return_value=smtp_cm) as smtp:
        es._deliver(["x@y.com", "z@w.com"], "Subject", "<p>body</p>", _cfg())

    smtp.assert_called_once_with("smtp.gmail.com", 587, timeout=es._SMTP_TIMEOUT)
    server.starttls.assert_called_once()
    server.login.assert_called_once_with("alerts@cropsphere.app", "app-password")
    server.send_message.assert_called_once()
    sent = server.send_message.call_args[0][0]
    assert sent["To"] == "x@y.com, z@w.com"
    assert "@" in sent["From"]
    # Multipart: a plain fallback plus the HTML alternative.
    assert sent.get_content_type() == "multipart/alternative"


def test_deliver_envelope_excludes_the_sender():
    """Regression: the SMTP sender must never be an envelope recipient, so it
    doesn't self-receive every alert (and can honour its own opt-out)."""
    server = MagicMock()
    cm = MagicMock()
    cm.__enter__.return_value = server
    cfg = _cfg()  # sender == alerts@cropsphere.app
    with patch.object(es.smtplib, "SMTP", return_value=cm):
        es._deliver(["admin1@x.com", "admin2@x.com"], "S", "<p>b</p>", cfg)
    _, kwargs = server.send_message.call_args
    assert kwargs["to_addrs"] == ["admin1@x.com", "admin2@x.com"]
    assert cfg["sender"] not in kwargs["to_addrs"]
    # No Bcc header that would leak addresses either.
    assert server.send_message.call_args[0][0]["Bcc"] is None


def test_deliver_skips_login_without_credentials():
    server = MagicMock()
    cm = MagicMock()
    cm.__enter__.return_value = server
    cfg = _cfg()
    cfg["user"] = ""
    cfg["password"] = ""
    with patch.object(es.smtplib, "SMTP", return_value=cm):
        es._deliver(["x@y.com"], "S", "<p>b</p>", cfg)
    server.login.assert_not_called()
    server.send_message.assert_called_once()


def test_deliver_never_raises_on_smtp_failure():
    with patch.object(es.smtplib, "SMTP", side_effect=OSError("connection refused")):
        # Must not propagate — a failed alert email can't break anything.
        es._deliver(["x@y.com"], "S", "<p>b</p>", _cfg())


# ── Templates ─────────────────────────────────────────────────────────────────


def test_render_includes_header_footer_and_message():
    html = es.render_notification_email("My title", "My message", "warning")
    assert "CropSphere" in html
    assert "My title" in html
    assert "My message" in html
    assert "You're receiving this because" in html
    assert "admin of CropSphere" in html


def test_render_button_only_with_dashboard_url():
    url = "https://dash.app"
    with_btn = es.render_notification_email("t", "m", "info", url)
    without = es.render_notification_email("t", "m", "info", "")
    assert "View in Dashboard" in with_btn
    # Match the href exactly rather than scanning the body for the URL: this
    # proves the link landed in the anchor, which a substring check does not
    # (it would also pass if the URL leaked into a text node). A bare
    # `url in html` is also what CodeQL's incomplete-URL-substring-sanitization
    # query flags, since that shape is a broken way to validate a real URL.
    href = re.search(r'href="([^"]+)"', with_btn)
    assert href is not None and href.group(1) == url
    assert "View in Dashboard" not in without


def test_render_escapes_html_in_title_and_message():
    html = es.render_notification_email("<script>x</script>", "a & b", "error")
    assert "<script>x</script>" not in html
    assert "&lt;script&gt;" in html
    assert "a &amp; b" in html


def test_render_converts_newlines_to_breaks():
    html = es.render_notification_email("t", "line1\nline2", "info")
    assert "line1<br>line2" in html


def test_render_uses_severity_accent_and_icon():
    for severity, icon in [
        ("success", "✅"),
        ("info", "ℹ️"),
        ("warning", "⚠️"),
        ("error", "❌"),
    ]:
        html = es.render_notification_email("t", "m", severity)
        assert icon in html
        assert es._SEVERITY_STYLES[severity]["color"] in html


def test_render_unknown_severity_falls_back_to_info():
    html = es.render_notification_email("t", "m", "banana")
    assert es._SEVERITY_STYLES["info"]["color"] in html
