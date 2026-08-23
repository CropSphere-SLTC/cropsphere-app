"""Unit tests for app.utils.firestore.

get_db() is patched at the module level so every helper function can be
tested without a real Firestore connection. init_firestore() tests patch
firebase_admin directly since that module is genuinely installed.
"""

import hashlib
import hmac
from unittest.mock import MagicMock, patch

import pytest

from app.utils import firestore as fs


def _mock_doc(exists: bool, data: dict = None, doc_id: str = "doc-1"):
    """Build a fake Firestore DocumentSnapshot."""
    doc = MagicMock()
    doc.exists = exists
    doc.id = doc_id
    doc.to_dict.return_value = data or {}
    return doc


@pytest.fixture(autouse=True)
def reset_db_singleton():
    """Ensure the module-level _db doesn't leak between tests."""
    original = fs._db
    yield
    fs._db = original


# ═══════════════════════════════════════════════════════════════════════════
# init_firestore
# ═══════════════════════════════════════════════════════════════════════════


def test_init_firestore_raises_for_placeholder_path():
    with pytest.raises(ValueError):
        fs.init_firestore("/path/to/creds.json", "proj")


def test_init_firestore_raises_for_empty_credentials():
    with pytest.raises(ValueError):
        fs.init_firestore("", "proj")


def test_init_firestore_initializes_new_app_with_json_string():
    with patch("firebase_admin._apps", new={}), patch(
        "firebase_admin.initialize_app"
    ) as mock_init, patch("firebase_admin.credentials.Certificate") as mock_cert, patch(
        "firebase_admin.firestore.client"
    ) as mock_client:
        fs.init_firestore('{"type": "service_account"}', "proj")

    mock_cert.assert_called_once_with({"type": "service_account"})
    mock_init.assert_called_once()
    mock_client.assert_called_once_with(database_id="cropsphere-database")


def test_init_firestore_initializes_new_app_with_file_path():
    with patch("firebase_admin._apps", new={}), patch(
        "firebase_admin.initialize_app"
    ) as mock_init, patch("firebase_admin.credentials.Certificate") as mock_cert, patch(
        "firebase_admin.firestore.client"
    ):
        fs.init_firestore("/etc/secrets/creds.json", "proj")

    mock_cert.assert_called_once_with("/etc/secrets/creds.json")
    mock_init.assert_called_once()


def test_init_firestore_reinits_when_existing_app_has_default_credentials():
    fake_app = MagicMock()
    fake_app.credential.__class__.__name__ = "ApplicationDefaultCredentials"

    with patch("firebase_admin._apps", new={"[DEFAULT]": fake_app}), patch(
        "firebase_admin.get_app", return_value=fake_app
    ), patch("firebase_admin.delete_app") as mock_delete, patch(
        "firebase_admin.initialize_app"
    ) as mock_init, patch(
        "firebase_admin.credentials.Certificate"
    ), patch(
        "firebase_admin.firestore.client"
    ):
        fs.init_firestore('{"type": "service_account"}', "proj")

    mock_delete.assert_called_once_with(fake_app)
    mock_init.assert_called_once()


def test_init_firestore_reinits_with_file_path_when_default_credentials():
    """Covers the else-branch (file path, not JSON) inside the re-init block."""
    fake_app = MagicMock()
    fake_app.credential.__class__.__name__ = "ApplicationDefaultCredentials"

    with patch("firebase_admin._apps", new={"[DEFAULT]": fake_app}), patch(
        "firebase_admin.get_app", return_value=fake_app
    ), patch("firebase_admin.delete_app") as mock_delete, patch(
        "firebase_admin.initialize_app"
    ) as mock_init, patch(
        "firebase_admin.credentials.Certificate"
    ) as mock_cert, patch(
        "firebase_admin.firestore.client"
    ):
        fs.init_firestore("/etc/secrets/creds.json", "proj")

    mock_cert.assert_called_once_with("/etc/secrets/creds.json")
    mock_delete.assert_called_once_with(fake_app)
    mock_init.assert_called_once()


