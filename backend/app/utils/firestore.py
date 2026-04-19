"""Firestore client initialisation and DevSecOps audit logging."""
import hashlib
import json
import logging
from datetime import datetime, timezone
from typing import Any, Dict

logger = logging.getLogger(__name__)

_db = None


def init_firestore(credentials_json: str, project_id: str) -> None:
    """Initialise Firestore once on app startup.

    credentials_json may be:
    - A file-system path to a service-account JSON file (local dev)
    - A raw JSON string (Railway/CI environment variable)
    """
    global _db
    import firebase_admin
    from firebase_admin import credentials, firestore

    if not firebase_admin._apps:
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
        db.collection("audit_logs").add({
            "user_id": user_id,
            "endpoint": endpoint,
            "input_hash": input_hash,
            "timestamp": datetime.now(timezone.utc),
        })
    except Exception as exc:
        logger.error(
            "Audit log write failed — user=%s endpoint=%s: %s",
            user_id, endpoint, exc,
        )
