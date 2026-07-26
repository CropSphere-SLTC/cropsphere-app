"""Prompt tuning from usage analytics — proposes supplementary system-prompt
instructions from real chat_analytics + chat_feedback patterns.

Build-time / admin-triggered, review-gated: analyze_and_generate_tuning() only
PROPOSES adjustments; nothing reaches the live prompt until an admin approves a
subset via the apply endpoint (see admin_router). Approved adjustments enter a
TRIAL: each carries a `validation_metric` and the `baseline_value` measured
over the window it was proposed from, so tuning_validation_service can later
decide whether it actually helped (see prompt_tuning_store for the lifecycle).

This module owns ANALYSIS only. Persistence and state transitions live in
prompt_tuning_store; measurement and auto-validation in
app.admin.services.tuning_validation_service.

SAFETY (never violated by construction):
- Every adjustment's instruction comes from a FIXED template keyed by dimension
  — never free-form model/user text — so tuning can only ADD guidance.
- It never modifies Part A grounding rules, the refusal text, the 'Reasoning:'
  prefix, the no-calculations rule, or the earnings-offer anchor phrase.
- User-derived strings (missing crop/district names) are whitelisted to letters
  before being embedded, so a crafted "crop" name can't inject instructions.

Best-effort on Firestore: with no DB (or too little data) it returns an empty
adjustment list, and the chatbot runs on its static prompt unchanged.
"""

import logging
import re
from datetime import datetime, timezone

from app.user.services.prompt_tuning_store import TUNING_PATH  # noqa: F401 (re-export)

logger = logging.getLogger(__name__)

_DEFAULT_DAYS = 7
# Below this many interactions in the window, usage signal is noise — propose
# nothing. Tuning the prompt off a handful of chats does more harm than good.
_MIN_SAMPLE = 30
# Dimension 2 needs enough votes per question_type before a low satisfaction
# rate is meaningful (one downvote shouldn't read as "0% satisfaction").
_MIN_TYPE_VOTES = 5
# Dimension 5 proxy needs a floor of yield/price answers before a low
# earnings-follow-through ratio means anything.
_MIN_EARNINGS_OFFERS = 10
# Cap missing-topic adjustments so the injection can't balloon.
_MAX_MISSING = 3

_BEGINNER_FRAC = 0.70
_ADVANCED_FRAC = 0.50
_SATISFACTION_FLOOR = 0.60
_MISSING_MIN_REQUESTS = 5
_SHORT_SESSION = 2.0
_CHIP_HIGH = 0.50
_CHIP_LOW = 0.10
_EARNINGS_FOLLOW_FLOOR = 0.10

# Only names matching this may be embedded into an injected instruction
# (Dimension 3). Blocks prompt injection via a crafted crop/district string.
_SAFE_NAME = re.compile(r"^[A-Za-z][A-Za-z ]{0,29}$")

# Dimension 2 — per-question_type remediation, keyed by _question_type output.
_PROBLEM_INSTRUCTIONS = {
    "earnings": (
        "Pay extra attention to earnings calculations. Show only the final "
        "number. Make sure the unit matches what the farmer specified."
    ),
    "yield": (
        "When answering yield questions, always mention which season gives "
        "the best results, not just the numbers."
    ),
    "season": (
        "When recommending a season, explain WHY that season is best, not "
        "just which one."
    ),
    "price": (
        "For price questions, give both the selling price at the farm and "
        "the shop price, and note that prices shift with the season."
    ),
    "general": (
        "For general questions, add one short practical tip a farmer can act "
        "on — not just facts."
    ),
}


