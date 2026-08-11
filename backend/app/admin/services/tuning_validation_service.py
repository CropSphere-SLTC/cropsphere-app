"""Auto-validation for prompt-tuning trials — did the adjustment actually help?

Each applied adjustment carries a `validation_metric` and the `baseline_value`
measured over the window it was proposed from. When its trial ends, this module
re-measures the same metric over the trial window and decides:

    enough data + improved/stable  → permanent
    enough data + declined >5%     → trashed (auto_validation_failed) + notify
    not enough data                → extend the trial (max 2 times), then notify

The pass is triggered opportunistically from the chat path (see
maybe_run_validations) because this deployment has no scheduler. The trigger
itself is a date comparison against an already-cached dict — zero I/O — and the
actual Firestore work runs on a background thread, so a chat response is never
delayed by validation.

Measurement mirrors gap_report_service: pull the window's documents in one
query and aggregate in Python (Firestore has no GROUP BY). chat_feedback stores
no knowledge_level or question_type, so votes are classified from the stored
message_text with the same chatbot_service helpers the analytics path uses.
"""

import logging
import threading
import time
from datetime import datetime, timedelta, timezone

logger = logging.getLogger(__name__)

# Relative change (vs baseline) inside ±_STABLE_MARGIN counts as "stable" and
# still promotes — Step 4 treats stable as a pass, not a failure.
_STABLE_MARGIN = 0.05

# A metric needs at least this many observations in its denominator before its
# value means anything; below it, measurement returns None ("can't measure")
# and the trial is extended rather than judged on noise.
_MIN_METRIC_DENOMINATOR = 5

# maybe_run_validations() is called per chat request; the real pass costs two
# Firestore scans, so it runs at most once per interval per worker.
_RUN_INTERVAL_SECONDS = 300

# "Never run yet" sentinel. Must be -inf, NOT 0.0: the throttle compares against
# time.monotonic(), whose epoch is arbitrary, so on a freshly-booted host
# monotonic() can be < _RUN_INTERVAL_SECONDS and `now - 0.0` would wrongly read
# as "throttled", suppressing the very first validation for up to 5 minutes.
_last_run_at = float("-inf")
_run_lock = threading.Lock()
_running = False

# Metrics where a LOWER value is better (everything else: higher is better).
_LOWER_IS_BETTER = frozenset({"refusal_rate"})

_KNOWLEDGE_METRICS = {
    "beginner_satisfaction_rate": "beginner",
    "intermediate_satisfaction_rate": "intermediate",
    "advanced_satisfaction_rate": "advanced",
}


def _now() -> datetime:
    return datetime.now(timezone.utc)


# ── Measurement ───────────────────────────────────────────────────────────────


def _fetch(collection: str, since: datetime, until: datetime | None = None) -> list:
    """Fetch a collection's docs in [since, until). Single-field inequality —
    no composite index needed. Raises on Firestore error (callers catch)."""
    from google.cloud.firestore_v1.base_query import FieldFilter

    from app.utils.firestore import get_db

    query = (
        get_db()
        .collection(collection)
        .where(filter=FieldFilter("timestamp", ">=", since))
    )
    if until is not None:
        query = query.where(filter=FieldFilter("timestamp", "<", until))
    return [doc.to_dict() for doc in query.stream()]


def count_interactions(since: datetime, until: datetime | None = None) -> int:
    """Number of chat_analytics documents in the window. This is the sample
    size the trial is judged against. Returns 0 on any Firestore failure."""
    try:
        return len(_fetch("chat_analytics", since, until))
    except Exception as exc:
        logger.warning("interaction count failed: %s", exc)
        return 0


