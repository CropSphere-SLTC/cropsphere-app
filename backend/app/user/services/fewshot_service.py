"""Few-shot example collection from thumbs-up feedback.

Build-time / admin-triggered: queries chat_feedback for "up" votes, maps each
to its (question, answer) pair in chat_conversations, groups by question_type,
merges hand-written manual examples (priority), and writes the JSON the chatbot
loads. Never raises on missing Firestore — falls back to manual-only.
"""

import json
import logging
import os
from datetime import datetime, timezone
from pathlib import Path

logger = logging.getLogger(__name__)

_DATA_DIR = Path(
    os.environ.get("FEWSHOT_DIR") or Path(__file__).resolve().parents[3] / "data"
)
FEWSHOT_PATH = _DATA_DIR / "fewshot_examples.json"
MANUAL_PATH = _DATA_DIR / "fewshot_manual.json"

# Question types (see chatbot_service._question_type) — kept in sync here so
# the collector and the prompt injection group by the same buckets.
_TYPES = ("yield", "price", "season", "earnings", "general")
_MAX_PER_TYPE = 2
_MAX_TOTAL = 10
_Q_MAX, _A_MAX = 200, 500


def build_fewshot_examples() -> dict:
    """Collect auto examples from feedback, merge with manual, write the file.

    Outputs the written dict {"updated_at", "examples": {type: [...]}}. Manual
    examples take priority per type; auto fills the remaining slots. Best-effort
    on Firestore — with no DB (or no up-votes) the result is manual-only.
    """
    auto = _collect_auto()
    manual = _load_manual()
    merged = _merge(manual, auto)
    out = {
        "updated_at": datetime.now(timezone.utc).isoformat(),
        "examples": merged,
    }
    try:
        _DATA_DIR.mkdir(parents=True, exist_ok=True)
        FEWSHOT_PATH.write_text(json.dumps(out, indent=2, ensure_ascii=False))
    except Exception as exc:
        logger.error("few-shot write failed: %s", exc)
    return out


def _load_manual() -> dict:
    """Hand-written examples ({type: [{question, answer}]}) or {}."""
    try:
        if MANUAL_PATH.exists():
            return json.loads(MANUAL_PATH.read_text()).get("examples", {})
    except Exception as exc:
        logger.warning("manual few-shot load failed: %s", exc)
    return {}


# Auto examples are only useful as few-shots if they demonstrate the answer
# shape the model is currently told to produce (three blank-line-separated
# sections — see chatbot_service._FORMATTING_RULES). Up-voted answers from
# before that rule are single paragraphs; merging them back in teaches the
# old merged format alongside the manual examples that teach the new one.
def _is_structured(answer: str) -> bool:
    """True when the answer has 2+ blank-line-separated non-empty sections."""
    return len([s for s in answer.split("\n\n") if s.strip()]) >= 2


def _collect_auto() -> dict:
    """{type: [{question, answer}]} from thumbs-up votes, most-recent first.

    Best-effort — returns {} if Firestore is unavailable. Stops early once
    every type has _MAX_PER_TYPE examples.
    """
    try:
        from google.cloud.firestore_v1.base_query import FieldFilter

        from app.user.services.chatbot_service import _question_type
        from app.utils.firestore import get_db

        db = get_db()
        ups = list(
            db.collection("chat_feedback")
            .where(filter=FieldFilter("feedback", "==", "up"))
            .stream()
        )
        # datetime.min must carry a tzinfo: Firestore returns tz-aware
        # timestamps, and mixing them with a naive sentinel raises TypeError
        # inside sort() — swallowed by the except below, silently dropping
        # the whole auto few-shot set because one doc lacked a timestamp.
        # Anything that is not a datetime at all sorts oldest for the same
        # reason.
        _oldest = datetime.min.replace(tzinfo=timezone.utc)

        def _ts(doc) -> datetime:
            value = (doc.to_dict() or {}).get("timestamp")
            if not isinstance(value, datetime):
                return _oldest
            return value if value.tzinfo else value.replace(tzinfo=timezone.utc)

        ups.sort(key=_ts, reverse=True)

        buckets: dict = {t: [] for t in _TYPES}
        conv_cache: dict = {}
        for doc in ups:
            pair = _extract_pair(db, doc.to_dict(), conv_cache)
            if not pair:
                continue
            question, answer = pair
            # Truncate before the structure check: an answer whose only blank
            # line falls past _A_MAX would be stored as a single paragraph.
            answer = answer[:_A_MAX]
            if not _is_structured(answer):
                continue
            qtype = _question_type(question)
            if qtype in buckets and len(buckets[qtype]) < _MAX_PER_TYPE:
                buckets[qtype].append({"question": question[:_Q_MAX], "answer": answer})
            if all(len(v) >= _MAX_PER_TYPE for v in buckets.values()):
                break
        return buckets
    except Exception as exc:
        logger.warning("auto few-shot collection failed: %s", exc)
        return {}


def _extract_pair(db, fb: dict, conv_cache: dict):
    """(question, answer) from the rated conversation message, validated.

    Returns None when the conversation is missing or the stored message_index
    doesn't line up with an assistant turn (client-side history trimming can
    shift it). The question falls back to the feedback doc's message_text.
    """
    conv_id = fb.get("conversation_id")
    idx = fb.get("message_index")
    if not conv_id or not isinstance(idx, int):
        return None
    if conv_id not in conv_cache:
        snap = db.collection("chat_conversations").document(conv_id).get()
        conv_cache[conv_id] = snap.to_dict().get("messages", []) if snap.exists else []
    msgs = conv_cache[conv_id]
    if not (0 <= idx < len(msgs)) or msgs[idx].get("role") != "assistant":
        return None
    answer = (msgs[idx].get("content") or "").strip()
    if not answer:
        return None
    question = fb.get("message_text") or ""
    if not question and idx > 0 and msgs[idx - 1].get("role") == "user":
        question = msgs[idx - 1].get("content") or ""
    question = question.strip()
    return (question, answer) if question else None


def _merge(manual: dict, auto: dict) -> dict:
    """Manual first, auto fills to _MAX_PER_TYPE, deduped by question (case-
    insensitive); capped at _MAX_TOTAL overall. All types present."""
    out: dict = {t: [] for t in _TYPES}
    total = 0
    for t in _TYPES:
        seen: set = set()
        for ex in manual.get(t, []) + auto.get(t, []):
            q = (ex.get("question") or "").strip()
            a = (ex.get("answer") or "").strip()
            key = q.lower()
            if not q or not a or key in seen:
                continue
            if len(out[t]) >= _MAX_PER_TYPE or total >= _MAX_TOTAL:
                break
            out[t].append({"question": q[:_Q_MAX], "answer": a[:_A_MAX]})
            seen.add(key)
            total += 1
    return out
