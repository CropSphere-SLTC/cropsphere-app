"""Unit tests for app.user.services.demand_service.

Calls the service function directly (no HTTP layer) so _build_features and
_infer_trend get exercised precisely, not just through the router.
"""

from unittest.mock import MagicMock, patch

import pytest

from app.models.schemas import DemandPredictRequest, TrendEnum
from app.user.services import demand_service

VALID_KWARGS = {
    "crop": "Carrot",
    "season": "Maha",
    "week_of_year": 10,
    "demand_lag1": 95.0,
    "demand_lag2": 90.0,
    "demand_lag4": 85.0,
    "retail_price_lkr_kg": 120.0,
    "inflation_index": 1.2,
    "holiday_flag": 0,
    "festival_flag": 0,
    "consumer_pref_index": 60.0,
    "search_trend_index": 45.0,
}


def _make_request(**overrides) -> DemandPredictRequest:
    return DemandPredictRequest(**{**VALID_KWARGS, **overrides})


# ═══════════════════════════════════════════════════════════════════════════
# predict_demand
# ═══════════════════════════════════════════════════════════════════════════


def test_predict_demand_returns_mock_when_model_missing():
    req = _make_request()

    with patch(
        "app.user.services.demand_service.model_loader.is_loaded",
        return_value=False,
    ):
        result = demand_service.predict_demand(req, "user-1")

    assert result.is_mock is True
    assert result.predicted_demand_index == 0.0
    assert result.trend == TrendEnum.stable


def test_predict_demand_returns_real_prediction_when_model_loaded():
    req = _make_request()
    mock_model = MagicMock()
    mock_model.predict.return_value = [105.0]

    with patch(
        "app.user.services.demand_service.model_loader.is_loaded",
        return_value=True,
    ), patch(
        "app.user.services.demand_service.model_loader.get_model",
        return_value=mock_model,
    ):
        result = demand_service.predict_demand(req, "user-1")

    assert result.is_mock is False
    assert result.predicted_demand_index == 105.0
    assert result.crop.value == "Carrot"


def test_predict_demand_prediction_error_raises_runtime_error():
    req = _make_request()
    mock_model = MagicMock()
    mock_model.predict.side_effect = ValueError("bad input")

    with patch(
        "app.user.services.demand_service.model_loader.is_loaded",
        return_value=True,
    ), patch(
        "app.user.services.demand_service.model_loader.get_model",
        return_value=mock_model,
    ):
        with pytest.raises(RuntimeError):
            demand_service.predict_demand(req, "user-1")


# ═══════════════════════════════════════════════════════════════════════════
# _build_features
# ═══════════════════════════════════════════════════════════════════════════


def test_build_features_returns_22_elements_in_expected_order():
    req = _make_request(
        demand_lag1=95.0, demand_lag2=90.0, demand_lag4=85.0, retail_price_lkr_kg=120.0
    )

    features = demand_service._build_features(req)

    assert len(features) == 22
    assert features[0] == 95.0  # demand_index proxy == lag1
    assert features[3] == 120.0  # retail_price_lkr_kg
    assert features[4] == pytest.approx(120.0 * 0.75)  # farmgate approx
    assert features[10] == 95.0  # demand_lag1
    assert features[11] == 90.0  # demand_lag2
    assert features[12] == pytest.approx((90.0 + 85.0) / 2.0)  # demand_lag3 interp
    assert features[13] == 85.0  # demand_lag4
    assert features[14] == 85.0  # demand_lag8 approx == lag4
    assert features[15] == 85.0  # demand_lag12 approx == lag4
    assert features[19] == 0.0  # price_change_pct placeholder
    assert features[21] == 0  # district_enc placeholder


def test_build_features_maps_season_enum_correctly():
    for season, expected in [("Inter", 0), ("Maha", 1), ("Yala", 2)]:
        req = _make_request(season=season)
        features = demand_service._build_features(req)
        assert features[20] == expected


def test_build_features_rolling_stats_computed_from_lags():
    req = _make_request(demand_lag1=100.0, demand_lag2=100.0, demand_lag4=100.0)

    features = demand_service._build_features(req)

    # All four lag values equal -> std should be 0, mean should equal the value
    assert features[16] == pytest.approx(100.0)  # roll4_mean
    assert features[17] == pytest.approx(0.0)  # roll4_std
    assert features[18] == pytest.approx(100.0)  # roll8_mean approx


# ═══════════════════════════════════════════════════════════════════════════
# _infer_trend
# ═══════════════════════════════════════════════════════════════════════════


def test_infer_trend_rising_when_delta_above_threshold():
    assert demand_service._infer_trend(predicted=110.0, lag1=100.0) == TrendEnum.rising


def test_infer_trend_falling_when_delta_below_threshold():
    assert demand_service._infer_trend(predicted=90.0, lag1=100.0) == TrendEnum.falling


def test_infer_trend_stable_within_threshold():
    assert demand_service._infer_trend(predicted=102.0, lag1=100.0) == TrendEnum.stable


def test_infer_trend_boundary_exactly_five_is_stable():
    # delta == 5 is not > 5, so it should be stable, not rising
    assert demand_service._infer_trend(predicted=105.0, lag1=100.0) == TrendEnum.stable


def test_infer_trend_boundary_exactly_negative_five_is_stable():
    assert demand_service._infer_trend(predicted=95.0, lag1=100.0) == TrendEnum.stable
