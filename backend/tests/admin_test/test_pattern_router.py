"""Integration tests for the /api/admin/*-pattern* routes.

Exercises the full HTTP stack — JWT auth, role gating (analysis/mutation is
superadmin-only, reads are admin-readable) and body validation — with the
override store redirected at a tmp_path and Firestore mocked out.
"""

from pathlib import Path
from unittest.mock import patch

import pytest

from app.admin.services import pattern_analyzer_service as svc
from app.user.services import chatbot_service as chat_svc
from app.user.services import pattern_override_store as store_mod


@pytest.fixture(autouse=True)
def _tmp_store(tmp_path, monkeypatch):
    monkeypatch.setattr(store_mod, "_DATA_DIR", Path(tmp_path))
    monkeypatch.setattr(
        store_mod, "OVERRIDES_PATH", tmp_path / "pattern_overrides.json"
    )
    monkeypatch.setattr(store_mod, "_LOCK_PATH", tmp_path / "pattern_overrides.lock")
    monkeypatch.setattr(store_mod, "_mirror_audit", lambda entry: None)
    monkeypatch.setattr(svc, "_notify_gaps", lambda proposals: None)
    monkeypatch.setattr(svc, "_notify_problematic", lambda patterns: None)
    svc._proposal_cache.clear()
    chat_svc._pattern_overrides = None
    yield
    svc._proposal_cache.clear()
    chat_svc._pattern_overrides = None


def _as(role):
    return patch("app.utils.firestore.get_user_role", return_value=role)


def _seed_active(pattern_id="reform_x", phrase="make it easier"):
    store_mod.apply_patterns(
        [
            {
                "id": pattern_id,
                "category": "reformulation",
                "phrase": phrase,
                "original_proposed_phrase": phrase,
                "edited": False,
                "evidence_count": 8,
            }
        ],
        "admin-uid",
    )


# ── Auth / role gating ────────────────────────────────────────────────────────


@pytest.mark.parametrize(
    "method,path",
    [
        ("post", "/api/admin/analyze-patterns"),
        ("post", "/api/admin/apply-patterns"),
        ("get", "/api/admin/active-patterns"),
        ("get", "/api/admin/revoked-patterns"),
        ("get", "/api/admin/pattern-analytics/reform_x"),
        ("post", "/api/admin/revoke-pattern/reform_x"),
        ("post", "/api/admin/restore-pattern/reform_x"),
        ("delete", "/api/admin/delete-pattern/reform_x"),
    ],
)
def test_no_jwt_returns_401(client, mock_expired_token, method, path):
    assert getattr(client, method)(path).status_code == 401


@pytest.mark.parametrize(
    "method,path,body",
    [
        ("post", "/api/admin/analyze-patterns", None),
        ("post", "/api/admin/apply-patterns", {"patterns": []}),
        ("post", "/api/admin/revoke-pattern/reform_x", {"reason": "Too broad"}),
        ("post", "/api/admin/restore-pattern/reform_x", None),
        ("delete", "/api/admin/delete-pattern/reform_x", None),
    ],
)
def test_plain_admin_gets_403_on_mutating_routes(
    client, mock_valid_token, valid_auth_header, method, path, body
):
    kwargs = {"headers": valid_auth_header}
    if body is not None:
        kwargs["json"] = body  # TestClient.delete() takes no json argument
    with _as("admin"):
        resp = getattr(client, method)(path, **kwargs)
    assert resp.status_code == 403


@pytest.mark.parametrize(
    "path", ["/api/admin/active-patterns", "/api/admin/revoked-patterns"]
)
def test_plain_admin_can_read(client, mock_valid_token, valid_auth_header, path):
    with _as("admin"):
        assert client.get(path, headers=valid_auth_header).status_code == 200


def test_regular_user_gets_403_on_reads(client, mock_valid_token, valid_auth_header):
    with _as("user"):
        resp = client.get("/api/admin/active-patterns", headers=valid_auth_header)
    assert resp.status_code == 403


# ── Analyze ───────────────────────────────────────────────────────────────────


