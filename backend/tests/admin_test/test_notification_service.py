"""Unit tests for app.admin.services.notification_service.

Firestore is mocked — either a hand-built fake collection or per-test MagicMocks
— so these cover the CRUD surface, the badge count cap, the read-marking, and
the analytics-alert trigger/dedup logic without a real database.
"""

from unittest.mock import MagicMock, patch

from app.admin.services import notification_service as ns

# ── Fakes ─────────────────────────────────────────────────────────────────────


class _FakeDoc:
    def __init__(self, doc_id, data):
        self.id = doc_id
        self._data = data
        self.reference = MagicMock()

    def to_dict(self):
        return dict(self._data)


def _doc(doc_id, **data):
    return _FakeDoc(doc_id, data)


def _db_returning(stream_docs):
    """A Firestore double whose every query path ends in .stream() → stream_docs.

    Covers collection().add(), .where().limit().stream(),
    .order_by().limit().stream(), and .document().update().
    """
    db = MagicMock()
    col = db.collection.return_value
    # add() returns (update_time, doc_ref) like firebase-admin.
    ref = MagicMock()
    ref.id = "new-id"
    col.add.return_value = (object(), ref)
    # Every chained query resolves to the same stream.
    for chain in (
        col.where.return_value,
        col.where.return_value.limit.return_value,
        col.order_by.return_value.limit.return_value,
    ):
        chain.stream.return_value = list(stream_docs)
    col.where.return_value.limit.return_value.stream.return_value = list(stream_docs)
    return db, col


# ── create_notification ───────────────────────────────────────────────────────


def test_create_returns_doc_id_and_writes_expected_shape():
    db, col = _db_returning([])
    with patch("app.utils.firestore.get_db", return_value=db):
        nid = ns.create_notification(
            "adjustment_promoted",
            "Promoted",
            "It improved",
            severity="success",
            related_id="dim1",
            action_url="/adjustment/dim1",
        )
    assert nid == "new-id"
    written = col.add.call_args[0][0]
    assert written["type"] == "adjustment_promoted"
    assert written["severity"] == "success"
    assert written["read"] is False
    assert written["read_at"] is None
    assert written["related_id"] == "dim1"
    assert written["action_url"] == "/adjustment/dim1"


def test_create_coerces_unknown_severity_to_info():
    db, col = _db_returning([])
    with patch("app.utils.firestore.get_db", return_value=db):
        ns.create_notification("x", "t", "m", severity="critical")
    assert col.add.call_args[0][0]["severity"] == "info"


def test_create_clamps_oversized_fields():
    db, col = _db_returning([])
    with patch("app.utils.firestore.get_db", return_value=db):
        ns.create_notification("x", "T" * 500, "M" * 5000, severity="info")
    written = col.add.call_args[0][0]
    assert len(written["title"]) == 200
    assert len(written["message"]) == 1000


def test_create_never_raises_and_returns_empty_on_failure():
    with patch("app.utils.firestore.get_db", side_effect=RuntimeError("no db")):
        assert ns.create_notification("x", "t", "m") == ""


# ── get_notifications ─────────────────────────────────────────────────────────


def test_get_notifications_serializes_and_sets_id():
    ts = MagicMock()
    ts.isoformat.return_value = "2026-07-24T10:00:00+00:00"
    docs = [_doc("a", type="x", read=False, created_at=ts, read_at=None)]
    db, _ = _db_returning(docs)
    with patch("app.utils.firestore.get_db", return_value=db):
        out = ns.get_notifications(limit=20)
    assert out[0]["id"] == "a"
    assert out[0]["created_at"] == "2026-07-24T10:00:00+00:00"


def test_get_notifications_unread_only_sorts_newest_first():
    docs = [
        _doc("old", read=False, created_at="2026-07-01T00:00:00+00:00"),
        _doc("new", read=False, created_at="2026-07-20T00:00:00+00:00"),
    ]
    db, col = _db_returning(docs)
    with patch("app.utils.firestore.get_db", return_value=db):
        out = ns.get_notifications(limit=20, unread_only=True)
    # Equality-filter path is used (no order_by), sorted in Python.
    col.where.assert_called()
    assert [n["id"] for n in out] == ["new", "old"]


