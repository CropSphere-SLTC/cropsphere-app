"""Persistent store for prompt-tuning adjustments and their lifecycle.

Owns data/prompt_tuning.json (compose-mounted, same pattern as
fewshot_examples.json) and every state transition an adjustment can make:

    trial ──promote/validate──> permanent
      │                             │
      └──── remove / auto_remove ───┴──> trash ──retention──> deleted
                    │
                    └──restore──> trial (fresh)

File schema (version 2):

    {
      "version": 2,
      "updated_at": iso8601,
      "active": [<adjustment>],       # status "trial" or "permanent"
      "trash":  [<trashed item>],
      "audit_log": [<entry>]          # newest last, capped at _AUDIT_CAP
    }

Concurrency: the container runs uvicorn with 2 workers and the auto-validation
pass can fire from either, so every read-modify-write goes through _mutate(),
which holds an exclusive flock on a sidecar lock file and writes atomically
(tmp + os.replace). Without flock available the module still works — it just
degrades to last-write-wins.

Best-effort by design: a missing or corrupt file yields an empty store rather
than raising, so the chatbot falls back to its static prompt.
"""

import json
import logging
import os
import tempfile
import threading
from datetime import datetime, timedelta, timezone
from pathlib import Path

logger = logging.getLogger(__name__)

_DATA_DIR = Path(
    os.environ.get("PROMPT_TUNING_DIR") or Path(__file__).resolve().parents[3] / "data"
)
TUNING_PATH = _DATA_DIR / "prompt_tuning.json"
_LOCK_PATH = _DATA_DIR / "prompt_tuning.lock"

SCHEMA_VERSION = 2

# Statuses that reach the live prompt. Anything else (trash, auto_removed) is
# invisible to chatbot_service.
LIVE_STATUSES = ("trial", "permanent")

# A trial may be extended at most this many times when the sample is too thin;
# after that the admin is notified and it stays trial pending a decision.
MAX_EXTENSIONS = 2

# The in-file audit log is a convenience view for the adjustment-detail screen;
# the durable trail is Firestore admin_audit_logs. Capped so the file the
# chatbot reads on every cache miss stays small.
_AUDIT_CAP = 500

_write_lock = threading.Lock()


# ── Time helpers ──────────────────────────────────────────────────────────────


def _now() -> datetime:
    return datetime.now(timezone.utc)


def _iso(dt: datetime) -> str:
    return dt.isoformat()


def parse_iso(value) -> datetime | None:
    """Parse a stored ISO-8601 timestamp, tolerating a trailing 'Z' and naive
    values (assumed UTC). Returns None for anything unparseable, so a corrupt
    date can never crash the validation pass."""
    if not isinstance(value, str) or not value:
        return None
    try:
        dt = datetime.fromisoformat(value.replace("Z", "+00:00"))
    except ValueError:
        return None
    return dt if dt.tzinfo else dt.replace(tzinfo=timezone.utc)


# ── Load / save ───────────────────────────────────────────────────────────────


def empty_store() -> dict:
    """A well-formed, empty store. Used as the fallback everywhere."""
    return {
        "version": SCHEMA_VERSION,
        "updated_at": None,
        "active": [],
        "trash": [],
        "audit_log": [],
    }


def load() -> dict:
    """Read the store from disk, migrating the v1 schema if needed.

    Inputs: none. Outputs: a dict with the version-2 keys, always present and
    always lists. Never raises — a missing/corrupt/partially-written file logs
    at WARNING and returns empty_store().
    """
    try:
        if not TUNING_PATH.exists():
            return empty_store()
        raw = json.loads(TUNING_PATH.read_text())
    except Exception as exc:
        logger.warning("prompt-tuning read failed: %s", exc)
        return empty_store()

    if not isinstance(raw, dict):
        return empty_store()
    if raw.get("version") != SCHEMA_VERSION or "active" not in raw:
        raw = _migrate_v1(raw)

    store = empty_store()
    store["updated_at"] = raw.get("updated_at")
    for key in ("active", "trash", "audit_log"):
        value = raw.get(key)
        store[key] = (
            [x for x in value if isinstance(x, dict)] if isinstance(value, list) else []
        )
    return store


