"""Chat conversation history service — reads/writes chat_conversations.

Ownership rule (shift-left): any conversation that doesn't exist OR belongs
to another uid is reported as "not found" — a 404, never a 403 — so
conversation ids can't be enumerated by probing.
"""

import logging
import re
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

# ── Conversation titles ──────────────────────────────────────────────────────
# Titles are built HERE, server-side, rather than in the Flutter client. The
# crop/district/topic detection this needs already exists in chatbot_service
# and is non-trivial (dataset-driven crop and district gazetteers, plus the
# keyword classifier that drives follow-up templates). A second copy of those
# rules in Dart would be exactly the kind of drift that has already bitten
# this codebase, so the title is assembled where the detectors live and the
# client just renders the string it is given.
#
# Script detection, not UI language. The backend never learns which language
# the app is currently displaying — ChatRequest carries no language field (the
# client sends one; the schema ignores it) — so the title follows the script
# the farmer actually typed in. A Sinhala question gets a Sinhala title.
_SINHALA_RANGE = re.compile(r"[\u0D80-\u0DFF]")
_TAMIL_RANGE = re.compile(r"[\u0B80-\u0BFF]")

# Topic words per _question_type bucket. "general" has no useful noun of its
# own, so a general question falls back to the raw first message instead of
# rendering "Carrot general · Badulla".
_TOPIC_WORDS = {
    "yield": {"en": "yield", "si": "අස්වැන්න", "ta": "விளைச்சல்"},
    "price": {"en": "price", "si": "මිල", "ta": "விலை"},
    "season": {"en": "season", "si": "කන්නය", "ta": "பருவம்"},
    "earnings": {"en": "earnings", "si": "ආදායම", "ta": "வருமானம்"},
}

# Display names for the six covered crops and eight covered districts. Keyed
# by the exact English value the detectors and the API enums return.
# Topic keywords for the two scripts chatbot_service._question_type cannot
# see. That classifier matches English substrings only, so EVERY Sinhala or
# Tamil question came back "general" and fell straight through to the raw
# message — leaving two of the three languages with exactly the
# indistinguishable-titles problem this is meant to fix.
#
# This is NOT a second copy of _question_type: it adds the buckets that
# function has no vocabulary for, and English still goes through the real
# classifier. Ordered like _question_type's own if-chain (yield, earnings,
# price, season) so the two agree on a message that somehow matches both.
_TOPIC_KEYWORDS = {
    "si": (
        ("yield", ("අස්වැන්න", "අස්වනු", "වගා")),
        ("earnings", ("ආදායම", "ලාභ", "මුදල්")),
        ("price", ("මිල", "විකුණ", "ගණන")),
        ("season", ("කන්න", "රෝපණ", "වපුර")),
    ),
    "ta": (
        ("yield", ("விளைச்சல்", "அறுவடை", "பயிரிட")),
        ("earnings", ("வருமானம்", "லாபம்", "பணம்")),
        ("price", ("விலை", "விற்க", "செலவு")),
        ("season", ("பருவம்", "நடவு", "விதைப்")),
    ),
}

_CROP_NAMES = {
    "Carrot": {"en": "Carrot", "si": "කැරට්", "ta": "கேரட்"},
    "Maize": {"en": "Maize", "si": "බඩඉරිඟු", "ta": "மக்காச்சோளம்"},
    "Green gram": {"en": "Green gram", "si": "මුං ඇට", "ta": "பச்சைப்பயறு"},
    "Cowpea": {"en": "Cowpea", "si": "කව්පි", "ta": "காராமணி"},
    "Finger millet": {"en": "Finger millet", "si": "කුරක්කන්", "ta": "கேழ்வரகு"},
    "Groundnut": {"en": "Groundnut", "si": "රටකජු", "ta": "வேர்க்கடலை"},
}