def analyze_and_generate_tuning(days: int = _DEFAULT_DAYS) -> dict:
    """Analyze the last `days` of analytics + feedback and PROPOSE prompt
    tuning adjustments. Does not save or apply anything.

    Inputs: days (clamped 1..30 by the underlying fetch window).
    Outputs: {updated_at, period_days, sample_size, adjustments: [...]}, where
    each adjustment is {id, dimension, trigger, instruction, recommended}. Only
    dimensions that actually trigger are included; below _MIN_SAMPLE
    interactions the list is empty. Never raises — returns an empty proposal on
    any Firestore/aggregation failure.
    Security: user-derived names are whitelisted before embedding; instruction
    text is always from a fixed template, never model or user free-text.
    """
    now = datetime.now(timezone.utc).isoformat()
    try:
        metrics = _aggregate(days)
    except Exception as exc:
        logger.warning("prompt-tuning aggregation failed: %s", exc)
        return {
            "updated_at": now,
            "period_days": days,
            "sample_size": 0,
            "adjustments": [],
        }

    sample = metrics["sample_size"]
    adjustments: list = []
    if sample >= _MIN_SAMPLE:
        adjustments.extend(_dim_language(metrics))
        adjustments.extend(_dim_problem_areas(metrics))
        adjustments.extend(_dim_missing(metrics))
        adjustments.extend(_dim_conversation(metrics))
        adjustments.extend(_dim_earnings(metrics))

    return {
        "updated_at": now,
        "period_days": days,
        "sample_size": sample,
        "adjustments": adjustments,
    }


def _aggregate(days: int) -> dict:
    """One pass over the window's analytics + feedback docs, producing every
    metric the five dimensions need. Reuses gap_report_service's fetch helpers
    and the dataset capability sets so the two features stay in sync."""
    from app.admin.services.gap_report_service import (
        _fetch_documents,
        _fetch_feedback,
    )
    from app.user.services.chatbot_service import (
        _dataset_capabilities,
        _detect_knowledge_level,
        _question_type,
    )
    from app.utils.firestore import get_db

    db = get_db()
    docs = _fetch_documents(db, days)
    feedback = _fetch_feedback(db, days)
    caps = _dataset_capabilities()
    covered_crops = set(caps["crops"])
    covered_districts = set(caps["districts"])

    knowledge = {"beginner": 0, "intermediate": 0, "advanced": 0}
    type_counts: dict = {}
    missing_crops: dict = {}
    missing_districts: dict = {}
    # Per-uncovered-topic {mentions, refusals} — the Dimension 3 baseline is a
    # refusal RATE, so the denominator has to be counted here too.
    topic_stats: dict = {}
    slen_sum = slen_n = 0
    chip_taps = 0

    for d in docs:
        level = d.get("knowledge_level")
        if level in knowledge:
            knowledge[level] += 1

        qtype = d.get("question_type")
        if qtype:
            type_counts[qtype] = type_counts.get(qtype, 0) + 1

        refused = d.get("response_type") in ("refusal", "near_miss")
        crop = d.get("crop_mentioned")
        if crop and crop not in covered_crops:
            missing_crops[crop] = missing_crops.get(crop, 0) + 1
            _bump_topic(topic_stats, crop, refused)
        district = d.get("district_mentioned")
        if district and district not in covered_districts:
            missing_districts[district] = missing_districts.get(district, 0) + 1
            _bump_topic(topic_stats, district, refused)

        slen = d.get("session_message_count")
        if isinstance(slen, (int, float)):
            slen_sum += slen
            slen_n += 1
        if d.get("followup_chip_tapped") is True:
            chip_taps += 1

    # Dimensions 1-2: feedback carries neither question_type nor
    # knowledge_level, so each vote's stored message_text is classified with
    # the same helpers the analytics writer used. type_votes drives the
    # Dimension 2 trigger; level_votes supplies the Dimension 1 baseline.
    type_votes: dict = {}
    level_votes: dict = {}
    for f in feedback:
        vote = f.get("feedback")
        if vote not in ("up", "down"):
            continue
        text = f.get("message_text") or ""
        type_votes.setdefault(_question_type(text), {"up": 0, "down": 0})[vote] += 1
        level_votes.setdefault(_detect_knowledge_level(text, []), {"up": 0, "down": 0})[
            vote
        ] += 1

    total = len(docs)
    return {
        "sample_size": total,
        "knowledge": knowledge,
        "type_counts": type_counts,
        "type_votes": type_votes,
        "level_votes": level_votes,
        "missing_crops": missing_crops,
        "missing_districts": missing_districts,
        "topic_stats": topic_stats,
        "avg_session_length": (slen_sum / slen_n) if slen_n else 0.0,
        "chip_tap_rate": (chip_taps / total) if total else 0.0,
    }