def _migrate_v1(raw: dict) -> dict:
    """Convert the original {updated_at, period_days, sample_size, adjustments}
    file into the version-2 shape.

    v1 adjustments were applied before baselines existed, so they carry no
    validation_metric. Per the safety rule "never auto-promote what we can't
    measure", they land in `trial` with trial_ends_at=None — they stay live and
    wait for an explicit admin decision rather than being auto-validated or
    auto-removed on data we never captured.
    """
    applied_at = raw.get("updated_at") or _iso(_now())
    active = []
    for adj in raw.get("adjustments", []) or []:
        if not isinstance(adj, dict) or not adj.get("id"):
            continue
        active.append(
            {
                **adj,
                "status": "trial",
                "applied_at": applied_at,
                "trial_ends_at": None,
                "extensions_used": 0,
                "validated_at": None,
                "validation_metric": adj.get("validation_metric"),
                "validation_target": adj.get("validation_target"),
                "baseline_value": adj.get("baseline_value"),
                "baseline_measured_at": None,
                "period_days": raw.get("period_days", 0),
            }
        )
    logger.info("prompt-tuning: migrated %d v1 adjustment(s) to v2", len(active))
    return {
        "version": SCHEMA_VERSION,
        "updated_at": applied_at,
        "active": active,
        "trash": [],
        "audit_log": [],
    }


def save(store: dict) -> dict:
    """Atomically write the store. Never raises — a write failure is logged and
    the in-memory dict is still returned so the caller's response is coherent."""
    store["version"] = SCHEMA_VERSION
    store["updated_at"] = _iso(_now())
    store["audit_log"] = store.get("audit_log", [])[-_AUDIT_CAP:]
    try:
        _DATA_DIR.mkdir(parents=True, exist_ok=True)
        # tmp + replace: a reader (chatbot cache miss) never sees a half file.
        fd, tmp = tempfile.mkstemp(dir=str(_DATA_DIR), suffix=".tmp")
        try:
            with os.fdopen(fd, "w") as fh:
                json.dump(store, fh, indent=2, ensure_ascii=False)
            os.replace(tmp, TUNING_PATH)
        except Exception:
            try:
                os.unlink(tmp)  # leave no orphan tmp behind on a failed write
            except OSError:
                # Cleanup is best-effort: the tmp file may never have been
                # created, or the same condition that broke the write blocks
                # the unlink. Either way the write error re-raised below is
                # the one worth surfacing, so this is deliberately swallowed.
                pass
            raise
    except Exception as exc:
        logger.error("prompt-tuning write failed: %s", exc)
    return store


def _mutate(fn):
    """Run fn(store) under an exclusive cross-process lock and persist the
    result. fn may return a value; _mutate returns (store, value).

    The flock covers the whole read-modify-write so two uvicorn workers can't
    both load, both mutate, and clobber each other's transition (e.g. one
    promoting while the other trashes). If fcntl is unavailable the thread lock
    still serialises within a worker.
    """
    with _write_lock:
        lock_fh = None
        try:
            import fcntl

            _DATA_DIR.mkdir(parents=True, exist_ok=True)
            lock_fh = open(_LOCK_PATH, "w")
            fcntl.flock(lock_fh, fcntl.LOCK_EX)
        except Exception as exc:  # pragma: no cover - platform dependent
            logger.debug("prompt-tuning file lock unavailable: %s", exc)
            if lock_fh:
                lock_fh.close()
                lock_fh = None
        try:
            store = load()
            result = fn(store)
            save(store)
            return store, result
        finally:
            if lock_fh:
                try:
                    import fcntl

                    fcntl.flock(lock_fh, fcntl.LOCK_UN)
                finally:
                    lock_fh.close()


# ── Audit trail ───────────────────────────────────────────────────────────────


def append_audit(
    store: dict,
    action: str,
    adjustment_id: str,
    performed_by: str = "system",
    comment: str = "",
    details: dict | None = None,
) -> dict:
    """Append one entry to the in-file audit log and mirror it to Firestore.

    Inputs: action — one of applied/promoted/auto_removed/manually_removed/
    restored/deleted/trial_extended. performed_by — "system" for automatic
    transitions, otherwise the acting admin's uid.
    Outputs: the entry that was appended.
    Security assumption: `comment` is admin-supplied free text. It is stored
    and displayed but NEVER injected into the prompt — only the fixed-template
    `instruction` field ever reaches the LLM.
    """
    entry = {
        "action": action,
        "adjustment_id": adjustment_id,
        "performed_by": performed_by or "system",
        "timestamp": _iso(_now()),
        "comment": (comment or "")[:500],
        "details": details or {},
    }
    store.setdefault("audit_log", []).append(entry)
    _mirror_audit(entry)
    return entry


