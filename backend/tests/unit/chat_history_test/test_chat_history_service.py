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


# ═══════════════════════════════════════════════════════════════════════════
# build_conversation_title
# ═══════════════════════════════════════════════════════════════════════════
#
# The detectors live in chatbot_service and are dataset-driven, so they are
# patched here to the six crops / eight districts the app actually covers.
# These tests pin the TITLE FORMAT, not the gazetteers.

_CROPS = ["Carrot", "Maize", "Green gram", "Cowpea", "Finger millet", "Groundnut"]
_DISTRICTS = [
    "Nuwara Eliya",
    "Badulla",
    "Anuradhapura",
    "Monaragala",
    "Ampara",
    "Hambantota",
    "Batticaloa",
    "Jaffna",
]


def _fake_crop(message):
    low = message.lower()
    return next((c for c in _CROPS if c.lower() in low), None)


def _fake_district(message):
    low = message.lower()
    return next((d for d in _DISTRICTS if d.lower() in low), None)


def _fake_qtype(message):
    low = message.lower()
    for keywords, topic in (
        (("yield", "harvest", "grow"), "yield"),
        (("earn", "money"), "earnings"),
        (("price", "cost", "sell"), "price"),
        (("season", "plant", "when"), "season"),
    ):
        if any(k in low for k in keywords):
            return topic
    return "general"


@pytest.fixture
def detectors():
    with patch(
        "app.user.services.chatbot_service._detect_crop_mention", _fake_crop
    ), patch(
        "app.user.services.chatbot_service._detect_district_mention", _fake_district
    ), patch(
        "app.user.services.chatbot_service._question_type", _fake_qtype
    ):
        yield


@pytest.mark.parametrize(
    "message,expected",
    [
        ("What is the carrot price in Badulla?", "Carrot price · Badulla"),
        ("Carrot yield in Badulla", "Carrot yield · Badulla"),
        (
            "How much can I earn from groundnut in Jaffna?",
            "Groundnut earnings · Jaffna",
        ),
        (
            "When should I plant maize in Ampara?",
            "Maize season · Ampara",
        ),
    ],
)
def test_title_is_built_from_crop_topic_and_district(detectors, message, expected):
    assert svc.build_conversation_title(message) == expected


def test_title_uses_the_script_the_farmer_typed_in(detectors):
    # Sinhala. The mention detectors match English only, so the crop and
    # district come from the request's context selections — which is exactly
    # why persist_chat_turn forwards them.
    assert (
        svc.build_conversation_title("බදුල්ල කැරට් මිල කීයද?", "Carrot", "Badulla")
        == "කැරට් මිල · බදුල්ල"
    )
    # Tamil.
    assert (
        svc.build_conversation_title("பதுளையில் கேரட் விலை என்ன?", "Carrot", "Badulla")
        == "கேரட் விலை · பதுளை"
    )


def test_sinhala_and_tamil_topics_are_classified(detectors):
    # _question_type is English-only, so without the script keyword layer both
    # of these would come back "general" and fall through to the raw message.
    assert (
        svc.build_conversation_title(
            "අනුරාධපුරයේ බඩඉරිඟු අස්වැන්න කොපමණද?", "Maize", "Anuradhapura"
        )
        == "බඩඉරිඟු අස්වැන්න · අනුරාධපුරය"
    )
    assert (
        svc.build_conversation_title(
            "யாழ்ப்பாணத்தில் வேர்க்கடலை விளைச்சல்", "Groundnut", "Jaffna"
        )
        == "வேர்க்கடலை விளைச்சல் · யாழ்ப்பாணம்"
    )


@pytest.mark.parametrize(
    "message",
    [
        "Explain this price",  # no crop, no district
        "What is the price of carrot?",  # crop but no district
        "Tell me about Badulla",  # district but no crop
    ],
)
def test_title_falls_back_to_truncated_message(detectors, message):
    assert svc.build_conversation_title(message) == message[:40]


def test_general_questions_fall_back_even_with_crop_and_district(detectors):
    # "Carrot general · Badulla" would be worse than the question itself.
    msg = "Is carrot difficult in Badulla for a beginner"
    assert svc.build_conversation_title(msg) == msg[:40]


def test_long_fallback_is_truncated_to_forty_characters(detectors):
    msg = "x" * 100
    assert svc.build_conversation_title(msg) == "x" * 40


def test_title_failure_never_breaks_persistence():
    # Any explosion inside the detectors must degrade to the raw message.
    with patch(
        "app.user.services.chatbot_service._detect_crop_mention",
        side_effect=RuntimeError("boom"),
    ):
        assert svc.build_conversation_title("Carrot price in Badulla") == (
            "Carrot price in Badulla"
        )


def test_persist_chat_turn_titles_a_new_conversation_from_context(detectors):
    with patch(
        "app.user.services.chat_history_service.list_conversations",
        return_value=[],
    ), patch(
        "app.user.services.chat_history_service.create_conversation",
        return_value="new-conv-id",
    ) as mock_create, patch(
        "app.user.services.chat_history_service.append_messages"
    ):
        svc.persist_chat_turn(
            UID,
            None,
            "What is the carrot price in Badulla?",
            "About Rs. 180/kg.",
            crop="Carrot",
            district="Badulla",
        )

    mock_create.assert_called_once_with(UID, "Carrot price · Badulla")