def measure_metric(
    metric: str,
    target: str | None,
    since: datetime,
    until: datetime | None = None,
) -> float | None:
    """Measure one validation metric over a time window.

    Inputs: metric — the metric name stored on the adjustment; target — the
    crop/district name for refusal_rate, else None; since/until — the window.
    Outputs: the measured value, or None when the metric is unknown, the
    window is empty, or the denominator is below _MIN_METRIC_DENOMINATOR.
    None always means "can't measure", never "measured zero" — the caller must
    distinguish the two, because Step 10 forbids auto-promoting what we can't
    measure. Never raises.
    Security assumption: `target` is a whitelisted name captured at proposal
    time (see prompt_tuning_service._SAFE_NAME) and is only compared against
    stored analytics fields, never interpolated into a query string.
    """
    if not metric:
        return None
    try:
        if metric in _KNOWLEDGE_METRICS or metric.startswith("satisfaction_rate"):
            return _measure_feedback_metric(metric, since, until)
        if metric == "refusal_rate":
            return _measure_refusal_rate(target, since, until)
        if metric in ("avg_session_length", "chip_tap_rate", "earnings_followup_rate"):
            return _measure_analytics_metric(metric, since, until)
    except Exception as exc:
        logger.warning("metric measurement failed (%s): %s", metric, exc)
    return None


def _measure_feedback_metric(
    metric: str, since: datetime, until: datetime | None
) -> float | None:
    """Satisfaction rate for one knowledge level or one question type.

    chat_feedback carries neither field, so each vote's stored message_text is
    re-classified with the same helpers the analytics writer used — the vote is
    attributed to the bucket its question belongs to.
    """
    from app.user.services.chatbot_service import (
        _detect_knowledge_level,
        _question_type,
    )

    docs = _fetch("chat_feedback", since, until)
    if metric in _KNOWLEDGE_METRICS:
        wanted = _KNOWLEDGE_METRICS[metric]

        def classify(text):
            return _detect_knowledge_level(text, [])

    else:
        wanted = metric[len("satisfaction_rate_") :]
        classify = _question_type

    up = down = 0
    for doc in docs:
        vote = doc.get("feedback")
        if vote not in ("up", "down"):
            continue
        if classify(doc.get("message_text") or "") != wanted:
            continue
        if vote == "up":
            up += 1
        else:
            down += 1

    total = up + down
    return (up / total) if total >= _MIN_METRIC_DENOMINATOR else None


def _measure_refusal_rate(
    target: str | None, since: datetime, until: datetime | None
) -> float | None:
    """Share of interactions mentioning `target` that ended in a refusal or
    near-miss. Falls back to the overall refusal rate when no target is set."""
    docs = _fetch("chat_analytics", since, until)
    wanted = (target or "").strip().lower()

    mentions = refusals = 0
    for doc in docs:
        if wanted:
            crop = (doc.get("crop_mentioned") or "").strip().lower()
            district = (doc.get("district_mentioned") or "").strip().lower()
            if wanted not in (crop, district):
                continue
        mentions += 1
        if doc.get("response_type") in ("refusal", "near_miss"):
            refusals += 1

    return (refusals / mentions) if mentions >= _MIN_METRIC_DENOMINATOR else None


def _measure_analytics_metric(
    metric: str, since: datetime, until: datetime | None
) -> float | None:
    """Engagement metrics straight off chat_analytics."""
    from app.user.services.chatbot_service import _question_type

    docs = _fetch("chat_analytics", since, until)
    total = len(docs)
    if total < _MIN_METRIC_DENOMINATOR:
        return None

    if metric == "chip_tap_rate":
        taps = sum(1 for d in docs if d.get("followup_chip_tapped") is True)
        return taps / total

    if metric == "avg_session_length":
        values = [
            d["session_message_count"]
            for d in docs
            if isinstance(d.get("session_message_count"), (int, float))
        ]
        return (
            (sum(values) / len(values))
            if len(values) >= _MIN_METRIC_DENOMINATOR
            else None
        )

    # earnings_followup_rate — same proxy the Dimension 5 proposal uses:
    # earnings questions per yield/price answer (analytics records no offers).
    counts: dict = {}
    for d in docs:
        qtype = d.get("question_type") or _question_type(d.get("question") or "")
        counts[qtype] = counts.get(qtype, 0) + 1
    offers = counts.get("yield", 0) + counts.get("price", 0)
    if offers < _MIN_METRIC_DENOMINATOR:
        return None
    return counts.get("earnings", 0) / offers


# ── Comparison ────────────────────────────────────────────────────────────────