def test_init_firestore_skips_reinit_when_existing_app_has_real_credentials():
    fake_app = MagicMock()
    fake_app.credential.__class__.__name__ = "Certificate"

    with patch("firebase_admin._apps", new={"[DEFAULT]": fake_app}), patch(
        "firebase_admin.get_app", return_value=fake_app
    ), patch("firebase_admin.delete_app") as mock_delete, patch(
        "firebase_admin.initialize_app"
    ) as mock_init, patch(
        "firebase_admin.firestore.client"
    ) as mock_client:
        fs.init_firestore('{"type": "service_account"}', "proj")

    mock_delete.assert_not_called()
    mock_init.assert_not_called()
    mock_client.assert_called_once_with(database_id="cropsphere-database")


# ═══════════════════════════════════════════════════════════════════════════
# get_db
# ═══════════════════════════════════════════════════════════════════════════


def test_get_db_raises_when_not_initialised():
    fs._db = None
    with pytest.raises(RuntimeError):
        fs.get_db()


def test_get_db_returns_client_when_initialised():
    fake_client = MagicMock()
    fs._db = fake_client
    assert fs.get_db() is fake_client


# ═══════════════════════════════════════════════════════════════════════════
# get_or_create_user
# ═══════════════════════════════════════════════════════════════════════════


def test_get_or_create_user_returns_existing_and_updates_photo():
    existing = {"uid": "u1", "role": "user"}
    mock_ref = MagicMock()
    mock_ref.get.return_value = _mock_doc(True, existing)
    mock_db = MagicMock()
    mock_db.collection.return_value.document.return_value = mock_ref

    with patch("app.utils.firestore.get_db", return_value=mock_db):
        result = fs.get_or_create_user("u1", photo_url="http://new.jpg")

    mock_ref.update.assert_called_once_with({"photo_url": "http://new.jpg"})
    assert result == existing


def test_get_or_create_user_creates_new_regular_user():
    mock_ref = MagicMock()
    mock_ref.get.return_value = _mock_doc(False)
    mock_db = MagicMock()
    mock_db.collection.return_value.document.return_value = mock_ref

    with patch("app.utils.firestore.get_db", return_value=mock_db), patch(
        "app.config.get_settings"
    ) as mock_settings:
        mock_settings.return_value.SUPERADMIN_UID = "super-uid-1"
        result = fs.get_or_create_user("new-uid", email="a@x.com")

    mock_ref.set.assert_called_once()
    assert result["role"] == "user"
    assert result["uid"] == "new-uid"


def test_get_or_create_user_assigns_superadmin_role_for_superadmin_uid():
    mock_ref = MagicMock()
    mock_ref.get.return_value = _mock_doc(False)
    mock_db = MagicMock()
    mock_db.collection.return_value.document.return_value = mock_ref

    with patch("app.utils.firestore.get_db", return_value=mock_db), patch(
        "app.config.get_settings"
    ) as mock_settings:
        mock_settings.return_value.SUPERADMIN_UID = "super-uid-1,super-uid-2"
        result = fs.get_or_create_user("super-uid-2")

    assert result["role"] == "superadmin"


def test_get_or_create_user_failure_returns_safe_fallback():
    with patch("app.utils.firestore.get_db", side_effect=RuntimeError("down")):
        result = fs.get_or_create_user("u1")

    assert result == {"uid": "u1", "role": "user", "is_banned": False}


# ═══════════════════════════════════════════════════════════════════════════
# get_user_role
# ═══════════════════════════════════════════════════════════════════════════


def test_get_user_role_returns_superadmin_for_superadmin_uid():
    with patch("app.config.get_settings") as mock_settings:
        mock_settings.return_value.SUPERADMIN_UID = "super-uid-1"
        result = fs.get_user_role("super-uid-1")
    assert result == "superadmin"


