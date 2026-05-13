"""Audit log HMAC tests."""
from unittest.mock import MagicMock, patch


def test_audit_log_has_hmac(monkeypatch):
    mock_db = MagicMock()
    mock_col = MagicMock()
    mock_db.collection.return_value = mock_col
    monkeypatch.setenv("AUDIT_HMAC_KEY", "test-key")

    with patch("app.utils.firestore.get_db", return_value=mock_db):
        from app.utils.firestore import audit_log
        audit_log(
            user_id="user-123",
            endpoint="/api/yield/predict",
            input_data={"crop": "Carrot"},
        )

    written = mock_col.add.call_args[0][0]
    assert "hmac_sha256" in written, "hmac_sha256 field නෑ!"
    assert "input_hash" in written
    assert "user_id" in written
    print("HMAC field OK")