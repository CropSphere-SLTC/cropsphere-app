"""Unit tests for app.user.services.chat_history_service.

Calls the service functions directly (no HTTP layer). Firestore helpers in
app.utils.firestore are mocked so no real infrastructure is required.
"""

from datetime import datetime, timezone
from unittest.mock import patch

import pytest

from app.models.schemas import RenameConversationRequest
from app.user.services import chat_history_service as svc

UID = "test-user-123"
CONV_ID = "conv-abc"


# ═══════════════════════════════════════════════════════════════════════════
# list_user_conversations
# ═══════════════════════════════════════════════════════════════════════════


def test_list_user_conversations_returns_summaries():
    ts = datetime(2026, 1, 15, 10, 30, tzinfo=timezone.utc)
    rows = [
        {"id": "c1", "title": "Rice yield", "updated_at": ts, "message_count": 4},
        {"id": "c2", "title": "Weather", "updated_at": None, "message_count": 0},
    ]

    with patch(
        "app.user.services.chat_history_service.list_conversations",
        return_value=rows,
    ) as mock_list:
        result = svc.list_user_conversations(UID)

    mock_list.assert_called_once_with(UID, limit=svc.MAX_CONVERSATIONS_PER_USER)
    assert len(result) == 2
    assert result[0].id == "c1"
    assert result[0].updated_at == ts.isoformat()
    assert result[1].updated_at is None


def test_list_user_conversations_firestore_failure_raises_runtime_error():
    with patch(
        "app.user.services.chat_history_service.list_conversations",
        side_effect=RuntimeError("down"),
    ):
        with pytest.raises(RuntimeError):
            svc.list_user_conversations(UID)


# ═══════════════════════════════════════════════════════════════════════════
# get_user_conversation
# ═══════════════════════════════════════════════════════════════════════════


def test_get_user_conversation_returns_full_detail():
    ts = datetime(2026, 1, 15, 10, 30, tzinfo=timezone.utc)
    data = {
        "id": CONV_ID,
        "uid": UID,
        "title": "Rice yield",
        "created_at": ts,
        "updated_at": ts,
        "message_count": 2,
        "messages": [
            {"role": "user", "content": "Hi", "timestamp": ts},
            {"role": "assistant", "content": "Hello!", "timestamp": ts},
        ],
    }

    with patch(
        "app.user.services.chat_history_service.get_conversation",
        return_value=data,
    ):
        result = svc.get_user_conversation(UID, CONV_ID)

    assert result.id == CONV_ID
    assert result.title == "Rice yield"
    assert len(result.messages) == 2
    assert result.messages[0].role == "user"
    assert result.messages[0].content == "Hi"


def test_get_user_conversation_not_found_when_missing():
    with patch(
        "app.user.services.chat_history_service.get_conversation",
        return_value=None,
    ):
        with pytest.raises(svc.ConversationNotFound):
            svc.get_user_conversation(UID, CONV_ID)


def test_get_user_conversation_not_found_when_owned_by_other_user():
    data = {"id": CONV_ID, "uid": "someone-else"}
    with patch(
        "app.user.services.chat_history_service.get_conversation",
        return_value=data,
    ):
        with pytest.raises(svc.ConversationNotFound):
            svc.get_user_conversation(UID, CONV_ID)


def test_get_user_conversation_firestore_failure_raises_runtime_error():
    with patch(
        "app.user.services.chat_history_service.get_conversation",
        side_effect=RuntimeError("down"),
    ):
        with pytest.raises(RuntimeError):
            svc.get_user_conversation(UID, CONV_ID)


def test_get_user_conversation_defaults_missing_message_fields():
    data = {
        "id": CONV_ID,
        "uid": UID,
        "messages": [{}],  # no role/content/timestamp
    }
    with patch(
        "app.user.services.chat_history_service.get_conversation",
        return_value=data,
    ):
        result = svc.get_user_conversation(UID, CONV_ID)

    assert result.messages[0].role == "user"
    assert result.messages[0].content == ""
    assert result.messages[0].timestamp is None


# ═══════════════════════════════════════════════════════════════════════════
# rename_user_conversation
# ═══════════════════════════════════════════════════════════════════════════


def test_rename_user_conversation_success():
    data = {"id": CONV_ID, "uid": UID}
    body = RenameConversationRequest(title="New title")

    with patch(
        "app.user.services.chat_history_service.get_conversation",
        return_value=data,
    ), patch(
        "app.user.services.chat_history_service.rename_conversation"
    ) as mock_rename:
        result = svc.rename_user_conversation(UID, CONV_ID, body)

    mock_rename.assert_called_once_with(CONV_ID, "New title")
    assert result["message"] == "Conversation renamed"
    assert result["title"] == "New title"


def test_rename_user_conversation_not_found_when_not_owned():
    data = {"id": CONV_ID, "uid": "someone-else"}
    body = RenameConversationRequest(title="New title")

    with patch(
        "app.user.services.chat_history_service.get_conversation",
        return_value=data,
    ):
        with pytest.raises(svc.ConversationNotFound):
            svc.rename_user_conversation(UID, CONV_ID, body)


def test_rename_user_conversation_firestore_failure_raises_runtime_error():
    data = {"id": CONV_ID, "uid": UID}
    body = RenameConversationRequest(title="New title")

    with patch(
        "app.user.services.chat_history_service.get_conversation",
        return_value=data,
    ), patch(
        "app.user.services.chat_history_service.rename_conversation",
        side_effect=RuntimeError("down"),
    ):
        with pytest.raises(RuntimeError):
            svc.rename_user_conversation(UID, CONV_ID, body)


