"""Pattern gap analysis — finds chat messages that SHOULD have matched one of
the chatbot's routing predicates but didn't, and proposes new phrases for admin
review.

The chatbot routes a turn by substring-matching a handful of hardcoded phrase
lists (_REFORMULATION_PHRASES, _CONTEXT_STATEMENT_PHRASES, _CAPABILITY_PATTERNS,
_AGRICULTURAL_INTENT_PHRASES). Real farmers phrase things the lists don't cover,
and the turn silently lands on the wrong branch — a rephrase request gets
refused as out of scope, a "we grow chillies in Jaffna" statement gets sent to
retrieval. This module reads chat_analytics, spots those misses by their
contextual fingerprint, groups them into candidate phrases, and ranks them by
how much evidence each has.

Nothing here changes chatbot behaviour: analysis is read-only and every proposal
requires an explicit admin approval through pattern_override_store (Step 11 —
no auto-applying). This module is also the read-side for the admin screens
(active patterns, per-pattern analytics, pattern health).

Best-effort on Firestore: with no DB, or too little data, analysis returns an
empty proposal list rather than raising.
"""

import logging
import re
import threading
from collections import defaultdict
from datetime import datetime, timedelta, timezone

from app.user.services import pattern_override_store as store_mod

logger = logging.getLogger(__name__)

_MAX_DAYS = 90
_DEFAULT_DAYS = 14

# Group sizes → confidence. A phrase seen 5+ times in the window is a real
# usage pattern; 1-2 is likely one farmer's habit and is proposed unchecked.
_HIGH_CONFIDENCE_MIN = 5
_MEDIUM_CONFIDENCE_MIN = 3

# Ceiling per category so one noisy window can't produce a 200-row review list.
_MAX_PROPOSALS_PER_CATEGORY = 10

# Message-length gates from the detection rules, in words.
_REFORMULATION_MAX_WORDS = 30
_CONTEXT_MAX_WORDS = 20

# ── Detection vocabularies ────────────────────────────────────────────────────
# Clue words that make a message *look* like a rephrase request even though no
# hardcoded pattern fired.
_REFORMULATION_CLUES = (
    "simple",
    "simpler",
    "easy",
    "easier",
    "again",
    "understand",
    "clear",
    "clearer",
    "different way",
    "other words",
    "shorter",
    "brief",
    "basic",
    "plain",
    "readable",
)
# Location / farming-identity phrases that mark a statement, not a question.
_CONTEXT_CLUES = (
    "i live",
    "my farm",
    "i plant",
    "i cultivate",
    "we grow",
    "our farm",
    "based in",
    "located in",
    "farming in",
    "my village",
    "our village",
    "my area",
)
# Asks about what the bot itself can do.
_CAPABILITY_CLUES = (
    "what information",
    "what data",
    "can you tell me about",
    "what do you know",
    "what topics",
    "help me with",
    "what can you do",
)
# Agricultural concepts absent from _AGRICULTURAL_INTENT_PHRASES — a refused
# message containing one of these deserved a clarifying question instead.
_INTENT_CLUES = (
    "fertilizer",
    "pesticide",
    "irrigation",
    "soil",
    "water",
    "disease",
    "pest",
    "weed",
    "seed",
    "land",
    "farm",
    "acre",
    "perch",
    "hectare",
    "paddy",
    "field",
    "compost",
    "manure",
    "greenhouse",
)

# Per category: (clue phrases, content words an n-gram must contain to be a
# candidate). Without the content-word gate the grouper would happily propose
# "in the" as a pattern.
_CATEGORY_CLUES = {
    "reformulation": (_REFORMULATION_CLUES, _REFORMULATION_CLUES),
    "context_statement": (
        _CONTEXT_CLUES,
        (
            "live",
            "farm",
            "farming",
            "plant",
            "cultivate",
            "grow",
            "based",
            "located",
            "village",
            "area",
        ),
    ),
    "capability": (
        _CAPABILITY_CLUES,
        ("information", "data", "know", "topics", "tell", "help", "cover"),
    ),
    "agricultural_intent": (_INTENT_CLUES, _INTENT_CLUES),
}

