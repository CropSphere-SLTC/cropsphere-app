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

_DISTRICT_IDX: Dict[str, int] = {
    "Nuwara Eliya": 0, "Badulla": 1, "Anuradhapura": 2, "Monaragala": 3,
    "Ampara": 4, "Hambantota": 5, "Batticaloa": 6, "Jaffna": 7,
}

# Climatological averages used for mock responses when model is absent
_DISTRICT_CLIMATE: Dict[str, Tuple[float, float, float, float]] = {
    "Nuwara Eliya": (120.0, 10.0, 22.0, 80.0),
    "Badulla":      (100.0, 12.0, 25.0, 75.0),
    "Anuradhapura": (60.0,  22.0, 33.0, 65.0),
    "Monaragala":   (80.0,  18.0, 30.0, 70.0),
    "Ampara":       (90.0,  20.0, 31.0, 68.0),
    "Hambantota":   (50.0,  21.0, 32.0, 60.0),
    "Batticaloa":   (95.0,  21.0, 30.0, 72.0),
    "Jaffna":       (55.0,  23.0, 34.0, 58.0),
}


def forecast_weather(req: WeatherForecastRequest) -> WeatherForecastResponse:
    """Forecast weekly weather for the given district.

    Inputs: WeatherForecastRequest (Pydantic-validated).
    Outputs: WeatherForecastResponse with per-week rainfall, temperature, humidity.
    Security assumption: JWT verified upstream.
    Returns is_mock=True using climatological averages if LSTM is absent.
    """
    if not model_loader.is_loaded("weather_lstm"):
        logger.warning("Weather LSTM absent — returning climatological mock for %s", req.district)
        return _mock_forecast(req)

    try:
        model = model_loader.get_model("weather_lstm")
        start = date.fromisoformat(req.start_date)
        forecasts = []

        for i in range(req.weeks_ahead):
            week_date = start + timedelta(weeks=i)
            week_num = week_date.isocalendar()[1]
            x = np.array(
                [[[_DISTRICT_IDX[req.district.value], week_num]]],
                dtype=np.float32,
            )
            pred = model.predict(x, verbose=0)[0]
            forecasts.append(WeekForecast(
                week_number=week_num,
                date=str(week_date),
                rainfall_mm=round(float(pred[0]), 1),
                temp_min_c=round(float(pred[1]), 1),
                temp_max_c=round(float(pred[2]), 1),
                humidity_pct=round(float(pred[3]), 1),
            ))

        return WeatherForecastResponse(district=req.district, forecasts=forecasts)
    except Exception as exc:
        logger.error("Weather forecast error district=%s: %s", req.district, exc)
        raise RuntimeError("Weather forecast unavailable") from exc


def forecast_weather_internal(district: DistrictEnum, start_date: str) -> WeatherForecastResponse:
    """Internal helper called by recommend_service — bypasses auth context."""
    return forecast_weather(
        WeatherForecastRequest(district=district, start_date=start_date, weeks_ahead=1)
    )


def _mock_forecast(req: WeatherForecastRequest) -> WeatherForecastResponse:
    rain, t_min, t_max, humidity = _DISTRICT_CLIMATE.get(
        req.district.value, (75.0, 18.0, 28.0, 70.0)
    )
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
    return WeatherForecastResponse(district=req.district, forecasts=forecasts, is_mock=True)