def test_get_user_role_returns_banned_when_flagged():
    mock_db = MagicMock()
    mock_db.collection.return_value.document.return_value.get.return_value = _mock_doc(
        True, {"is_banned": True, "role": "user"}
    )

    with patch("app.config.get_settings") as mock_settings, patch(
        "app.utils.firestore.get_db", return_value=mock_db
    ):
        mock_settings.return_value.SUPERADMIN_UID = "someone-else"
        result = fs.get_user_role("u1")

    assert result == "banned"


def test_get_user_role_returns_stored_role():
    mock_db = MagicMock()
    mock_db.collection.return_value.document.return_value.get.return_value = _mock_doc(
        True, {"is_banned": False, "role": "admin"}
    )

    with patch("app.config.get_settings") as mock_settings, patch(
        "app.utils.firestore.get_db", return_value=mock_db
    ):
        mock_settings.return_value.SUPERADMIN_UID = "someone-else"
        result = fs.get_user_role("u1")

    assert result == "admin"


def test_get_user_role_returns_user_when_doc_missing():
    mock_db = MagicMock()
    mock_db.collection.return_value.document.return_value.get.return_value = _mock_doc(
        False
    )

    with patch("app.config.get_settings") as mock_settings, patch(
        "app.utils.firestore.get_db", return_value=mock_db
    ):
        mock_settings.return_value.SUPERADMIN_UID = "someone-else"
        result = fs.get_user_role("u1")

    assert result == "user"


def test_get_user_role_failure_returns_user_fallback():
    with patch("app.config.get_settings", side_effect=RuntimeError("down")):
        result = fs.get_user_role("u1")
    assert result == "user"


# ═══════════════════════════════════════════════════════════════════════════
# is_user_banned
# ═══════════════════════════════════════════════════════════════════════════


def test_is_user_banned_true():
    mock_db = MagicMock()
    mock_db.collection.return_value.document.return_value.get.return_value = _mock_doc(
        True, {"is_banned": True}
    )
    with patch("app.utils.firestore.get_db", return_value=mock_db):
        assert fs.is_user_banned("u1") is True


def test_is_user_banned_false_when_doc_missing():
    mock_db = MagicMock()
    mock_db.collection.return_value.document.return_value.get.return_value = _mock_doc(
        False
    )
    with patch("app.utils.firestore.get_db", return_value=mock_db):
        assert fs.is_user_banned("u1") is False


def test_is_user_banned_failure_returns_false():
    with patch("app.utils.firestore.get_db", side_effect=RuntimeError("down")):
        assert fs.is_user_banned("u1") is False


# ═══════════════════════════════════════════════════════════════════════════
# get_user_profile / update_user_profile
# ═══════════════════════════════════════════════════════════════════════════


def test_get_user_profile_returns_data():
    mock_db = MagicMock()
    mock_db.collection.return_value.document.return_value.get.return_value = _mock_doc(
        True, {"email": "a@x.com"}
    )
    with patch("app.utils.firestore.get_db", return_value=mock_db):
        result = fs.get_user_profile("u1")
    assert result == {"email": "a@x.com"}


def test_get_user_profile_raises_when_missing():
    mock_db = MagicMock()
    mock_db.collection.return_value.document.return_value.get.return_value = _mock_doc(
        False
    )
    with patch("app.utils.firestore.get_db", return_value=mock_db):
        with pytest.raises(RuntimeError):
            fs.get_user_profile("u1")


def test_update_user_profile_calls_update():
    mock_ref = MagicMock()
    mock_db = MagicMock()
    mock_db.collection.return_value.document.return_value = mock_ref
    with patch("app.utils.firestore.get_db", return_value=mock_db):
        fs.update_user_profile("u1", "New Name")
    mock_ref.update.assert_called_once_with({"display_name": "New Name"})


# ═══════════════════════════════════════════════════════════════════════════
# get_user_preferences / update_user_preferences
# ═══════════════════════════════════════════════════════════════════════════


def test_get_user_preferences_returns_saved_prefs():
    mock_db = MagicMock()
    mock_db.collection.return_value.document.return_value.get.return_value = _mock_doc(
        True, {"preferences": {"language": "si"}}
    )
    with patch("app.utils.firestore.get_db", return_value=mock_db):
        result = fs.get_user_preferences("u1")
    assert result == {"language": "si"}