_DISTRICT_NAMES = {
    "Nuwara Eliya": {"en": "Nuwara Eliya", "si": "නුවරඑළිය", "ta": "நுவரெலியா"},
    "Badulla": {"en": "Badulla", "si": "බදුල්ල", "ta": "பதுளை"},
    "Anuradhapura": {"en": "Anuradhapura", "si": "අනුරාධපුරය", "ta": "அனுராதபுரம்"},
    "Monaragala": {"en": "Monaragala", "si": "මොනරාගල", "ta": "மொணராகலை"},
    "Ampara": {"en": "Ampara", "si": "අම්පාර", "ta": "அம்பாறை"},
    "Hambantota": {"en": "Hambantota", "si": "හම්බන්තොට", "ta": "அம்பாந்தோட்டை"},
    "Batticaloa": {"en": "Batticaloa", "si": "මඩකලපුව", "ta": "மட்டக்களப்பு"},
    "Jaffna": {"en": "Jaffna", "si": "යාපනය", "ta": "யாழ்ப்பாணம்"},
}


def _script_of(message: str) -> str:
    """Which script the farmer typed in: 'si', 'ta' or 'en'.

    Presence of any character in the block wins — Sinhala and Tamil questions
    routinely carry English crop names or digits, so requiring a majority
    would misfile most real messages as English.
    """
    if _SINHALA_RANGE.search(message):
        return "si"
    if _TAMIL_RANGE.search(message):
        return "ta"
    return "en"


def _topic_for_script(message: str, lang: str) -> str:
    """_question_type's job for Sinhala and Tamil — see _TOPIC_KEYWORDS."""
    for topic, keywords in _TOPIC_KEYWORDS.get(lang, ()):
        if any(k in message for k in keywords):
            return topic
    return "general"


def build_conversation_title(
    message: str,
    crop: Optional[str] = None,
    district: Optional[str] = None,
) -> str:
    """A conversation title from what the first message is ABOUT.

    "[Crop] [topic] · [District]" — "Carrot price · Badulla" — in the script
    the message was written in. Falls back to the truncated message whenever
    crop, district or a nameable topic is missing, which is what every title
    used to be: five "Explain this price" questions produced five
    indistinguishable sidebar entries.

    [crop] and [district] are the request's explicit context selections when
    the farmer set them. They matter most for Sinhala and Tamil: the mention
    detectors match English names only, so a farmer typing in Sinhala who
    picked a crop from the context picker still gets a structured title.
    """
    fallback = message[:_TITLE_LEN]
    try:
        # Imported inside the function: chatbot_service imports THIS module
        # (persist_chat_turn) at call time, so a module-level import here
        # would close the cycle. Same pattern as fewshot_service.
        from app.user.services.chatbot_service import (
            _detect_crop_mention,
            _detect_district_mention,
            _question_type,
        )

        crop = crop or _detect_crop_mention(message)
        district = district or _detect_district_mention(message)
        if not crop or not district:
            return fallback

        lang = _script_of(message)
        topic = _TOPIC_WORDS.get(
            _question_type(message)
            if lang == "en"
            else _topic_for_script(message, lang)
        )
        if topic is None:  # "general" — nothing worth naming
            return fallback

        crop_name = _CROP_NAMES.get(crop, {}).get(lang, crop)
        district_name = _DISTRICT_NAMES.get(district, {}).get(lang, district)
        return f"{crop_name} {topic[lang]} \u00b7 {district_name}"
    except Exception as exc:
        # A title is cosmetic; never let it cost the farmer their history.
        logger.warning("Title generation failed, using raw message: %s", exc)
        return fallback


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
    uid: str,
    conversation_id: Optional[str],
    user_msg: str,
    assistant_msg: str,
    crop: Optional[str] = None,
    district: Optional[str] = None,
) -> str:
    """Append a chat turn to a conversation, creating one when needed.

    Returns the conversation id the turn was written to, or "" on any
    failure — persistence must never break the chat response, so the
    caller wraps this in try/except and treats "" as "not saved".

    [crop] and [district] are the request's context selections, used only to
    title a NEWLY created conversation — see build_conversation_title. Both
    optional so existing callers keep working unchanged.
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
        conversation_id = create_conversation(
            uid, build_conversation_title(user_msg, crop, district)
        )

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