def compare(metric: str, baseline, current) -> dict:
    """Compare a measured value against its baseline, direction-aware.

    Outputs: {"trend": improving|stable|worsened|unknown, "relative_change":
    float|None, "direction": higher_is_better|lower_is_better}. relative_change
    is signed so that POSITIVE always means "better", regardless of which way
    the raw metric moves — refusal_rate falling from 0.4 to 0.2 reports +0.5.
    A zero baseline is compared on absolute movement instead (no division).
    """
    direction = "lower_is_better" if metric in _LOWER_IS_BETTER else "higher_is_better"
    if not isinstance(baseline, (int, float)) or not isinstance(current, (int, float)):
        return {"trend": "unknown", "relative_change": None, "direction": direction}

    delta = (
        (current - baseline)
        if direction == "higher_is_better"
        else (baseline - current)
    )
    if baseline == 0:
        # No ratio to take: treat any movement beyond the margin as real.
        relative = 0.0 if abs(delta) <= _STABLE_MARGIN else (1.0 if delta > 0 else -1.0)
    else:
        relative = delta / abs(baseline)

    if relative >= _STABLE_MARGIN:
        trend = "improving"
    elif relative <= -_STABLE_MARGIN:
        trend = "worsened"
    else:
        trend = "stable"
    return {
        "trend": trend,
        "relative_change": round(relative, 4),
        "direction": direction,
    }


# ── The validation pass ───────────────────────────────────────────────────────


def has_due_trials(store: dict) -> bool:
    """Cheap, I/O-free check: is any active trial past its trial_ends_at?

    Called on the chat path against the already-cached tuning dict. An
    adjustment with trial_ends_at=None (no measurable metric) is never due —
    it waits for an admin decision.
    """
    from app.user.services.prompt_tuning_store import parse_iso

    now = _now()
    for adj in (store or {}).get("active", []):
        if adj.get("status") != "trial":
            continue
        ends_at = parse_iso(adj.get("trial_ends_at"))
        if ends_at is not None and ends_at <= now:
            return True
    return False


def maybe_run_validations(store: dict) -> bool:
    """Trigger a validation pass if one is due and none ran recently.

    Inputs: store — the cached tuning dict (no disk read).
    Outputs: True if a pass was started. The pass itself runs on a daemon
    thread and never raises into the caller, mirroring the fire-and-forget
    analytics writes — validation must never slow or break a chat response.
    """
    global _last_run_at, _running
    if not has_due_trials(store):
        return False

    now = time.monotonic()
    with _run_lock:
        if _running or (now - _last_run_at) < _RUN_INTERVAL_SECONDS:
            return False
        _running = True
        _last_run_at = now

    def _worker():
        global _running
        try:
            run_due_validations()
        except Exception as exc:
            logger.warning("prompt-tuning validation pass failed: %s", exc)
        finally:
            with _run_lock:
                _running = False

    threading.Thread(target=_worker, daemon=True, name="tuning-validation").start()
    return True


def run_due_validations() -> dict:
    """Validate every active trial whose trial_ends_at has passed, and purge
    expired trash in the same sweep.

    Outputs: {"promoted": [...], "removed": [...], "extended": [...],
    "flagged": [...], "purged": [...]} — adjustment ids per outcome.
    Never raises; per-adjustment failures are logged and skipped so one bad
    record can't stall the rest.
    """
    from app.admin.services.system_config_service import get_prompt_tuning_config
    from app.user.services import prompt_tuning_store as store_mod

    config = get_prompt_tuning_config()
    store = store_mod.load()
    now = _now()
    out = {
        "promoted": [],
        "removed": [],
        "extended": [],
        "flagged": [],
        "purged": [],
    }

    for adj in list(store.get("active", [])):
        if adj.get("status") != "trial":
            continue
        ends_at = store_mod.parse_iso(adj.get("trial_ends_at"))
        if ends_at is None or ends_at > now:
            continue
        try:
            _validate_one(adj, config, now, out)
        except Exception as exc:
            logger.warning(
                "validation failed for adjustment %s: %s", adj.get("id"), exc
            )

    purged = store_mod.purge_expired_trash()
    out["purged"] = purged.get("deleted", [])

    if any(out.values()):
        logger.info("prompt-tuning validation pass: %s", out)
    _reload_chatbot_cache()
    return out