def test_get_user_preferences_empty_when_doc_missing():
    mock_db = MagicMock()
    mock_db.collection.return_value.document.return_value.get.return_value = _mock_doc(
        False
    )
    with patch("app.utils.firestore.get_db", return_value=mock_db):
        result = fs.get_user_preferences("u1")
    assert result == {}


def test_update_user_preferences_writes_dotted_paths():
    """Saving preferences must not clobber siblings it wasn't given.

    This previously asserted a whole-map replace
    ({"preferences": {...}}), which is what made an Account Settings save
    silently wipe preferred_crop / preferred_district / context_updated_at
    written separately by update_user_context(). Dotted paths touch only
    the supplied keys — same guarantee the context writer already had.
    """
    mock_ref = MagicMock()
    mock_db = MagicMock()
    mock_db.collection.return_value.document.return_value = mock_ref
    with patch("app.utils.firestore.get_db", return_value=mock_db):
        fs.update_user_preferences("u1", {"language": "ta"})
    payload = mock_ref.update.call_args[0][0]
    assert payload == {"preferences.language": "ta"}
    assert "preferences" not in payload  # never a whole-map replace


def test_update_user_preferences_preserves_unrelated_keys():
    """A language-only save must not emit any preferred_* field path."""
    mock_ref = MagicMock()
    mock_db = MagicMock()
    mock_db.collection.return_value.document.return_value = mock_ref
    with patch("app.utils.firestore.get_db", return_value=mock_db):
        fs.update_user_preferences(
            "u1", {"language": "si", "notifications": {"price_alerts": False}}
        )
    payload = mock_ref.update.call_args[0][0]
    assert set(payload) == {"preferences.language", "preferences.notifications"}
    assert "preferences.preferred_crop" not in payload
    assert "preferences.preferred_district" not in payload


def test_update_user_preferences_noop_on_empty():
    """Nothing to write means no Firestore call at all."""
    mock_ref = MagicMock()
    mock_db = MagicMock()
    mock_db.collection.return_value.document.return_value = mock_ref
    with patch("app.utils.firestore.get_db", return_value=mock_db):
        fs.update_user_preferences("u1", {})
    mock_ref.update.assert_not_called()


def test_update_user_context_merges_via_field_paths():
    mock_ref = MagicMock()
    mock_db = MagicMock()
    mock_db.collection.return_value.document.return_value = mock_ref
    with patch("app.utils.firestore.get_db", return_value=mock_db):
        fs.update_user_context("u1", preferred_district="Jaffna")
    payload = mock_ref.update.call_args[0][0]
    # Dotted paths only — language/notifications siblings are never touched.
    assert payload["preferences.preferred_district"] == "Jaffna"
    assert "preferences.preferred_crop" not in payload
    assert "preferences.context_updated_at" in payload
    assert "preferences" not in payload  # never a whole-map replace


def test_update_user_context_noop_when_nothing_given():
    mock_ref = MagicMock()
    mock_db = MagicMock()
    mock_db.collection.return_value.document.return_value = mock_ref
    with patch("app.utils.firestore.get_db", return_value=mock_db):
        fs.update_user_context("u1")
    mock_ref.update.assert_not_called()


# ═══════════════════════════════════════════════════════════════════════════
# update_last_login
# ═══════════════════════════════════════════════════════════════════════════


def test_update_last_login_calls_update():
    mock_ref = MagicMock()
    mock_db = MagicMock()
    mock_db.collection.return_value.document.return_value = mock_ref
    with patch("app.utils.firestore.get_db", return_value=mock_db):
        fs.update_last_login("u1")
    mock_ref.update.assert_called_once()


def test_update_last_login_swallows_failure():
    with patch("app.utils.firestore.get_db", side_effect=RuntimeError("down")):
        fs.update_last_login("u1")  # must not raise


