# Prompt Tuning — Admin API Contract (for the Flutter screens)

Endpoint contract for the self-improving prompt-tuning feature: analytics
propose adjustments, an admin approves them, each approved one runs a **trial**,
and auto-validation promotes or removes it based on whether its metric actually
improved.

Owner: backend (Shifan). Consumer: Flutter admin UI (Supun).

> **Access:** every endpoint below is **superadmin-only**. Gate the whole
> screen behind the superadmin role — a plain admin gets `403`. Auto-validation
> events (promote / auto-remove / extend / needs-review) are delivered through
> the general admin notification bell, not a tuning-specific feed — see the
> separate notifications API.

---

## Common conventions

- **Prefixes:** `/api/admin` (analysis + trash listing) and `/api/superadmin`
  (config + manual override). Note it is `superadmin`, **not** `super-admin`.
- **Auth:** Firebase JWT in `Authorization: Bearer <token>`.
- **Errors:** `401` missing/expired token · `403` wrong role · `404` unknown
  adjustment id · `409` conflicting state · `422` invalid body · `429` rate
  limited (`Retry-After` header).

### The lifecycle

```
proposed ──apply──> trial ──validate/force──> permanent
                      │                          │
                      └──── remove / auto ───────┴──> trash ──retention──> deleted
                                  │
                                  └──restore──> trial (fresh)
```

Only `trial` and `permanent` reach the live prompt.

### The `Adjustment` object

| field                  | type          | meaning / UI use                                                            |
|------------------------|---------------|-----------------------------------------------------------------------------|
| `id`                   | string        | Stable id. Sent back in `approved_ids` and used in every path param.        |
| `dimension`            | string        | Category — drives the label chip (table below).                             |
| `trigger`              | string        | Why it fired, e.g. `"78% beginner users (threshold: 70%)"`. Subtitle.       |
| `instruction`          | string        | The prompt text. Show expandable.                                           |
| `recommended`          | bool          | **Default checkbox state** on proposals.                                    |
| `validation_metric`    | string?       | Metric it will be judged on. `null` = not measurable.                       |
| `validation_target`    | string?       | Scope for `refusal_rate` (a crop/district name).                            |
| `baseline_value`       | number?       | Metric value when applied. `null` = not measurable.                         |
| `status`               | string        | `trial` \| `permanent` (active only).                                       |
| `applied_at`           | iso8601       | When the trial started.                                                     |
| `trial_ends_at`        | iso8601?      | When auto-validation runs. **`null` = no auto-validation** (see below).     |
| `trial_period_days`    | int           | Trial length at apply time.                                                 |
| `extensions_used`      | int           | 0–2. Trials extend when the sample is too thin.                             |
| `validated_at`         | iso8601?      | When it became permanent.                                                   |
| `needs_attention`      | bool?         | Ran out of extensions without enough data — show a warning badge.           |
| `attention_reason`     | string?       | Text for that badge.                                                        |

> **`trial_ends_at: null` is normal, not an error.** An adjustment with no
> measurable metric (or no baseline — too few observations to measure one) is
> never auto-promoted or auto-removed. It stays live as a trial until a
> superadmin decides. Show it as **"Awaiting your decision"**, not "Day X of Y".

**Dimension → display label:** `language_complexity` → Language Complexity ·
`problem_areas` → Problem Areas · `missing_topics` → Missing Topics ·
`conversation_patterns` → Conversation Patterns · `earnings_effectiveness` →
Earnings Offer.

---

## 1. Analyze (propose) — read-only

```
POST /api/admin/analyze-prompt-tuning?days=7
```

Query `days` (1–30, default 7). No body. 5/min.

```json
{
  "proposed_adjustments": [
    {
      "id": "language_complexity",
      "dimension": "language_complexity",
      "trigger": "78% beginner users (threshold: 70%)",
      "instruction": "Most of your users are new to farming. …",
      "recommended": true,
      "validation_metric": "beginner_satisfaction_rate",
      "baseline_value": 0.45
    }
  ],
  "period_days": 7,
  "sample_size": 142
}
```

