"""Conversation analytics — how farmers actually move through a chat.

Reconstructs real conversations from chat_analytics and reports on their
shape: how long they run, where farmers abandon them, which question-type
flows are most common, and whether follow-up chips are still being tapped.

Pipeline
--------
    chat_analytics docs
      -> reconstruct_conversations()   group by conversation_id, order by
                                       session_message_count, stitch orphan
                                       first turns
      -> _drop_off_analysis()          leave/continue rates per response state
      -> conversation_health()         lengths, flows, per-type drop-off,
                                       chip tap trend

Read-only and advisory: this module reports, it never changes chatbot
behaviour. Follow-up chips are generated per-reply by the LLM and validated
against RAG (see chatbot_service._resolve_followup_chips) — there is no chip
config to mine into any more, so nothing here writes anything.

Conversation ids: chat_analytics historically carried no conversation_id, and
even now the first turn of a NEW conversation has none — the server mints the
id in persist_chat_turn AFTER chat() has already emitted analytics. So
reconstruction stitches a null-id first turn onto the conversation its
same-user follow-up turn belongs to (see _stitch_orphans). Docs that predate
the field simply form single-turn conversations.

Best-effort on Firestore: with no DB or too little data, this returns a
well-formed empty result rather than raising.
"""

import logging
from collections import Counter, defaultdict
from datetime import datetime, timedelta, timezone

logger = logging.getLogger(__name__)

_MAX_DAYS = 90
_DEFAULT_DAYS = 30
_SHORT_WINDOW_DAYS = 7


# Floor for reporting a rate as meaningful. Below this a percentage is noise
# dressed as a finding, so the abandonment alert stays silent.
_MIN_EMIT_SAMPLE = 5

# Two analytics docs from the same user this far apart are different sessions —
# used only when stitching a null-id first turn onto its conversation.
_SESSION_GAP_MINUTES = 30

# Confidence label prefix that marks a low-confidence answer, for the drop-off
# breakdown (chatbot_service writes "Low confidence — ...").
_LOW_CONFIDENCE_PREFIX = "Low confidence"


def _parse_iso(value) -> datetime | None:
    """Parse a stored ISO-8601 timestamp, tolerating a trailing 'Z' and naive
    values (assumed UTC). Returns None for anything unparseable, so a corrupt
    date can never crash a run."""
    if isinstance(value, datetime):
        return value if value.tzinfo else value.replace(tzinfo=timezone.utc)
    if not isinstance(value, str) or not value:
        return None
    try:
        dt = datetime.fromisoformat(value.replace("Z", "+00:00"))
    except ValueError:
        return None
    return dt if dt.tzinfo else dt.replace(tzinfo=timezone.utc)


def _season_for(when) -> str:
    """Cultivation season for a timestamp: Maha (Nov-Mar), Yala (Apr-Aug),
    Inter (Sep-Oct). Mirrors chatbot_service._season_for_now, which stamps the
    season onto new documents; this covers rows written before that field
    existed."""
    dt = _parse_iso(when) or _now()
    if dt.month in (11, 12, 1, 2, 3):
        return "Maha"
    if 4 <= dt.month <= 8:
        return "Yala"
    return "Inter"


def _now() -> datetime:
    return datetime.now(timezone.utc)


def _iso(dt: datetime) -> str:
    return dt.isoformat()


# ── Firestore read ────────────────────────────────────────────────────────────


def _fetch_analytics(days: int) -> list:
    """Fetch chat_analytics docs for the window in one query.

    A single-field inequality on `timestamp` needs no composite index (same
    approach as gap_report_service._fetch_documents). Returns [] rather than
    raising when Firestore is unavailable — mining degrades to "no data".
    """
    try:
        from google.cloud.firestore_v1.base_query import FieldFilter

        from app.utils.firestore import get_db

        cutoff = _now() - timedelta(days=days)
        docs = (
            get_db()
            .collection("chat_analytics")
            .where(filter=FieldFilter("timestamp", ">=", cutoff))
            .stream()
        )
        return [d.to_dict() for d in docs]
    except Exception as exc:
        logger.warning("chat_analytics fetch failed (days=%s): %s", days, exc)
        return []


def _doc_time(doc: dict) -> datetime | None:
    """Normalise a doc's timestamp to an aware datetime, or None.

    Firestore hands back DatetimeWithNanoseconds; a locally written doc may
    carry an ISO string; an unwritten SERVER_TIMESTAMP sentinel is neither.
    """
    ts = doc.get("timestamp")
    if isinstance(ts, datetime):
        return ts if ts.tzinfo else ts.replace(tzinfo=timezone.utc)
    return _parse_iso(ts)


