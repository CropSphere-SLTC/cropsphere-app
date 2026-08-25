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

# Districts where M2's TRAINING DATA is wrong, so its forecast cannot be
# trusted however well-formed the request is.
#
# Derived, not hand-listed: scripts/check_weather_trust.py compares mean weekly
# temp_max between M2's training set and the agronomic-band dataset and flags
# any district disagreeing by more than 3 C. Today that is Nuwara Eliya
# (34.0 vs 18.9) and Badulla (31.6 vs 26.0); every other district agrees to
# within 1.1 C. Re-run that script after either dataset changes — it fails if
# this constant has gone stale.
#
# NOT keyed off the scaler-range excursion, deliberately. Four districts breach
# that range and two of them (Hambantota, Jaffna) produce the most accurate
# forecasts of the eight; gating on it would badge them low-confidence for no
# reason. See the script's docstring for the full argument.
_UNTRUSTED_FORECAST_DISTRICTS = frozenset({"Nuwara Eliya", "Badulla"})

# Feature order of a seed row / the M2 scaler's columns, for diagnostics.
_SEED_FEATURES = (
    "rainfall_mm",
    "temp_min_c",
    "temp_max_c",
    "humidity_pct",
    "wind_speed_kmh",
    "solar_radiation_mj",
)


def _seed_excursions(seed_row: list, scaler) -> Dict[str, tuple]:
    """{feature: (raw, normalized)} for any seed component outside [0, 1].

    MinMaxScaler does NOT clip. A seed below the fitted floor becomes a
    NEGATIVE input the LSTM never saw in training, and the model does not
    degrade gracefully on those — it collapses. Nuwara Eliya's temp_max seed
    of 22 C normalizes to -0.441 (the scaler's floor is 27.81) and drives
    predicted rainfall from ~41mm down to 1.6mm, a 26x under-prediction,
    with the rainfall seed held constant. Holding everything else fixed and
    sweeping temp_max alone moves the rainfall output 1.58 -> 68.28.

    Reported, never silently corrected. Clamping 22 C up to 27.81 C would
    hard-code the claim that Nuwara Eliya is a hot district — the seed is
    RIGHT and M2's training data is wrong (see the module note in
    data/description.md), so a clamp would launder a known-bad number into a
    confident-looking forecast.
    """
    if scaler is None:
        return {}
    try:
        norm = scaler.transform(np.array([seed_row], dtype=np.float64))[0]
    except Exception:
        return {}
    return {
        _SEED_FEATURES[i]: (float(seed_row[i]), float(norm[i]))
        for i in range(min(len(seed_row), len(_SEED_FEATURES)))
        if norm[i] < 0.0 or norm[i] > 1.0
    }


def assert_weather_seeds_in_range() -> None:
    """Log every climatological seed that falls outside the M2 scaler's range.

    Same shift-left spirit as recommend_service.assert_feature_contract, but
    WARNING rather than RuntimeError: four of the eight districts breach the
    range today and two of them forecast perfectly well (Hambantota and
    Jaffna are ~0.05-0.11 below the humidity floor and land within 3% of
    their training means). Raising here would take the app down for a
    condition that is only sometimes harmful.

    Severity is what separates them: the two collapsed districts are ~0.2-0.44
    outside on temp_max. The trust gate that actually routes traffic is
    _UNTRUSTED_FORECAST_DISTRICTS, which keys off dataset disagreement rather
    than this excursion — see that constant for why.
    """
    scaler = model_loader.get_model("weather_scaler")
    if scaler is None:
        logger.warning("weather_scaler absent — cannot check seed ranges")
        return

    total = 0
    for district, climate in _DISTRICT_CLIMATE.items():
        for feature, (raw, norm) in _seed_excursions(list(climate), scaler).items():
            total += 1
            logger.warning(
                "Weather seed OUT OF RANGE: %s %s=%.1f normalizes to %.3f "
                "(outside [0,1]) — the LSTM never saw this input during "
                "training and its output there is unreliable",
                district,
                feature,
                raw,
                norm,
            )
    if total:
        logger.warning(
            "%d weather seed excursion(s) across %d districts. This is a known "
            "limitation, not a new fault — see data/description.md.",
            total,
            len(_DISTRICT_CLIMATE),
        )
    else:
        logger.info("Weather seeds OK — all within the M2 scaler's fitted range")


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

        if req.district.value in _UNTRUSTED_FORECAST_DISTRICTS:
            logger.warning(
                "Serving LOW-CONFIDENCE forecast for %s: M2's training data "
                "disagrees with the agronomic reference for this district "
                "(see scripts/check_weather_trust.py). Labelled as such in "
                "the response.",
                req.district.value,
            )

        # Per-request visibility. The boot check reports the same excursions
        # once for every district; this names the one actually being served,
        # so a collapsed forecast in the logs can be traced to its cause
        # instead of looking like a plausible dry-week prediction.
        excursions = _seed_excursions(seed_row, scaler)
        if excursions:
            logger.warning(
                "Weather seed for %s is outside the M2 scaler's fitted range "
                "(%s) — forecast magnitude is unreliable for this district",
                req.district.value,
                ", ".join(
                    f"{f}={raw:.1f}->{norm:.3f}" for f, (raw, norm) in excursions.items()
                ),
            )

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

            # Slide window forward using the new prediction as the next step
            new_raw = np.array(
                [[rainfall, temp_min, temp_max, humidity, seed_row[4], seed_row[5]]]
            )
            new_scaled = (
                scaler.transform(new_raw)[0] if scaler is not None else new_raw[0]
            )
            current_window = np.vstack([current_window[1:], new_scaled])

            # Slide window forward using the new prediction as the next step
            new_raw = np.array(
                [[rainfall, temp_min, temp_max, humidity, seed_row[4], seed_row[5]]]
            )
            new_scaled = (
                scaler.transform(new_raw)[0] if scaler is not None else new_raw[0]
            )
            current_window = np.vstack([current_window[1:], new_scaled])

        # Provenance travels with the numbers. A district M2 was trained
        # wrongly on still gets a forecast — nothing else can look four weeks
        # ahead — but it is labelled, not passed off as reliable.
        return WeatherForecastResponse(
            district=req.district,
            forecasts=forecasts,
            forecast_source=(
                "model_low_confidence"
                if req.district.value in _UNTRUSTED_FORECAST_DISTRICTS
                else "model"
            ),
        )
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
        district=req.district,
        forecasts=forecasts,
        is_mock=True,
        forecast_source="climatology",
    )