# ═══════════════════════════════════════════════════════════════════════════
# delete_user_conversation
# ═══════════════════════════════════════════════════════════════════════════


def test_delete_user_conversation_success():
    data = {"id": CONV_ID, "uid": UID}

    with patch(
        "app.user.services.chat_history_service.get_conversation",
        return_value=data,
    ), patch(
        "app.user.services.chat_history_service.delete_conversation"
    ) as mock_delete:
        result = svc.delete_user_conversation(UID, CONV_ID)

    mock_delete.assert_called_once_with(CONV_ID)
    assert result["message"] == "Conversation deleted"


def test_delete_user_conversation_not_found_when_not_owned():
    data = {"id": CONV_ID, "uid": "someone-else"}

    with patch(
        "app.user.services.chat_history_service.get_conversation",
        return_value=data,
    ):
        with pytest.raises(svc.ConversationNotFound):
            svc.delete_user_conversation(UID, CONV_ID)


def test_delete_user_conversation_firestore_failure_raises_runtime_error():
    data = {"id": CONV_ID, "uid": UID}

    with patch(
        "app.user.services.chat_history_service.get_conversation",
        return_value=data,
    ), patch(
        "app.user.services.chat_history_service.delete_conversation",
        side_effect=RuntimeError("down"),
    ):
        with pytest.raises(RuntimeError):
            svc.delete_user_conversation(UID, CONV_ID)


# ═══════════════════════════════════════════════════════════════════════════
# persist_chat_turn
# ═══════════════════════════════════════════════════════════════════════════


def test_persist_chat_turn_creates_new_conversation_when_none_given():
    with patch(
        "app.user.services.chat_history_service.list_conversations",
        return_value=[],
    ), patch(
        "app.user.services.chat_history_service.create_conversation",
        return_value="new-conv-id",
    ) as mock_create, patch(
        "app.user.services.chat_history_service.append_messages"
    ) as mock_append:
        result = svc.persist_chat_turn(UID, None, "Hi there", "Hello!")

    mock_create.assert_called_once_with(UID, "Hi there")
    mock_append.assert_called_once_with("new-conv-id", "Hi there", "Hello!")
    assert result == "new-conv-id"


def test_persist_chat_turn_appends_to_existing_owned_conversation():
    data = {"id": CONV_ID, "uid": UID, "message_count": 2}

    with patch(
        "app.user.services.chat_history_service.get_conversation",
        return_value=data,
    ), patch("app.user.services.chat_history_service.append_messages") as mock_append:
        result = svc.persist_chat_turn(UID, CONV_ID, "Hi", "Hello!")

    mock_append.assert_called_once_with(CONV_ID, "Hi", "Hello!")
    assert result == CONV_ID


def test_persist_chat_turn_starts_fresh_when_conversation_id_foreign():
    data = {"id": CONV_ID, "uid": "someone-else", "message_count": 2}

    with patch(
        "app.user.services.chat_history_service.get_conversation",
        return_value=data,
    ), patch(
        "app.user.services.chat_history_service.list_conversations",
        return_value=[],
    ), patch(
        "app.user.services.chat_history_service.create_conversation",
        return_value="new-conv-id",
    ), patch(
        "app.user.services.chat_history_service.append_messages"
    ) as mock_append:
        result = svc.persist_chat_turn(UID, CONV_ID, "Hi", "Hello!")

    assert result == "new-conv-id"
    mock_append.assert_called_once_with("new-conv-id", "Hi", "Hello!")


def test_persist_chat_turn_starts_fresh_when_conversation_id_stale():
    with patch(
        "app.user.services.chat_history_service.get_conversation",
        return_value=None,
    ), patch(
        "app.user.services.chat_history_service.list_conversations",
        return_value=[],
    ), patch(
        "app.user.services.chat_history_service.create_conversation",
        return_value="new-conv-id",
    ), patch(
        "app.user.services.chat_history_service.append_messages"
    ) as mock_append:
        result = svc.persist_chat_turn(UID, "stale-id", "Hi", "Hello!")

    assert result == "new-conv-id"
    mock_append.assert_called_once_with("new-conv-id", "Hi", "Hello!")


def test_persist_chat_turn_skips_write_when_conversation_full():
    data = {
        "id": CONV_ID,
        "uid": UID,
        "message_count": svc.MAX_MESSAGES_PER_CONVERSATION,
    }

    with patch(
        "app.user.services.chat_history_service.get_conversation",
        return_value=data,
    ), patch("app.user.services.chat_history_service.append_messages") as mock_append:
        result = svc.persist_chat_turn(UID, CONV_ID, "Hi", "Hello!")

    mock_append.assert_not_called()
    assert result == CONV_ID


def test_persist_chat_turn_evicts_oldest_conversation_at_cap():
    existing_rows = [
        {"id": f"c{i}", "updated_at": None, "title": "x", "message_count": 1}
        for i in range(svc.MAX_CONVERSATIONS_PER_USER)
    ]

    with patch(
        "app.user.services.chat_history_service.list_conversations",
        return_value=existing_rows,
    ), patch(
        "app.user.services.chat_history_service.delete_conversation"
    ) as mock_delete, patch(
        "app.user.services.chat_history_service.create_conversation",
        return_value="new-conv-id",
    ), patch(
        "app.user.services.chat_history_service.append_messages"
    ):
        svc.persist_chat_turn(UID, None, "Hi", "Hello!")

    # Oldest conversation (last in the descending-sorted list) gets evicted
    mock_delete.assert_called_once_with(existing_rows[-1]["id"])
