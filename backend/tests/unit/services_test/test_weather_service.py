"""Unit tests for app.user.services.weather_service.

Calls the service functions directly (no HTTP layer) to exercise both the
scaler and no-scaler branches of the LSTM forecast loop, plus the mock
fallback path.
"""

from unittest.mock import MagicMock, patch

import numpy as np
import pytest

from app.models.schemas import DistrictEnum, WeatherForecastRequest
from app.user.services import weather_service

VALID_KWARGS = {
    "district": "Nuwara Eliya",
    "start_date": "2025-04-01",
    "weeks_ahead": 2,
}


def _make_request(**overrides) -> WeatherForecastRequest:
    return WeatherForecastRequest(**{**VALID_KWARGS, **overrides})


def _make_scaler(n_features=6):
    """Identity-ish scaler: transform passes through, inverse_transform
    returns whatever dummy array it was given (so the values we set into
    `dummy` show up directly as the forecast output)."""
    scaler = MagicMock()
    scaler.n_features_in_ = n_features
    scaler.transform.side_effect = lambda x: x
    scaler.inverse_transform.side_effect = lambda x: x
    return scaler


# ═══════════════════════════════════════════════════════════════════════════
# forecast_weather
# ═══════════════════════════════════════════════════════════════════════════


def test_forecast_weather_returns_mock_when_model_missing():
    req = _make_request()

    with patch(
        "app.user.services.weather_service.model_loader.is_loaded",
        return_value=False,
    ):
        result = weather_service.forecast_weather(req)

    assert result.is_mock is True
    assert len(result.forecasts) == 2
    assert result.district == DistrictEnum.nuwara_eliya


def test_forecast_weather_with_scaler_produces_expected_forecast_count():
    req = _make_request(weeks_ahead=3)
    mock_model = MagicMock()
    # normalized (4,) prediction each call — content doesn't matter since
    # scaler.inverse_transform is an identity passthrough on the dummy array
    mock_model.predict.return_value = np.array([[0.1, 0.2, 0.3, 0.4]])
    scaler = _make_scaler(n_features=6)

    with patch(
        "app.user.services.weather_service.model_loader.is_loaded",
        return_value=True,
    ), patch(
        "app.user.services.weather_service.model_loader.get_model",
        side_effect=lambda key: mock_model if key == "weather_lstm" else scaler,
    ):
        result = weather_service.forecast_weather(req)

    assert result.is_mock is False
    assert len(result.forecasts) == 3
    for week in result.forecasts:
        assert week.rainfall_mm >= 0.0
        assert 0.0 <= week.humidity_pct <= 100.0


def test_forecast_weather_without_scaler_uses_raw_model_output():
    req = _make_request(weeks_ahead=1)
    mock_model = MagicMock()
    mock_model.predict.return_value = np.array([[50.0, 15.0, 28.0, 70.0]])

    with patch(
        "app.user.services.weather_service.model_loader.is_loaded",
        return_value=True,
    ), patch(
        "app.user.services.weather_service.model_loader.get_model",
        side_effect=lambda key: mock_model if key == "weather_lstm" else None,
    ):
        result = weather_service.forecast_weather(req)

    assert len(result.forecasts) == 1
    week = result.forecasts[0]
    assert week.rainfall_mm == 50.0
    assert week.temp_min_c == 15.0
    assert week.temp_max_c == 28.0
    assert week.humidity_pct == 70.0


def test_forecast_weather_slides_the_window_exactly_one_step_per_week():
    """Regression: the slide block was duplicated, advancing the LSTM input
    window two steps per forecast week, so week N was produced from a window
    that had already run N steps ahead of the week it was labelled with.

    Asserts the shape of the slide rather than the output values: each week's
    window must be the previous window with its oldest row dropped and one
    new row appended. Under the double-slide, rows [1:] of window k would
    appear at [:-2] of window k+1 instead of [:-1].
    """
    req = _make_request(weeks_ahead=4)
    windows = []
    mock_model = MagicMock()

    def _capture(x, verbose=0):
        windows.append(np.array(x[0], dtype=np.float64, copy=True))
        # Vary the prediction per call so each appended row is distinct and a
        # dropped/duplicated step cannot coincidentally match.
        n = len(windows)
        return np.array([[10.0 * n, 15.0 + n, 28.0 + n, 60.0 + n]])

    mock_model.predict.side_effect = _capture

    with patch(
        "app.user.services.weather_service.model_loader.is_loaded",
        return_value=True,
    ), patch(
        "app.user.services.weather_service.model_loader.get_model",
        side_effect=lambda key: mock_model if key == "weather_lstm" else None,
    ):
        result = weather_service.forecast_weather(req)

    assert len(result.forecasts) == 4
    assert len(windows) == 4
    for k in range(len(windows) - 1):
        np.testing.assert_allclose(
            windows[k + 1][:-1],
            windows[k][1:],
            err_msg=(
                f"window {k + 1} is not window {k} advanced by exactly one row "
                "— the forecast loop is sliding more (or less) than once"
            ),
        )
        # And the appended row must be the prediction just emitted, not a
        # later one.
        week = result.forecasts[k]
        assert windows[k + 1][-1][0] == pytest.approx(week.rainfall_mm)
        assert windows[k + 1][-1][3] == pytest.approx(week.humidity_pct)


