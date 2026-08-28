"""Unit tests for app.user.services.price_service.

Calls the service functions directly (no HTTP layer) so _build_sequence and
both the scaler / no-scaler branches of predict_price get exercised.
"""

from unittest.mock import MagicMock, patch

import numpy as np
import pytest

from app.models.schemas import ConfidenceEnum, PricePredictRequest
from app.user.services import price_service

VALID_KWARGS = {
    "crop": "Carrot",
    "district": "Nuwara Eliya",
    "season": "Maha",
    "week_of_year": 10,
    "inflation_index": 1.2,
    "fuel_price_index": 1.1,
    "transport_cost_index": 1.0,
    "supply_index": 100.0,
    "demand_index": 110.0,
    "holiday_flag": 0,
    "festival_flag": 0,
    "farmgate_price_lag1": 85.0,
    "farmgate_price_lag2": 80.0,
    "farmgate_price_lag4": 75.0,
}


def _make_request(**overrides) -> PricePredictRequest:
    return PricePredictRequest(**{**VALID_KWARGS, **overrides})


def _make_scaler(n_features=9, inverse_result=None):
    """Build a fake scaler with transform/inverse_transform returning a
    predictable (1, n_features) numpy array."""
    scaler = MagicMock()
    scaler.n_features_in_ = n_features
    scaler.transform.side_effect = lambda x: x  # identity — shape preserved
    if inverse_result is not None:
        scaler.inverse_transform.return_value = np.array([inverse_result])
    return scaler


# ═══════════════════════════════════════════════════════════════════════════
# predict_price
# ═══════════════════════════════════════════════════════════════════════════


def test_predict_price_returns_mock_when_model_missing():
    req = _make_request()

    with patch(
        "app.user.services.price_service.model_loader.is_loaded",
        return_value=False,
    ):
        result = price_service.predict_price(req, "user-1")

    assert result.is_mock is True
    assert result.predicted_farmgate_price_lkr_kg == 0.0
    assert result.predicted_retail_price_lkr_kg == 0.0
    assert result.confidence == ConfidenceEnum.low


def test_predict_price_with_scaler_inverse_transforms_correctly():
    req = _make_request()
    mock_model = MagicMock()
    mock_model.predict.return_value = np.array([[0.5, 0.6]])

    # Inverse-transform result: pos 0 = farmgate, pos 1 = retail
    scaler = _make_scaler(n_features=9, inverse_result=[88.5, 128.3] + [0.0] * 7)
    scalers_dict = {"Carrot": scaler}

    with patch(
        "app.user.services.price_service.model_loader.is_loaded",
        return_value=True,
    ), patch(
        "app.user.services.price_service.model_loader.get_model",
        side_effect=lambda key: mock_model if key == "price_Carrot" else scalers_dict,
    ):
        result = price_service.predict_price(req, "user-1")

    assert result.is_mock is False
    assert result.predicted_farmgate_price_lkr_kg == 88.5
    assert result.predicted_retail_price_lkr_kg == 128.3
    assert result.confidence == ConfidenceEnum.medium


def test_predict_price_without_scaler_uses_raw_model_output():
    req = _make_request()
    mock_model = MagicMock()
    mock_model.predict.return_value = np.array([[90.0, 130.0]])

    with patch(
        "app.user.services.price_service.model_loader.is_loaded",
        return_value=True,
    ), patch(
        "app.user.services.price_service.model_loader.get_model",
        side_effect=lambda key: mock_model if key == "price_Carrot" else None,
    ):
        result = price_service.predict_price(req, "user-1")

    assert result.predicted_farmgate_price_lkr_kg == 90.0
    assert result.predicted_retail_price_lkr_kg == 130.0


def test_predict_price_without_scaler_and_single_value_output_derives_retail():
    req = _make_request()
    mock_model = MagicMock()
    mock_model.predict.return_value = np.array([[90.0]])  # only farmgate returned

    with patch(
        "app.user.services.price_service.model_loader.is_loaded",
        return_value=True,
    ), patch(
        "app.user.services.price_service.model_loader.get_model",
        side_effect=lambda key: mock_model if key == "price_Carrot" else None,
    ):
        result = price_service.predict_price(req, "user-1")

    assert result.predicted_farmgate_price_lkr_kg == 90.0
    assert result.predicted_retail_price_lkr_kg == pytest.approx(90.0 * 1.25)


def test_predict_price_negative_farmgate_clamped_to_zero_with_scaler():
    """The max(0.0, ...) clamp only exists in the scaler branch — the
    no-scaler branch returns the raw (possibly negative) model output."""
    req = _make_request()
    mock_model = MagicMock()
    mock_model.predict.return_value = np.array([[0.1, 0.1]])

    scaler = _make_scaler(n_features=9, inverse_result=[-10.0, -5.0] + [0.0] * 7)
    scalers_dict = {"Carrot": scaler}

    with patch(
        "app.user.services.price_service.model_loader.is_loaded",
        return_value=True,
    ), patch(
        "app.user.services.price_service.model_loader.get_model",
        side_effect=lambda key: mock_model if key == "price_Carrot" else scalers_dict,
    ):
        result = price_service.predict_price(req, "user-1")

    assert result.predicted_farmgate_price_lkr_kg == 0.0
    assert result.predicted_retail_price_lkr_kg == 0.0