def _mirror_audit(entry: dict) -> None:
    """Copy an audit entry into Firestore admin_audit_logs so prompt-tuning
    actions show up in the existing audit-log screens alongside role changes
    and bans. Best-effort — the file remains the source of truth for the
    per-adjustment history."""
    try:
        from app.utils.firestore import admin_audit_log

        performed_by = entry["performed_by"]
        admin_audit_log(
            actor_uid=performed_by,
            actor_role="system" if performed_by == "system" else "superadmin",
            action=f"prompt_tuning_{entry['action']}",
            target_uid="",
            details={
                "adjustment_id": entry["adjustment_id"],
                "comment": entry["comment"],
                **entry["details"],
            },
        )
    except Exception as exc:
        logger.debug("prompt-tuning audit mirror failed: %s", exc)


# ── Queries ───────────────────────────────────────────────────────────────────


def find_active(store: dict, adjustment_id: str) -> dict | None:
    """The active adjustment with this id, or None."""
    for adj in store.get("active", []):
        if adj.get("id") == adjustment_id:
            return adj
    return None


def find_trashed(store: dict, adjustment_id: str) -> dict | None:
    """The trash item wrapping this adjustment id, or None."""
    for item in store.get("trash", []):
        if (item.get("adjustment") or {}).get("id") == adjustment_id:
            return item
    return None


def live_adjustments(store: dict | None = None) -> list:
    """Active adjustments whose status reaches the prompt (trial + permanent),
    in application order. Anything trashed or auto-removed is excluded."""
    store = store if store is not None else load()
    return [a for a in store.get("active", []) if a.get("status") in LIVE_STATUSES]


def adjustment_history(store: dict, adjustment_id: str) -> list:
    """Every audit entry for one adjustment, oldest first."""
    return [
        e for e in store.get("audit_log", []) if e.get("adjustment_id") == adjustment_id
    ]


# ── Transitions ───────────────────────────────────────────────────────────────


def apply_adjustments(
    proposals: list,
    approved_ids: list,
    actor_uid: str,
    config: dict,
    trial_period_days: int | None = None,
) -> dict:
    """Move approved proposals into `active` with status "trial".

    Inputs: proposals — freshly re-derived adjustment dicts (each already
    carrying validation_metric/baseline_value from the analysis). approved_ids
    — the subset the admin ticked. config — the effective prompt-tuning config.
    trial_period_days — optional per-apply override of config's value.
    Outputs: {"applied": [ids], "skipped": [ids]}. An approved id that no
    longer triggers, or that is already active, is skipped rather than
    duplicated.
    Security assumption: `proposals` must come from
    prompt_tuning_service.analyze_and_generate_tuning (fixed templates), never
    from a client request body.
    """
    approved = set(approved_ids or [])
    period = int(trial_period_days or config.get("trial_period_days", 14))
    now = _now()
    ends_at = now + timedelta(days=period)

    def _fn(store):
        applied, skipped = [], []
        existing = {a.get("id") for a in store.get("active", [])}
        for proposal in proposals:
            pid = proposal.get("id")
            if pid not in approved:
                continue
            if pid in existing:
                skipped.append(pid)
                continue
            metric = proposal.get("validation_metric")
            baseline = proposal.get("baseline_value")
            # "Measurable" needs BOTH a metric and a numeric baseline to
            # compare it against — a metric with no baseline can be read but
            # not judged, which Step 10 treats the same as not measurable.
            measurable = bool(metric) and isinstance(baseline, (int, float))
            adjustment = {
                "id": pid,
                "dimension": proposal.get("dimension"),
                "trigger": proposal.get("trigger"),
                "instruction": proposal.get("instruction"),
                "recommended": proposal.get("recommended", False),
                "validation_metric": metric,
                "validation_target": proposal.get("validation_target"),
                "baseline_value": baseline,
                "baseline_measured_at": _iso(now) if measurable else None,
                "status": "trial",
                "applied_at": _iso(now),
                # Not measurable → no auto-validation clock. Step 10: never
                # auto-promote what the system can't measure, so it stays
                # trial until a superadmin decides.
                "trial_ends_at": _iso(ends_at) if measurable else None,
                "trial_period_days": period,
                "extensions_used": 0,
                "validated_at": None,
                "period_days": proposal.get("period_days"),
            }
            store["active"].append(adjustment)
            existing.add(pid)
            applied.append(pid)
            append_audit(
                store,
                "applied",
                pid,
                performed_by=actor_uid,
                details={
                    "after_status": "trial",
                    "validation_metric": metric,
                    "baseline_value": baseline,
                    "measurable": measurable,
                    "trial_period_days": period,
                },
            )
        return {"applied": applied, "skipped": skipped}

    _, result = _mutate(_fn)
    return result