def _bump_topic(stats: dict, name: str, refused: bool) -> None:
    """Count one mention (and possibly one refusal) for an uncovered topic."""
    bucket = stats.setdefault(name, {"mentions": 0, "refusals": 0})
    bucket["mentions"] += 1
    if refused:
        bucket["refusals"] += 1


# Minimum denominator before a baseline value is trustworthy. Below it the
# baseline is None, which makes the adjustment unmeasurable — it is applied as
# a trial with no auto-validation clock and waits for an admin decision
# (Step 10: never auto-promote what the system can't measure).
_MIN_BASELINE_DENOMINATOR = 5


def _rate(votes: dict | None) -> float | None:
    """Satisfaction rate from an {up, down} bucket, or None if too thin."""
    if not votes:
        return None
    total = votes.get("up", 0) + votes.get("down", 0)
    if total < _MIN_BASELINE_DENOMINATOR:
        return None
    return round(votes["up"] / total, 4)


def _pct(x: float) -> int:
    """Whole-percent for trigger strings."""
    return int(round(x * 100))


def _dim_language(m: dict) -> list:
    """Dimension 1 — default complexity from the knowledge-level mix.

    Validation metric: satisfaction rate for the DOMINANT level — if we tell
    the bot to simplify because most users are beginners, beginners are who
    should end up happier.
    """
    k = m["knowledge"]
    graded = k["beginner"] + k["intermediate"] + k["advanced"]
    if not graded:
        return []
    level_votes = m.get("level_votes", {})
    beginner = k["beginner"] / graded
    advanced = k["advanced"] / graded
    if beginner > _BEGINNER_FRAC:
        return [
            {
                "id": "language_complexity",
                "dimension": "language_complexity",
                "trigger": (
                    f"{_pct(beginner)}% beginner users "
                    f"(threshold: {_pct(_BEGINNER_FRAC)}%)"
                ),
                "instruction": (
                    "Most of your users are new to farming. Default to the "
                    "simplest possible explanations."
                ),
                "recommended": True,
                "validation_metric": "beginner_satisfaction_rate",
                "baseline_value": _rate(level_votes.get("beginner")),
            }
        ]
    if advanced > _ADVANCED_FRAC:
        return [
            {
                "id": "language_complexity",
                "dimension": "language_complexity",
                "trigger": (
                    f"{_pct(advanced)}% advanced users "
                    f"(threshold: {_pct(_ADVANCED_FRAC)}%)"
                ),
                "instruction": (
                    "Most of your users are experienced farmers. You can be more "
                    "concise and data-focused."
                ),
                "recommended": True,
                "validation_metric": "advanced_satisfaction_rate",
                "baseline_value": _rate(level_votes.get("advanced")),
            }
        ]
    return []


def _dim_problem_areas(m: dict) -> list:
    """Dimension 2 — per-type remediation where satisfaction < floor."""
    out: list = []
    for qtype, votes in sorted(m["type_votes"].items()):
        total = votes["up"] + votes["down"]
        if total < _MIN_TYPE_VOTES:
            continue
        satisfaction = votes["up"] / total
        if satisfaction >= _SATISFACTION_FLOOR:
            continue
        instruction = _PROBLEM_INSTRUCTIONS.get(qtype)
        if not instruction:
            continue
        out.append(
            {
                "id": f"problem_{qtype}",
                "dimension": "problem_areas",
                "trigger": (
                    f"{qtype} satisfaction {_pct(satisfaction)}% "
                    f"(threshold: {_pct(_SATISFACTION_FLOOR)}%)"
                ),
                "instruction": instruction,
                "recommended": True,
                # Validated against the same per-type satisfaction rate that
                # triggered it — the number the instruction is meant to lift.
                "validation_metric": f"satisfaction_rate_{qtype}",
                "baseline_value": round(satisfaction, 4),
            }
        )
    return out