def _validate_one(adj: dict, config: dict, now: datetime, out: dict) -> None:
    """Decide one trial's fate. Mutates `out` with the outcome."""
    from app.user.services import prompt_tuning_store as store_mod

    adj_id = adj.get("id")
    metric = adj.get("validation_metric")
    preview = _preview(adj)
    ext_days = int(config.get("trial_extension_days", 7))
    applied_at = store_mod.parse_iso(adj.get("applied_at")) or (
        now - timedelta(days=int(config.get("trial_period_days", 14)))
    )

    # Step 10: an unmeasurable adjustment is never auto-promoted. Belt and
    # braces — apply_adjustments already leaves trial_ends_at None for these.
    if not metric:
        store_mod.mark_needs_attention(
            adj_id, "No validation metric — needs a manual decision."
        )
        out["flagged"].append(adj_id)
        return

    sample = count_interactions(applied_at, now)
    min_sample = int(config.get("min_sample_size", 20))

    if sample < min_sample:
        extensions = int(adj.get("extensions_used", 0))
        if extensions >= store_mod.MAX_EXTENSIONS:
            total_days = _days_since(applied_at, now)
            note = (
                f"Only {sample} interactions since it was applied "
                f"({min_sample} needed) after {extensions} extensions."
            )
            store_mod.mark_needs_attention(adj_id, note)
            _notify(
                adj_id,
                "not_enough_data",
                f"'{preview}' has been in trial for {total_days} days without "
                f"enough data ({sample}/{min_sample}). Please review manually.",
            )
            out["flagged"].append(adj_id)
        else:
            store_mod.update_trial(
                adj_id,
                extend_days=ext_days,
                note=f"Only {sample}/{min_sample} interactions — trial extended.",
            )
            _notify(
                adj_id,
                "extended",
                f"'{preview}' extended by {ext_days} days — only "
                f"{sample}/{min_sample} interactions so far.",
            )
            out["extended"].append(adj_id)
        return

    current = measure_metric(metric, adj.get("validation_target"), applied_at, now)
    if current is None:
        # Enough interactions overall, but this particular metric has too thin
        # a denominator (e.g. few votes on that question type). Same treatment
        # as too little data: extend, then flag.
        extensions = int(adj.get("extensions_used", 0))
        if extensions >= store_mod.MAX_EXTENSIONS:
            total_days = _days_since(applied_at, now)
            note = f"'{metric}' could not be measured over the trial window."
            store_mod.mark_needs_attention(adj_id, note)
            _notify(
                adj_id,
                "not_enough_data",
                f"'{preview}' has been in trial for {total_days} days but "
                f"{tuning_metric_note(metric)} still can't be measured. "
                "Please review manually.",
            )
            out["flagged"].append(adj_id)
        else:
            store_mod.update_trial(
                adj_id,
                extend_days=ext_days,
                note=f"'{metric}' not measurable yet — trial extended.",
            )
            _notify(
                adj_id,
                "extended",
                f"'{preview}' extended by {ext_days} days — "
                f"{tuning_metric_note(metric)} not measurable yet.",
            )
            out["extended"].append(adj_id)
        return

    baseline = adj.get("baseline_value")
    verdict = compare(metric, baseline, current)

    if verdict["trend"] == "worsened":
        store_mod.trash(
            adj_id,
            actor_uid="system",
            reason="auto_validation_failed",
            comment=(
                f"{metric} declined from {_fmt(baseline)} to {_fmt(current)} "
                f"({verdict['relative_change']:+.1%})."
            ),
            config=config,
        )
        _notify(
            adj_id,
            "auto_removed",
            f"'{preview}' was removed — {metric} declined from {_fmt(baseline)} "
            f"to {_fmt(current)}. Moved to trash.",
        )
        out["removed"].append(adj_id)
        return

    store_mod.update_trial(
        adj_id,
        new_status="permanent",
        current_value=current,
        note=(
            f"{metric} {verdict['trend']}: {_fmt(baseline)} → {_fmt(current)} "
            f"({verdict['relative_change']:+.1%}) over {sample} interactions."
        ),
    )
    _notify(
        adj_id,
        "promoted",
        f"'{preview}' was validated — {metric} improved from {_fmt(baseline)} "
        f"to {_fmt(current)}.",
    )
    out["promoted"].append(adj_id)


