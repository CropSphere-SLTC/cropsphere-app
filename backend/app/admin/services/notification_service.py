"""In-app admin notifications — system events surfaced to the admin/superadmin
bell, backed by the `admin_notifications` Firestore collection.

This is the SINGLE writer/reader of that collection. Prompt-tuning decisions,
analytics alerts, and any future system event all funnel through
create_notification here so the schema stays uniform (see the field list in
create_notification). tuning_validation_service delegates to this module rather
than writing the collection itself.

Best-effort by design (mirrors analytics_service / audit_log): notification
creation NEVER raises into its caller, so it can never fail a chat request or a
tuning transition. Reads degrade to empty/zero rather than surfacing a 500 to
the bell.

Firestore indexing: every query here is either a single-field equality
(`read == False`) or a single-field inequality (`created_at >= cutoff`) or a
single-field order (`created_at DESC`). None needs a composite index, so the
feature works against a fresh Firestore with no index setup.
"""

import logging
import threading
import time
from datetime import datetime, timedelta, timezone

logger = logging.getLogger(__name__)

_COLLECTION = "admin_notifications"

# The four severities the UI knows how to render (icon + colour). Anything else
# is coerced to "info" so a bad caller can't produce an unstyleable card.
SEVERITIES = ("info", "warning", "success", "error")

# Reading unread for the badge is capped — the badge only needs to distinguish
# 0..9 from "9+", so counting past this is wasted Firestore reads.
_UNREAD_CAP = 50
_MAX_LIMIT = 100
# mark_all_read commits in batches (Firestore caps a batch at 500 writes).
_BATCH = 400

# ── Analytics-alert thresholds ────────────────────────────────────────────────
# A refusal/satisfaction rate is only meaningful above a floor of activity;
# below it the alert check stays silent rather than crying wolf on 3 chats.
_ALERT_MIN_INTERACTIONS = 20
_ALERT_MIN_FEEDBACK = 10
_HIGH_REFUSAL_RATE = 0.40
_LOW_SATISFACTION_RATE = 0.50
_MILESTONE_STEP = 100

# ── Email escalation (Phase B) ────────────────────────────────────────────────
# Only these notification types escalate to email — the urgent / action-needed
# ones. Success/info notifications stay in-app only. Kept as a set so the policy
# is a one-line edit.
_EMAIL_WORTHY_TYPES = {
    "adjustment_auto_removed",
    "adjustment_needs_review",
    "high_refusal_rate",
    "low_satisfaction",
}

# Human plural phrasing for the batched "N X in the last hour" subject.
_EMAIL_TYPE_PLURALS = {
    "adjustment_auto_removed": "adjustments were auto-removed",
    "adjustment_needs_review": "adjustments need review",
    "high_refusal_rate": "high refusal rate alerts",
    "low_satisfaction": "low satisfaction alerts",
}

# One email per type per hour (Step 8). Extra events of a type within the window
# are counted and folded into the next email's "N in the last hour" summary.
_EMAIL_COOLDOWN_SECONDS = 3600

# Admin recipient list is cached this long so a burst of notifications doesn't
# re-scan the users collection each time.
_RECIPIENT_TTL_SECONDS = 300

# {type: {"last_sent": monotonic, "pending": int}} — in-memory only; resetting
# on restart is acceptable (Step 8). Guarded by _email_lock.
_email_state: dict[str, dict] = {}
_email_lock = threading.Lock()

# (expires_at_monotonic, [recipient emails]).
_recipient_cache: tuple[float, list] | None = None
_recipient_lock = threading.Lock()


def _now() -> datetime:
    return datetime.now(timezone.utc)


# ── Core CRUD ─────────────────────────────────────────────────────────────────