def test_get_notifications_returns_empty_on_failure():
    with patch("app.utils.firestore.get_db", side_effect=RuntimeError("boom")):
        assert ns.get_notifications() == []


def test_get_notifications_clamps_limit():
    db, col = _db_returning([])
    with patch("app.utils.firestore.get_db", return_value=db):
        ns.get_notifications(limit=99999)
    # order_by(...).limit(N) — N must be clamped to the module max.
    assert col.order_by.return_value.limit.call_args[0][0] == ns._MAX_LIMIT


# ── unread count ──────────────────────────────────────────────────────────────


def test_unread_count_counts_stream():
    docs = [_doc(str(i), read=False) for i in range(3)]
    db, _ = _db_returning(docs)
    with patch("app.utils.firestore.get_db", return_value=db):
        assert ns.get_unread_count() == 3


def test_unread_count_zero_on_failure():
    with patch("app.utils.firestore.get_db", side_effect=RuntimeError("x")):
        assert ns.get_unread_count() == 0


# ── mark read ─────────────────────────────────────────────────────────────────


def test_mark_read_updates_the_document():
    db, col = _db_returning([])
    with patch("app.utils.firestore.get_db", return_value=db):
        ns.mark_read("abc")
    col.document.assert_called_once_with("abc")
    update = col.document.return_value.update.call_args[0][0]
    assert update["read"] is True
    assert update["read_at"] is not None


def test_mark_read_never_raises():
    with patch("app.utils.firestore.get_db", side_effect=RuntimeError("x")):
        ns.mark_read("abc")  # no exception


def test_mark_all_read_batches_updates():
    docs = [_doc(str(i), read=False) for i in range(3)]
    db, col = _db_returning(docs)
    batch = db.batch.return_value
    with patch("app.utils.firestore.get_db", return_value=db):
        ns.mark_all_read()
    # One update per unread doc, then a single commit for the batch.
    assert batch.update.call_count == 3
    batch.commit.assert_called_once()


def test_mark_all_read_no_op_when_nothing_unread():
    db, col = _db_returning([])
    with patch("app.utils.firestore.get_db", return_value=db):
        ns.mark_all_read()
    db.batch.return_value.commit.assert_not_called()


# ── analytics alerts ──────────────────────────────────────────────────────────


def _report(**over):
    base = {
        "period": "last_7_days",
        "total_interactions": 100,
        "response_breakdown": {"answer": 90, "refusal": 5, "near_miss": 5},
        "missing_crops": [{"crop": "Okra", "request_count": 8}],
        "missing_districts": [],
        "top_refused_questions": [],
        "feedback_summary": {
            "total_feedback": 40,
            "satisfaction_rate": 0.8,
            "most_downvoted_questions": [],
        },
    }
    base.update(over)
    return base


def test_high_refusal_rate_triggers_alert():
    report = _report(
        response_breakdown={"answer": 40, "refusal": 40, "near_miss": 20},
    )
    with patch.object(ns, "_recent_types", return_value=set()), patch.object(
        ns, "create_notification", return_value="id1"
    ) as create:
        out = ns.check_analytics_alerts(report)
    types = [c.args[0] for c in create.call_args_list]
    assert "high_refusal_rate" in types
    assert "id1" in out


def test_high_refusal_includes_top_topics():
    report = _report(response_breakdown={"answer": 40, "refusal": 60})
    with patch.object(ns, "_recent_types", return_value=set()), patch.object(
        ns, "create_notification", return_value="id"
    ) as create:
        ns.check_analytics_alerts(report)
    msg = next(
        c.args[2] for c in create.call_args_list if c.args[0] == "high_refusal_rate"
    )
    assert "Okra" in msg