def _fmt(value) -> str:
    """Render a metric value for audit/notification text."""
    if isinstance(value, (int, float)):
        return f"{value:.2f}"
    return "n/a"


def tuning_metric_note(metric) -> str:
    """Short human phrase for a metric name in notification text."""
    return str(metric or "the metric")


def _preview(adj: dict, length: int = 60) -> str:
    """First words of an adjustment's instruction, for notification titles.
    Trimmed on a word boundary with an ellipsis so the message stays readable."""
    text = (adj.get("instruction") or adj.get("id") or "").strip()
    if len(text) <= length:
        return text
    return text[:length].rsplit(" ", 1)[0] + "…"


def _days_since(applied_at: datetime, now: datetime) -> int:
    """Whole days the adjustment has been in trial (min 1)."""
    return max(1, (now - applied_at).days)


def _reload_chatbot_cache() -> None:
    """Drop the chatbot's tuning cache so promotions/removals take effect on
    the next request in this worker. Best-effort — other workers pick the
    change up on their own next reload."""
    try:
        from app.user.services.chatbot_service import _reload_prompt_tuning

        _reload_prompt_tuning()
    except Exception as exc:
        logger.debug("tuning cache reload skipped: %s", exc)


# kind (internal) → (notification type, title, severity) for the admin bell.
# The four kinds map onto the Step-2 notification taxonomy. Keeping `kind` as
# the call-site vocabulary preserves _notify's (id, kind, message) signature.
_NOTIFY_KINDS = {
    "promoted": (
        "adjustment_promoted",
        "Adjustment promoted to permanent",
        "success",
    ),
    "auto_removed": (
        "adjustment_auto_removed",
        "Adjustment auto-removed",
        "warning",
    ),
    "extended": ("adjustment_extended", "Trial extended", "info"),
    "not_enough_data": (
        "adjustment_needs_review",
        "Adjustment needs review",
        "warning",
    ),
}


def _notify(adjustment_id: str, kind: str, message: str) -> None:
    """Raise an admin notification for a tuning auto-decision. Best-effort — a
    failed notification must not roll back the transition that produced it.

    Delegates to notification_service (the single writer of admin_notifications)
    so tuning events share the schema and surface in the admin bell. `kind` is
    the internal event key; it is mapped to the notification type/title/severity
    via _NOTIFY_KINDS. related_id + action_url deep-link to the adjustment.
    """
    type_, title, severity = _NOTIFY_KINDS.get(
        kind, (f"adjustment_{kind}", "Prompt tuning update", "info")
    )
    from app.admin.services.notification_service import create_notification

    create_notification(
        type_,
        title,
        message,
        severity=severity,
        related_id=adjustment_id,
        action_url=f"/adjustment/{adjustment_id}",
    )


# Prompt-tuning auto-validation events reach admins through the general
# notification bell — _notify above writes them via notification_service, which
# the GET /api/admin/notifications endpoints then serve. There is no
# tuning-specific notification feed.


# ── Per-adjustment analytics (Step 7) ─────────────────────────────────────────