# ── 2a. Conversation reconstruction ───────────────────────────────────────────


def reconstruct_conversations(docs: list) -> list:
    """Rebuild conversations from flat analytics documents.

    Inputs: raw chat_analytics dicts.
    Outputs: a list of conversations, each
        {"id", "user_id", "crop", "district", "season", "started_at",
         "turns": [{"type", "crop", "district", "confidence",
                    "response_type", "timestamp", "season", ...}]}
    ordered by session_message_count then timestamp. A conversation's crop /
    district is the first one any of its turns named — a farmer asking three
    questions about Carrot in Jaffna is one Carrot+Jaffna conversation, even
    though only the first message spelled it out. Season comes from the
    conversation's first turn (2b), so a conversation spanning a season
    boundary is attributed to where it started.
    """
    grouped: dict = defaultdict(list)
    orphans: list = []
    for doc in docs:
        if not isinstance(doc, dict):
            continue
        conv_id = doc.get("conversation_id")
        turn = _to_turn(doc)
        if conv_id:
            grouped[str(conv_id)].append(turn)
        else:
            orphans.append(turn)

    _stitch_orphans(grouped, orphans)

    conversations = []
    for conv_id, turns in grouped.items():
        turns.sort(
            key=lambda t: (
                t["index"],
                t["timestamp"] or datetime.min.replace(tzinfo=timezone.utc),
            )
        )
        conversations.append(_to_conversation(conv_id, turns))
    return sorted(
        conversations,
        key=lambda c: c["started_at"] or datetime.min.replace(tzinfo=timezone.utc),
    )


def _to_turn(doc: dict) -> dict:
    """One analytics document as a conversation turn."""
    ts = _doc_time(doc)
    return {
        "type": doc.get("question_type") or "general",
        "crop": doc.get("crop_mentioned") or None,
        "district": doc.get("district_mentioned") or None,
        "confidence": doc.get("confidence") or "",
        "response_type": doc.get("response_type") or "",
        "timestamp": ts,
        # Prefer the season recorded at write time; older docs predate the
        # field and get it derived from their timestamp instead.
        "season": doc.get("season") or _season_for(ts),
        "index": int(doc.get("session_message_count") or 1),
        "user_id": doc.get("user_id") or "",
        "chip_tapped": bool(doc.get("followup_chip_tapped")),
        "conversation_id": doc.get("conversation_id") or None,
    }


def _stitch_orphans(grouped: dict, orphans: list) -> None:
    """Attach null-conversation_id first turns to the conversation they began.

    A brand-new conversation's first turn is logged before the server mints the
    id, so it arrives with conversation_id=None. For each such turn we look for
    the same user's SECOND turn (session_message_count == 2) that starts a
    known conversation shortly afterwards, and fold the orphan into it.
    Unattachable orphans become single-turn conversations of their own — they
    contribute no transitions but still count for drop-off (a farmer who asked
    one question and left is exactly the signal Step 10 wants).
    Mutates `grouped` in place.
    """
    # Candidate heads: {user_id: [(timestamp, conv_id)]} for second turns.
    heads: dict = defaultdict(list)
    for conv_id, turns in grouped.items():
        for turn in turns:
            if turn["index"] == 2 and turn["timestamp"] and turn["user_id"]:
                heads[turn["user_id"]].append((turn["timestamp"], conv_id))
    for rows in heads.values():
        rows.sort(key=lambda r: r[0])

    gap = timedelta(minutes=_SESSION_GAP_MINUTES)
    unattached = 0
    for turn in orphans:
        target = None
        if turn["index"] == 1 and turn["timestamp"] and turn["user_id"]:
            for ts, conv_id in heads.get(turn["user_id"], []):
                if turn["timestamp"] <= ts <= turn["timestamp"] + gap:
                    target = conv_id
                    break
        if target:
            grouped[target].append(turn)
        else:
            unattached += 1
            grouped[f"_orphan_{unattached}"] = [turn]


def _to_conversation(conv_id: str, turns: list) -> dict:
    """Collapse ordered turns into a conversation record with its context."""
    crop = next((t["crop"] for t in turns if t["crop"]), None)
    district = next((t["district"] for t in turns if t["district"]), None)
    started = next((t["timestamp"] for t in turns if t["timestamp"]), None)
    return {
        "id": conv_id,
        "user_id": turns[0]["user_id"] if turns else "",
        "crop": crop,
        "district": district,
        "season": turns[0]["season"] if turns else _season_for(started),
        "started_at": started,
        "turns": turns,
    }


# ── Drop-off analysis ─────────────────────────────────────────────────────────