def test_predict_price_error_raises_runtime_error():
    req = _make_request()
    mock_model = MagicMock()
    mock_model.predict.side_effect = ValueError("bad input")

    with patch(
        "app.user.services.price_service.model_loader.is_loaded",
        return_value=True,
    ), patch(
        "app.user.services.price_service.model_loader.get_model",
        side_effect=lambda key: mock_model if key == "price_Carrot" else None,
    ):
        with pytest.raises(RuntimeError):
            price_service.predict_price(req, "user-1")


def test_predict_price_internal_uses_system_user():
    req = _make_request()

    with patch(
        "app.user.services.price_service.model_loader.is_loaded",
        return_value=False,
    ):
        result = price_service.predict_price_internal(req)

    assert result.is_mock is True


# ═══════════════════════════════════════════════════════════════════════════
# _build_sequence
# ═══════════════════════════════════════════════════════════════════════════


def test_build_sequence_shape_without_scaler():
    req = _make_request(
        farmgate_price_lag1=85.0, farmgate_price_lag2=80.0, farmgate_price_lag4=75.0
    )

    seq = price_service._build_sequence(req, crop_scaler=None)

    assert seq.shape == (1, 8, 9)
    # Oldest-to-newest ordering: lag4, lag4, lag4, lag4, lag2, lag2, lag1, lag1
    assert seq[0, 0, 0] == pytest.approx(75.0)  # oldest = lag4
    assert seq[0, 4, 0] == pytest.approx(80.0)  # lag2 starts at index 4
    assert seq[0, 6, 0] == pytest.approx(85.0)  # lag1 starts at index 6
    assert seq[0, 7, 0] == pytest.approx(85.0)  # newest = lag1


def test_build_sequence_retail_column_uses_markup():
    req = _make_request(farmgate_price_lag1=100.0)

    seq = price_service._build_sequence(req, crop_scaler=None)

    # retail column (index 1) = farmgate * _RETAIL_MARKUP
    assert seq[0, 7, 1] == pytest.approx(100.0 * price_service._RETAIL_MARKUP)


def test_build_sequence_uses_scaler_transform_when_present():
    req = _make_request()
    scaler = _make_scaler(n_features=9)

    seq = price_service._build_sequence(req, crop_scaler=scaler)

    scaler.transform.assert_called_once()
    assert seq.shape == (1, 8, 9)
    assert seq.dtype == np.float32


def test_failed_average_price_load_is_attempted_only_once():
    """Regression: emptiness was the "not warmed yet" signal, so when the
    CSVs are unreadable the cache never fills and every /api/price/predict
    re-opened both files across all four candidate encodings — the opposite
    of the documented read-once-at-boot behaviour.
    """
    calls = []

    def _failing_load():
        calls.append(1)
        return {}  # unreadable CSVs yield nothing

    # Snapshot and restore rather than clear: leaving the module "warmed"
    # with an empty cache would silently hand every later test the frozen
    # fallback table instead of the CSV figures.
    original_cache = dict(price_service._avg_price_cache)
    original_warmed = price_service._avg_price_warmed
    price_service._avg_price_cache.clear()
    price_service._avg_price_warmed = False
    try:
        with patch.object(
            price_service, "_load_average_farmgate_prices", _failing_load
        ):
            for _ in range(5):
                price_service._get_average_farmgate_price("Carrot")
    finally:
        price_service._avg_price_warmed = original_warmed
        price_service._avg_price_cache.clear()
        price_service._avg_price_cache.update(original_cache)

    assert len(calls) == 1, (
        f"a failed load was retried {len(calls)} times — the warm-up flag is "
        "not separating 'no data' from 'not attempted'"
    )


def test_average_price_falls_back_to_frozen_table_when_load_fails():
    """The one-shot warm-up must not cost callers their fallback figure."""
    original_cache = dict(price_service._avg_price_cache)
    original_warmed = price_service._avg_price_warmed
    price_service._avg_price_cache.clear()
    price_service._avg_price_warmed = False
    crop, (expected, _src) = next(iter(price_service._AVG_PRICE_FALLBACK.items()))
    try:
        with patch.object(price_service, "_load_average_farmgate_prices", lambda: {}):
            avg, source = price_service._get_average_farmgate_price(crop)
    finally:
        price_service._avg_price_warmed = original_warmed
        price_service._avg_price_cache.clear()
        price_service._avg_price_cache.update(original_cache)

    assert avg == pytest.approx(expected)
    assert source is not None