def promote(adjustment_id: str, actor_uid: str, reason: str = "manual") -> dict:
    """Force a trial adjustment to "permanent".

    Outputs: {"ok": bool, "error": str|None, "adjustment": dict|None}. Returns
    ok=False (never raises) when the id isn't active or is already permanent,
    so the router can map it to a 404/409 with a clear message.
    """

    def _fn(store):
        adj = find_active(store, adjustment_id)
        if adj is None:
            return {"ok": False, "error": "not_found", "adjustment": None}
        if adj.get("status") == "permanent":
            return {"ok": False, "error": "already_permanent", "adjustment": adj}
        before = adj.get("status")
        adj["status"] = "permanent"
        adj["validated_at"] = _iso(_now())
        adj["promotion_reason"] = reason
        append_audit(
            store,
            "promoted",
            adjustment_id,
            performed_by=actor_uid,
            details={
                "before_status": before,
                "after_status": "permanent",
                "reason": reason,
            },
        )
        return {"ok": True, "error": None, "adjustment": adj}

    _, result = _mutate(_fn)
    return result


def trash(
    adjustment_id: str,
    actor_uid: str,
    reason: str,
    comment: str = "",
    config: dict | None = None,
) -> dict:
    """Move an active adjustment (trial or permanent) into the trash.

    Inputs: reason — "manual_removal" or "auto_validation_failed". comment —
    required by the router for manual removals; stored verbatim, never
    injected into the prompt.
    Outputs: {"ok", "error", "item"}. ok=False when the id isn't active.
    """
    from app.admin.services.system_config_service import get_prompt_tuning_config

    cfg = config or get_prompt_tuning_config()
    now = _now()
    retention_until = now + timedelta(days=int(cfg.get("trash_retention_days", 14)))
    action = (
        "auto_removed" if reason == "auto_validation_failed" else "manually_removed"
    )

    def _fn(store):
        adj = find_active(store, adjustment_id)
        if adj is None:
            return {"ok": False, "error": "not_found", "item": None}
        before = adj.get("status")
        store["active"] = [a for a in store["active"] if a.get("id") != adjustment_id]
        adj = dict(adj)
        adj["status"] = "auto_removed" if action == "auto_removed" else before
        item = {
            "adjustment": adj,
            "trashed_at": _iso(now),
            "trashed_by": actor_uid or "system",
            "reason": reason,
            "comment": (comment or "")[:500],
            "retention_until": _iso(retention_until),
            "can_restore": True,
        }
        store.setdefault("trash", []).append(item)
        append_audit(
            store,
            action,
            adjustment_id,
            performed_by=actor_uid or "system",
            comment=comment,
            details={"before_status": before, "after_status": "trash"},
        )
        return {"ok": True, "error": None, "item": item}

    _, result = _mutate(_fn)
    return result


def restore(adjustment_id: str, actor_uid: str, config: dict | None = None) -> dict:
    """Restore a trashed adjustment to `active` as a FRESH trial.

    A restored adjustment starts a brand-new trial (baseline re-captured by the
    caller if it can be measured, extensions reset) rather than resuming the
    old one — the usage it was measured against has moved on.
    Outputs: {"ok", "error", "adjustment"}.
    """
    from app.admin.services.system_config_service import get_prompt_tuning_config

    cfg = config or get_prompt_tuning_config()
    period = int(cfg.get("trial_period_days", 14))
    now = _now()

    def _fn(store):
        item = find_trashed(store, adjustment_id)
        if item is None:
            return {"ok": False, "error": "not_found", "adjustment": None}
        if find_active(store, adjustment_id) is not None:
            return {"ok": False, "error": "already_active", "adjustment": None}
        adj = dict(item.get("adjustment") or {})
        measurable = bool(adj.get("validation_metric")) and isinstance(
            adj.get("baseline_value"), (int, float)
        )
        adj.update(
            {
                "status": "trial",
                "applied_at": _iso(now),
                "trial_ends_at": (
                    _iso(now + timedelta(days=period)) if measurable else None
                ),
                "trial_period_days": period,
                "extensions_used": 0,
                "validated_at": None,
                "restored_at": _iso(now),
                # A fresh trial re-earns its verdict — clear any stale flag
                # from the run that got it trashed.
                "needs_attention": False,
                "attention_reason": None,
            }
        )
        store["trash"] = [
            t
            for t in store["trash"]
            if (t.get("adjustment") or {}).get("id") != adjustment_id
        ]
        store["active"].append(adj)
        append_audit(
            store,
            "restored",
            adjustment_id,
            performed_by=actor_uid,
            details={"before_status": "trash", "after_status": "trial"},
        )
        return {"ok": True, "error": None, "adjustment": adj}

    _, result = _mutate(_fn)
    return result


