"""Chat feedback logging — one document per thumbs up/down to chat_feedback.

Best-effort like analytics: never blocks or slows the chat experience. Called
from POST /api/chat/feedback; the Flutter client fires it and ignores the
result.
"""

import hashlib
import logging
from datetime import datetime, timezone

logger = logging.getLogger(__name__)

_COLLECTION = "chat_feedback"
_TEXT_MAX = 500


def _anonymize_uid(user_id: str) -> str:
    """One-way hash so feedback can be counted without storing the raw uid
    (privacy / DevSecOps, consistent with analytics_service)."""
    return hashlib.sha256((user_id or "").encode()).hexdigest()[:16]


def _doc_id(user_id: str, conversation_id: str, message_index: int) -> str:
    """Deterministic id for one (user, conversation, message) vote so a repeat
    or changed vote overwrites the same document — no duplicate rows in the
    gap report, and a clean one-vote-per-message read-back on reload."""
    raw = f"{_anonymize_uid(user_id)}|{conversation_id}|{message_index}"
    return hashlib.sha256(raw.encode()).hexdigest()


def log_feedback(
    user_id: str,
    conversation_id: str,
    message_index: int,
    feedback: str,
    message_text: str,
) -> None:
    """Persist one feedback vote to chat_feedback. Never raises.

    Inputs: JWT-verified user_id (stored anonymised), conversation id, message
    index, feedback ("up"/"down" — constrained by the Pydantic schema), and
    the rated question text (truncated).
    Outputs: None. Firestore failures are logged and swallowed so feedback
    never affects the chat experience.
    Security assumption: feedback value validated by the schema; user_id comes
    from the auth dependency.
    """
    try:
        from app.utils.firestore import get_db

        # Upsert by deterministic id (not add()) so re-voting overwrites.
        get_db().collection(_COLLECTION).document(
            _doc_id(user_id, conversation_id, message_index)
        ).set(
            {
                "user_id": _anonymize_uid(user_id),
                "conversation_id": (conversation_id or "")[:128],
                "message_index": message_index,
                "feedback": feedback,
                "message_text": (message_text or "")[:_TEXT_MAX],
                "timestamp": datetime.now(timezone.utc),
            }
        )
    except Exception as exc:
        logger.warning("chat_feedback log failed: %s", exc)


def get_conversation_feedback(user_id: str, conversation_id: str) -> dict:
    """Return the caller's votes for a conversation as {message_index: feedback}.

    Lets the client restore thumbs state after a page reload. Queries
    chat_feedback by conversation_id (single-field equality — no composite
    index) and keeps only rows matching the caller's anonymised uid.
    Best-effort: returns {} on any failure; never raises.
    """
    try:
        from google.cloud.firestore_v1.base_query import FieldFilter

        from app.utils.firestore import get_db

        anon = _anonymize_uid(user_id)
        docs = (
            get_db()
            .collection(_COLLECTION)
            .where(filter=FieldFilter("conversation_id", "==", conversation_id))
            .stream()
        )
        votes: dict = {}
        for d in docs:
            data = d.to_dict()
            if data.get("user_id") == anon and data.get("message_index") is not None:
                votes[data["message_index"]] = data.get("feedback")
        return votes
    except Exception as exc:
        logger.warning("get_conversation_feedback failed: %s", exc)
        return {}
