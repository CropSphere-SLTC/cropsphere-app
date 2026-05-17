"""Tests for NoSQL Injection Prevention."""
import pytest
from app.utils.sanitizer import sanitize_string, sanitize_dict


def test_normal_input_passes():
    """Normal crop names should pass sanitization."""
    result = sanitize_string("Carrot")
    assert result == "Carrot"
    print("✅ Test 1 Passed — Normal input accepted")


def test_dollar_sign_injection_blocked():
    """MongoDB-style $ operators must be blocked."""
    with pytest.raises(ValueError):
        sanitize_string("$where: function()")
    print("✅ Test 2 Passed — $ injection blocked")


def test_script_injection_blocked():
    """Script injection must be blocked."""
    with pytest.raises(ValueError):
        sanitize_string("<script>alert('hacked')</script>")
    print("✅ Test 3 Passed — Script injection blocked")


def test_javascript_injection_blocked():
    """JavaScript injection must be blocked."""
    with pytest.raises(ValueError):
        sanitize_string("javascript:alert(1)")
    print("✅ Test 4 Passed — JavaScript injection blocked")


def test_dict_sanitization_works():
    """Dictionary with normal values should pass."""
    data = {"crop": "Maize", "district": "Colombo"}
    result = sanitize_dict(data)
    assert result["crop"] == "Maize"
    print("✅ Test 5 Passed — Dict sanitization works")


def test_dict_with_malicious_value_blocked():
    """Dictionary with malicious value must be blocked."""
    data = {"crop": "$where: hack", "district": "Colombo"}
    with pytest.raises(ValueError):
        sanitize_dict(data)
    print("✅ Test 6 Passed — Malicious dict blocked")