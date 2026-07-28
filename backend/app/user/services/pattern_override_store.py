"""Persistent store for admin-approved pattern overrides and their lifecycle.

Owns data/pattern_overrides.json (compose-mounted, same pattern as
prompt_tuning.json) and every state transition an override can make:

    proposed ──approve──> active ──revoke──> revoked ──retention──> deleted
                             ▲                   │
                             └─────restore───────┘

An override is a plain lowercase phrase that SUPPLEMENTS one of the chatbot's
hardcoded routing lists (see chatbot_service._load_pattern_overrides). It can
never remove or shadow a hardcoded pattern — the runtime checks the hardcoded
list first and only consults overrides when that misses.

File schema (version 1):

    {
      "version": 1,
      "updated_at": iso8601,
      "last_analysis_at": iso8601 | null,
      "active":  [<override>],
      "revoked": [<revoked override>],
      "audit":   [<entry>],          # newest last, capped at _AUDIT_CAP
      "hits":    [<hit>]             # newest last, capped at _HIT_CAP
    }

Why `hits` lives here: chat_analytics carries no conversation_id/message_index,
and chat_feedback is a separate collection keyed on (conversation_id,
message_index) — there is no join key between them. The ledger records each
override match with the message text that triggered it, so a later thumbs vote
can be attributed back to the pattern that routed the turn, and so the detail
screen can show real example hits and false-positive candidates. It is bounded,
so the file the chatbot reads on a cache miss stays small.

Concurrency: identical to prompt_tuning_store — every read-modify-write goes
through _mutate(), which holds an exclusive flock on a sidecar lock file and
writes atomically (tmp + os.replace). Without flock the module still works, it
just degrades to last-write-wins.

Best-effort by design: a missing or corrupt file yields an empty store rather
than raising, so the chatbot falls back to its hardcoded patterns alone.
"""

import json
import logging
import os
import re
import tempfile
import threading
from datetime import datetime, timedelta, timezone
from pathlib import Path

logger = logging.getLogger(__name__)

_DATA_DIR = Path(
    os.environ.get("PATTERN_OVERRIDES_DIR")
    or os.environ.get("PROMPT_TUNING_DIR")
    or Path(__file__).resolve().parents[3] / "data"
)
OVERRIDES_PATH = _DATA_DIR / "pattern_overrides.json"
_LOCK_PATH = _DATA_DIR / "pattern_overrides.lock"

SCHEMA_VERSION = 1

# The four routing predicates an override can extend. The id prefix is how the
# apply endpoint derives a category server-side instead of trusting the body.
CATEGORIES = {
    "reformulation": "reform",
    "context_statement": "context",
    "capability": "capability",
    "agricultural_intent": "intent",
}

# How long a revoked override stays restorable before auto-deletion. Mirrors
# prompt tuning's trash_retention_days default; overridable per-revoke.
DEFAULT_RETENTION_DAYS = 14

# Step 11 phrase constraints. A phrase is used as a plain lowercase substring
# test, never compiled as a regex — but regex metacharacters are still rejected
# so a phrase can never become one if the matching strategy ever changes, and
# so an admin can't paste something that silently matches nothing.
MAX_PHRASE_LEN = 50
MIN_PHRASE_LEN = 3
_FORBIDDEN_CHARS = set("[]{}()*+?|^$\\.<>\"'`;")

# The in-file audit is the per-pattern history view; the durable trail is
# Firestore admin_audit_logs. Both capped so the file stays small.
_AUDIT_CAP = 500
_HIT_CAP = 1000
# Per-pattern example hits kept for the detail screen (newest first).
EXAMPLE_HIT_LIMIT = 5

_write_lock = threading.Lock()


# ── Time helpers ──────────────────────────────────────────────────────────────


def _now() -> datetime:
    return datetime.now(timezone.utc)


def _iso(dt: datetime) -> str:
    return dt.isoformat()


def parse_iso(value) -> datetime | None:
    """Parse a stored ISO-8601 timestamp, tolerating a trailing 'Z' and naive
    values (assumed UTC). Returns None for anything unparseable, so a corrupt
    date can never crash the retention sweep."""
    if not isinstance(value, str) or not value:
        return None
    try:
        dt = datetime.fromisoformat(value.replace("Z", "+00:00"))
    except ValueError:
        return None
    return dt if dt.tzinfo else dt.replace(tzinfo=timezone.utc)


# ── Validation (Step 11) ──────────────────────────────────────────────────────


