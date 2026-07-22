"""Firestore client initialisation and DevSecOps audit logging."""

import hashlib
import hmac
import json
import logging
import os
from datetime import datetime, timedelta, timezone
from typing import Any, Dict

logger = logging.getLogger(__name__)

_db = None


def init_firestore(credentials_json: str, project_id: str) -> None:
    """Initialise Firestore audit logging using a service-account key.

    credentials_json may be:
    - A file-system path to a service-account JSON file (local dev)
    - A raw JSON string (Railway/CI environment variable)

    Raises ValueError for placeholder/missing credentials so the caller can
    disable Firestore gracefully without crashing JWT verification.
    """
    global _db
    import firebase_admin
    from firebase_admin import credentials, firestore

    if not credentials_json or credentials_json.strip().startswith("/path/to"):
        raise ValueError(
            "FIREBASE_CREDENTIALS_JSON is not configured"
            " — Firestore audit logging disabled"
        )

    # App may already be initialised by main.py for JWT verification; only
    # re-initialise with credentials if the existing app has no credential.
    if not firebase_admin._apps:
        if credentials_json.strip().startswith("{"):
            cred = credentials.Certificate(json.loads(credentials_json))
        else:
            cred = credentials.Certificate(credentials_json)
        firebase_admin.initialize_app(cred, {"projectId": project_id})
    elif (
        firebase_admin.get_app().credential.__class__.__name__
        == "ApplicationDefaultCredentials"
    ):

        # App was initialised without a service account — re-init with credentials
        firebase_admin.delete_app(firebase_admin.get_app())
        if credentials_json.strip().startswith("{"):
            cred = credentials.Certificate(json.loads(credentials_json))
        else:
            cred = credentials.Certificate(credentials_json)
        firebase_admin.initialize_app(cred, {"projectId": project_id})

    _db = firestore.client(database_id="cropsphere-database")
    logger.info("Firestore initialised for project: %s", project_id)


def get_db():
    """Return the Firestore client. Raises if init_firestore was not called."""
    if _db is None:
        raise RuntimeError("Firestore not initialised. Call init_firestore() first.")
    return _db


def get_or_create_user(
    uid: str, email: str = "", photo_url: str = ""
) -> Dict[str, Any]:
    """Get user document from Firestore or create it if it doesn't exist.
    New users get role 'user' by default.
    Superadmin UID gets role 'superadmin' automatically.
    """
    try:
        from app.config import get_settings

        db = get_db()
        ref = db.collection("users").document(uid)
        doc = ref.get()
        if doc.exists:
            data = doc.to_dict()
            # Update photo_url only when it actually changed (Google OAuth
            # photo can change) — this is called on every authenticated
            # request, and the decoded token always carries a photo_url for
            # Google sign-in, so an unconditional write here hammers this
            # single document with a write on every request and is a real
            # source of Firestore write-contention 429s under load.
            if photo_url and data.get("photo_url") != photo_url:
                ref.update({"photo_url": photo_url})
                data["photo_url"] = photo_url
            return data
        # Determine role — superadmin UID always gets superadmin role
        settings = get_settings()
        superadmin_uids = [u.strip() for u in settings.SUPERADMIN_UID.split(",")]
        role = "superadmin" if uid in superadmin_uids else "user"
        user_data = {
            "uid": uid,
            "email": email,
            "photo_url": photo_url,
            "role": role,
            "is_banned": False,
            "created_at": datetime.now(timezone.utc),
        }
        ref.set(user_data)
        logger.info(f"Created user document: uid={uid} role={role}")
        return user_data
    except Exception as exc:
        logger.error(f"get_or_create_user failed: {exc}")
        return {"uid": uid, "role": "user", "is_banned": False}


def get_user_role(uid: str) -> str:
    """Get user role from Firestore. Returns 'user' as safe fallback."""
    try:
        from app.config import get_settings

        settings = get_settings()
        # Superadmin UID always returns superadmin regardless of Firestore
        superadmin_uids = [u.strip() for u in settings.SUPERADMIN_UID.split(",")]
        if uid in superadmin_uids:
            return "superadmin"
        db = get_db()
        doc = db.collection("users").document(uid).get()
        if doc.exists:
            data = doc.to_dict()
            if data.get("is_banned"):
                return "banned"
            return data.get("role", "user")
        return "user"
    except Exception as exc:
        logger.error(f"get_user_role failed: {exc}")
        return "user"


def is_user_banned(uid: str) -> bool:
    """Check if user is banned."""
    try:
        db = get_db()
        doc = db.collection("users").document(uid).get()
        if doc.exists:
            return doc.to_dict().get("is_banned", False)
        return False
    except Exception as exc:
        logger.error(f"is_user_banned failed: {exc}")
        return False