def test_low_satisfaction_triggers_alert():
    report = _report(
        feedback_summary={
            "total_feedback": 30,
            "satisfaction_rate": 0.4,
            "most_downvoted_questions": [{"question": "carrot price in Galle"}],
        },
    )
    with patch.object(ns, "_recent_types", return_value=set()), patch.object(
        ns, "create_notification", return_value="id2"
    ) as create:
        ns.check_analytics_alerts(report)
    types = [c.args[0] for c in create.call_args_list]
    assert "low_satisfaction" in types


def test_low_satisfaction_needs_enough_feedback():
    """A 40% rate off 3 votes is noise, not an alert."""
    report = _report(
        response_breakdown={"answer": 100},
        feedback_summary={
            "total_feedback": 3,
            "satisfaction_rate": 0.33,
            "most_downvoted_questions": [],
        },
    )
    with patch.object(ns, "_recent_types", return_value=set()), patch.object(
        ns, "create_notification", return_value="id"
    ) as create:
        ns.check_analytics_alerts(report)
    types = [c.args[0] for c in create.call_args_list]
    assert "low_satisfaction" not in types


def test_dedup_skips_alert_created_in_last_24h():
    report = _report(response_breakdown={"answer": 40, "refusal": 60})
    with patch.object(
        ns, "_recent_types", return_value={"high_refusal_rate"}
    ), patch.object(ns, "create_notification", return_value="id") as create:
        ns.check_analytics_alerts(report)
    types = [c.args[0] for c in create.call_args_list]
    assert "high_refusal_rate" not in types


def test_small_sample_produces_no_alerts():
    report = _report(
        total_interactions=5,
        response_breakdown={"refusal": 5},
    )
    with patch.object(ns, "_recent_types", return_value=set()) as recent, patch.object(
        ns, "create_notification"
    ) as create:
        out = ns.check_analytics_alerts(report)
    assert out == []
    create.assert_not_called()
    recent.assert_not_called()  # short-circuits before the dedup lookup


def test_milestone_alert_fires_once():
    report = _report(
        response_breakdown={"answer": 100},  # no refusal alert
        feedback_summary={"total_feedback": 0, "satisfaction_rate": 0.0},
    )
    with patch.object(ns, "_recent_types", return_value=set()), patch.object(
        ns, "create_notification", return_value="id"
    ) as create:
        ns.check_analytics_alerts(report)
    types = [c.args[0] for c in create.call_args_list]
    assert types == ["analytics_milestone"]


def test_check_never_raises():
    with patch.object(ns, "_recent_types", side_effect=RuntimeError("x")):
        # A malformed/oversized report or a failed dedup lookup must not bubble.
        assert ns.check_analytics_alerts(_report()) == []


# ═══════════════════════════════════════════════════════════════════════════
# Email escalation (Phase B)
# ═══════════════════════════════════════════════════════════════════════════

import time  # noqa: E402
import pytest  # noqa: E402


@pytest.fixture(autouse=True)
def _reset_email_state():
    """The per-type rate-limit dict and recipient cache are module globals —
    reset them so email tests don't leak state into each other."""
    ns._email_state.clear()
    ns.invalidate_recipient_cache()
    yield
    ns._email_state.clear()
    ns.invalidate_recipient_cache()


# ── _maybe_email: worthiness gate ─────────────────────────────────────────────


def test_non_worthy_type_never_spawns_an_email_thread():
    with patch.object(ns.threading, "Thread") as thread:
        ns._maybe_email("adjustment_promoted", "t", "m", "success")
        ns._maybe_email("analytics_milestone", "t", "m", "info")
    thread.assert_not_called()


@pytest.mark.parametrize(
    "type_",
    [
        "adjustment_auto_removed",
        "adjustment_needs_review",
        "high_refusal_rate",
        "low_satisfaction",
    ],
)
def test_worthy_types_spawn_an_email_thread(type_):
    with patch.object(ns.threading, "Thread") as thread:
        ns._maybe_email(type_, "t", "m", "warning")
    thread.assert_called_once()
    assert thread.call_args.kwargs["target"] is ns._process_email
    thread.return_value.start.assert_called_once()


