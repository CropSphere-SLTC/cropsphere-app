"""Chatbot analytics logging — one document per chatbot interaction, written
to the `chat_analytics` Firestore collection for later analysis of
questioning patterns, refused topics, and usage.

Design rule (mirrors persist_chat_turn / audit_log): analytics must NEVER
break or slow a chat response. This writer swallows its own errors, and
callers invoke it from a fire-and-forget background thread so the Firestore
round-trip is off the response path.
"""

import logging

logger = logging.getLogger(__name__)

# Lives in the existing cropsphere-database, alongside chat_conversations /
# audit_logs (see app.utils.firestore.init_firestore).
_COLLECTION = "chat_analytics"
_QUESTION_MAX_LEN = 200


def log_chat_interaction(data: dict) -> None:
    """Log a chatbot interaction for analytics. Never raises — analytics
    must never break the chat experience.

    Inputs: data — the analytics record (field set assembled by
    chatbot_service._run_analytics). A Firestore server timestamp is added
    here when absent, and `question` is defensively truncated to 200 chars.
    Outputs: None. Any failure (Firestore down / not initialised / bad
    payload) is logged at WARNING and swallowed.
    Security assumption: user_id is already anonymised by the caller; no raw
    PII is expected in `data`.
    """
    try:
        from firebase_admin import firestore

        from app.utils.firestore import get_db

        record = dict(data)  # copy — never mutate the caller's dict
        record.setdefault("timestamp", firestore.SERVER_TIMESTAMP)
        question = record.get("question")
        if isinstance(question, str) and len(question) > _QUESTION_MAX_LEN:
            record["question"] = question[:_QUESTION_MAX_LEN]
        get_db().collection(_COLLECTION).add(record)
    except Exception as exc:
        logger.warning("chat_analytics log failed: %s", exc)
