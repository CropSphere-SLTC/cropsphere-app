"""Gap Report analytics — aggregates the chat_analytics collection into the
admin dashboard's Gap Report (what users ask for that we can't answer yet).

Firestore has no GROUP BY, so we pull the window's documents in one query and
aggregate in Python. Results are cached _CACHE_TTL_SECONDS per day-window so
repeated dashboard refreshes don't re-scan the collection.
"""

import logging
import threading
import time
from collections import Counter
from datetime import datetime, timedelta, timezone

from fastapi import HTTPException

logger = logging.getLogger(__name__)

_MAX_DAYS = 30
_DEFAULT_DAYS = 7
_TOP_N = 10
_CACHE_TTL_SECONDS = 300  # 5 minutes

# Response types surfaced in the breakdown, in a stable display order. Always
# emitted (0 when absent) so the dashboard shows every category.
_RESPONSE_TYPES = (
    "answer",
    "refusal",
    "clarification",
    "near_miss",
    "capability",
    "context_ack",
    "reformulation",
)

# {days: (expires_at_monotonic, report)}
_cache: dict[int, tuple[float, dict]] = {}
_cache_lock = threading.Lock()


def get_gap_report(days: int = _DEFAULT_DAYS) -> dict:
    """Return aggregated gap-report analytics for the last `days` days.

    days is clamped to 1.._MAX_DAYS. The result is cached _CACHE_TTL_SECONDS
    per distinct day-window. An empty collection is not an error — it returns
    a well-formed report with zeroed aggregates. Raises HTTPException(500) only
    on a real Firestore/aggregation failure.
    """
    days = max(1, min(int(days), _MAX_DAYS))

    now = time.monotonic()
    with _cache_lock:
        cached = _cache.get(days)
        if cached and cached[0] > now:
            return cached[1]

    try:
        report = _build_report(days)
    except Exception as exc:
        logger.error("gap report build failed (days=%s): %s", days, exc)
        raise HTTPException(status_code=500, detail="Failed to build gap report")

    with _cache_lock:
        _cache[days] = (time.monotonic() + _CACHE_TTL_SECONDS, report)
    return report


def _build_report(days: int) -> dict:
    """Fetch the window's documents and aggregate them in Python."""
    from app.user.services.chatbot_service import _dataset_capabilities
    from app.utils.firestore import get_db

    db = get_db()
    docs = _fetch_documents(db, days)
    caps = _dataset_capabilities()
    covered_crops = set(caps["crops"])
    covered_districts = set(caps["districts"])

    total = len(docs)
    response_breakdown = {rt: 0 for rt in _RESPONSE_TYPES}
    confidence_dist: Counter = Counter()
    knowledge_dist: Counter = Counter()
    refused: Counter = Counter()
    missing_crops: Counter = Counter()
    missing_districts: Counter = Counter()
    rtime_sum = rtime_n = 0
    slen_sum = slen_n = 0
    chip_taps = 0

    for d in docs:
        rt = d.get("response_type")
        if rt in response_breakdown:
            response_breakdown[rt] += 1

        conf = _normalize_confidence(d.get("confidence"))
        if conf:
            confidence_dist[conf] += 1

        level = d.get("knowledge_level")
        if level:
            knowledge_dist[level] += 1

        # Top refused: an out-of-scope refusal or near-miss.
        if rt in ("refusal", "near_miss") and d.get("confidence") == "Out of scope":
            q = (d.get("question") or "").strip()
            if q:
                refused[q] += 1

        crop = d.get("crop_mentioned")
        if crop and crop not in covered_crops:
            missing_crops[crop] += 1

        district = d.get("district_mentioned")
        if district and district not in covered_districts:
            missing_districts[district] += 1

        rtime = d.get("response_time_ms")
        if isinstance(rtime, (int, float)):
            rtime_sum += rtime
            rtime_n += 1

        slen = d.get("session_message_count")
        if isinstance(slen, (int, float)):
            slen_sum += slen
            slen_n += 1

        if d.get("followup_chip_tapped") is True:
            chip_taps += 1

    feedback_summary = _aggregate_feedback(_fetch_feedback(db, days))

    return {
        "period": f"last_{days}_days",
        "total_interactions": total,
        "response_breakdown": response_breakdown,
        "top_refused_questions": [
            {"question": q, "count": c} for q, c in refused.most_common(_TOP_N)
        ],
        "missing_crops": [
            {"crop": c, "request_count": n}
            for c, n in missing_crops.most_common(_TOP_N)
        ],
        "missing_districts": [
            {"district": c, "request_count": n}
            for c, n in missing_districts.most_common(_TOP_N)
        ],
        "confidence_distribution": dict(confidence_dist),
        "knowledge_level_distribution": dict(knowledge_dist),
        "avg_response_time_ms": round(rtime_sum / rtime_n) if rtime_n else 0,
        "chip_tap_rate": round(chip_taps / total, 2) if total else 0.0,
        "avg_session_length": round(slen_sum / slen_n, 1) if slen_n else 0.0,
        "feedback_summary": feedback_summary,
    }


def _normalize_confidence(conf):
    """Collapse the verbose low-confidence label to its short bucket so the
    distribution has clean keys (High/Moderate/Low confidence, Out of scope)."""
    if not conf:
        return None
    if conf.startswith("Low confidence"):
        return "Low confidence"
    return conf


def _fetch_documents(db, days: int) -> list:
    """Fetch all chat_analytics docs with timestamp >= now-days in one query.

    A single-field inequality needs no composite index. Raises on Firestore
    error (get_gap_report turns it into a 500).
    """
    from google.cloud.firestore_v1.base_query import FieldFilter

    cutoff = datetime.now(timezone.utc) - timedelta(days=days)
    docs = (
        db.collection("chat_analytics")
        .where(filter=FieldFilter("timestamp", ">=", cutoff))
        .stream()
    )
    return [doc.to_dict() for doc in docs]


def _fetch_feedback(db, days: int) -> list:
    """Fetch chat_feedback docs with timestamp >= now-days (same window)."""
    from google.cloud.firestore_v1.base_query import FieldFilter

    cutoff = datetime.now(timezone.utc) - timedelta(days=days)
    docs = (
        db.collection("chat_feedback")
        .where(filter=FieldFilter("timestamp", ">=", cutoff))
        .stream()
    )
    return [doc.to_dict() for doc in docs]


def _aggregate_feedback(docs: list) -> dict:
    """Aggregate thumbs up/down votes into the feedback_summary block.

    most_downvoted_questions groups downvotes by the stored question text
    (the user message that produced the answer), top _TOP_N by count.
    """
    up = down = 0
    downvoted: Counter = Counter()
    for f in docs:
        vote = f.get("feedback")
        if vote == "up":
            up += 1
        elif vote == "down":
            down += 1
            q = (f.get("message_text") or "").strip()
            if q:
                downvoted[q] += 1
    total = up + down
    return {
        "total_feedback": total,
        "thumbs_up": up,
        "thumbs_down": down,
        "satisfaction_rate": round(up / total, 2) if total else 0.0,
        "most_downvoted_questions": [
            {"question": q, "count": c} for q, c in downvoted.most_common(_TOP_N)
        ],
    }