def validate_phrase(phrase) -> tuple[bool, str]:
    """Check an admin-supplied (possibly edited) phrase.

    Inputs: phrase — free text from the apply request body.
    Outputs: (ok, error_message). error_message is "" when ok.
    Security assumption: this is the ONLY gate between an admin request body
    and a string that influences chat routing, so it is deliberately strict —
    length-bounded, letter-bearing, and free of regex/quote metacharacters.
    """
    if not isinstance(phrase, str):
        return False, "Phrase must be text"
    cleaned = phrase.strip().lower()
    if not cleaned:
        return False, "Phrase cannot be empty"
    if len(cleaned) < MIN_PHRASE_LEN:
        return False, f"Phrase must be at least {MIN_PHRASE_LEN} characters"
    if len(cleaned) > MAX_PHRASE_LEN:
        return False, f"Phrase cannot exceed {MAX_PHRASE_LEN} characters"
    bad = sorted(_FORBIDDEN_CHARS & set(cleaned))
    if bad:
        return False, f"Phrase cannot contain: {' '.join(bad)}"
    if not re.search(r"[a-z]", cleaned):
        return False, "Phrase must contain letters"
    return True, ""


def normalize_phrase(phrase: str) -> str:
    """Canonical stored form: lowercased, whitespace-collapsed, trimmed. The
    runtime does `phrase in message.lower()`, so double spaces from a paste
    would silently never match."""
    return re.sub(r"\s+", " ", (phrase or "").strip().lower())


def category_for_id(pattern_id: str) -> str | None:
    """Map an override id back to its category via the id prefix. Used by the
    apply path so a client body can never assign a phrase to a category the
    analyzer didn't propose it for."""
    for category, prefix in CATEGORIES.items():
        if str(pattern_id or "").startswith(f"{prefix}_"):
            return category
    return None


# ── Load / save ───────────────────────────────────────────────────────────────


def empty_store() -> dict:
    """A well-formed, empty store. The fallback everywhere."""
    return {
        "version": SCHEMA_VERSION,
        "updated_at": None,
        "last_analysis_at": None,
        "active": [],
        "revoked": [],
        "audit": [],
        "hits": [],
    }


def _read() -> dict:
    """Raw read with no retention sweep. Never raises — a missing, corrupt, or
    half-written file logs at WARNING and yields empty_store()."""
    try:
        if not OVERRIDES_PATH.exists():
            return empty_store()
        raw = json.loads(OVERRIDES_PATH.read_text())
    except Exception as exc:
        logger.warning("pattern-overrides read failed: %s", exc)
        return empty_store()

    if not isinstance(raw, dict):
        return empty_store()

    store = empty_store()
    store["updated_at"] = raw.get("updated_at")
    store["last_analysis_at"] = raw.get("last_analysis_at")
    for key in ("active", "revoked", "audit", "hits"):
        value = raw.get(key)
        store[key] = (
            [x for x in value if isinstance(x, dict)] if isinstance(value, list) else []
        )
    return store


def load() -> dict:
    """Read the store, sweeping expired revoked items first (Step 7).

    Inputs: none. Outputs: a dict with every version-1 key present and every
    collection a list. Never raises.

    The sweep only takes the write lock when something has actually expired, so
    the common path (nothing due) is a single file read — this runs on the
    chatbot's cache-miss path.
    """
    store = _read()
    if _expired_ids(store):
        store, _ = _mutate(lambda s: None)  # _mutate purges before calling fn
    return store


def save(store: dict) -> dict:
    """Atomically write the store. Never raises — a write failure is logged and
    the in-memory dict is still returned so the caller's response is coherent."""
    store["version"] = SCHEMA_VERSION
    store["updated_at"] = _iso(_now())
    store["audit"] = store.get("audit", [])[-_AUDIT_CAP:]
    store["hits"] = store.get("hits", [])[-_HIT_CAP:]
    try:
        _DATA_DIR.mkdir(parents=True, exist_ok=True)
        # tmp + replace: a reader (chatbot cache miss) never sees a half file.
        fd, tmp = tempfile.mkstemp(dir=str(_DATA_DIR), suffix=".tmp")
        try:
            with os.fdopen(fd, "w") as fh:
                json.dump(store, fh, indent=2, ensure_ascii=False)
            os.replace(tmp, OVERRIDES_PATH)
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
        logger.error("pattern-overrides write failed: %s", exc)
    return store