def test_analyze_returns_proposals(client, mock_valid_token, valid_auth_header):
    docs = [
        {
            "question": "make it easier to understand",
            "response_type": "refusal",
            "session_message_count": 3,
        }
    ] * 6
    with _as("superadmin"), patch.object(svc, "_fetch_analytics", return_value=docs):
        resp = client.post(
            "/api/admin/analyze-patterns?days=14", headers=valid_auth_header
        )

    assert resp.status_code == 200
    body = resp.json()
    assert body["period_days"] == 14
    assert body["total_analyzed"] == 6
    assert body["proposed_patterns"][0]["confidence"] == "high"


def test_analyze_saves_nothing(client, mock_valid_token, valid_auth_header):
    docs = [
        {
            "question": "make it easier to understand",
            "response_type": "refusal",
            "session_message_count": 3,
        }
    ] * 6
    with _as("superadmin"), patch.object(svc, "_fetch_analytics", return_value=docs):
        client.post("/api/admin/analyze-patterns", headers=valid_auth_header)
    assert store_mod.load()["active"] == []


# ── Apply ─────────────────────────────────────────────────────────────────────


def _analyze_then(client, header, selections):
    docs = [
        {
            "question": "make it easier to understand",
            "response_type": "refusal",
            "session_message_count": 3,
        }
    ] * 6
    with _as("superadmin"), patch.object(svc, "_fetch_analytics", return_value=docs):
        analysis = client.post("/api/admin/analyze-patterns", headers=header).json()
        pid = analysis["proposed_patterns"][0]["id"]
        phrase = analysis["proposed_patterns"][0]["proposed_phrase"]
        resp = client.post(
            "/api/admin/apply-patterns",
            json={"patterns": selections(pid, phrase)},
            headers=header,
        )
    return pid, phrase, resp


def test_apply_activates_and_reloads_cache(client, mock_valid_token, valid_auth_header):
    pid, phrase, resp = _analyze_then(
        client,
        valid_auth_header,
        lambda pid, phrase: [{"id": pid, "phrase": phrase, "edited": False}],
    )
    assert resp.status_code == 200
    assert resp.json()["applied_ids"] == [pid]
    # The cache was reloaded, so the phrase routes immediately.
    assert chat_svc._is_reformulation_request(f"can you {phrase}")


def test_apply_honours_an_edit(client, mock_valid_token, valid_auth_header):
    pid, _phrase, resp = _analyze_then(
        client,
        valid_auth_header,
        lambda pid, phrase: [
            {
                "id": pid,
                "phrase": "much more readable",
                "edited": True,
                "original_phrase": phrase,
            }
        ],
    )
    assert resp.status_code == 200
    item = store_mod.find_active(store_mod.load(), pid)
    assert item["phrase"] == "much more readable"
    assert item["edited"] is True


def test_apply_rejects_regex_metacharacters(
    client, mock_valid_token, valid_auth_header
):
    _pid, _phrase, resp = _analyze_then(
        client,
        valid_auth_header,
        lambda pid, phrase: [{"id": pid, "phrase": "grow.*", "edited": True}],
    )
    assert resp.status_code == 200
    assert resp.json()["applied_count"] == 0
    assert "cannot contain" in resp.json()["skipped"][0]["reason"]


@pytest.mark.parametrize(
    "body",
    [
        {},
        {"patterns": []},
        {"patterns": [{"id": "reform_x"}]},
        {"patterns": [{"id": "reform_x", "phrase": "ab"}]},
        {"patterns": [{"id": "reform_x", "phrase": "x" * 51}]},
        {"patterns": [{"id": "", "phrase": "make it easier"}]},
    ],
)
def test_apply_rejects_malformed_bodies(
    client, mock_valid_token, valid_auth_header, body
):
    with _as("superadmin"):
        resp = client.post(
            "/api/admin/apply-patterns", json=body, headers=valid_auth_header
        )
    assert resp.status_code == 422


# ── Read side ─────────────────────────────────────────────────────────────────


def test_active_patterns_reports_counters(client, mock_valid_token, valid_auth_header):
    _seed_active()
    store_mod.record_hit("reform_x", "make it easier", "make it easier", "c1")
    with _as("admin"):
        body = client.get(
            "/api/admin/active-patterns", headers=valid_auth_header
        ).json()

    assert body["count"] == 1
    pattern = body["active"][0]
    assert pattern["hit_count"] == 1
    assert pattern["verdict"] == "insufficient_data"
    assert pattern["satisfaction_rate"] == 0.0