def test_create_notification_escalates_worthy_types():
    """End-to-end through create_notification: a worthy type reaches _maybe_email."""
    db, _ = _db_returning([])
    with patch("app.utils.firestore.get_db", return_value=db), patch.object(
        ns, "_maybe_email"
    ) as maybe:
        ns.create_notification("low_satisfaction", "Low", "msg", "error")
    maybe.assert_called_once_with("low_satisfaction", "Low", "msg", "error")


# ── _process_email: single vs batched ─────────────────────────────────────────


def test_process_email_single_event():
    with patch.object(ns, "_rate_limit_decision", return_value=1), patch.object(
        ns, "_admin_recipients", return_value=["a@b.com"]
    ), patch("app.admin.services.email_service.send_email_to") as send, patch(
        "app.config.get_settings"
    ) as settings:
        settings.return_value.dashboard_url = "https://dash.app"
        ns._process_email("low_satisfaction", "Low satisfaction alert", "msg", "error")
    send.assert_called_once()
    subject = send.call_args[0][1]
    assert subject == "CropSphere: Low satisfaction alert"


def test_process_email_batched_uses_plural_summary():
    with patch.object(ns, "_rate_limit_decision", return_value=3), patch.object(
        ns, "_admin_recipients", return_value=["a@b.com"]
    ), patch("app.admin.services.email_service.send_email_to") as send, patch(
        "app.config.get_settings"
    ):
        ns._process_email("adjustment_auto_removed", "one removed", "msg", "warning")
    subject = send.call_args[0][1]
    assert subject == "CropSphere: 3 adjustments were auto-removed in the last hour"


def test_process_email_suppressed_when_rate_limited():
    with patch.object(ns, "_rate_limit_decision", return_value=None), patch(
        "app.admin.services.email_service.send_email_to"
    ) as send:
        ns._process_email("high_refusal_rate", "t", "m", "warning")
    send.assert_not_called()


def test_process_email_no_send_without_recipients():
    with patch.object(ns, "_rate_limit_decision", return_value=1), patch.object(
        ns, "_admin_recipients", return_value=[]
    ), patch("app.admin.services.email_service.send_email_to") as send:
        ns._process_email("high_refusal_rate", "t", "m", "warning")
    send.assert_not_called()


def test_process_email_never_raises():
    with patch.object(ns, "_rate_limit_decision", side_effect=RuntimeError("boom")):
        ns._process_email("high_refusal_rate", "t", "m", "warning")  # no exception


# ── _rate_limit_decision: one per hour, with batching ─────────────────────────


def test_first_event_sends_immediately():
    assert ns._rate_limit_decision("high_refusal_rate") == 1


def test_events_within_the_hour_are_suppressed_and_counted():
    assert ns._rate_limit_decision("high_refusal_rate") == 1
    assert ns._rate_limit_decision("high_refusal_rate") is None
    assert ns._rate_limit_decision("high_refusal_rate") is None
    # Two were suppressed and counted as pending.
    assert ns._email_state["high_refusal_rate"]["pending"] == 2


def test_next_window_folds_in_the_suppressed_count():
    ns._rate_limit_decision("high_refusal_rate")  # sends (1)
    ns._rate_limit_decision("high_refusal_rate")  # pending 1
    ns._rate_limit_decision("high_refusal_rate")  # pending 2
    # Force the cooldown to have elapsed.
    ns._email_state["high_refusal_rate"]["last_sent"] = time.monotonic() - 3601
    # The re-opening event reports itself plus the two suppressed = 3.
    assert ns._rate_limit_decision("high_refusal_rate") == 3
    assert ns._email_state["high_refusal_rate"]["pending"] == 0


def test_rate_limit_is_per_type():
    assert ns._rate_limit_decision("high_refusal_rate") == 1
    # A different type has its own independent window.
    assert ns._rate_limit_decision("low_satisfaction") == 1


# ── _admin_recipients: filter + cache ─────────────────────────────────────────


def _users_db(users):
    docs = [_doc(f"u{i}", **u) for i, u in enumerate(users)]
    db = MagicMock()
    db.collection.return_value.stream.return_value = docs
    return db