def create_notification(
    type: str,
    title: str,
    message: str,
    severity: str = "info",
    related_id: str | None = None,
    action_url: str | None = None,
) -> str:
    """Create one admin notification and return its Firestore document id.

    Inputs: type (event key, see module notes), title (short list text),
    message (detail text), severity (one of SEVERITIES; coerced to "info" if
    not), related_id (e.g. an adjustment_id, for deep-linking), action_url
    (client route, e.g. "/adjustment/dim1").
    Outputs: the new doc id, or "" on any failure.
    Never raises — a failed notification must not roll back the operation that
    triggered it. Field lengths are clamped so a runaway caller can't write an
    oversized document.
    Security assumption: callers are internal; `message`/`title` may contain
    system-derived text but never raw user input beyond already-sanitised
    analytics fields, and nothing here is ever injected into a prompt.
    """
    try:
        from firebase_admin import firestore

        from app.utils.firestore import get_db

        doc = {
            "type": str(type)[:64],
            "title": str(title)[:200],
            "message": str(message)[:1000],
            "severity": severity if severity in SEVERITIES else "info",
            "created_at": firestore.SERVER_TIMESTAMP,
            "read": False,
            "read_at": None,
            "related_id": related_id,
            "action_url": action_url,
        }
        _, ref = get_db().collection(_COLLECTION).add(doc)
        # Escalate to email if this type warrants it. Fully isolated and
        # non-blocking (its own thread) — an email path failure must never
        # affect the notification that was just saved.
        _maybe_email(doc["type"], doc["title"], doc["message"], doc["severity"])
        return ref.id
    except Exception as exc:
        logger.warning("notification create failed (%s): %s", type, exc)
        return ""


def get_notifications(limit: int = 20, unread_only: bool = False) -> list:
    """Return recent notifications, newest first.

    Inputs: limit (clamped 1.._MAX_LIMIT), unread_only (when True, only
    `read == False`).
    Outputs: list of dicts with `id` set and `created_at`/`read_at` rendered as
    ISO strings. Empty list on any failure.
    Note: unread_only uses an equality filter (no composite index) and sorts in
    Python, so it never requires index setup.
    """
    limit = max(1, min(int(limit), _MAX_LIMIT))
    try:
        from google.cloud.firestore_v1.base_query import FieldFilter

        from app.utils.firestore import get_db

        col = get_db().collection(_COLLECTION)
        if unread_only:
            # Equality-only query, then Python sort — avoids a (read,created_at)
            # composite index. Capped so the fetch stays bounded.
            docs = (
                col.where(filter=FieldFilter("read", "==", False))
                .limit(_MAX_LIMIT)
                .stream()
            )
            items = [_serialize(d) for d in docs]
            items.sort(key=lambda n: n.get("created_at") or "", reverse=True)
            return items[:limit]
        docs = col.order_by("created_at", direction="DESCENDING").limit(limit).stream()
        return [_serialize(d) for d in docs]
    except Exception as exc:
        logger.warning("notification list failed: %s", exc)
        return []


def get_unread_count() -> int:
    """Count unread notifications for the badge.

    Bounded by _UNREAD_CAP — the badge renders anything over 9 as "9+", so an
    exact count beyond the cap is not worth the reads. Returns 0 on failure.
    """
    try:
        from google.cloud.firestore_v1.base_query import FieldFilter

        from app.utils.firestore import get_db

        docs = (
            get_db()
            .collection(_COLLECTION)
            .where(filter=FieldFilter("read", "==", False))
            .limit(_UNREAD_CAP)
            .stream()
        )
        return sum(1 for _ in docs)
    except Exception as exc:
        logger.warning("unread count failed: %s", exc)
        return 0


def mark_read(notification_id: str) -> None:
    """Mark a single notification read. Never raises (a missing id is a no-op
    at the Firestore layer, logged and swallowed)."""
    try:
        from app.utils.firestore import get_db

        get_db().collection(_COLLECTION).document(notification_id).update(
            {"read": True, "read_at": _now()}
        )
    except Exception as exc:
        logger.warning("mark_read failed (%s): %s", notification_id, exc)


def mark_all_read() -> None:
    """Mark every unread notification read, in batches. Never raises."""
    try:
        from google.cloud.firestore_v1.base_query import FieldFilter

        from app.utils.firestore import get_db

        db = get_db()
        col = db.collection(_COLLECTION)
        now = _now()
        while True:
            docs = list(
                col.where(filter=FieldFilter("read", "==", False))
                .limit(_BATCH)
                .stream()
            )
            if not docs:
                break
            batch = db.batch()
            for d in docs:
                batch.update(d.reference, {"read": True, "read_at": now})
            batch.commit()
            if len(docs) < _BATCH:
                break
    except Exception as exc:
        logger.warning("mark_all_read failed: %s", exc)


