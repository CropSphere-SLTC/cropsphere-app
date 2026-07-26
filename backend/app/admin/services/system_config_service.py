"""Superadmin-adjustable runtime settings, persisted in Firestore.

Unlike superadmin_service._runtime_config (in-memory, lost on restart), these
values survive redeploys because the prompt-tuning lifecycle depends on them:
a trial that started under a 14-day period must not silently become a 7-day
trial because the container restarted.

Storage: collection `system_config`, document `settings`, one field per config
section (currently only `prompt_tuning`). Reads are cached _CACHE_TTL_SECONDS
so the per-chat validation check doesn't hit Firestore on every request.

Best-effort by design: with Firestore unavailable, get_prompt_tuning_config()
returns the defaults rather than raising, so the chatbot and the tuning
lifecycle keep working on sane values.
"""

import logging
import threading
import time

from fastapi import HTTPException

logger = logging.getLogger(__name__)

_COLLECTION = "system_config"
_DOCUMENT = "settings"
_SECTION = "prompt_tuning"
_CACHE_TTL_SECONDS = 60

# Defaults match the Step-2 contract. Every key here is settable by a
# superadmin; anything absent from the stored document falls back to these.
_DEFAULTS = {
    "min_sample_size": 20,
    "trial_period_days": 14,
    "trial_extension_days": 7,
    "trash_retention_days": 14,
}

# Inclusive (min, max) bounds enforced on write. Chosen so a mistyped value
# can't strand an adjustment in a decade-long trial or expire trash instantly.
_BOUNDS = {
    "min_sample_size": (1, 10000),
    "trial_period_days": (1, 90),
    "trial_extension_days": (1, 30),
    "trash_retention_days": (1, 365),
}

# (expires_at_monotonic, config)
_cache: tuple[float, dict] | None = None
_cache_lock = threading.Lock()


def get_prompt_tuning_config() -> dict:
    """Return the effective prompt-tuning config (stored values over defaults).

    Inputs: none. Outputs: dict with exactly the _DEFAULTS keys, all ints.
    Cached _CACHE_TTL_SECONDS. Never raises — a Firestore failure logs at
    WARNING and yields the defaults, because the caller is often on the chat
    path where a config read must never surface as a user-visible error.
    Security assumption: the document is only writable via
    update_prompt_tuning_config, which is superadmin-gated at the router.
    """
    global _cache
    now = time.monotonic()
    with _cache_lock:
        if _cache and _cache[0] > now:
            return dict(_cache[1])

    config = dict(_DEFAULTS)
    try:
        from app.utils.firestore import get_db

        snap = get_db().collection(_COLLECTION).document(_DOCUMENT).get()
        stored = (snap.to_dict() or {}).get(_SECTION, {}) if snap.exists else {}
        for key in _DEFAULTS:
            value = stored.get(key)
            # Reject anything that isn't a plain in-range int, even though
            # writes are validated — the document could have been edited
            # directly in the Firestore console.
            if isinstance(value, int) and not isinstance(value, bool):
                low, high = _BOUNDS[key]
                if low <= value <= high:
                    config[key] = value
    except Exception as exc:
        logger.warning("system_config read failed, using defaults: %s", exc)

    with _cache_lock:
        _cache = (time.monotonic() + _CACHE_TTL_SECONDS, dict(config))
    return config


def update_prompt_tuning_config(updates: dict, actor_uid: str = "") -> dict:
    """Merge `updates` into the stored prompt-tuning config and return the new
    effective config.

    Inputs: updates — a dict of {key: int} limited to the _DEFAULTS keys;
    None values are ignored (PATCH semantics). actor_uid — the superadmin, for
    the audit trail.
    Outputs: the full effective config after the write.
    Raises HTTPException(400) on an unknown key or an out-of-bounds value, and
    HTTPException(500) if the write fails.
    Security assumption: the caller (superadmin_router) has already enforced
    the superadmin role; Pydantic bounds are re-checked here so the service is
    safe to call from anywhere.
    """
    clean: dict = {}
    for key, value in (updates or {}).items():
        if value is None:
            continue
        if key not in _DEFAULTS:
            raise HTTPException(status_code=400, detail=f"Unknown config key: {key}")
        if not isinstance(value, int) or isinstance(value, bool):
            raise HTTPException(status_code=400, detail=f"{key} must be an integer")
        low, high = _BOUNDS[key]
        if not (low <= value <= high):
            raise HTTPException(
                status_code=400, detail=f"{key} must be between {low} and {high}"
            )
        clean[key] = value

    if not clean:
        return get_prompt_tuning_config()

    current = get_prompt_tuning_config()
    merged = {**current, **clean}
    try:
        from app.utils.firestore import get_db

        get_db().collection(_COLLECTION).document(_DOCUMENT).set(
            {_SECTION: merged}, merge=True
        )
    except Exception as exc:
        logger.error("system_config write failed: %s", exc)
        raise HTTPException(status_code=500, detail="Failed to save configuration")

    invalidate_cache()
    _audit(actor_uid, clean)
    return merged


def invalidate_cache() -> None:
    """Drop the cached config so the next read re-fetches. Called after a
    write, and by tests that stub Firestore."""
    global _cache
    with _cache_lock:
        _cache = None


def _audit(actor_uid: str, changed: dict) -> None:
    """Record the config change in the admin audit trail. Best-effort — a
    failed audit write must not fail an otherwise-successful update."""
    try:
        from app.utils.firestore import admin_audit_log

        admin_audit_log(
            actor_uid=actor_uid,
            actor_role="superadmin",
            action="prompt_tuning_config_updated",
            details={"changed": changed},
        )
    except Exception as exc:
        logger.debug("config audit not recorded: %s", exc)