# An n-gram ending in one of these dangles ("make it easier to"), so it is
# dropped in favour of the tighter form.
_TRAILING_STOPWORDS = frozenset(
    {
        "a",
        "an",
        "the",
        "to",
        "of",
        "in",
        "on",
        "for",
        "and",
        "or",
        "is",
        "are",
        "be",
        "it",
        "this",
        "that",
        "my",
        "our",
        "your",
        "me",
        "you",
        "i",
        "we",
        "do",
        "does",
        "can",
        "with",
        "at",
        "as",
        "but",
        "so",
        "if",
        "how",
        "what",
    }
)

# Last analysis result per process, so apply-patterns can look a proposal's
# category and evidence up server-side instead of trusting the request body.
# Two uvicorn workers means the apply may land on a worker that never ran the
# analysis, so apply falls back to re-running it (see apply_proposals).
_proposal_cache: dict[str, dict] = {}
_proposal_lock = threading.Lock()


def _now() -> datetime:
    return datetime.now(timezone.utc)


# ── Analysis (Step 2) ─────────────────────────────────────────────────────────


def analyze_pattern_gaps(days: int = _DEFAULT_DAYS) -> dict:
    """Analyze recent chat analytics and PROPOSE new routing phrases.

    Inputs: days — look-back window, clamped to 1.._MAX_DAYS.
    Outputs: {"analyzed_at", "period_days", "total_analyzed",
    "proposed_patterns": [...]} sorted by evidence, highest first. Read-only:
    saves nothing and changes no chatbot behaviour.
    Security assumption: caller is superadmin-gated at the router. Analytics
    `question` text is already sanitised (HTML-stripped, 200-char capped) by
    chatbot_service before it is written.
    """
    days = max(1, min(int(days), _MAX_DAYS))
    docs = _fetch_analytics(days)

    proposals: list = []
    known = store_mod.known_phrases()
    for category in _CATEGORY_CLUES:
        misses = _detect_misses(category, docs)
        proposals.extend(_group_misses(category, misses, known))

    proposals.sort(
        key=lambda p: (p["evidence_count"], len(p["proposed_phrase"])), reverse=True
    )

    with _proposal_lock:
        _proposal_cache.clear()
        _proposal_cache.update({p["id"]: p for p in proposals})

    store_mod.set_last_analysis()
    _notify_gaps(proposals)

    return {
        "analyzed_at": _now().isoformat(),
        "period_days": days,
        "total_analyzed": len(docs),
        "proposed_patterns": proposals,
    }


def _fetch_analytics(days: int) -> list:
    """Fetch chat_analytics docs within the window. Single-field inequality —
    no composite index needed. Returns [] on any Firestore failure, so the
    analysis degrades to "no proposals" rather than a 500."""
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
        logger.warning("pattern analysis fetch failed: %s", exc)
        return []


def _detect_misses(category: str, docs: list) -> list:
    """Messages in `docs` that carry this category's fingerprint but were routed
    elsewhere. Returns the raw question strings.

    Every category first excludes anything the LIVE predicates already catch
    (hardcoded lists plus any active override) — the point is to find what is
    missing, not to re-propose what already works.
    """
    from app.user.services.chatbot_service import (
        _has_agricultural_intent,
        _is_capability_question,
        _is_context_statement,
        _is_reformulation_request,
    )

    predicate = {
        "reformulation": _is_reformulation_request,
        "context_statement": _is_context_statement,
        "capability": _is_capability_question,
        "agricultural_intent": _has_agricultural_intent,
    }[category]

    out = []
    for doc in docs:
        question = (doc.get("question") or "").strip()
        if not question:
            continue
        if not _category_matches(category, doc, question):
            continue
        if predicate(question):
            continue  # already routed correctly today
        out.append(question)
    return out