`proposed_adjustments` may be empty — either nothing triggered, or the window
had fewer than 30 interactions (`sample_size` tells you which).

---

## 2. Apply — start trials

```
POST /api/admin/apply-prompt-tuning?days=7
{ "approved_ids": ["language_complexity"], "trial_period_days": 14 }
```

`trial_period_days` is optional (1–90); omit it to use the configured value.
5/min.

```json
{
  "status": "ok",
  "applied_count": 1,
  "applied_ids": ["language_complexity"],
  "skipped_ids": []
}
```

> The server **re-runs the analysis** and keeps only approved ids from the fresh
> result — it never trusts a client-sent adjustment body. An id that no longer
> triggers appears in **neither** list; one that is already active appears in
> `skipped_ids`. Treat `applied_count` as the source of truth, then re-fetch
> *active*.

---

## 3. Active — what's live now

```
GET /api/admin/active-prompt-tuning
```

10/min.

```json
{
  "active_adjustments": [ /* Adjustment objects with lifecycle fields */ ],
  "count": 3,
  "trial_count": 1,
  "permanent_count": 2,
  "trash_count": 4,
  "updated_at": "2026-07-23T10:00:00+00:00"
}
```

---

## 4. Clear all — revert to the default prompt

```
DELETE /api/admin/clear-prompt-tuning
```

Moves **everything active to the trash** (reversible until retention expires) —
it does not destroy anything. 5/min. → `{ "status": "ok", "cleared_count": 3 }`

---

## 5. Per-adjustment analytics (the detail screen)

```
GET /api/superadmin/adjustment-analytics/{adjustment_id}
```

20/min. `404` if the id is unknown. Works for **trashed** adjustments too (their
measurement window freezes at `trashed_at`).

```json
{
  "adjustment": { /* … */ },
  "status": "trial",
  "trial_progress": "Day 8 of 14",
  "trial_day": 8,
  "trial_total_days": 14,
  "interactions_during_trial": 45,
  "min_sample_required": 20,
  "sample_met": true,
  "extensions_used": 0,
  "max_extensions": 2,
  "needs_attention": false,
  "attention_reason": null,
  "baseline":  { "metric_name": "beginner_satisfaction_rate", "value": 0.45,
                 "measured_at": "2026-07-01T09:00:00+00:00" },
  "current":   { "metric_name": "beginner_satisfaction_rate", "value": 0.68,
                 "measured_at": "2026-07-08T09:00:00+00:00",
                 "trend": "improving", "relative_change": 0.5111,
                 "direction": "higher_is_better" },
  "verdict": "on_track_for_permanent",
  "trashed": null,
  "history": [ { "action": "applied", "adjustment_id": "…",
                 "performed_by": "uid", "timestamp": "…",
                 "comment": "", "details": {} } ]
}
```

**`trend` → arrow:** `improving` ↑ · `stable` → · `worsened` ↓ ·
`unknown` (no value yet) — show a dash.

> **`relative_change` is always signed so positive = better**, including for
> `refusal_rate` where the raw number falling is the good outcome. Use
> `direction` only if you want to caption the raw values.

**`verdict` → headline:** `on_track_for_permanent` · `at_risk_of_removal` ·
`insufficient_data` · `not_measurable` · `validated_permanent` · `removed`.

---

## 6. Manual override (superadmin)

```
POST   /api/superadmin/force-permanent/{adjustment_id}
POST   /api/superadmin/remove-adjustment/{adjustment_id}   { "comment": "why" }
```

`force-permanent`: 404 unknown · 409 already permanent. 10/min.
`remove-adjustment`: **`comment` is required**, 3–500 chars — a shorter or
missing comment is a `422`. 404 unknown. 10/min.

Both are intended to be used from the detail screen *after* the admin has seen
the analytics above.

---

## 7. Trash

