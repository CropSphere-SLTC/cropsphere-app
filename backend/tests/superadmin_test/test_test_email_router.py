"""HTTP tests for POST /api/superadmin/test-email.

Verifies role gating and that the endpoint sends only to the requesting
superadmin's own address (never to other users). email_service is mocked — no
real mail is sent.
"""

from unittest.mock import patch


def _as_role(role):
    return patch("app.utils.firestore.get_user_role", return_value=role)


def test_test_email_no_jwt_returns_401(client, mock_expired_token):
    resp = client.post("/api/superadmin/test-email")
    assert resp.status_code == 401


def test_test_email_admin_gets_403(client, mock_valid_token, valid_auth_header):
    """A plain admin cannot trigger the SMTP test — superadmin only."""
    with _as_role("admin"):
        resp = client.post("/api/superadmin/test-email", headers=valid_auth_header)
    assert resp.status_code == 403


def test_test_email_sends_to_requesting_superadmin(
    client, mock_valid_token, valid_auth_header
):
    with _as_role("superadmin"), patch(
        "app.utils.firestore.get_user_profile",
        return_value={"email": "super@cropsphere.app"},
    ), patch("app.admin.services.email_service.send_email") as send:
        resp = client.post("/api/superadmin/test-email", headers=valid_auth_header)

    assert resp.status_code == 200
    body = resp.json()
    assert body["status"] == "ok"
    assert body["sent_to"] == "super@cropsphere.app"
    assert "email_enabled" in body
    # Sent to the caller's own address only.
    assert send.call_args[0][0] == "super@cropsphere.app"


def test_test_email_400_when_no_email_on_file(
    client, mock_valid_token, valid_auth_header
):
    with _as_role("superadmin"), patch(
        "app.utils.firestore.get_user_profile", return_value={"email": ""}
    ), patch("app.admin.services.email_service.send_email") as send:
        resp = client.post("/api/superadmin/test-email", headers=valid_auth_header)
    assert resp.status_code == 400
    send.assert_not_called()