def _serialize(doc) -> dict:
    """Firestore snapshot → JSON-safe dict with id and ISO timestamps."""
    data = doc.to_dict() or {}
    for key in ("created_at", "read_at"):
        value = data.get(key)
        if hasattr(value, "isoformat"):
            data[key] = value.isoformat()
    data["id"] = doc.id
    return data


def _recent_types(within_hours: int = 24) -> set:
    """Set of notification `type`s created within the window — the dedup key
    for analytics alerts. On any failure returns an empty set, which biases
    toward creating (better a rare duplicate than a silently dropped alert)."""
    try:
        from google.cloud.firestore_v1.base_query import FieldFilter

        from app.utils.firestore import get_db

        cutoff = _now() - timedelta(hours=within_hours)
        docs = (
            get_db()
            .collection(_COLLECTION)
            .where(filter=FieldFilter("created_at", ">=", cutoff))
            .stream()
        )
        return {(d.to_dict() or {}).get("type") for d in docs}
    except Exception as exc:
        logger.debug("recent-type dedup lookup failed: %s", exc)
        return set()


# ── Analytics alerts ──────────────────────────────────────────────────────────


def check_analytics_alerts(report: dict) -> list:
    """Raise notifications from an already-built gap report.

    Takes the gap-report dict (which already aggregated the window's analytics),
    so this adds ZERO extra scans of chat_analytics — only the dedup lookup and
    the writes. Creates at most one of each alert type per 24h.

    Triggers:
    - refusal rate (refusal + near_miss over total) > 40%  → high_refusal_rate
    - satisfaction rate < 50% (with enough feedback)       → low_satisfaction
    - total interactions crosses a 100-count milestone     → analytics_milestone

    Inputs: report — the dict returned by gap_report_service._build_report.
    Outputs: list of created notification ids (may be empty). Never raises —
    it is called from the report build path and must not break the report.
    """
    created: list = []
    try:
        total = int(report.get("total_interactions", 0) or 0)
        if total < _ALERT_MIN_INTERACTIONS:
            return created

        days = _period_days(report.get("period"))
        recent = _recent_types()

        # High refusal rate.
        breakdown = report.get("response_breakdown", {}) or {}
        refusals = int(breakdown.get("refusal", 0)) + int(breakdown.get("near_miss", 0))
        refusal_rate = refusals / total if total else 0.0
        if refusal_rate > _HIGH_REFUSAL_RATE and "high_refusal_rate" not in recent:
            topics = _top_names(report)
            nid = create_notification(
                "high_refusal_rate",
                "High refusal rate detected",
                f"Refusal rate is {round(refusal_rate * 100)}% over the last "
                f"{days} days."
                + (f" Top refused topics: {topics}." if topics else "")
                + " Consider adding data or running prompt analysis.",
                severity="warning",
                action_url="/gap-report",
            )
            if nid:
                created.append(nid)

        # Low satisfaction.
        fb = report.get("feedback_summary", {}) or {}
        fb_total = int(fb.get("total_feedback", 0) or 0)
        satisfaction = fb.get("satisfaction_rate")
        if (
            fb_total >= _ALERT_MIN_FEEDBACK
            and isinstance(satisfaction, (int, float))
            and satisfaction < _LOW_SATISFACTION_RATE
            and "low_satisfaction" not in recent
        ):
            downvoted = _downvoted_preview(fb)
            nid = create_notification(
                "low_satisfaction",
                "Low satisfaction alert",
                f"Overall satisfaction is {round(satisfaction * 100)}%."
                + (f" Most downvoted: {downvoted}." if downvoted else "")
                + " Review prompt tuning or answer quality.",
                severity="error",
                action_url="/gap-report",
            )
            if nid:
                created.append(nid)

        # Milestone — a gentle "things are happening" signal, deduped so it
        # fires at most once per 24h regardless of how often the report builds.
        if total >= _MILESTONE_STEP and "analytics_milestone" not in recent:
            hundreds = (total // _MILESTONE_STEP) * _MILESTONE_STEP
            nid = create_notification(
                "analytics_milestone",
                f"{hundreds}+ interactions in the last {days} days",
                f"The chatbot has handled {total} interactions over the last "
                f"{days} days.",
                severity="info",
                action_url="/gap-report",
            )
            if nid:
                created.append(nid)
    except Exception as exc:
        logger.warning("analytics alert check failed: %s", exc)
    return created


def _period_days(period) -> int:
    """Parse gap_report's 'last_7_days' period string into 7. Falls back to 7."""
    try:
        if isinstance(period, str) and period.startswith("last_"):
            return int(period.split("_")[1])
    except (ValueError, IndexError):
        # Malformed period string ("last_", "weekly"). The 7-day default below
        # is the right answer for a label we can't parse — the alert text is
        # cosmetic and must never fail the report that triggered it.
        pass
    return 7


def _top_names(report: dict, limit: int = 3) -> str:
    """Comma-joined top uncovered topics for the refusal alert — prefers named
    missing crops, then missing districts, else falls back to refused questions.
    """
    crops = [c.get("crop") for c in report.get("missing_crops", []) if c.get("crop")]
    districts = [
        d.get("district")
        for d in report.get("missing_districts", [])
        if d.get("district")
    ]
    names = crops + districts
    if not names:
        names = [
            q.get("question", "")[:40]
            for q in report.get("top_refused_questions", [])
            if q.get("question")
        ]
    return ", ".join(names[:limit])


def _downvoted_preview(fb: dict, limit: int = 2) -> str:
    """First few most-downvoted questions, truncated, for the satisfaction alert."""
    questions = [
        (q.get("question") or "")[:50]
        for q in fb.get("most_downvoted_questions", [])
        if q.get("question")
    ]
    return "; ".join(questions[:limit])


# ── Email escalation (Phase B) ────────────────────────────────────────────────


def _maybe_email(type_: str, title: str, message: str, severity: str) -> None:
    """Escalate an email-worthy notification to admins, off the caller's thread.

    Cheap and synchronous up front: non-worthy types return immediately with no
    work. Worthy ones hand off to a daemon thread that applies the per-type
    hourly rate limit, gathers recipients, and delivers — so create_notification
    never blocks on SMTP or a Firestore recipient scan. Never raises.
    """
    if type_ not in _EMAIL_WORTHY_TYPES:
        return
    threading.Thread(
        target=_process_email,
        args=(type_, title, message, severity),
        daemon=True,
        name="notif-email",
    ).start()


def _process_email(type_: str, title: str, message: str, severity: str) -> None:
    """Background worker: decide (rate limit + batch), then deliver. Best-effort."""
    try:
        decision = _rate_limit_decision(type_)
        if decision is None:
            return  # within cooldown — counted for the next window, not sent now
        count = decision
        if count > 1:
            noun = _EMAIL_TYPE_PLURALS.get(type_, "notifications")
            subject = f"CropSphere: {count} {noun} in the last hour"
            email_title = f"{count} {noun} in the last hour"
            email_message = (
                f"{count} '{type_}' notifications fired in the last hour. "
                "The most recent: " + message
            )
        else:
            subject = f"CropSphere: {title}"
            email_title = title
            email_message = message

        recipients = _admin_recipients()
        if not recipients:
            return

        from app.admin.services.email_service import render_notification_email
        from app.admin.services.email_service import send_email_to
        from app.config import get_settings

        body = render_notification_email(
            email_title,
            email_message,
            severity,
            dashboard_url=get_settings().dashboard_url,
        )
        send_email_to(recipients, subject, body)
    except Exception as exc:
        logger.warning("email escalation failed (%s): %s", type_, exc)


def _rate_limit_decision(type_: str) -> int | None:
    """Enforce one email per type per hour, with batching.

    Returns the count to report when an email SHOULD go out now (1 for a fresh
    window, or N when N-1 events were suppressed during the previous window and
    this one re-opens it), or None when we're still inside the cooldown (the
    event is counted and no email is sent). In-memory and lock-guarded so two
    workers don't both send.
    """
    now = time.monotonic()
    with _email_lock:
        state = _email_state.get(type_)
        if state is None or (now - state["last_sent"]) >= _EMAIL_COOLDOWN_SECONDS:
            # Window elapsed (or first ever) — send now, folding in any events
            # that were suppressed while we were cooling down.
            pending = state["pending"] if state else 0
            _email_state[type_] = {"last_sent": now, "pending": 0}
            return pending + 1
        # Inside the cooldown — count it, stay silent.
        state["pending"] += 1
        return None


def _admin_recipients() -> list:
    """Email addresses of admins/superadmins who opted in, cached 5 minutes.

    Streams the users collection once per TTL and keeps those with role admin or
    superadmin, a non-empty email, and email_notifications not disabled (default
    on — Step 7). Never raises — returns [] on any Firestore failure, so a DB
    blip just means no email this round.
    """
    global _recipient_cache
    now = time.monotonic()
    with _recipient_lock:
        if _recipient_cache and _recipient_cache[0] > now:
            return list(_recipient_cache[1])

    recipients: list = []
    try:
        from app.utils.firestore import get_db

        for doc in get_db().collection("users").stream():
            data = doc.to_dict() or {}
            role = data.get("role")
            if role not in ("admin", "superadmin"):
                continue
            prefs = data.get("preferences")
            opted_in = _email_opt_in(prefs)
            # TEMP DIAGNOSTIC (remove after debugging the toggle): shows, per
            # admin, the exact doc id, role, the raw stored preference value,
            # and the resulting opt-in decision — so a field-name/value/cache
            # mismatch is visible in the container logs at send time.
            logger.info(
                "[EMAIL DEBUG] recipient scan uid=%s role=%s email=%s "
                "raw_pref=%r opted_in=%s",
                doc.id,
                role,
                data.get("email"),
                (prefs or {}).get("email_notifications", "<unset>"),
                opted_in,
            )
            if not opted_in:
                continue
            email = (data.get("email") or "").strip()
            if email:
                recipients.append(email)
        logger.info(
            "[EMAIL DEBUG] recipient list built: %d recipient(s) -> %s",
            len(recipients),
            recipients,
        )
    except Exception as exc:
        logger.warning("admin recipient lookup failed: %s", exc)
        return []

    with _recipient_lock:
        _recipient_cache = (now + _RECIPIENT_TTL_SECONDS, list(recipients))
    return recipients


def invalidate_recipient_cache() -> None:
    """Drop the cached recipient list so a preference change takes effect on the
    next email rather than waiting out the TTL (this worker only)."""
    global _recipient_cache
    with _recipient_lock:
        _recipient_cache = None


# ── Per-admin email preference (Step 7 / Step 9) ──────────────────────────────


def _email_opt_in(preferences: dict | None) -> bool:
    """Whether these preferences opt in to email alerts.

    Absent → opted in (default on, Step 7). Any falsy value → opted out. A
    non-canonical stored value is handled defensively: the string 'false'/'0'/
    'no'/'off' counts as opted out (a plain bool() would read the non-empty
    string 'false' as True and wrongly keep sending).
    """
    value = (preferences or {}).get("email_notifications", True)
    if isinstance(value, str):
        return value.strip().lower() not in ("false", "0", "no", "off", "")
    return bool(value)


def get_email_preference(uid: str) -> bool:
    """Whether this admin receives email alerts. Defaults to True when unset —
    admins are opted in by default. Never raises (returns True on read error,
    matching the default-on policy)."""
    try:
        from app.utils.firestore import get_user_preferences

        return _email_opt_in(get_user_preferences(uid))
    except Exception as exc:
        logger.warning("email preference read failed (%s): %s", uid, exc)
        return True


def set_email_preference(uid: str, enabled: bool) -> bool:
    """Merge email_notifications into the user's preferences and return the new
    value. Read-modify-write because update_user_preferences replaces the whole
    map. Invalidates the recipient cache so the change reflects promptly."""
    from app.utils.firestore import get_user_preferences, update_user_preferences

    prefs = get_user_preferences(uid)
    prefs["email_notifications"] = bool(enabled)
    update_user_preferences(uid, prefs)
    invalidate_recipient_cache()
    # TEMP DIAGNOSTIC (remove after debugging the toggle): confirms the write
    # target uid and the full preferences map actually persisted.
    logger.info(
        "[EMAIL DEBUG] set_email_preference uid=%s enabled=%s persisted_prefs=%r",
        uid,
        enabled,
        prefs,
    )
    return bool(enabled)