def _category_matches(category: str, doc: dict, question: str) -> bool:
    """Apply one category's detection rules to a single analytics document."""
    msg = question.lower()
    response_type = doc.get("response_type")
    words = len(msg.split())

    if category == "reformulation":
        # A rephrase request only makes sense mid-conversation (there has to be
        # a previous bot answer to rephrase), is short, names no crop/district,
        # and reads like "say that differently".
        return (
            response_type in ("refusal", "answer")
            and int(doc.get("session_message_count") or 0) > 1
            and words < _REFORMULATION_MAX_WORDS
            and not doc.get("crop_mentioned")
            and not doc.get("district_mentioned")
            and any(c in msg for c in _REFORMULATION_CLUES)
        )

    if category == "context_statement":
        return (
            response_type in ("answer", "refusal")
            and not msg.endswith("?")
            and words < _CONTEXT_MAX_WORDS
            and any(c in msg for c in _CONTEXT_CLUES)
        )

    if category == "capability":
        return response_type in ("refusal", "answer") and any(
            c in msg for c in _CAPABILITY_CLUES
        )

    # agricultural_intent: got refused outright despite naming a farming
    # concept, so it should have been a clarifying question instead.
    return response_type == "refusal" and any(c in msg for c in _INTENT_CLUES)


# ── Grouping and ranking ──────────────────────────────────────────────────────


def _group_misses(category: str, messages: list, known: set) -> list:
    """Group missed messages into candidate phrases.

    Extracts every 2- and 3-word n-gram containing one of the category's content
    words, counts how many DISTINCT messages each covers, then greedily selects
    the best-supported ones. Each message is claimed by at most one group, so
    "make it easier" and "it easier" don't both ship as separate proposals.

    `known` is the set of (category, phrase) pairs already active or revoked —
    re-proposing those would be noise.
    """
    if not messages:
        return []

    _, content_words = _CATEGORY_CLUES[category]
    candidates: dict[str, set] = defaultdict(set)
    for index, message in enumerate(messages):
        for ngram in _ngrams(message, content_words):
            candidates[ngram].add(index)

    ranked = sorted(
        candidates.items(),
        key=lambda kv: (len(kv[1]), len(kv[0].split()), -len(kv[0])),
        reverse=True,
    )

    proposals: list = []
    claimed: set = set()
    selected_phrases: list = []
    for phrase, supporters in ranked:
        if len(proposals) >= _MAX_PROPOSALS_PER_CATEGORY:
            break
        if (category, phrase) in known:
            continue
        # Skip a phrase that merely overlaps one we already took ("it easier"
        # after "make it easier") — the tighter/better-supported one wins.
        if any(phrase in p or p in phrase for p in selected_phrases):
            continue
        fresh = supporters - claimed
        if not fresh:
            continue
        ok, _error = store_mod.validate_phrase(phrase)
        if not ok:
            continue

        evidence = len(supporters)
        confidence = _confidence(evidence)
        proposals.append(
            {
                "id": _proposal_id(category, phrase),
                "category": category,
                "proposed_phrase": phrase,
                "pattern_type": "phrase",
                "evidence_count": evidence,
                "example_messages": [messages[i] for i in sorted(supporters)][:5],
                "confidence": confidence,
                "recommended": confidence == "high",
            }
        )
        claimed |= supporters
        selected_phrases.append(phrase)
    return proposals


def _ngrams(message: str, content_words: tuple) -> set:
    """2- and 3-word n-grams of `message` that could serve as a routing phrase.

    Kept only when the n-gram contains a category content word, doesn't dangle
    on a stopword, and passes the store's phrase validator's length rules.
    """
    tokens = re.findall(r"[a-z]+", message.lower())
    out = set()
    for size in (3, 2):
        for i in range(len(tokens) - size + 1):
            window = tokens[i : i + size]
            if window[-1] in _TRAILING_STOPWORDS:
                continue
            if not any(any(c in w for c in content_words) for w in window):
                continue
            phrase = " ".join(window)
            if store_mod.MIN_PHRASE_LEN <= len(phrase) <= store_mod.MAX_PHRASE_LEN:
                out.add(phrase)
    return out


def _confidence(evidence_count: int) -> str:
    """high (5+) / medium (3-4) / low (1-2)."""
    if evidence_count >= _HIGH_CONFIDENCE_MIN:
        return "high"
    if evidence_count >= _MEDIUM_CONFIDENCE_MIN:
        return "medium"
    return "low"


def _proposal_id(category: str, phrase: str) -> str:
    """Stable id from the category prefix and a slug of the phrase. Stable
    matters: re-running the analysis must produce the same id for the same
    phrase, so an admin's selection survives a refresh."""
    prefix = store_mod.CATEGORIES[category]
    slug = re.sub(r"[^a-z0-9]+", "_", phrase.lower()).strip("_")[:32]
    return f"{prefix}_{slug}"


