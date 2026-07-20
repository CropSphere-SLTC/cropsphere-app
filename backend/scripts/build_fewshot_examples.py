#!/usr/bin/env python3
"""Rebuild backend/data/fewshot_examples.json from thumbs-up feedback.

Run inside the backend container (where Firestore creds are available):
    python scripts/build_fewshot_examples.py
Without Firestore it still runs, producing manual-only examples.
"""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))


def main() -> int:
    from app.user.services.fewshot_service import (
        FEWSHOT_PATH,
        build_fewshot_examples,
    )

    try:
        from app.config import get_settings
        from app.utils.firestore import init_firestore

        s = get_settings()
        init_firestore(s.FIREBASE_CREDENTIALS_JSON, s.FIREBASE_PROJECT_ID)
    except Exception as exc:
        print(f"[warn] Firestore unavailable ({exc}) — manual examples only.")

    out = build_fewshot_examples()
    counts = {t: len(v) for t, v in out["examples"].items() if v}
    total = sum(counts.values())
    print(f"Wrote {total} examples {counts} to {FEWSHOT_PATH}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