def _drop_off_analysis(conversations: list) -> dict:
    """How often farmers abandon the chat after each kind of response.

    A turn "leaves" when it is the last in its conversation. After a refusal
    the alternative is a rephrase (the next turn asks the same question type,
    or is routed as a reformulation); after a clarification the useful outcome
    is an actual answer. Rates are of the turns in that state, so an absent
    state reports zeros rather than being omitted.
    """
    stats = {
        "after_refusal": {"total": 0, "leave": 0, "rephrase": 0},
        "after_low_confidence": {"total": 0, "leave": 0, "continue": 0},
        "after_clarification": {"total": 0, "leave": 0, "answer": 0},
    }
    for conv in conversations:
        turns = conv["turns"]
        for i, turn in enumerate(turns):
            nxt = turns[i + 1] if i + 1 < len(turns) else None
            left = nxt is None
            rtype = turn["response_type"]
            conf = turn["confidence"] or ""

            if rtype in ("refusal", "near_miss"):
                bucket = stats["after_refusal"]
                bucket["total"] += 1
                if left:
                    bucket["leave"] += 1
                elif (
                    nxt["response_type"] == "reformulation"
                    or nxt["type"] == turn["type"]
                ):
                    bucket["rephrase"] += 1
            if conf.startswith(_LOW_CONFIDENCE_PREFIX):
                bucket = stats["after_low_confidence"]
                bucket["total"] += 1
                bucket["leave" if left else "continue"] += 1
            if rtype == "clarification":
                bucket = stats["after_clarification"]
                bucket["total"] += 1
                if left:
                    bucket["leave"] += 1
                elif nxt["response_type"] == "answer":
                    bucket["answer"] += 1

    def rate(bucket: dict, key: str) -> float:
        return round(bucket[key] / bucket["total"], 2) if bucket["total"] else 0.0

    return {
        "after_refusal": {
            "sample_size": stats["after_refusal"]["total"],
            "leave_rate": rate(stats["after_refusal"], "leave"),
            "rephrase_rate": rate(stats["after_refusal"], "rephrase"),
        },
        "after_low_confidence": {
            "sample_size": stats["after_low_confidence"]["total"],
            "leave_rate": rate(stats["after_low_confidence"], "leave"),
            "continue_rate": rate(stats["after_low_confidence"], "continue"),
        },
        "after_clarification": {
            "sample_size": stats["after_clarification"]["total"],
            "leave_rate": rate(stats["after_clarification"], "leave"),
            "answer_rate": rate(stats["after_clarification"], "answer"),
        },
    }


# ── Public API ────────────────────────────────────────────────────────────────


def mine_conversation_patterns(days: int = _DEFAULT_DAYS) -> dict:
    """Analyse the last `days` of conversations for admin insight.

    Inputs: days, clamped to 1.._MAX_DAYS.
    Outputs: a report — analyzed_at, period_days, conversation counts, the
    drop-off breakdown, the most common and worst-abandoning flows, per-
    question-type drop-off, and the chip tap trend. Purely descriptive: it
    changes nothing about how the chatbot behaves.
    Security assumption: reads anonymised analytics only — no raw uid, and no
    user text beyond the already-truncated `question` field. Nothing here ever
    reaches an LLM prompt.
    Never raises: Firestore problems yield an empty, well-formed report.
    """
    days = max(1, min(int(days or _DEFAULT_DAYS), _MAX_DAYS))
    now = _now()
    docs = _fetch_analytics(days)
    conversations = reconstruct_conversations(docs)

    recent_cutoff = now - timedelta(days=_SHORT_WINDOW_DAYS)
    recent = [
        c for c in conversations if c["started_at"] and c["started_at"] >= recent_cutoff
    ]

    result = {
        "analyzed_at": _iso(now),
        "period_days": days,
        "total_conversations": len(conversations),
        "total_turns": sum(len(c["turns"]) for c in conversations),
        "multi_turn_conversations": sum(
            1 for c in conversations if len(c["turns"]) > 1
        ),
        "recent_window": {
            "period_days": _SHORT_WINDOW_DAYS,
            "total_conversations": len(recent),
        },
        "drop_off_analysis": _drop_off_analysis(conversations),
        "conversation_health": conversation_health(docs),
    }
    _notify_mining(result)
    return result


# ── Conversation health (Step 10) ─────────────────────────────────────────────


