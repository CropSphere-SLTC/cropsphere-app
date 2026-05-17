"""Tests for HTTPS/SSL Enforcement."""
import pytest
from fastapi.testclient import TestClient
from app.main import app

client = TestClient(app)


def test_hsts_header_present():
    """HSTS header must be present in every response."""
    response = client.get("/api/health")
    assert response.status_code == 200
    assert "strict-transport-security" in response.headers
    print("✅ Test 1 Passed — HSTS header present")


def test_hsts_header_correct_value():
    """HSTS header must have correct max-age value."""
    response = client.get("/api/health")
    hsts = response.headers.get("strict-transport-security", "")
    assert "max-age=31536000" in hsts
    print("✅ Test 2 Passed — HSTS max-age correct")


def test_http_request_gets_hsts_header():
    """Every HTTP request must receive HSTS header."""
    response = client.get("/api/health")
    assert "strict-transport-security" in response.headers
    print("✅ Test 3 Passed — HTTP request gets HSTS header")


def test_normal_request_not_blocked():
    """Normal requests must not be blocked by HTTPS middleware."""
    response = client.get("/api/health")
    assert response.status_code == 200
    print("✅ Test 4 Passed — Normal requests not blocked")