def test_pattern_analytics_returns_detail(client, mock_valid_token, valid_auth_header):
    _seed_active()
    store_mod.record_hit("reform_x", "make it easier pls", "make it easier", "c1")
    store_mod.record_feedback("c1", "make it easier pls", "down")

    with _as("admin"):
        resp = client.get(
            "/api/admin/pattern-analytics/reform_x", headers=valid_auth_header
        )

    assert resp.status_code == 200
    body = resp.json()
    assert body["hit_count"] == 1
    assert body["feedback"]["thumbs_down"] == 1
    assert body["false_positive_candidates"][0]["message"] == "make it easier pls"


def test_pattern_analytics_unknown_id_returns_404(
    client, mock_valid_token, valid_auth_header
):
    with _as("admin"):
        resp = client.get(
            "/api/admin/pattern-analytics/nope", headers=valid_auth_header
        )
    assert resp.status_code == 404


# ── Revoke / restore / delete ─────────────────────────────────────────────────


def test_revoke_requires_a_reason(client, mock_valid_token, valid_auth_header):
    _seed_active()
    with _as("superadmin"):
        assert (
            client.post(
                "/api/admin/revoke-pattern/reform_x",
                json={"reason": ""},
                headers=valid_auth_header,
            ).status_code
            == 422
        )
        assert (
            client.post(
                "/api/admin/revoke-pattern/reform_x",
                json={},
                headers=valid_auth_header,
            ).status_code
            == 422
        )


def test_revoke_moves_pattern_and_stops_matching(
    client, mock_valid_token, valid_auth_header
):
    _seed_active()
    chat_svc._reload_pattern_overrides()
    assert chat_svc._is_reformulation_request("make it easier")

    with _as("superadmin"), patch(
        "app.admin.services.system_config_service.get_prompt_tuning_config",
        return_value={"trash_retention_days": 14},
    ):
        resp = client.post(
            "/api/admin/revoke-pattern/reform_x",
            json={"reason": "Too broad - matched real questions"},
            headers=valid_auth_header,
        )

    assert resp.status_code == 200
    assert (
        resp.json()["pattern"]["revoke_reason"] == "Too broad - matched real questions"
    )
    assert not chat_svc._is_reformulation_request("make it easier")


def test_revoke_unknown_id_returns_404(client, mock_valid_token, valid_auth_header):
    with _as("superadmin"), patch(
        "app.admin.services.system_config_service.get_prompt_tuning_config",
        return_value={"trash_retention_days": 14},
    ):
        resp = client.post(
            "/api/admin/revoke-pattern/nope",
            json={"reason": "gone"},
            headers=valid_auth_header,
        )
    assert resp.status_code == 404


def test_restore_returns_pattern_with_fresh_counters(
    client, mock_valid_token, valid_auth_header
):
    _seed_active()
    store_mod.record_hit("reform_x", "make it easier", "make it easier", "c1")
    store_mod.revoke_pattern("reform_x", "admin-uid", "Too broad")

    with _as("superadmin"):
        resp = client.post(
            "/api/admin/restore-pattern/reform_x", headers=valid_auth_header
        )

    assert resp.status_code == 200
    assert resp.json()["pattern"]["hit_count"] == 0


def test_restore_conflict_returns_409(client, mock_valid_token, valid_auth_header):
    _seed_active()
    store_mod.revoke_pattern("reform_x", "admin-uid", "Too broad")
    _seed_active()  # same id active again while still in the revoked list

    with _as("superadmin"):
        resp = client.post(
            "/api/admin/restore-pattern/reform_x", headers=valid_auth_header
        )
    assert resp.status_code == 409


def test_delete_refuses_an_active_pattern(client, mock_valid_token, valid_auth_header):
    _seed_active()
    with _as("superadmin"):
        resp = client.delete(
            "/api/admin/delete-pattern/reform_x", headers=valid_auth_header
        )
    assert resp.status_code == 404
    assert store_mod.find_active(store_mod.load(), "reform_x") is not None


def test_delete_removes_a_revoked_pattern(client, mock_valid_token, valid_auth_header):
    _seed_active()
    store_mod.revoke_pattern("reform_x", "admin-uid", "Too broad")
    with _as("superadmin"):
        resp = client.delete(
            "/api/admin/delete-pattern/reform_x", headers=valid_auth_header
        )
    assert resp.status_code == 200
    assert store_mod.load()["revoked"] == []
