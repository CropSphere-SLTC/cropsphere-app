"""Firestore client initialisation and DevSecOps audit logging."""

import hashlib
import hmac
import json
import logging
import os
from datetime import datetime, timezone
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

    _db = firestore.client()
    logger.info("Firestore initialised for project: %s", project_id)


def get_db():
    """Return the Firestore client. Raises if init_firestore was not called."""
    if _db is None:
        raise RuntimeError("Firestore not initialised. Call init_firestore() first.")
    return _db


def get_or_create_user(uid: str, email: str = "") -> Dict[str, Any]:
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
            return doc.to_dict()
        # Determine role — superadmin UID always gets superadmin role
        settings = get_settings()
        role = "superadmin" if uid == settings.SUPERADMIN_UID else "user"
        user_data = {
            "uid": uid,
            "email": email,
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
        if uid == settings.SUPERADMIN_UID:
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
        db.collection("admin_audit_logs").add({
            "actor_uid": actor_uid,
            "actor_role": actor_role,
            "action": action,
            "target_uid": target_uid,
            "details": details,
            "timestamp": datetime.now(timezone.utc),
        })
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