# ── User profile & sessions ────────────────────────────────────────────────────


def get_user_profile(uid: str) -> Dict[str, Any]:
    """Return the raw user document — profile fields plus preferences.

    Raises RuntimeError if the document doesn't exist (shouldn't happen for
    an authenticated caller — get_or_create_user runs on every login).
    """
    db = get_db()
    doc = db.collection("users").document(uid).get()
    if not doc.exists:
        raise RuntimeError(f"User document not found for uid={uid}")
    return doc.to_dict()


def update_user_profile(uid: str, display_name: str) -> None:
    """Update display_name on a user's Firestore document."""
    db = get_db()
    db.collection("users").document(uid).update({"display_name": display_name})


def get_user_preferences(uid: str) -> Dict[str, Any]:
    """Return the preferences dict from a user's Firestore document.

    Returns {} if the user has never saved preferences — callers apply
    their own defaults.
    """
    db = get_db()
    doc = db.collection("users").document(uid).get()
    if not doc.exists:
        return {}
    return doc.to_dict().get("preferences", {})


def update_user_preferences(uid: str, preferences: Dict[str, Any]) -> None:
    """Save preferences to a user's Firestore document."""
    db = get_db()
    db.collection("users").document(uid).update({"preferences": preferences})


def update_user_context(
    uid: str, preferred_crop: str = None, preferred_district: str = None
) -> None:
    """Merge saved chat context into the user's preferences WITHOUT touching
    siblings (language/notifications).

    Uses dotted field paths so only the given keys change, creating the nested
    preferences map if absent. A context_updated_at server timestamp is set
    whenever anything is written. No-op if neither crop nor district is given.
    Security assumption: uid is JWT-verified; caller runs this fire-and-forget.
    """
    from firebase_admin import firestore

    payload: Dict[str, Any] = {}
    if preferred_crop:
        payload["preferences.preferred_crop"] = preferred_crop
    if preferred_district:
        payload["preferences.preferred_district"] = preferred_district
    if not payload:
        return
    payload["preferences.context_updated_at"] = firestore.SERVER_TIMESTAMP
    get_db().collection("users").document(uid).update(payload)


def update_last_login(uid: str) -> None:
    """Update last_login timestamp on a user's Firestore document.

    Called from the auth middleware on every verified request — failures
    are logged but never allowed to block authentication.
    """
    try:
        db = get_db()
        db.collection("users").document(uid).update(
            {"last_login": datetime.now(timezone.utc)}
        )
    except Exception as exc:
        logger.error(f"update_last_login failed: {exc}")


def get_active_sessions(uid: str) -> int:
    """Count sessions for uid with last_active within the past 24 hours.

    Note: this equality + range query needs a composite Firestore index on
    (uid ASC, last_active ASC) — Firestore's error message links directly
    to the console page to create it if missing.
    """
    try:
        from google.cloud.firestore_v1.base_query import FieldFilter

        db = get_db()
        cutoff = datetime.now(timezone.utc) - timedelta(hours=24)
        docs = (
            db.collection("sessions")
            .where(filter=FieldFilter("uid", "==", uid))
            .where(filter=FieldFilter("last_active", ">=", cutoff))
            .stream()
        )
        return sum(1 for _ in docs)
    except Exception as exc:
        logger.error(f"get_active_sessions failed: {exc}")
        return 0


def create_session(uid: str, device_info: str) -> None:
    """Record a session document — called from the auth middleware on every
    verified request. Failures are logged but never allowed to block
    authentication.
    """
    try:
        db = get_db()
        now = datetime.now(timezone.utc)
        db.collection("sessions").add(
            {
                "uid": uid,
                "device_info": device_info,
                "created_at": now,
                "last_active": now,
            }
        )
    except Exception as exc:
        logger.error(f"create_session failed: {exc}")


# ── Chat conversation history ─────────────────────────────────────────────────

MAX_MESSAGES_PER_CONVERSATION = 50


def list_conversations(uid: str, limit: int = 50) -> list:
    """List a user's chat conversations, newest first.

    Returns summaries only (id, title, updated_at, message_count) — never the
    embedded messages array. Needs a composite index on (uid ASC,
    updated_at DESC); Firestore's error links to the console page if missing.
    """
    from google.cloud.firestore_v1.base_query import FieldFilter
    from google.cloud import firestore as gcf

    db = get_db()
    docs = (
        db.collection("chat_conversations")
        .where(filter=FieldFilter("uid", "==", uid))
        .order_by("updated_at", direction=gcf.Query.DESCENDING)
        .limit(limit)
        .stream()
    )
    out = []
    for doc in docs:
        data = doc.to_dict()
        out.append(
            {
                "id": doc.id,
                "title": data.get("title", ""),
                "updated_at": data.get("updated_at"),
                "message_count": data.get("message_count", 0),
            }
        )
    return out