def _mutate(fn):
    """Run fn(store) under an exclusive cross-process lock and persist.

    Every mutation first sweeps expired revoked items, so retention is enforced
    on any write path as well as on load(). fn may return a value; _mutate
    returns (store, value). fn may be a no-op (used by load()'s sweep).
    """
    with _write_lock:
        lock_fh = None
        try:
            import fcntl

            _DATA_DIR.mkdir(parents=True, exist_ok=True)
            lock_fh = open(_LOCK_PATH, "w")
            fcntl.flock(lock_fh, fcntl.LOCK_EX)
        except Exception as exc:  # pragma: no cover - platform dependent
            logger.debug("pattern-overrides file lock unavailable: %s", exc)
            if lock_fh:
                lock_fh.close()
                lock_fh = None
        try:
            store = _read()
            _purge_expired_inplace(store)
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


def _expired_ids(store: dict) -> list:
    """Ids of revoked overrides whose retention_until has passed. An
    unparseable date keeps the item — losing a pattern to a bad date is worse
    than keeping it around."""
    now = _now()
    out = []
    for item in store.get("revoked", []):
        until = parse_iso(item.get("retention_until"))
        if until is not None and until <= now:
            out.append(item.get("id", ""))
    return out


def _purge_expired_inplace(store: dict) -> list:
    """Drop expired revoked items and audit each deletion (Step 7). Mutates
    `store`; returns the deleted ids."""
    now = _now()
    keep, deleted = [], []
    for item in store.get("revoked", []):
        until = parse_iso(item.get("retention_until"))
        if until is not None and until <= now:
            deleted.append(item.get("id", ""))
            append_audit(
                store,
                "auto_deleted",
                item.get("id", ""),
                performed_by="system",
                details={
                    "phrase": item.get("phrase"),
                    "retention_until": item.get("retention_until"),
                },
            )
        else:
            keep.append(item)
    store["revoked"] = keep
    return deleted


# ── Audit trail ───────────────────────────────────────────────────────────────


def append_audit(
    store: dict,
    action: str,
    pattern_id: str,
    performed_by: str = "system",
    details: dict | None = None,
) -> dict:
    """Append one entry to the in-file audit log and mirror it to Firestore.

    Inputs: action — one of approved/approved_with_edit/revoked/restored/
    deleted/auto_deleted. performed_by — "system" for the retention sweep,
    otherwise the acting admin's uid (stored raw, matching prompt_tuning_store
    and the admin_audit_logs collection).
    Outputs: the appended entry.
    Security assumption: `details` may carry admin free text (a revoke reason).
    It is stored and displayed but NEVER reaches the LLM — overrides only ever
    contribute a boolean routing decision, never prompt text.
    """
    entry = {
        "action": action,
        "pattern_id": pattern_id,
        "performed_by": performed_by or "system",
        "timestamp": _iso(_now()),
        "details": details or {},
    }
    store.setdefault("audit", []).append(entry)
    _mirror_audit(entry)
    return entry


def _mirror_audit(entry: dict) -> None:
    """Copy an audit entry into Firestore admin_audit_logs so pattern actions
    appear in the existing audit-log screens. Best-effort — the file remains the
    source of truth for per-pattern history."""
    try:
        from app.utils.firestore import admin_audit_log

        performed_by = entry["performed_by"]
        admin_audit_log(
            actor_uid=performed_by,
            actor_role="system" if performed_by == "system" else "superadmin",
            action=f"pattern_override_{entry['action']}",
            target_uid="",
            details={"pattern_id": entry["pattern_id"], **entry["details"]},
        )
    except Exception as exc:
        logger.debug("pattern-override audit mirror failed: %s", exc)


# ── Queries ───────────────────────────────────────────────────────────────────


def find_active(store: dict, pattern_id: str) -> dict | None:
    """The active override with this id, or None."""
    for item in store.get("active", []):
        if item.get("id") == pattern_id:
            return item
    return None


def find_revoked(store: dict, pattern_id: str) -> dict | None:
    """The revoked override with this id, or None."""
    for item in store.get("revoked", []):
        if item.get("id") == pattern_id:
            return item
    return None


def known_phrases(store: dict | None = None) -> set:
    """(category, phrase) pairs already active or revoked — the analyzer skips
    proposing these again. Revoked ones are included deliberately: re-proposing
    a phrase an admin just rejected would be noise."""
    store = store if store is not None else load()
    pairs = set()
    for bucket in ("active", "revoked"):
        for item in store.get(bucket, []):
            phrase = item.get("phrase")
            if phrase:
                pairs.add((item.get("category"), phrase))
    return pairs


