"""Weather forecasting service — LSTM model."""

import logging
from datetime import date, timedelta
from typing import Dict, Tuple

import numpy as np

from app.models.loader import model_loader
from app.models.schemas import (
    DistrictEnum,
    WeatherForecastRequest,
    WeatherForecastResponse,
    WeekForecast,
)

logger = logging.getLogger(__name__)


# Climatological averages per district:
# (rainfall_mm, temp_min_c, temp_max_c, humidity_pct,
#  wind_speed_kmh, solar_radiation_mj)
_DISTRICT_CLIMATE: Dict[str, Tuple[float, float, float, float, float, float]] = {
    "Nuwara Eliya": (120.0, 10.0, 22.0, 80.0, 8.0, 14.0),
    "Badulla": (100.0, 12.0, 25.0, 75.0, 9.0, 16.0),
    "Anuradhapura": (60.0, 22.0, 33.0, 65.0, 12.0, 20.0),
    "Monaragala": (80.0, 18.0, 30.0, 70.0, 11.0, 18.0),
    "Ampara": (90.0, 20.0, 31.0, 68.0, 12.0, 19.0),
    "Hambantota": (50.0, 21.0, 32.0, 60.0, 14.0, 21.0),
    "Batticaloa": (95.0, 21.0, 30.0, 72.0, 11.0, 19.0),
    "Jaffna": (55.0, 23.0, 34.0, 58.0, 13.0, 22.0),
}
_LSTM_TIMESTEPS = 12  # number of historical timesteps the model expects


def forecast_weather(req: WeatherForecastRequest) -> WeatherForecastResponse:
    """Forecast weekly weather for the given district.

    Inputs: WeatherForecastRequest (Pydantic-validated).
    Outputs: WeatherForecastResponse with per-week rainfall, temperature, humidity.
    Security assumption: JWT verified upstream.
    Returns is_mock=True using climatological averages if LSTM is absent.
    """
    if not model_loader.is_loaded("weather_lstm"):
        logger.warning(
            "Weather LSTM absent — returning climatological mock for %s", req.district
        )
        return _mock_forecast(req)

    try:
        model = model_loader.get_model("weather_lstm")
        scaler = model_loader.get_model("weather_scaler")
        start = date.fromisoformat(req.start_date)

        climate = _DISTRICT_CLIMATE.get(
            req.district.value, (75.0, 18.0, 28.0, 70.0, 10.0, 15.0)
        )
        seed_row = list(climate)  # 6 features: rain, tmin, tmax, hum, wind, solar

        # Build 12-step seed sequence from climatological averages
        seed_sequence = np.array(
            [seed_row] * _LSTM_TIMESTEPS, dtype=np.float64
        )  # (12, 6)

        if scaler is not None:
            current_window = scaler.transform(seed_sequence)  # (12, 6) normalized
        else:
            logger.warning("weather_scaler absent — feeding raw climatological values")
            current_window = seed_sequence

        forecasts = []
        for i in range(req.weeks_ahead):
            week_date = start + timedelta(weeks=i)
            week_num = week_date.isocalendar()[1]

            x = current_window.reshape(1, _LSTM_TIMESTEPS, 6).astype(np.float32)
            pred = model.predict(x, verbose=0)[
                0
            ]  # (4,): normalized rain, tmin, tmax, hum

            if scaler is not None:
                # Inverse-transform: LSTM outputs 4 features; scaler covers 6
                dummy = np.zeros((1, scaler.n_features_in_))
                dummy[0, : len(pred)] = pred
                result = scaler.inverse_transform(dummy)[0]
                rainfall = max(0.0, round(float(result[0]), 1))
                temp_min = round(float(result[1]), 1)
                temp_max = round(float(result[2]), 1)
                humidity = min(100.0, max(0.0, round(float(result[3]), 1)))
            else:
                rainfall = max(0.0, round(float(pred[0]), 1))
                temp_min = round(float(pred[1]), 1)
                temp_max = round(float(pred[2]), 1)
                humidity = min(100.0, max(0.0, round(float(pred[3]), 1)))

            forecasts.append(
                WeekForecast(
                    week_number=week_num,
                    date=str(week_date),
                    rainfall_mm=rainfall,
                    temp_min_c=temp_min,
                    temp_max_c=temp_max,
                    humidity_pct=humidity,
                )
            )
<<<<<<< HEAD

            # Slide window forward using the new prediction as the next step
            new_raw = np.array(
                [[rainfall, temp_min, temp_max, humidity, seed_row[4], seed_row[5]]]
            )
            new_scaled = (
                scaler.transform(new_raw)[0] if scaler is not None else new_raw[0]
            )
            current_window = np.vstack([current_window[1:], new_scaled])
=======
>>>>>>> dev

            # Slide window forward using the new prediction as the next step
            new_raw = np.array(
                [[rainfall, temp_min, temp_max, humidity, seed_row[4], seed_row[5]]]
            )
            new_scaled = (
                scaler.transform(new_raw)[0] if scaler is not None else new_raw[0]
            )
            current_window = np.vstack([current_window[1:], new_scaled])

        return WeatherForecastResponse(district=req.district, forecasts=forecasts)
    except Exception as exc:
        logger.error("Weather forecast error district=%s: %s", req.district, exc)
        raise RuntimeError("Weather forecast unavailable") from exc


def forecast_weather_internal(
    district: DistrictEnum, start_date: str
) -> WeatherForecastResponse:
    """Internal helper called by recommend_service — bypasses auth context."""
    return forecast_weather(
        WeatherForecastRequest(district=district, start_date=start_date, weeks_ahead=1)
    )


def _mock_forecast(req: WeatherForecastRequest) -> WeatherForecastResponse:
    climate = _DISTRICT_CLIMATE.get(
        req.district.value, (75.0, 18.0, 28.0, 70.0, 10.0, 15.0)
    )
<<<<<<< HEAD

=======
>>>>>>> dev
    rain, t_min, t_max, humidity = climate[0], climate[1], climate[2], climate[3]
    start = date.fromisoformat(req.start_date)
    forecasts = [
        WeekForecast(
            week_number=(start + timedelta(weeks=i)).isocalendar()[1],
            date=str(start + timedelta(weeks=i)),
            rainfall_mm=rain,
            temp_min_c=t_min,
            temp_max_c=t_max,
            humidity_pct=humidity,
        )
        for i in range(req.weeks_ahead)
    ]
    return WeatherForecastResponse(
        district=req.district, forecasts=forecasts, is_mock=True
    )
