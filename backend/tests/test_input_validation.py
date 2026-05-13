import pytest
from pydantic import ValidationError
from app.middleware.validation import PredictionInput, PriceInput


# ============================================
# TEST 1 — Valid Input
# ============================================
def test_valid_prediction_input():
    data = PredictionInput(
        crop="Carrot",
        rainfall=500.0,
        temperature=25.0,
        humidity=80.0
    )
    assert data.crop == "Carrot"
    assert data.rainfall == 500.0
    print("✅ Test 1 Passed — Valid input accepted")


# ============================================
# TEST 2 — Invalid Input
# ============================================
def test_invalid_crop_name():
    with pytest.raises(ValidationError) as exc_info:
        PredictionInput(
            crop="InvalidCrop",
            rainfall=500.0,
            temperature=25.0,
            humidity=80.0
        )
    assert "Invalid crop" in str(exc_info.value)
    print("✅ Test 2 Passed — Invalid crop rejected")


def test_invalid_rainfall():
    with pytest.raises(ValidationError):
        PredictionInput(
            crop="Carrot",
            rainfall=-999,  # Invalid — negative
            temperature=25.0,
            humidity=80.0
        )
    print("✅ Test 3 Passed — Invalid rainfall rejected")


def test_invalid_temperature():
    with pytest.raises(ValidationError):
        PredictionInput(
            crop="Carrot",
            rainfall=500.0,
            temperature=999,  # Invalid — too high
            humidity=80.0
        )
    print("✅ Test 4 Passed — Invalid temperature rejected")


def test_invalid_humidity():
    with pytest.raises(ValidationError):
        PredictionInput(
            crop="Carrot",
            rainfall=500.0,
            temperature=25.0,
            humidity=150  # Invalid — over 100
        )
    print("✅ Test 5 Passed — Invalid humidity rejected")


def test_invalid_month():
    with pytest.raises(ValidationError):
        PriceInput(
            crop="Carrot",
            month=13  # Invalid — no 13th month
        )
    print("✅ Test 6 Passed — Invalid month rejected")