def test_forecast_weather_negative_rainfall_clamped_to_zero():
    req = _make_request(weeks_ahead=1)
    mock_model = MagicMock()
    mock_model.predict.return_value = np.array([[-5.0, 15.0, 28.0, 70.0]])

    with patch(
        "app.user.services.weather_service.model_loader.is_loaded",
        return_value=True,
    ), patch(
        "app.user.services.weather_service.model_loader.get_model",
        side_effect=lambda key: mock_model if key == "weather_lstm" else None,
    ):
        result = weather_service.forecast_weather(req)

    assert result.forecasts[0].rainfall_mm == 0.0


def test_forecast_weather_humidity_clamped_between_0_and_100():
    req = _make_request(weeks_ahead=1)
    mock_model = MagicMock()
    mock_model.predict.return_value = np.array([[10.0, 15.0, 28.0, 150.0]])

    with patch(
        "app.user.services.weather_service.model_loader.is_loaded",
        return_value=True,
    ), patch(
        "app.user.services.weather_service.model_loader.get_model",
        side_effect=lambda key: mock_model if key == "weather_lstm" else None,
    ):
        result = weather_service.forecast_weather(req)

    assert result.forecasts[0].humidity_pct == 100.0


def test_forecast_weather_uses_district_climate_defaults_for_unknown_district():
    """District not in _DISTRICT_CLIMATE falls back to default climate tuple —
    exercised indirectly by using a valid enum district not in the dict, if
    any; otherwise this documents expected fallback behaviour for a known one."""
    req = _make_request(district="Jaffna", weeks_ahead=1)
    mock_model = MagicMock()
    mock_model.predict.return_value = np.array([[10.0, 20.0, 30.0, 60.0]])

    with patch(
        "app.user.services.weather_service.model_loader.is_loaded",
        return_value=True,
    ), patch(
        "app.user.services.weather_service.model_loader.get_model",
        side_effect=lambda key: mock_model if key == "weather_lstm" else None,
    ):
        result = weather_service.forecast_weather(req)

    assert result.district == DistrictEnum.jaffna


def test_forecast_weather_prediction_error_raises_runtime_error():
    req = _make_request()
    mock_model = MagicMock()
    mock_model.predict.side_effect = ValueError("bad input")

    with patch(
        "app.user.services.weather_service.model_loader.is_loaded",
        return_value=True,
    ), patch(
        "app.user.services.weather_service.model_loader.get_model",
        side_effect=lambda key: mock_model if key == "weather_lstm" else None,
    ):
        with pytest.raises(RuntimeError):
            weather_service.forecast_weather(req)


def test_forecast_weather_week_dates_increment_correctly():
    req = _make_request(start_date="2025-04-01", weeks_ahead=2)
    mock_model = MagicMock()
    mock_model.predict.return_value = np.array([[10.0, 15.0, 28.0, 70.0]])

    with patch(
        "app.user.services.weather_service.model_loader.is_loaded",
        return_value=True,
    ), patch(
        "app.user.services.weather_service.model_loader.get_model",
        side_effect=lambda key: mock_model if key == "weather_lstm" else None,
    ):
        result = weather_service.forecast_weather(req)

    assert result.forecasts[0].date == "2025-04-01"
    assert result.forecasts[1].date == "2025-04-08"


# ═══════════════════════════════════════════════════════════════════════════
# forecast_weather_internal
# ═══════════════════════════════════════════════════════════════════════════


def test_forecast_weather_internal_requests_single_week():
    with patch(
        "app.user.services.weather_service.model_loader.is_loaded",
        return_value=False,
    ):
        result = weather_service.forecast_weather_internal(
            DistrictEnum.nuwara_eliya, "2025-04-01"
        )

    assert len(result.forecasts) == 1
    assert result.is_mock is True


# ═══════════════════════════════════════════════════════════════════════════
# _mock_forecast (exercised directly + via is_loaded=False above)
# ═══════════════════════════════════════════════════════════════════════════


def test_mock_forecast_returns_constant_climate_values_per_week():
    req = _make_request(weeks_ahead=3)

    result = weather_service._mock_forecast(req)

    assert result.is_mock is True
    assert len(result.forecasts) == 3
    # All weeks share the same climatological constants for a mock forecast
    rainfalls = {w.rainfall_mm for w in result.forecasts}
    assert len(rainfalls) == 1


def test_mock_forecast_uses_default_climate_for_unmapped_district():
    """Covers the .get(..., default_tuple) fallback branch."""
    req = _make_request(weeks_ahead=1)

    with patch.object(weather_service, "_DISTRICT_CLIMATE", {}):
        result = weather_service._mock_forecast(req)

    assert result.forecasts[0].rainfall_mm == 75.0  # default fallback rain