def purge_expired_trash(actor_uid: str = "system", force_all: bool = False) -> dict:
    """Permanently delete trash items whose retention_until has passed.

    Inputs: force_all — when True, empties the trash regardless of retention
    (the superadmin "clear trash now" action).
    Outputs: {"deleted": [ids], "remaining": int}. Items with an unparseable
    retention_until are kept, not deleted — losing an adjustment to a bad date
    is worse than keeping it around.
    """
    now = _now()

    def _fn(store):
        keep, deleted = [], []
        for item in store.get("trash", []):
            adj_id = (item.get("adjustment") or {}).get("id", "")
            until = parse_iso(item.get("retention_until"))
            expired = force_all or (until is not None and until <= now)
            if expired:
                deleted.append(adj_id)
                append_audit(
                    store,
                    "deleted",
                    adj_id,
                    performed_by=actor_uid,
                    details={
                        "before_status": "trash",
                        "after_status": "deleted",
                        "retention_until": item.get("retention_until"),
                        "forced": bool(force_all),
                    },
                )
            else:
                keep.append(item)
        store["trash"] = keep
        return {"deleted": deleted, "remaining": len(keep)}

    _, result = _mutate(_fn)
    return result


def update_trial(
    adjustment_id: str,
    actor_uid: str = "system",
    *,
    new_status: str | None = None,
    extend_days: int | None = None,
    current_value=None,
    note: str = "",
) -> dict:
    """Apply an auto-validation outcome to one trial adjustment.

    Inputs: new_status — "permanent" to promote. extend_days — push
    trial_ends_at out by this many days and bump extensions_used.
    current_value — the measured metric at validation time, recorded for the
    detail screen. note — the reason string shown in the audit entry.
    Outputs: {"ok", "error", "adjustment"}. Used only by the validation pass;
    admin-facing transitions go through promote()/trash().
    """

    def _fn(store):
        adj = find_active(store, adjustment_id)
        if adj is None:
            return {"ok": False, "error": "not_found", "adjustment": None}
        before = adj.get("status")
        if current_value is not None:
            adj["last_measured_value"] = current_value
            adj["last_measured_at"] = _iso(_now())
        if extend_days:
            ends = parse_iso(adj.get("trial_ends_at")) or _now()
            adj["trial_ends_at"] = _iso(ends + timedelta(days=int(extend_days)))
            adj["extensions_used"] = int(adj.get("extensions_used", 0)) + 1
            append_audit(
                store,
                "trial_extended",
                adjustment_id,
                performed_by=actor_uid,
                comment=note,
                details={
                    "before_status": before,
                    "after_status": before,
                    "extensions_used": adj["extensions_used"],
                    "new_trial_ends_at": adj["trial_ends_at"],
                },
            )
        if new_status:
            adj["status"] = new_status
            adj["validated_at"] = _iso(_now())
            append_audit(
                store,
                "promoted",
                adjustment_id,
                performed_by=actor_uid,
                comment=note,
                details={
                    "before_status": before,
                    "after_status": new_status,
                    "current_value": current_value,
                    "baseline_value": adj.get("baseline_value"),
                },
            )
        return {"ok": True, "error": None, "adjustment": adj}

    _, result = _mutate(_fn)
    return result


def mark_needs_attention(adjustment_id: str, note: str) -> dict:
    """Flag a trial that exhausted its extensions without enough data. It stays
    live and trial; the flag drives the "not enough data" banner and stops the
    validator from re-extending it."""

    def _fn(store):
        adj = find_active(store, adjustment_id)
        if adj is None:
            return {"ok": False}
        adj["needs_attention"] = True
        adj["attention_reason"] = note
        return {"ok": True}

    _, result = _mutate(_fn)
    return result


def clear_all(actor_uid: str, comment: str = "Cleared all tuning") -> dict:
    """Move every active adjustment to the trash in one pass (the existing
    "Clear all" action). Returns {"cleared": [ids]}."""
    ids = [a.get("id") for a in load().get("active", [])]
    for adj_id in ids:
        trash(adj_id, actor_uid, reason="manual_removal", comment=comment)
    return {"cleared": ids}