# ── Apply (Step 6) ────────────────────────────────────────────────────────────


def apply_proposals(
    selections: list, actor_uid: str, days: int = _DEFAULT_DAYS
) -> dict:
    """Approve a subset of proposals, honouring admin edits to the phrase.

    Inputs: selections — the request body's pattern list, each
    {"id", "phrase", "edited", "original_phrase"?}. actor_uid — the acting
    superadmin. days — window to re-derive proposals from if this worker has no
    cached analysis.
    Outputs: {"applied": [ids], "skipped": [{"id", "reason"}]}.

    Security assumptions (Step 11): the CATEGORY and evidence count are taken
    from the server-side analysis, never from the body — a client can choose
    which proposal to approve and can edit its phrase, but cannot invent a
    category or point a phrase at a different predicate. Every phrase, edited
    or not, goes through store_mod.validate_phrase before it can reach the
    routing lists. Unknown ids are skipped, not applied blindly.
    """
    known = _lookup_proposals([s.get("id") for s in selections], days)

    approved, skipped = [], []
    for selection in selections:
        pid = selection.get("id")
        proposal = known.get(pid)
        if proposal is None:
            skipped.append({"id": pid, "reason": "unknown_proposal"})
            continue
        raw_phrase = selection.get("phrase") or proposal["proposed_phrase"]
        phrase = store_mod.normalize_phrase(raw_phrase)
        ok, error = store_mod.validate_phrase(phrase)
        if not ok:
            skipped.append({"id": pid, "reason": error})
            continue
        original = proposal["proposed_phrase"]
        approved.append(
            {
                "id": pid,
                "category": proposal["category"],
                "phrase": phrase,
                "original_proposed_phrase": original,
                "edited": phrase != original,
                "evidence_count": proposal.get("evidence_count", 0),
            }
        )

    result = (
        store_mod.apply_patterns(approved, actor_uid)
        if approved
        else {
            "applied": [],
            "skipped": [],
        }
    )
    result["skipped"] = skipped + result.get("skipped", [])
    return result


def _lookup_proposals(ids: list, days: int) -> dict:
    """Resolve proposal ids to their server-derived definitions.

    Reads this worker's cache first; if any id is missing (a different uvicorn
    worker ran the analysis, or the process restarted) the analysis is re-run
    once for the window and the cache is refilled.
    """
    wanted = {i for i in ids if i}
    with _proposal_lock:
        found = {i: _proposal_cache[i] for i in wanted if i in _proposal_cache}
    if wanted - set(found):
        analyze_pattern_gaps(days)
        with _proposal_lock:
            found = {i: _proposal_cache[i] for i in wanted if i in _proposal_cache}
    return found


# ── Read side (Steps 6 and 9) ─────────────────────────────────────────────────


def get_active_patterns() -> dict:
    """Active overrides grouped by category, with hit counts and feedback.

    Outputs: {"active": [...], "by_category": {...}, "count", "revoked_count",
    "last_analysis_at", "updated_at"}. Each item carries a computed
    satisfaction_rate and verdict so the list can render its health bar without
    a per-pattern round trip.
    """
    store = store_mod.load()
    items = [_decorate(p) for p in store.get("active", [])]
    items.sort(key=lambda p: p.get("applied_at") or "", reverse=True)

    by_category: dict[str, list] = {c: [] for c in store_mod.CATEGORIES}
    for item in items:
        by_category.setdefault(item.get("category"), []).append(item)

    return {
        "active": items,
        "by_category": by_category,
        "count": len(items),
        "revoked_count": len(store.get("revoked", [])),
        "last_analysis_at": store.get("last_analysis_at"),
        "updated_at": store.get("updated_at"),
    }


def get_revoked_patterns() -> dict:
    """Revoked overrides, newest first, with their retention deadline and
    days_remaining for the countdown label."""
    store = store_mod.load()
    now = _now()
    items = []
    for item in sorted(
        store.get("revoked", []),
        key=lambda r: r.get("revoked_at") or "",
        reverse=True,
    ):
        row = dict(item)
        until = store_mod.parse_iso(item.get("retention_until"))
        row["days_remaining"] = (
            max(0, (until - now).days) if until is not None else None
        )
        items.append(row)
    return {"revoked": items, "count": len(items)}


