from typing import Dict, Any
from datetime import datetime, timezone
from app.dependencies import get_db
from app.utils.logger import logger


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