def compile_overrides(store: dict | None = None) -> dict:
    """Build the lookup the chatbot's predicates consult.

    Outputs: {category: {"phrases": [(phrase, id)],
                         "patterns": [((verb, (qual, ...)), id)]}}
    Only ACTIVE overrides are compiled — revoked ones stop matching the moment
    the cache reloads. `patterns` carries combo entries (verb + qualifiers) for
    parity with _REFORMULATION_PATTERNS; the analyzer only proposes plain
    phrases today, so it is normally empty.
    """
    store = store if store is not None else load()
    out = {c: {"phrases": [], "patterns": []} for c in CATEGORIES}
    for item in store.get("active", []):
        category = item.get("category")
        phrase = item.get("phrase")
        pattern_id = item.get("id")
        if category not in out or not phrase or not pattern_id:
            continue
        if item.get("pattern_type") == "combo":
            verb = item.get("verb")
            quals = tuple(item.get("qualifiers") or ())
            if verb and quals:
                out[category]["patterns"].append(((verb, quals), pattern_id))
            continue
        out[category]["phrases"].append((phrase, pattern_id))
    return out


def pattern_history(store: dict, pattern_id: str) -> list:
    """Every audit entry for one override, oldest first."""
    return [e for e in store.get("audit", []) if e.get("pattern_id") == pattern_id]


def pattern_hits(store: dict, pattern_id: str) -> list:
    """Ledger entries for one override, newest first."""
    hits = [h for h in store.get("hits", []) if h.get("pattern_id") == pattern_id]
    hits.reverse()
    return hits


# ── Transitions ───────────────────────────────────────────────────────────────


def _blank_feedback() -> dict:
    return {"thumbs_up": 0, "thumbs_down": 0, "no_feedback": 0}


def _sync_no_feedback(item: dict) -> None:
    """Keep feedback.no_feedback consistent with hit_count minus rated hits, so
    the three numbers always add up to hit_count in the UI."""
    fb = item.setdefault("feedback", _blank_feedback())
    rated = int(fb.get("thumbs_up", 0)) + int(fb.get("thumbs_down", 0))
    fb["no_feedback"] = max(0, int(item.get("hit_count", 0)) - rated)


def apply_patterns(approved: list, actor_uid: str) -> dict:
    """Move approved proposals into `active`.

    Inputs: approved — a list of dicts already merged by the caller from the
    client's selection and the server-side analysis:
        {"id", "category", "phrase", "original_proposed_phrase",
         "edited", "evidence_count"}
    The caller (pattern_analyzer_service.apply_proposals) is responsible for
    validating each phrase and deriving `category` server-side; this function
    trusts its input and only guards against duplicates.
    Outputs: {"applied": [ids], "skipped": [{"id", "reason"}]}.
    """
    now = _now()

    def _fn(store):
        applied, skipped = [], []
        existing = {a.get("id") for a in store.get("active", [])}
        active_phrases = {
            (a.get("category"), a.get("phrase")) for a in store.get("active", [])
        }
        for proposal in approved:
            pid = proposal.get("id")
            phrase = proposal.get("phrase")
            category = proposal.get("category")
            if pid in existing:
                skipped.append({"id": pid, "reason": "already_active"})
                continue
            if (category, phrase) in active_phrases:
                skipped.append({"id": pid, "reason": "duplicate_phrase"})
                continue
            original = proposal.get("original_proposed_phrase") or phrase
            edited = bool(proposal.get("edited")) and original != phrase
            item = {
                "id": pid,
                "category": category,
                "phrase": phrase,
                "original_proposed_phrase": original,
                "edited": edited,
                "pattern_type": "phrase",
                "status": "active",
                "applied_at": _iso(now),
                "applied_by": actor_uid or "system",
                "evidence_count": int(proposal.get("evidence_count", 0) or 0),
                "hit_count": 0,
                "last_hit": None,
                "feedback": _blank_feedback(),
            }
            store["active"].append(item)
            existing.add(pid)
            active_phrases.add((category, phrase))
            applied.append(pid)
            append_audit(
                store,
                "approved_with_edit" if edited else "approved",
                pid,
                performed_by=actor_uid,
                details={
                    "original": original,
                    "edited_to": phrase if edited else None,
                    "category": category,
                    "evidence_count": item["evidence_count"],
                },
            )
        return {"applied": applied, "skipped": skipped}

    _, result = _mutate(_fn)
    return result