def _dim_missing(m: dict) -> list:
    """Dimension 3 — proactively acknowledge frequently-requested uncovered
    topics. Reframed from the spec's 'edit the refusal template' to a
    supplementary instruction, because Step 8 forbids touching the refusal
    text. Names are whitelisted before embedding (prompt-injection guard)."""
    combined = [("crop", n, c) for n, c in m["missing_crops"].items()]
    combined += [("district", n, c) for n, c in m["missing_districts"].items()]
    combined = [x for x in combined if x[2] > _MISSING_MIN_REQUESTS]
    combined.sort(key=lambda x: x[2], reverse=True)

    stats = m.get("topic_stats", {})
    out: list = []
    for kind, name, count in combined[:_MAX_MISSING]:
        clean = (name or "").strip()
        if not _SAFE_NAME.match(clean):
            continue
        slug = clean.lower().replace(" ", "_")
        topic = stats.get(name, {})
        mentions = topic.get("mentions", 0)
        # Lower is better here: a warm acknowledgement should turn some flat
        # refusals into useful near-misses. See tuning_validation_service.
        baseline = (
            round(topic["refusals"] / mentions, 4)
            if mentions >= _MIN_BASELINE_DENOMINATOR
            else None
        )
        out.append(
            {
                "id": f"missing_{slug}",
                "dimension": "missing_topics",
                "trigger": (
                    f"{clean} requested {count} times "
                    f"(threshold: >{_MISSING_MIN_REQUESTS})"
                ),
                "instruction": (
                    f"Many farmers ask about {clean} — we don't have {clean} "
                    "data yet, but it's coming. If asked, acknowledge this "
                    "warmly instead of only refusing."
                ),
                "recommended": True,
                "validation_metric": "refusal_rate",
                "validation_target": clean,
                "baseline_value": baseline,
                "_kind": kind,
            }
        )
    return out


def _dim_conversation(m: dict) -> list:
    """Dimension 4 — engagement tweaks from session length and chip usage."""
    out: list = []
    if 0 < m["avg_session_length"] < _SHORT_SESSION:
        out.append(
            {
                "id": "engagement_short",
                "dimension": "conversation_patterns",
                "trigger": (
                    f"avg session {round(m['avg_session_length'], 1)} msgs "
                    f"(threshold: <{_SHORT_SESSION})"
                ),
                "instruction": (
                    "Always end your answer with an engaging follow-up question "
                    "to keep the conversation going."
                ),
                "recommended": True,
                "validation_metric": "avg_session_length",
                "baseline_value": round(m["avg_session_length"], 4),
            }
        )
    rate = m["chip_tap_rate"]
    if rate > _CHIP_HIGH:
        out.append(
            {
                "id": "chip_high",
                "dimension": "conversation_patterns",
                "trigger": (
                    f"chip tap rate {_pct(rate)}% " f"(threshold: >{_pct(_CHIP_HIGH)}%)"
                ),
                "instruction": (
                    "Followup suggestions are working well — make sure your "
                    "answers naturally lead to the suggested next questions."
                ),
                "recommended": True,
                "validation_metric": "chip_tap_rate",
                "baseline_value": round(rate, 4),
            }
        )
    elif rate < _CHIP_LOW:
        out.append(
            {
                "id": "chip_low",
                "dimension": "conversation_patterns",
                "trigger": (
                    f"chip tap rate {_pct(rate)}% " f"(threshold: <{_pct(_CHIP_LOW)}%)"
                ),
                "instruction": (
                    "Farmers prefer typing their own questions. Focus on giving "
                    "complete answers that don't require follow-ups."
                ),
                "recommended": True,
                # Chip taps are the wrong success signal for this one — the
                # instruction deliberately reduces reliance on chips — so it is
                # validated on whether conversations stay as long.
                "validation_metric": "avg_session_length",
                "baseline_value": round(m["avg_session_length"], 4),
            }
        )
    return out