```
GET    /api/admin/prompt-tuning-trash
POST   /api/admin/restore-from-trash/{adjustment_id}
DELETE /api/superadmin/clear-trash[?all_items=true]
```

Trash listing (10/min), newest first:

```json
{
  "trash": [
    {
      "adjustment": { /* … */ },
      "trashed_at": "2026-07-14T10:00:00+00:00",
      "trashed_by": "system",
      "reason": "auto_validation_failed",
      "comment": "beginner_satisfaction_rate declined from 0.45 to 0.20 (-55.6%).",
      "retention_until": "2026-07-28T10:00:00+00:00",
      "can_restore": true
    }
  ],
  "count": 1
}
```

`reason` is `auto_validation_failed` (removed by the system) or
`manual_removal`. Restore (5/min) returns the adjustment as a **fresh trial** —
new clock, extensions reset. 404 if not in the trash, 409 if an adjustment with
that id is already active.

`clear-trash` deletes only items past `retention_until`; `all_items=true` empties
it regardless. 5/min. → `{ "status": "ok", "deleted_count": 2, "deleted_ids": […], "remaining": 0 }`

---

## 8. Config (superadmin settings section)

```
GET   /api/superadmin/prompt-tuning-config
PATCH /api/superadmin/prompt-tuning-config
```

10/min each. Both return the full effective config:

```json
{
  "min_sample_size": 20,
  "trial_period_days": 14,
  "trial_extension_days": 7,
  "trash_retention_days": 14
}
```

PATCH accepts any subset; omitted fields are unchanged. Bounds (violations are
`422`): `min_sample_size` 1–10000 · `trial_period_days` 1–90 ·
`trial_extension_days` 1–30 · `trash_retention_days` 1–365.

---

## 9. Notifications

Auto-validation events are **not** a tuning-specific feed. When a trial is
promoted, auto-removed, extended, or flagged for review, the validator writes an
admin notification (types `adjustment_promoted`, `adjustment_auto_removed`,
`adjustment_extended`, `adjustment_needs_review`) carrying `related_id` = the
adjustment id and `action_url` = `/adjustment/{id}`.

These surface through the general **admin notification bell**:

```
GET  /api/admin/notifications?limit=20&unread_only=false
GET  /api/admin/notifications/unread-count
POST /api/admin/notifications/{id}/read
POST /api/admin/notifications/read-all
```

All admin-readable. Tapping an `adjustment_*` notification deep-links to that
adjustment's detail screen (§5). See the admin-notifications contract for the
full payload shape.

---

## Suggested screen flow

**Prompt Tuning screen (superadmin)**
1. **Analyse** → §1, render proposals as a checklist pre-checked from
   `recommended`.
2. **Apply Selected** → §2, show `applied_count`, refresh active.
3. **Currently Active** → §3. Status badge per row (Trial / Permanent), plus a
   warning badge when `needs_attention`. Tapping a row pushes the detail screen.
4. **Trash** (collapsible) → §7, restore buttons.

**Adjustment Detail screen (superadmin)**
- §5 payload: status badge, trial progress bar (`trial_day` / `trial_total_days`
  — hide the bar when `trial_ends_at` is null), before/after values with the
  trend arrow, sample progress (`interactions_during_trial` /
  `min_sample_required`), verdict headline, audit `history` list.
- **Make Permanent** / **Remove** (§6). Remove opens a comment dialog and must
  block submit under 3 characters, matching the server rule.

**Settings section (superadmin)** → §8, four number fields, client-side bounds
matching the server.

## Notes / edge cases

- Auto-validation has **no scheduler** — it is triggered opportunistically by
  chat traffic and is throttled to once every 5 minutes per worker. A trial that
  ended a minute ago may not have been evaluated yet; the detail screen computes
  its numbers live, so it is always current even when the stored status lags.
- `analyze` and `apply` scan Firestore — show a spinner, respect the 5/min cap.
- Empty proposal + low `sample_size` is a normal state, not an error.