def revoke_pattern(
    pattern_id: str,
    actor_uid: str,
    reason: str,
    retention_days: int = DEFAULT_RETENTION_DAYS,
) -> dict:
    """Move an active override to `revoked` with a performance snapshot.

    Inputs: reason — required non-empty admin text (enforced by the router
    schema). retention_days — how long it stays restorable.
    Outputs: {"ok", "error", "item"}. ok=False with error="not_found" when the
    id isn't active — never raises, so the router can map it to a 404.
    """
    now = _now()
    retention_until = now + timedelta(days=int(retention_days))

    def _fn(store):
        item = find_active(store, pattern_id)
        if item is None:
            return {"ok": False, "error": "not_found", "item": None}
        store["active"] = [a for a in store["active"] if a.get("id") != pattern_id]
        fb = item.get("feedback") or _blank_feedback()
        up = int(fb.get("thumbs_up", 0))
        down = int(fb.get("thumbs_down", 0))
        rated = up + down
        revoked = dict(item)
        revoked.update(
            {
                "status": "revoked",
                "revoked_at": _iso(now),
                "revoked_by": actor_uid or "system",
                "revoke_reason": (reason or "")[:500],
                "performance_at_revoke": {
                    "hit_count": int(item.get("hit_count", 0)),
                    "thumbs_up": up,
                    "thumbs_down": down,
                    "satisfaction": round(up / rated, 2) if rated else 0.0,
                },
                "retention_until": _iso(retention_until),
                "can_restore": True,
            }
        )
        store.setdefault("revoked", []).append(revoked)
        append_audit(
            store,
            "revoked",
            pattern_id,
            performed_by=actor_uid,
            details={
                "reason": revoked["revoke_reason"],
                "phrase": item.get("phrase"),
                "performance": revoked["performance_at_revoke"],
            },
        )
        return {"ok": True, "error": None, "item": revoked}

    _, result = _mutate(_fn)
    return result


def restore_pattern(pattern_id: str, actor_uid: str) -> dict:
    """Move a revoked override back to `active` with FRESH counters.

    hit_count, last_hit and feedback all reset: the pattern earns its verdict
    again from scratch, because the usage it was judged on has moved on (same
    rule prompt_tuning_store.restore applies to trials).
    Outputs: {"ok", "error", "item"}.
    """
    now = _now()

    def _fn(store):
        item = find_revoked(store, pattern_id)
        if item is None:
            return {"ok": False, "error": "not_found", "item": None}
        if find_active(store, pattern_id) is not None:
            return {"ok": False, "error": "already_active", "item": None}
        store["revoked"] = [r for r in store["revoked"] if r.get("id") != pattern_id]
        restored = dict(item)
        for key in (
            "revoked_at",
            "revoked_by",
            "revoke_reason",
            "performance_at_revoke",
            "retention_until",
            "can_restore",
        ):
            restored.pop(key, None)
        restored.update(
            {
                "status": "active",
                "applied_at": _iso(now),
                "applied_by": actor_uid or "system",
                "restored_at": _iso(now),
                "hit_count": 0,
                "last_hit": None,
                "feedback": _blank_feedback(),
            }
        )
        store["active"].append(restored)
        # Drop the old ledger rows too, so the fresh run's example hits and
        # false-positive candidates aren't mixed with the revoked run's.
        store["hits"] = [
            h for h in store.get("hits", []) if h.get("pattern_id") != pattern_id
        ]
        append_audit(
            store,
            "restored",
            pattern_id,
            performed_by=actor_uid,
            details={"phrase": restored.get("phrase"), "counters_reset": True},
        )
        return {"ok": True, "error": None, "item": restored}

    _, result = _mutate(_fn)
    return result


def delete_pattern(pattern_id: str, actor_uid: str) -> dict:
    """Permanently remove a revoked override (and its ledger rows).

    Outputs: {"ok", "error"}. ok=False with error="not_found" when the id isn't
    in `revoked` — active overrides must be revoked before they can be deleted.
    """

    def _fn(store):
        item = find_revoked(store, pattern_id)
        if item is None:
            return {"ok": False, "error": "not_found"}
        store["revoked"] = [r for r in store["revoked"] if r.get("id") != pattern_id]
        store["hits"] = [
            h for h in store.get("hits", []) if h.get("pattern_id") != pattern_id
        ]
        append_audit(
            store,
            "deleted",
            pattern_id,
            performed_by=actor_uid,
            details={"phrase": item.get("phrase")},
        )
        return {"ok": True, "error": None}

    _, result = _mutate(_fn)
    return result