def _dim_earnings(m: dict) -> list:
    """Dimension 5 — earnings-offer effectiveness. APPROXIMATE: analytics does
    not record offers or their uptake, so this proxies yield+price answers as
    'offers' and earnings questions as 'follow-ups'. Marked recommended=False
    so an admin opts in consciously. The instruction preserves the land-size
    anchor phrase (Step 8: never override the earnings anchor)."""
    tc = m["type_counts"]
    offers = tc.get("yield", 0) + tc.get("price", 0)
    follows = tc.get("earnings", 0)
    if offers < _MIN_EARNINGS_OFFERS:
        return []
    ratio = follows / offers
    if ratio >= _EARNINGS_FOLLOW_FLOOR:
        return []
    return [
        {
            "id": "earnings_offer",
            "dimension": "earnings_effectiveness",
            "trigger": (
                f"~{_pct(ratio)}% earnings follow-through (approx, "
                f"threshold: <{_pct(_EARNINGS_FOLLOW_FLOOR)}%)"
            ),
            "validation_metric": "earnings_followup_rate",
            "baseline_value": round(ratio, 4),
            "instruction": (
                "The earnings offer isn't resonating. Make it more specific: "
                "instead of a generic offer, say something like 'For your 2 "
                "acres, that could mean around X LKR — want me to calculate it "
                "exactly?'. Still invite them to tell you their land size so the "
                "calculation can proceed."
            ),
            "recommended": False,
        }
    ]


# ── Persistence (thin wrappers over prompt_tuning_store) ──────────────────────
#
# State lives in prompt_tuning_store; these keep the service's public surface
# stable for the routers and give apply_approved its "re-derive server-side"
# guarantee.


def load_active_tuning() -> dict:
    """The live adjustments (status trial or permanent) plus store metadata.

    Outputs: {updated_at, adjustments: [...], trash_count}. `adjustments` is
    exactly what the chatbot injects — nothing trashed or auto-removed.
    """
    from app.user.services import prompt_tuning_store as store_mod

    store = store_mod.load()
    return {
        "updated_at": store.get("updated_at"),
        "adjustments": store_mod.live_adjustments(store),
        "trash_count": len(store.get("trash", [])),
    }


def apply_approved(
    approved_ids: list,
    days: int = _DEFAULT_DAYS,
    actor_uid: str = "",
    trial_period_days: int | None = None,
) -> dict:
    """Re-run the analysis and start a TRIAL for each approved adjustment.

    Inputs: approved_ids — the ids the admin ticked; days — the same window
    they reviewed; actor_uid — for the audit trail; trial_period_days —
    optional override of the configured trial length.
    Outputs: {applied: [ids], skipped: [ids], adjustments: [...]}.
    Security assumption: the instructions persisted are re-derived here from
    the fixed dimension templates, never taken from the client body — an
    approved id that no longer triggers is simply dropped, and one that is
    already active is skipped rather than duplicated.
    """
    from app.admin.services.system_config_service import get_prompt_tuning_config
    from app.user.services import prompt_tuning_store as store_mod

    proposal = analyze_and_generate_tuning(days)
    for adj in proposal["adjustments"]:
        adj["period_days"] = proposal["period_days"]

    result = store_mod.apply_adjustments(
        proposal["adjustments"],
        approved_ids,
        actor_uid=actor_uid,
        config=get_prompt_tuning_config(),
        trial_period_days=trial_period_days,
    )
    result["adjustments"] = store_mod.live_adjustments()
    return result


def clear_tuning(actor_uid: str = "", comment: str = "Cleared all tuning") -> dict:
    """Move every active adjustment to the trash — the chatbot reverts to its
    static prompt on the next cache reload. Reversible until retention expires
    (see prompt_tuning_store.restore)."""
    from app.user.services import prompt_tuning_store as store_mod

    return store_mod.clear_all(actor_uid, comment)