def conversation_health(docs: list) -> dict:
    """Conversation Health block for the gap report.

    Takes the analytics documents the gap report ALREADY fetched, so this adds
    no Firestore reads to the dashboard. Returns average length, drop-off
    rates overall and per question type, the most common complete flows, the
    worst abandonment flows, and the week-over-week chip tap trend.
    Never raises — any failure yields a zeroed block.
    """
    try:
        conversations = reconstruct_conversations(docs)
        total = len(conversations)
        lengths = [len(c["turns"]) for c in conversations]

        per_type: dict = defaultdict(lambda: {"total": 0, "leave": 0})
        flows: Counter = Counter()
        problem_flows: Counter = Counter()
        for conv in conversations:
            turns = conv["turns"]
            for i, turn in enumerate(turns):
                bucket = per_type[turn["type"]]
                bucket["total"] += 1
                if i + 1 == len(turns):
                    bucket["leave"] += 1
            path = [t["type"] for t in turns]
            if len(path) >= 2:
                flows[" → ".join(path[:4])] += 1
                if turns[-1]["response_type"] in ("refusal", "near_miss"):
                    problem_flows[" → ".join(path[:3] + ["leave"])] += 1

        return {
            "total_conversations": total,
            "avg_conversation_length": round(sum(lengths) / total, 1) if total else 0.0,
            "single_turn_rate": (
                round(sum(1 for n in lengths if n == 1) / total, 2) if total else 0.0
            ),
            "drop_off_by_response": _drop_off_analysis(conversations),
            "drop_off_by_question_type": [
                {
                    "question_type": qtype,
                    "turns": vals["total"],
                    "leave_rate": (
                        round(vals["leave"] / vals["total"], 2)
                        if vals["total"]
                        else 0.0
                    ),
                }
                for qtype, vals in sorted(
                    per_type.items(), key=lambda kv: -kv[1]["total"]
                )
            ],
            "top_flows": [
                {"flow": flow, "count": count} for flow, count in flows.most_common(5)
            ],
            "problem_flows": [
                {"flow": flow, "count": count}
                for flow, count in problem_flows.most_common(5)
            ],
            "chip_tap_trend": _chip_tap_trend(docs),
        }
    except Exception as exc:
        logger.warning("conversation health build failed: %s", exc)
        return {
            "total_conversations": 0,
            "avg_conversation_length": 0.0,
            "single_turn_rate": 0.0,
            "drop_off_by_response": _drop_off_analysis([]),
            "drop_off_by_question_type": [],
            "top_flows": [],
            "problem_flows": [],
            "chip_tap_trend": {"this_week": 0.0, "last_week": 0.0, "change": 0.0},
        }


def _chip_tap_trend(docs: list) -> dict:
    """Chip tap rate this week vs the week before, from the same docs."""
    now = _now()
    this_week, last_week = [0, 0], [0, 0]  # [taps, turns]
    for doc in docs:
        ts = _doc_time(doc)
        if ts is None:
            continue
        age = (now - ts).days
        bucket = this_week if age < 7 else (last_week if age < 14 else None)
        if bucket is None:
            continue
        bucket[1] += 1
        if doc.get("followup_chip_tapped"):
            bucket[0] += 1
    rate_now = round(this_week[0] / this_week[1], 2) if this_week[1] else 0.0
    rate_prev = round(last_week[0] / last_week[1], 2) if last_week[1] else 0.0
    return {
        "this_week": rate_now,
        "last_week": rate_prev,
        "change": round(rate_now - rate_prev, 2),
    }


# ── Step 11. Notifications ────────────────────────────────────────────────────


def _notify(
    type_: str, title: str, message: str, severity: str, action_url: str
) -> None:
    """Create one admin notification. Fully isolated — a notification failure
    must never fail a mining run or a chat request."""
    try:
        from app.admin.services.notification_service import create_notification

        create_notification(
            type=type_,
            title=title,
            message=message,
            severity=severity,
            action_url=action_url,
        )
    except Exception as exc:
        logger.debug("chip notification skipped (%s): %s", type_, exc)


def _notify_mining(result: dict) -> None:
    """Raise an admin notification when an analysis run finds a conversation
    health problem worth acting on.

    Only abandonment is alerted: it is the one signal a human can act on
    (rewriting a refusal, widening the dataset). Chip-pattern notifications
    are gone — chips are generated per reply now, so there is no config to
    review. Best-effort; never raises into the caller.
    """
    health = result.get("conversation_health") or {}
    refusal = (health.get("drop_off_by_response") or {}).get("after_refusal") or {}
    leave_rate = refusal.get("leave_rate") or 0
    if refusal.get("sample_size", 0) >= _MIN_EMIT_SAMPLE and leave_rate >= 0.7:
        _notify(
            "high_abandonment",
            f"{int(leave_rate * 100)}% of farmers leave after a refusal",
            (
                f"Across {result['total_conversations']} conversations in the last "
                f"{result['period_days']} days, {refusal['sample_size']} turns ended "
                f"in a refusal and {int(leave_rate * 100)}% of those farmers left "
                "without asking anything else."
            ),
            "warning",
            "/gap-report",
        )