# ═══════════════════════════════════════════════════════════════════════════
# get_active_sessions / create_session
# ═══════════════════════════════════════════════════════════════════════════


def test_get_active_sessions_counts_docs():
    mock_query = MagicMock()
    mock_query.stream.return_value = [MagicMock(), MagicMock(), MagicMock()]
    mock_db = MagicMock()
    mock_db.collection.return_value.where.return_value.where.return_value = mock_query
    with patch("app.utils.firestore.get_db", return_value=mock_db):
        result = fs.get_active_sessions("u1")
    assert result == 3


def test_get_active_sessions_failure_returns_zero():
    with patch("app.utils.firestore.get_db", side_effect=RuntimeError("down")):
        result = fs.get_active_sessions("u1")
    assert result == 0


def test_create_session_adds_document():
    mock_collection = MagicMock()
    mock_db = MagicMock()
    mock_db.collection.return_value = mock_collection
    with patch("app.utils.firestore.get_db", return_value=mock_db):
        fs.create_session("u1", "Chrome on Mac")
    mock_collection.add.assert_called_once()
    call_args = mock_collection.add.call_args[0][0]
    assert call_args["uid"] == "u1"
    assert call_args["device_info"] == "Chrome on Mac"


def test_create_session_swallows_failure():
    with patch("app.utils.firestore.get_db", side_effect=RuntimeError("down")):
        fs.create_session("u1", "Chrome")  # must not raise


# ═══════════════════════════════════════════════════════════════════════════
# Chat conversation history
# ═══════════════════════════════════════════════════════════════════════════


def test_list_conversations_returns_summaries():
    docs = [
        _mock_doc(
            True,
            {"title": "Rice", "updated_at": "t1", "message_count": 4},
            doc_id="c1",
        ),
        _mock_doc(
            True,
            {"title": "Weather", "updated_at": "t2", "message_count": 0},
            doc_id="c2",
        ),
    ]
    mock_stream = MagicMock()
    mock_stream.where.return_value.order_by.return_value.limit.return_value.stream.return_value = (  # noqa: E501
        docs
    )
    mock_db = MagicMock()
    mock_db.collection.return_value = mock_stream

    with patch("app.utils.firestore.get_db", return_value=mock_db):
        result = fs.list_conversations("u1")

    assert len(result) == 2
    assert result[0]["id"] == "c1"
    assert result[0]["title"] == "Rice"


def test_get_conversation_returns_data_with_id():
    mock_db = MagicMock()
    mock_db.collection.return_value.document.return_value.get.return_value = _mock_doc(
        True, {"uid": "u1", "title": "Rice"}, doc_id="c1"
    )
    with patch("app.utils.firestore.get_db", return_value=mock_db):
        result = fs.get_conversation("c1")

    assert result["id"] == "c1"
    assert result["title"] == "Rice"


def test_get_conversation_returns_none_when_missing():
    mock_db = MagicMock()
    mock_db.collection.return_value.document.return_value.get.return_value = _mock_doc(
        False
    )
    with patch("app.utils.firestore.get_db", return_value=mock_db):
        result = fs.get_conversation("missing-id")
    assert result is None


def test_create_conversation_returns_new_id():
    mock_ref = MagicMock()
    mock_ref.id = "new-conv-id"
    mock_db = MagicMock()
    mock_db.collection.return_value.add.return_value = (None, mock_ref)
    with patch("app.utils.firestore.get_db", return_value=mock_db):
        result = fs.create_conversation("u1", "New chat")
    assert result == "new-conv-id"


def test_append_messages_raises_when_conversation_missing():
    mock_db = MagicMock()
    mock_db.collection.return_value.document.return_value.get.return_value = _mock_doc(
        False
    )
    with patch("app.utils.firestore.get_db", return_value=mock_db):
        with pytest.raises(ValueError):
            fs.append_messages("missing-id", "hi", "hello")