def get_conversation(conversation_id: str):
    """Return the full conversation dict (including messages) or None.

    Caller is responsible for checking ownership (uid field) before
    returning data to a client.
    """
    db = get_db()
    doc = db.collection("chat_conversations").document(conversation_id).get()
    if not doc.exists:
        return None
    data = doc.to_dict()
    data["id"] = doc.id
    return data


def create_conversation(uid: str, title: str) -> str:
    """Create an empty conversation document and return its id."""
    db = get_db()
    now = datetime.now(timezone.utc)
    _, ref = db.collection("chat_conversations").add(
        {
            "uid": uid,
            "title": title,
            "created_at": now,
            "updated_at": now,
            "message_count": 0,
            "messages": [],
        }
    )
    return ref.id


def append_messages(conversation_id: str, user_msg: str, assistant_msg: str) -> None:
    """Append a user/assistant message pair to a conversation.

    Raises ValueError if the conversation would exceed
    MAX_MESSAGES_PER_CONVERSATION messages, or if it doesn't exist.
    """
    db = get_db()
    ref = db.collection("chat_conversations").document(conversation_id)
    doc = ref.get()
    if not doc.exists:
        raise ValueError(f"Conversation not found: {conversation_id}")
    data = doc.to_dict()
    messages = data.get("messages", [])
    if len(messages) + 2 > MAX_MESSAGES_PER_CONVERSATION:
        raise ValueError("Conversation message limit reached")
    now = datetime.now(timezone.utc)
    messages.append({"role": "user", "content": user_msg, "timestamp": now})
    messages.append({"role": "assistant", "content": assistant_msg, "timestamp": now})
    ref.update(
        {
            "messages": messages,
            "message_count": len(messages),
            "updated_at": now,
        }
    )


def rename_conversation(conversation_id: str, title: str) -> None:
    """Rename a conversation. Ownership must be checked by the caller."""
    db = get_db()
    db.collection("chat_conversations").document(conversation_id).update(
        {"title": title, "updated_at": datetime.now(timezone.utc)}
    )


def delete_conversation(conversation_id: str) -> None:
    """Delete a conversation. Ownership must be checked by the caller."""
    db = get_db()
    db.collection("chat_conversations").document(conversation_id).delete()


def admin_audit_log(
    actor_uid: str,
    actor_role: str,
    action: str,
    target_uid: str = "",
    details: Dict[str, Any] = {},
) -> None:
    """Write admin action to Firestore audit log with actor_role field.
    Superadmin activities are only visible to superadmin.
    Admin activities are visible to both admin and superadmin.
    """
    try:
        db = get_db()
        db.collection("admin_audit_logs").add(
            {
                "actor_uid": actor_uid,
                "actor_role": actor_role,
                "action": action,
                "target_uid": target_uid,
                "details": details,
                "timestamp": datetime.now(timezone.utc),
            }
        )
    except Exception as exc:
        logger.error(f"admin_audit_log failed: {exc}")


def audit_log(user_id: str, endpoint: str, input_data: Dict[str, Any]) -> None:
    """Write a prediction audit record to Firestore.

    Stores an SHA-256 hash of the input rather than raw data to avoid
    storing PII or sensitive farm data in plaintext (DevSecOps requirement).
    Failures are logged but never allowed to crash the prediction endpoint.
    """
    try:
        db = get_db()
        input_hash = hashlib.sha256(
            json.dumps(input_data, sort_keys=True, default=str).encode()
        ).hexdigest()
        hmac_key = os.environ.get("AUDIT_HMAC_KEY", "")
        hmac_sig = hmac.new(
            hmac_key.encode(),
            input_hash.encode(),
            hashlib.sha256,
        ).hexdigest()
        db.collection("audit_logs").add(
            {
                "user_id": user_id,
                "endpoint": endpoint,
                "input_hash": input_hash,
                "hmac_sha256": hmac_sig,
                "timestamp": datetime.now(timezone.utc),
            }
        )
    except Exception as exc:
        logger.error(
            "Audit log write failed — user=%s endpoint=%s: %s",
            user_id,
            endpoint,
            exc,
        )


# ── Security events (monitoring) ──────────────────────────────────────────────

# The three event types persisted to the security_events collection. Kept as a
# tuple so callers (services, tests) can validate/iterate without hard-coding
# the strings in multiple places.
SECURITY_EVENT_TYPES = (
    "failed_login",
    "rate_limit_violation",
    "banned_access_attempt",
)


