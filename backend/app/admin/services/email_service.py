"""Transactional email delivery for admin alerts — Gmail SMTP over stdlib.

Deliberately dependency-free: Python's smtplib + email.message, so there is
nothing to add to requirements.txt. Gmail with an App Password is the intended
setup (simplest for the project); any STARTTLS SMTP server works via the
EMAIL_SMTP_* settings.

Best-effort by design (same rule as analytics_service / notification_service):
delivery ALWAYS runs on a background thread and NEVER raises into the caller, so
sending an email can never slow or break a request or a tuning transition. When
EMAIL_ENABLED is false the send is a no-op — safe for dev and tests.

Security: the SMTP password comes from the environment only (never logged). Email
bodies carry only a notification's title/message — no raw user queries, no keys.
"""

import html
import logging
import smtplib
import threading
from email.message import EmailMessage

logger = logging.getLogger(__name__)

# SMTP dialog timeout — a hung server must not pin the background thread open.
_SMTP_TIMEOUT = 15

# Per-severity accent colour + emoji for the template. Unknown severities fall
# back to the "info" styling.
_SEVERITY_STYLES = {
    "success": {"color": "#2E7D32", "icon": "✅", "label": "Success"},
    "info": {"color": "#1976D2", "icon": "ℹ️", "label": "Info"},
    "warning": {"color": "#F57F17", "icon": "⚠️", "label": "Warning"},
    "error": {"color": "#C62828", "icon": "❌", "label": "Alert"},
}

_HEADER_GREEN = "#1B5E20"


def send_email(to: str, subject: str, body_html: str) -> None:
    """Send one HTML email. Best-effort: never raises, always backgrounded.

    Inputs: to (a single recipient address), subject, body_html (full HTML
    document). Outputs: None — returns immediately; delivery happens on a
    daemon thread. When EMAIL_ENABLED is false this logs at debug and returns
    without connecting. A single recipient convenience wrapper over
    send_email_to (which the notification fan-out uses for many recipients).
    """
    send_email_to([to], subject, body_html)


def send_email_to(recipients: list, subject: str, body_html: str) -> None:
    """Send one HTML email to many recipients on a single background thread.

    Inputs: recipients (list of addresses; empty → no-op), subject, body_html.
    Outputs: None. One SMTP session serves all recipients; the SMTP sender is
    never itself a recipient (they are addressed in To and set as the explicit
    envelope). Never raises — a misconfigured server or auth failure is logged
    at warning and swallowed, because an alert email failing must not affect
    anything else.
    """
    clean = [r for r in (recipients or []) if isinstance(r, str) and r.strip()]
    if not clean:
        return

    from app.config import get_settings

    settings = get_settings()
    if not settings.EMAIL_ENABLED:
        logger.debug(
            "email disabled — not sending %r to %d recipient(s)", subject, len(clean)
        )
        return

    # Snapshot config now (on the calling thread) so the worker is self-contained.
    cfg = {
        "host": settings.EMAIL_SMTP_HOST,
        "port": settings.EMAIL_SMTP_PORT,
        "user": settings.EMAIL_SMTP_USER,
        "password": settings.EMAIL_SMTP_PASSWORD,
        "sender": settings.EMAIL_FROM or settings.EMAIL_SMTP_USER,
    }
    threading.Thread(
        target=_deliver,
        args=(clean, subject, body_html, cfg),
        daemon=True,
        name="email-send",
    ).start()


def _deliver(recipients: list, subject: str, body_html: str, cfg: dict) -> None:
    """Blocking SMTP send — runs only on the background thread. Swallows every
    error so a delivery failure never surfaces."""
    try:
        msg = EmailMessage()
        msg["Subject"] = subject
        msg["From"] = cfg["sender"]
        # Address the actual admins — NOT the SMTP sender. Previously the sender
        # was placed in To (to hide addresses), which made it a recipient of
        # every alert regardless of anyone's preference — the reported "sent to
        # the sender, and opt-out doesn't work" bug.
        msg["To"] = ", ".join(recipients)
        msg.set_content(_plain_fallback(subject))
        msg.add_alternative(body_html, subtype="html")

        with smtplib.SMTP(cfg["host"], cfg["port"], timeout=_SMTP_TIMEOUT) as smtp:
            smtp.starttls()
            if cfg["user"] and cfg["password"]:
                smtp.login(cfg["user"], cfg["password"])
            # Explicit envelope = exactly the recipients. The sender is never in
            # it, so the SMTP account never self-receives, even if it also
            # happens to be one of the admins who opted out.
            smtp.send_message(msg, from_addr=cfg["sender"], to_addrs=recipients)
        logger.info("alert email sent to %d recipient(s): %r", len(recipients), subject)
    except Exception as exc:
        # Never log the password or full config; just the failure reason.
        logger.warning("email delivery failed (%r): %s", subject, exc)