def test_append_messages_raises_when_limit_reached():
    existing_messages = [{"role": "user", "content": "x"}] * (
        fs.MAX_MESSAGES_PER_CONVERSATION - 1
    )
    mock_db = MagicMock()
    mock_db.collection.return_value.document.return_value.get.return_value = _mock_doc(
        True, {"messages": existing_messages}
    )
    with patch("app.utils.firestore.get_db", return_value=mock_db):
        with pytest.raises(ValueError):
            fs.append_messages("c1", "hi", "hello")


def test_append_messages_success_updates_document():
    mock_ref = MagicMock()
    mock_ref.get.return_value = _mock_doc(True, {"messages": []})
    mock_db = MagicMock()
    mock_db.collection.return_value.document.return_value = mock_ref

    with patch("app.utils.firestore.get_db", return_value=mock_db):
        fs.append_messages("c1", "hi", "hello")

    mock_ref.update.assert_called_once()
    updated = mock_ref.update.call_args[0][0]
    assert updated["message_count"] == 2
    assert updated["messages"][0]["content"] == "hi"
    assert updated["messages"][1]["content"] == "hello"


def test_rename_conversation_calls_update():
    mock_ref = MagicMock()
    mock_db = MagicMock()
    mock_db.collection.return_value.document.return_value = mock_ref
    with patch("app.utils.firestore.get_db", return_value=mock_db):
        fs.rename_conversation("c1", "New title")
    args = mock_ref.update.call_args[0][0]
    assert args["title"] == "New title"


def test_delete_conversation_calls_delete():
    mock_ref = MagicMock()
    mock_db = MagicMock()
    mock_db.collection.return_value.document.return_value = mock_ref
    with patch("app.utils.firestore.get_db", return_value=mock_db):
        fs.delete_conversation("c1")
    mock_ref.delete.assert_called_once()


# ═══════════════════════════════════════════════════════════════════════════
# admin_audit_log
# ═══════════════════════════════════════════════════════════════════════════


def test_admin_audit_log_adds_document():
    mock_collection = MagicMock()
    mock_db = MagicMock()
    mock_db.collection.return_value = mock_collection
    with patch("app.utils.firestore.get_db", return_value=mock_db):
        fs.admin_audit_log("admin-1", "admin", "ban_user", "target-1", {"k": "v"})

    mock_collection.add.assert_called_once()
    payload = mock_collection.add.call_args[0][0]
    assert payload["actor_uid"] == "admin-1"
    assert payload["actor_role"] == "admin"
    assert payload["action"] == "ban_user"
    assert payload["target_uid"] == "target-1"


def test_admin_audit_log_swallows_failure():
    with patch("app.utils.firestore.get_db", side_effect=RuntimeError("down")):
        fs.admin_audit_log("admin-1", "admin", "ban_user")  # must not raise


# ═══════════════════════════════════════════════════════════════════════════
# audit_log
# ═══════════════════════════════════════════════════════════════════════════


def test_audit_log_writes_hash_and_hmac():
    mock_collection = MagicMock()
    mock_db = MagicMock()
    mock_db.collection.return_value = mock_collection

    with patch("app.utils.firestore.get_db", return_value=mock_db), patch.dict(
        "os.environ", {"AUDIT_HMAC_KEY": "test-key"}
    ):
        fs.audit_log("u1", "/api/yield/predict", {"crop": "Carrot"})

    mock_collection.add.assert_called_once()
    payload = mock_collection.add.call_args[0][0]
    assert payload["user_id"] == "u1"
    assert payload["endpoint"] == "/api/yield/predict"
    assert "input_hash" in payload
    assert "hmac_sha256" in payload

    # Verify the HMAC is correctly derived from the hash
    expected_hmac = hmac.new(
        b"test-key", payload["input_hash"].encode(), hashlib.sha256
    ).hexdigest()
    assert payload["hmac_sha256"] == expected_hmac


def test_audit_log_swallows_failure():
    with patch("app.utils.firestore.get_db", side_effect=RuntimeError("down")):
        fs.audit_log("u1", "/api/yield/predict", {"crop": "Carrot"})  # must not raise