def get_pattern_analytics(pattern_id: str) -> dict | None:
    """Per-pattern detail: counters, example hits, false-positive candidates,
    verdict.

    Outputs: the detail dict, or None when the id is neither active nor revoked
    (the router turns that into a 404).
    """
    store = store_mod.load()
    item = store_mod.find_active(store, pattern_id) or store_mod.find_revoked(
        store, pattern_id
    )
    if item is None:
        return None

    hits = store_mod.pattern_hits(store, pattern_id)
    decorated = _decorate(item)
    feedback = decorated["feedback"]

    detail = {
        "pattern": decorated,
        "hit_count": decorated["hit_count"],
        "last_hit": item.get("last_hit"),
        "feedback": feedback,
        "satisfaction_rate": decorated["satisfaction_rate"],
        "hit_rate_per_day": _hit_rate_per_day(item),
        "example_hits": [
            {
                "message": h.get("message"),
                "matched_phrase": h.get("matched_phrase"),
                "timestamp": h.get("timestamp"),
                "feedback": h.get("feedback"),
            }
            for h in hits[: store_mod.EXAMPLE_HIT_LIMIT]
        ],
        # Thumbs-down hits are the concrete evidence that a phrase is catching
        # real questions it shouldn't — exactly what an admin needs to decide
        # whether to edit or revoke.
        "false_positive_candidates": [
            {
                "message": h.get("message"),
                "feedback": "down",
                "timestamp": h.get("timestamp"),
            }
            for h in hits
            if h.get("feedback") == "down"
        ][: store_mod.EXAMPLE_HIT_LIMIT],
        "verdict": decorated["verdict"],
        "history": store_mod.pattern_history(store, pattern_id),
    }
    _notify_problematic([decorated])
    return detail


def get_pattern_health(days: int = 7) -> dict:
    """Pattern Health block for the gap report (Step 9).

    Inputs: days — the gap report's window, used for "hits this period".
    Outputs: counts, period hits, average satisfaction across rated overrides,
    how many need review, and when the analysis last ran. Never raises — a
    failure yields a zeroed block so the gap report still renders.
    """
    try:
        store = store_mod.load()
        active = [_decorate(p) for p in store.get("active", [])]
        cutoff = _now() - timedelta(days=max(1, int(days)))
        period_hits = 0
        for hit in store.get("hits", []):
            stamp = store_mod.parse_iso(hit.get("timestamp"))
            if stamp is not None and stamp >= cutoff:
                period_hits += 1

        rated = [p for p in active if p["rated_count"] > 0]
        avg_satisfaction = (
            round(sum(p["satisfaction_rate"] for p in rated) / len(rated), 2)
            if rated
            else 0.0
        )
        needs_review = sum(
            1 for p in active if p["verdict"] in ("needs_review", "likely_problematic")
        )
        _notify_problematic(active)
        return {
            "active_count": len(active),
            "revoked_count": len(store.get("revoked", [])),
            "total_hits": sum(p["hit_count"] for p in active),
            "hits_this_period": period_hits,
            "avg_satisfaction": avg_satisfaction,
            "needs_review_count": needs_review,
            "last_analysis_at": store.get("last_analysis_at"),
        }
    except Exception as exc:
        logger.warning("pattern health build failed: %s", exc)
        return {
            "active_count": 0,
            "revoked_count": 0,
            "total_hits": 0,
            "hits_this_period": 0,
            "avg_satisfaction": 0.0,
            "needs_review_count": 0,
            "last_analysis_at": None,
        }


def _decorate(item: dict) -> dict:
    """Add computed satisfaction_rate, rated_count and verdict to a stored
    override, without mutating the store's dict."""
    row = dict(item)
    fb = dict(row.get("feedback") or {})
    up = int(fb.get("thumbs_up", 0))
    down = int(fb.get("thumbs_down", 0))
    hit_count = int(row.get("hit_count", 0))
    rated = up + down
    fb.setdefault("thumbs_up", up)
    fb.setdefault("thumbs_down", down)
    fb["no_feedback"] = max(0, hit_count - rated)
    row["feedback"] = fb
    row["hit_count"] = hit_count
    row["rated_count"] = rated
    row["satisfaction_rate"] = round(up / rated, 2) if rated else 0.0
    row["verdict"] = _verdict(hit_count, rated, row["satisfaction_rate"], down)
    return row