def get_adjustment_analytics(adjustment_id: str) -> dict | None:
    """Before/after comparison for one adjustment, active or trashed.

    Outputs: the Step-7 payload — adjustment, status, trial progress, sample
    size vs requirement, baseline/current metric values, trend and verdict — or
    None when the id is unknown (router maps that to 404).
    Never raises: if the current value can't be measured, `current` is null and
    the verdict falls back to "insufficient_data" rather than failing the call.
    """
    from app.admin.services.system_config_service import get_prompt_tuning_config
    from app.user.services import prompt_tuning_store as store_mod

    store = store_mod.load()
    adj = store_mod.find_active(store, adjustment_id)
    trashed_item = None
    if adj is None:
        trashed_item = store_mod.find_trashed(store, adjustment_id)
        if trashed_item is None:
            return None
        adj = trashed_item.get("adjustment") or {}

    config = get_prompt_tuning_config()
    now = _now()
    applied_at = store_mod.parse_iso(adj.get("applied_at"))
    ends_at = store_mod.parse_iso(adj.get("trial_ends_at"))
    metric = adj.get("validation_metric")
    baseline = adj.get("baseline_value")
    min_sample = int(config.get("min_sample_size", 20))

    # A trashed adjustment is frozen at its removal time; measuring "now" would
    # attribute post-removal traffic to it.
    window_end = store_mod.parse_iso((trashed_item or {}).get("trashed_at")) or now

    interactions = count_interactions(applied_at, window_end) if applied_at else 0
    current = (
        measure_metric(metric, adj.get("validation_target"), applied_at, window_end)
        if (metric and applied_at)
        else None
    )
    verdict_info = compare(metric, baseline, current)

    status = adj.get("status", "trial")
    if trashed_item is not None:
        status = (
            "auto_removed"
            if (trashed_item.get("reason") == "auto_validation_failed")
            else "removed"
        )

    return {
        "adjustment": adj,
        "status": status,
        "trial_progress": _trial_progress(applied_at, ends_at, now, status),
        "trial_day": _trial_day(applied_at, now),
        "trial_total_days": adj.get("trial_period_days"),
        "interactions_during_trial": interactions,
        "min_sample_required": min_sample,
        "sample_met": interactions >= min_sample,
        "extensions_used": int(adj.get("extensions_used", 0)),
        "max_extensions": store_mod.MAX_EXTENSIONS,
        "needs_attention": bool(adj.get("needs_attention")),
        "attention_reason": adj.get("attention_reason"),
        "baseline": {
            "metric_name": metric,
            "value": baseline,
            "measured_at": adj.get("baseline_measured_at"),
        },
        "current": {
            "metric_name": metric,
            "value": current,
            "measured_at": window_end.isoformat(),
            "trend": verdict_info["trend"],
            "relative_change": verdict_info["relative_change"],
            "direction": verdict_info["direction"],
        },
        "verdict": _verdict(
            status, metric, current, interactions, min_sample, verdict_info
        ),
        "trashed": (
            {
                "trashed_at": trashed_item.get("trashed_at"),
                "trashed_by": trashed_item.get("trashed_by"),
                "reason": trashed_item.get("reason"),
                "comment": trashed_item.get("comment"),
                "retention_until": trashed_item.get("retention_until"),
                "can_restore": trashed_item.get("can_restore", True),
            }
            if trashed_item
            else None
        ),
        "history": store_mod.adjustment_history(store, adjustment_id),
    }


def _trial_day(applied_at: datetime | None, now: datetime) -> int:
    """1-based day number within the trial."""
    if not applied_at:
        return 0
    return max(1, (now - applied_at).days + 1)


def _trial_progress(
    applied_at: datetime | None,
    ends_at: datetime | None,
    now: datetime,
    status: str,
) -> str:
    """Human-readable trial progress for the detail screen."""
    if status == "permanent":
        return "Permanent"
    if status in ("auto_removed", "removed"):
        return "Removed"
    if not applied_at:
        return "Unknown"
    if ends_at is None:
        return f"Day {_trial_day(applied_at, now)} — awaiting manual decision"
    total = max(1, (ends_at - applied_at).days)
    return f"Day {min(_trial_day(applied_at, now), total)} of {total}"


def _verdict(
    status: str,
    metric,
    current,
    interactions: int,
    min_sample: int,
    verdict_info: dict,
) -> str:
    """One-word outcome for the detail screen's headline."""
    if status == "permanent":
        return "validated_permanent"
    if status in ("auto_removed", "removed"):
        return "removed"
    if not metric:
        return "not_measurable"
    if interactions < min_sample or current is None:
        return "insufficient_data"
    if verdict_info["trend"] == "worsened":
        return "at_risk_of_removal"
    return "on_track_for_permanent"