def test_recipients_include_only_admins_who_opted_in():
    db = _users_db(
        [
            {"role": "admin", "email": "admin@x.com"},
            {"role": "superadmin", "email": "super@x.com"},
            {"role": "user", "email": "farmer@x.com"},  # not an admin
            {
                "role": "admin",
                "email": "optout@x.com",
                "preferences": {"email_notifications": False},
            },
            {"role": "admin", "email": ""},  # no address
        ]
    )
    with patch("app.utils.firestore.get_db", return_value=db):
        out = ns._admin_recipients()
    assert set(out) == {"admin@x.com", "super@x.com"}


def test_recipients_default_to_opted_in_when_unset():
    db = _users_db([{"role": "admin", "email": "a@x.com", "preferences": {}}])
    with patch("app.utils.firestore.get_db", return_value=db):
        assert ns._admin_recipients() == ["a@x.com"]


def test_recipients_exclude_non_canonical_false_string():
    """A preference stored as the string 'false' must still count as opted out —
    a plain truthiness check would read the non-empty string as opted in."""
    db = _users_db(
        [
            {
                "role": "admin",
                "email": "a@x.com",
                "preferences": {"email_notifications": "false"},
            },
            {
                "role": "admin",
                "email": "b@x.com",
                "preferences": {"email_notifications": True},
            },
        ]
    )
    with patch("app.utils.firestore.get_db", return_value=db):
        assert ns._admin_recipients() == ["b@x.com"]


@pytest.mark.parametrize(
    "prefs,expected",
    [
        (None, True),
        ({}, True),
        ({"email_notifications": True}, True),
        ({"email_notifications": False}, False),
        ({"email_notifications": "false"}, False),
        ({"email_notifications": "off"}, False),
        ({"email_notifications": 0}, False),
        ({"email_notifications": "true"}, True),
    ],
)
def test_email_opt_in_helper(prefs, expected):
    assert ns._email_opt_in(prefs) is expected


def test_recipients_are_cached():
    db = _users_db([{"role": "admin", "email": "a@x.com"}])
    with patch("app.utils.firestore.get_db", return_value=db):
        ns._admin_recipients()
        ns._admin_recipients()
    # Streamed once; the second call hit the cache.
    assert db.collection.return_value.stream.call_count == 1


def test_recipients_empty_on_firestore_failure():
    with patch("app.utils.firestore.get_db", side_effect=RuntimeError("down")):
        assert ns._admin_recipients() == []


# ── email preference get/set ──────────────────────────────────────────────────


def test_get_email_preference_defaults_true():
    with patch("app.utils.firestore.get_user_preferences", return_value={}):
        assert ns.get_email_preference("uid") is True


def test_get_email_preference_reads_stored_false():
    with patch(
        "app.utils.firestore.get_user_preferences",
        return_value={"email_notifications": False},
    ):
        assert ns.get_email_preference("uid") is False


def test_set_email_preference_merges_without_clobbering():
    prefs = {"language": "en", "email_notifications": True}
    with patch(
        "app.utils.firestore.get_user_preferences", return_value=dict(prefs)
    ), patch("app.utils.firestore.update_user_preferences") as update:
        out = ns.set_email_preference("uid", False)
    assert out is False
    written = update.call_args[0][1]
    assert written["email_notifications"] is False
    assert written["language"] == "en"  # existing keys preserved


def test_set_email_preference_invalidates_recipient_cache():
    # Prime the cache.
    db = _users_db([{"role": "admin", "email": "a@x.com"}])
    with patch("app.utils.firestore.get_db", return_value=db):
        ns._admin_recipients()
    with patch("app.utils.firestore.get_user_preferences", return_value={}), patch(
        "app.utils.firestore.update_user_preferences"
    ):
        ns.set_email_preference("uid", True)
    # Next lookup must re-stream (cache was dropped).
    with patch("app.utils.firestore.get_db", return_value=db):
        ns._admin_recipients()
    assert db.collection.return_value.stream.call_count == 2