def _verdict(hit_count: int, rated: int, satisfaction: float, thumbs_down: int) -> str:
    """working_well / needs_review / likely_problematic / insufficient_data.

    `rated == 0` also counts as insufficient data, not as 0% satisfaction — an
    unrated pattern with 20 clean hits must not be labelled problematic purely
    for never having been thumbed.
    """
    if hit_count < 5 or rated == 0:
        return "insufficient_data"
    if satisfaction < 0.4:
        return "likely_problematic"
    if satisfaction < 0.7 or thumbs_down >= 3:
        return "needs_review"
    return "working_well"


def _hit_rate_per_day(item: dict) -> float:
    """Average hits per day since the override went live. Uses a 1-day floor so
    a pattern applied an hour ago doesn't report an absurd rate."""
    applied = store_mod.parse_iso(item.get("applied_at"))
    if applied is None:
        return 0.0
    elapsed_days = max(1.0, (_now() - applied).total_seconds() / 86400.0)
    return round(int(item.get("hit_count", 0)) / elapsed_days, 2)


# ── Notifications (Step 10) ───────────────────────────────────────────────────


def _notify_gaps(proposals: list) -> None:
    """Notify when a single category yields 5+ high-confidence proposals.

    Deduped per category over 24h, so re-running the analysis three times in an
    afternoon doesn't produce three identical cards. Best-effort.
    """
    try:
        from app.admin.services.notification_service import create_notification

        counts: dict[str, int] = defaultdict(int)
        for proposal in proposals:
            if proposal.get("confidence") == "high":
                counts[proposal["category"]] += 1

        recent = _recent_notification_targets("pattern_gaps_detected")
        for category, count in counts.items():
            if count < _HIGH_CONFIDENCE_MIN or category in recent:
                continue
            label = category.replace("_", " ")
            create_notification(
                "pattern_gaps_detected",
                "Pattern gaps detected",
                f"{count} potential {label} patterns found. "
                "Review in Pattern Management.",
                severity="info",
                related_id=category,
                action_url="/pattern-management",
            )
    except Exception as exc:
        logger.debug("pattern gap notification skipped: %s", exc)


def _notify_problematic(patterns: list) -> None:
    """Notify when an active override's verdict reads likely_problematic.

    Deduped per pattern id over 24h. Best-effort — this runs off the gap report
    and detail reads, neither of which may fail because of a notification.
    """
    try:
        from app.admin.services.notification_service import create_notification

        flagged = [p for p in patterns if p.get("verdict") == "likely_problematic"]
        if not flagged:
            return
        recent = _recent_notification_targets("pattern_problematic")
        for pattern in flagged:
            pid = pattern.get("id")
            if not pid or pid in recent:
                continue
            create_notification(
                "pattern_problematic",
                "Pattern may need revoking",
                f"'{pattern.get('phrase')}' has "
                f"{round(pattern.get('satisfaction_rate', 0.0) * 100)}% "
                f"satisfaction after {pattern.get('hit_count', 0)} matches. "
                "Review recommended.",
                severity="warning",
                related_id=pid,
                action_url=f"/pattern-management/{pid}",
            )
    except Exception as exc:
        logger.debug("problematic pattern notification skipped: %s", exc)


def _recent_notification_targets(type_: str, within_hours: int = 24) -> set:
    """related_id values already notified for this type inside the window — the
    dedup key. Returns an empty set on failure, biasing toward notifying (a
    rare duplicate beats a silently dropped alert), matching the policy in
    notification_service._recent_types."""
    try:
        from app.admin.services.notification_service import get_notifications

        cutoff = _now() - timedelta(hours=within_hours)
        out = set()
        for notification in get_notifications(limit=100):
            if notification.get("type") != type_:
                continue
            created = store_mod.parse_iso(notification.get("created_at"))
            if created is None or created >= cutoff:
                out.add(notification.get("related_id"))
        return out
    except Exception as exc:
        logger.debug("notification dedup lookup failed: %s", exc)
        return set()