def write_security_event(
    event_type: str,
    uid: str = "",
    email: str = "",
    ip_address: str = "",
    endpoint: str = "",
    details: Dict[str, Any] = None,
) -> None:
    """Persist a security-monitoring event to the security_events collection.

    Called from the request path (auth failures, 429s, banned access) so it is
    strictly best-effort: any failure — including Firestore being unreachable
    or uninitialised — is logged and swallowed, never propagated to the caller.
    Empty string fields are normalised to None so the stored document is clean.
    """
    try:
        db = get_db()
        db.collection("security_events").add(
            {
                "type": event_type,
                "uid": uid or None,
                "email": email or None,
                "ip_address": ip_address or None,
                "endpoint": endpoint or None,
                "details": details or {},
                "timestamp": datetime.now(timezone.utc),
            }
        )
    except Exception as exc:
        logger.error("write_security_event failed (type=%s): %s", event_type, exc)


def query_recent_security_events(limit: int = 200) -> list:
    """Return the most recent security_events, newest first.

    Ordered by the single `timestamp` field only — Firestore auto-creates that
    single-field index, so callers that need per-type slices filter in Python.
    This deliberately avoids a composite (type + timestamp) index so the feature
    works with zero manual Firestore console setup, which is acceptable at this
    project's event volume. timestamp is returned as an ISO-8601 string.
    """
    from google.cloud import firestore as gcf

    db = get_db()
    docs = (
        db.collection("security_events")
        .order_by("timestamp", direction=gcf.Query.DESCENDING)
        .limit(limit)
        .stream()
    )
    out = []
    for doc in docs:
        data = doc.to_dict()
        data["id"] = doc.id
        ts = data.get("timestamp")
        if hasattr(ts, "isoformat"):
            data["timestamp"] = ts.isoformat()
        out.append(data)
    return out


def get_security_events_since(cutoff: datetime) -> list:
    """Return all security_events with timestamp >= cutoff (as raw dicts).

    A single-field range filter, so it needs no composite index. Used for the
    24h summary counts, where exact totals matter more than ordering.
    """
    from google.cloud.firestore_v1.base_query import FieldFilter

    db = get_db()
    docs = (
        db.collection("security_events")
        .where(filter=FieldFilter("timestamp", ">=", cutoff))
        .stream()
    )
    return [doc.to_dict() for doc in docs]


# ── Active sessions (security view) ───────────────────────────────────────────


def count_active_sessions(hours: int = 24) -> int:
    """Count session documents whose last_active falls within the past `hours`.

    Single-field range filter — no composite index required.
    """
    from google.cloud.firestore_v1.base_query import FieldFilter

    db = get_db()
    cutoff = datetime.now(timezone.utc) - timedelta(hours=hours)
    docs = (
        db.collection("sessions")
        .where(filter=FieldFilter("last_active", ">=", cutoff))
        .stream()
    )
    return sum(1 for _ in docs)


def list_active_sessions(hours: int = 24, limit: int = 100) -> list:
    """Return active sessions (last_active within `hours`), newest first.

    Each row is enriched with the user's email/role from the users collection.
    Ordering on the same field as the range filter keeps this on a single-field
    index. The users lookup is a one-off collection read (fine at this project's
    scale); timestamps are returned as ISO-8601 strings.
    """
    from google.cloud import firestore as gcf
    from google.cloud.firestore_v1.base_query import FieldFilter

    db = get_db()
    cutoff = datetime.now(timezone.utc) - timedelta(hours=hours)
    docs = (
        db.collection("sessions")
        .where(filter=FieldFilter("last_active", ">=", cutoff))
        .order_by("last_active", direction=gcf.Query.DESCENDING)
        .limit(limit)
        .stream()
    )

    sessions = []
    for doc in docs:
        d = doc.to_dict()
        start = d.get("created_at")
        last = d.get("last_active")
        sessions.append(
            {
                "uid": d.get("uid", ""),
                "email": "",
                "role": "",
                "device_info": d.get("device_info", ""),
                "session_start": (
                    start.isoformat() if hasattr(start, "isoformat") else None
                ),
                "last_activity": (
                    last.isoformat() if hasattr(last, "isoformat") else None
                ),
            }
        )

    # Enrich with email/role in a single pass over the users collection.
    if sessions:
        uids = {s["uid"] for s in sessions if s["uid"]}
        user_map = {}
        for user_doc in db.collection("users").stream():
            data = user_doc.to_dict()
            if data.get("uid") in uids:
                user_map[data["uid"]] = data
        for s in sessions:
            u = user_map.get(s["uid"])
            if u:
                s["email"] = u.get("email", "")
                s["role"] = u.get("role", "user")

    return sessions