def set_last_analysis(timestamp: str | None = None) -> None:
    """Stamp when the gap analysis last ran (shown in the gap report's Pattern
    Health block). Best-effort — a failure here must not fail the analysis."""
    stamp = timestamp or _iso(_now())

    def _fn(store):
        store["last_analysis_at"] = stamp

    try:
        _mutate(_fn)
    except Exception as exc:
        logger.debug("last_analysis stamp failed: %s", exc)


# ── Hit + feedback ledger (Step 5) ────────────────────────────────────────────


def hit_key(conversation_id, message: str) -> str:
    """Join key between an override match and a later thumbs vote.

    chat_analytics has no conversation_id and the client mints none on the
    first turn, so the message text is the primary key and conversation_id is
    only a tie-breaker (see record_feedback). Normalised the same way on both
    sides: lowercased, whitespace-collapsed, truncated.
    """
    return re.sub(r"\s+", " ", (message or "").strip().lower())[:200]


def record_hit(
    pattern_id: str,
    message: str,
    matched_phrase: str,
    conversation_id: str | None = None,
) -> None:
    """Record one override match: bump the pattern's counters and append a
    ledger row. Never raises.

    Called from the analytics background thread (see chatbot_service.
    _run_analytics), so the file write is fully off the chat response path.
    A hit for an id that is no longer active is dropped — the cache may lag a
    revoke by one request.
    """
    now = _now()

    def _fn(store):
        item = find_active(store, pattern_id)
        if item is None:
            return False
        item["hit_count"] = int(item.get("hit_count", 0)) + 1
        item["last_hit"] = _iso(now)
        _sync_no_feedback(item)
        store.setdefault("hits", []).append(
            {
                "pattern_id": pattern_id,
                "key": hit_key(conversation_id, message),
                "message": (message or "")[:200],
                "matched_phrase": matched_phrase,
                "conversation_id": (conversation_id or "")[:128],
                "timestamp": _iso(now),
                "feedback": None,
            }
        )
        return True

    try:
        _mutate(_fn)
    except Exception as exc:
        logger.warning("pattern hit record failed (%s): %s", pattern_id, exc)


def record_feedback(conversation_id: str, message_text: str, vote: str) -> str | None:
    """Attribute a thumbs vote to the override that routed that turn, if any.

    Inputs: the same (conversation_id, message_text) the client sent to
    POST /api/chat/feedback, and vote "up"/"down".
    Outputs: the pattern id the vote was attributed to, or None when the turn
    matched no override (the overwhelmingly common case).
    Never raises — feedback logging must never break.

    Re-votes are handled: a hit already carrying a vote has the old counter
    decremented before the new one is incremented, so flipping thumbs up to
    down doesn't inflate both.
    """
    if vote not in ("up", "down"):
        return None
    key = hit_key(conversation_id, message_text)
    if not key:
        return None

    # Cheap unlocked pre-check: the overwhelming majority of votes are on turns
    # no override touched, and those must not take the write lock or rewrite
    # the file. A race here only costs a missed attribution, never corruption —
    # the authoritative re-scan happens under the lock below.
    if not any(h.get("key") == key for h in _read().get("hits", [])):
        return None

    def _fn(store):
        hits = store.get("hits", [])
        # Newest first: a repeated question in one conversation attributes to
        # the most recent match, which is the turn the user is rating.
        match = None
        for hit in reversed(hits):
            if hit.get("key") != key:
                continue
            hit_conv = hit.get("conversation_id") or ""
            # conversation_id only discriminates when BOTH sides have one.
            if conversation_id and hit_conv and hit_conv != conversation_id:
                continue
            match = hit
            break
        if match is None:
            return None
        pattern_id = match.get("pattern_id")
        item = find_active(store, pattern_id)
        if item is None:
            return None
        fb = item.setdefault("feedback", _blank_feedback())
        previous = match.get("feedback")
        if previous == vote:
            return pattern_id  # same vote again — idempotent
        if previous in ("up", "down"):
            counter = "thumbs_up" if previous == "up" else "thumbs_down"
            fb[counter] = max(0, int(fb.get(counter, 0)) - 1)
        counter = "thumbs_up" if vote == "up" else "thumbs_down"
        fb[counter] = int(fb.get(counter, 0)) + 1
        match["feedback"] = vote
        _sync_no_feedback(item)
        return pattern_id

    try:
        _, result = _mutate(_fn)
        return result
    except Exception as exc:
        logger.warning("pattern feedback link failed: %s", exc)
        return None
