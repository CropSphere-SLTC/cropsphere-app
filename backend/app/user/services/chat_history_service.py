"""Chat conversation history service — reads/writes chat_conversations.

Ownership rule (shift-left): any conversation that doesn't exist OR belongs
to another uid is reported as "not found" — a 404, never a 403 — so
conversation ids can't be enumerated by probing.
"""

import logging
from typing import Optional

from app.models.schemas import (
    ConversationDetail,
    ConversationMessage,
    ConversationSummary,
    RenameConversationRequest,
)
from app.utils.firestore import (
    MAX_MESSAGES_PER_CONVERSATION,
    append_messages,
    create_conversation,
    delete_conversation,
    get_conversation,
    list_conversations,
    rename_conversation,
)

logger = logging.getLogger(__name__)

MAX_CONVERSATIONS_PER_USER = 50
_TITLE_LEN = 40


class ConversationNotFound(Exception):
    """Raised when a conversation doesn't exist or isn't owned by the caller."""


def _iso(value) -> Optional[str]:
    """Firestore timestamps → ISO strings for JSON responses."""
    return value.isoformat() if value is not None else None


def _get_owned(conversation_id: str, uid: str) -> dict:
    """Return the conversation dict, enforcing the 404-on-foreign-uid rule."""
    data = get_conversation(conversation_id)
    if data is None or data.get("uid") != uid:
        raise ConversationNotFound()
    return data


def list_user_conversations(uid: str) -> list[ConversationSummary]:
    """List the caller's conversations, newest first, summaries only."""
    try:
        rows = list_conversations(uid, limit=MAX_CONVERSATIONS_PER_USER)
        return [
            ConversationSummary(
                id=r["id"],
                title=r["title"],
                updated_at=_iso(r["updated_at"]),
                message_count=r["message_count"],
            )
            for r in rows
        ]
    except Exception as exc:
        logger.error(f"list_user_conversations failed uid={uid}: {exc}")
        raise RuntimeError("Failed to list conversations") from exc


def get_user_conversation(uid: str, conversation_id: str) -> ConversationDetail:
    """Return the full conversation with messages. 404 if not owned."""
    try:
        data = _get_owned(conversation_id, uid)
        return ConversationDetail(
            id=data["id"],
            title=data.get("title", ""),
            created_at=_iso(data.get("created_at")),
            updated_at=_iso(data.get("updated_at")),
            message_count=data.get("message_count", 0),
            messages=[
                ConversationMessage(
                    role=m.get("role", "user"),
                    content=m.get("content", ""),
                    timestamp=_iso(m.get("timestamp")),
                )
                for m in data.get("messages", [])
            ],
        )
    except ConversationNotFound:
        raise
    except Exception as exc:
        logger.error(f"get_user_conversation failed uid={uid}: {exc}")
        raise RuntimeError("Failed to load conversation") from exc


def rename_user_conversation(
    uid: str, conversation_id: str, body: RenameConversationRequest
) -> dict:
    """Rename an owned conversation. 404 if not owned."""
    try:
        _get_owned(conversation_id, uid)
        rename_conversation(conversation_id, body.title)
        return {"message": "Conversation renamed", "title": body.title}
    except ConversationNotFound:
        raise
    except Exception as exc:
        logger.error(f"rename_user_conversation failed uid={uid}: {exc}")
        raise RuntimeError("Failed to rename conversation") from exc


def delete_user_conversation(uid: str, conversation_id: str) -> dict:
    """Delete an owned conversation. 404 if not owned."""
    try:
        _get_owned(conversation_id, uid)
        delete_conversation(conversation_id)
        return {"message": "Conversation deleted"}
    except ConversationNotFound:
        raise
    except Exception as exc:
        logger.error(f"delete_user_conversation failed uid={uid}: {exc}")
        raise RuntimeError("Failed to delete conversation") from exc


def persist_chat_turn(
    uid: str, conversation_id: Optional[str], user_msg: str, assistant_msg: str
) -> str:
    """Append a chat turn to a conversation, creating one when needed.

    Returns the conversation id the turn was written to, or "" on any
    failure — persistence must never break the chat response, so the
    caller wraps this in try/except and treats "" as "not saved".
    """
    if conversation_id:
        data = get_conversation(conversation_id)
        if data is None or data.get("uid") != uid:
            # Foreign or stale id — silently start a fresh conversation
            # rather than leaking existence or failing the chat.
            conversation_id = None
        elif data.get("message_count", 0) + 2 > MAX_MESSAGES_PER_CONVERSATION:
            logger.warning("Conversation %s full — turn not persisted", conversation_id)
            return conversation_id

    if not conversation_id:
        _enforce_conversation_cap(uid)
        conversation_id = create_conversation(uid, user_msg[:_TITLE_LEN])

    append_messages(conversation_id, user_msg, assistant_msg)
    return conversation_id


def _enforce_conversation_cap(uid: str) -> None:
    """Delete the user's oldest conversation once they hit the cap."""
    rows = list_conversations(uid, limit=MAX_CONVERSATIONS_PER_USER)
    if len(rows) >= MAX_CONVERSATIONS_PER_USER:
        oldest = rows[-1]  # rows are sorted updated_at descending
        delete_conversation(oldest["id"])
        logger.info(
            "Conversation cap reached uid=%s — deleted oldest %s", uid, oldest["id"]
        )
