#!/usr/bin/env python3
"""Inspect the prompt-tuning proposal from recent analytics (dry run).

Run inside the backend container (where Firestore creds are available):
    python scripts/generate_prompt_tuning.py [--days N]
Prints the adjustments the analyzer WOULD propose. It never writes the live
tuning file — applying is deliberately admin-gated via the API so a human
reviews each adjustment (see admin_router apply-prompt-tuning). Without
Firestore it still runs and reports an empty proposal.
"""

import argparse
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--days", type=int, default=7)
    args = parser.parse_args()

    from app.user.services.prompt_tuning_service import (
        analyze_and_generate_tuning,
    )

    try:
        from app.config import get_settings
        from app.utils.firestore import init_firestore

        s = get_settings()
        init_firestore(s.FIREBASE_CREDENTIALS_JSON, s.FIREBASE_PROJECT_ID)
    except Exception as exc:
        print(f"[warn] Firestore unavailable ({exc}) — empty proposal expected.")

    out = analyze_and_generate_tuning(args.days)
    print(
        f"period={out['period_days']}d  sample_size={out['sample_size']}  "
        f"proposed={len(out['adjustments'])}"
    )
    for a in out["adjustments"]:
        star = "" if a.get("recommended", True) else "  (opt-in)"
        print(f"\n[{a['dimension']}] {a['id']}{star}")
        print(f"  trigger:     {a['trigger']}")
        print(f"  instruction: {a['instruction']}")
        # No metric or no baseline means auto-validation can't judge it — it
        # would be applied as a trial that waits for a manual decision.
        metric = a.get("validation_metric")
        baseline = a.get("baseline_value")
        if metric and isinstance(baseline, (int, float)):
            print(f"  validates on: {metric} (baseline {baseline})")
        else:
            print(f"  validates on: {metric or 'n/a'} — NOT auto-validatable")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