def _plain_fallback(subject: str) -> str:
    """A minimal text/plain part so the message isn't HTML-only (spam-friendly
    and readable in text clients)."""
    return (
        f"{subject}\n\n"
        "Open the CropSphere admin dashboard to view this alert.\n"
        "— CropSphere Admin Alerts"
    )


# ── Templates ─────────────────────────────────────────────────────────────────


def render_notification_email(
    title: str,
    message: str,
    severity: str,
    dashboard_url: str = "",
) -> str:
    """Render the shared notification email layout.

    Inputs: title, message (plain text — both are HTML-escaped here, so a
    system-derived string with an angle bracket can't break the markup),
    severity (drives accent colour + icon), dashboard_url (the "View in
    Dashboard" button target; the button is omitted when empty).
    Outputs: a complete, self-contained HTML document (inline styles only, so
    it renders in email clients that strip <style>).
    Security: title/message are escaped; no user PII or secrets are included by
    the callers (only a notification's own title/message).
    """
    style = _SEVERITY_STYLES.get(severity, _SEVERITY_STYLES["info"])
    safe_title = html.escape(title or "")
    safe_message = html.escape(message or "").replace("\n", "<br>")

    button = ""
    if dashboard_url:
        button = f"""
        <tr><td style="padding:8px 24px 24px;">
          <a href="{html.escape(dashboard_url)}"
             style="display:inline-block;background:{_HEADER_GREEN};color:#ffffff;
                    text-decoration:none;font-weight:600;font-size:14px;
                    padding:10px 20px;border-radius:6px;">View in Dashboard</a>
        </td></tr>"""

    return f"""\
<!DOCTYPE html>
<html>
<head><meta charset="utf-8"><meta name="viewport" content="width=device-width"></head>
<body style="margin:0;padding:0;background:#f1f7f1;
             font-family:-apple-system,Segoe UI,Roboto,Helvetica,Arial,sans-serif;">
  <table role="presentation" width="100%" cellpadding="0" cellspacing="0"
         style="background:#f1f7f1;padding:24px 0;">
    <tr><td align="center">
      <table role="presentation" width="480" cellpadding="0" cellspacing="0"
             style="background:#ffffff;border-radius:12px;overflow:hidden;
                    box-shadow:0 1px 4px rgba(0,0,0,0.08);max-width:480px;width:100%;">
        <tr><td style="background:{_HEADER_GREEN};padding:16px 24px;">
          <span style="color:#ffffff;font-size:18px;font-weight:700;
                       letter-spacing:0.5px;">🌱 CropSphere</span>
        </td></tr>
        <tr><td style="padding:0;">
          <table role="presentation" width="100%" cellpadding="0" cellspacing="0">
            <tr>
              <td style="width:6px;background:{style['color']};">&nbsp;</td>
              <td style="padding:20px 24px 8px;">
                <div style="font-size:16px;font-weight:700;color:#1a2b1a;">
                  {style['icon']} {safe_title}
                </div>
                <div style="font-size:14px;line-height:1.5;color:#3d4d3d;
                            padding-top:8px;">{safe_message}</div>
              </td>
            </tr>
          </table>
        </td></tr>
        {button}
        <tr><td style="padding:16px 24px;border-top:1px solid #eef2ee;
                       font-size:11px;color:#8fa88f;line-height:1.5;">
          CropSphere Admin Alerts — You're receiving this because you're an
          admin of CropSphere.
        </td></tr>
      </table>
    </td></tr>
  </table>
</body>
</html>"""
