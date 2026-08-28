"""The M2 weather trust gate and the seed-range diagnostic.

M2 was trained on `Cropsphere_Real_Test_Dataset.csv`, which records the hill
country as lowland-hot (Nuwara Eliya at a 34.0 C mean weekly maximum against
the agronomic reference's 18.9 C). `_DISTRICT_CLIMATE` seeds that district
with a CORRECT 22 C, which lands below the scaler's fitted floor of 27.81 C,
normalizes to -0.441, and collapses the LSTM's rainfall output to ~1.6mm
against a 41.8mm training mean.

Two separate mechanisms, deliberately not merged — see
weather_service._UNTRUSTED_FORECAST_DISTRICTS:

  * the range check is a DIAGNOSTIC and fires on four districts, two of which
    forecast accurately;
  * the trust gate ROUTES traffic and fires on the two districts whose
    training data is actually wrong.
"""

import logging

import pytest

from app.models.loader import model_loader
from app.user.services.weather_service import (
    _DISTRICT_CLIMATE,
    _SEED_FEATURES,
    _UNTRUSTED_FORECAST_DISTRICTS,
    _seed_excursions,
    assert_weather_seeds_in_range,
)


@pytest.fixture(scope="module")
def scaler():
    from pathlib import Path

    model_dir = Path(__file__).resolve().parents[3] / "models" / "files"
    model_loader.load_all(str(model_dir))
    sc = model_loader.get_model("weather_scaler")
    if sc is None:
        pytest.skip("M2 scaler not available")
    return sc


# ── Trust gate ──────────────────────────────────────────────────────────────


def test_trust_gate_names_the_two_broken_districts():
    assert _UNTRUSTED_FORECAST_DISTRICTS == {"Nuwara Eliya", "Badulla"}


def test_trust_gate_matches_what_the_data_says():
    """The constant must stay in step with the datasets it was derived from."""
    import pandas as pd
    from pathlib import Path

    files = Path(__file__).resolve().parents[3] / "models" / "files"
    m2 = pd.read_csv(files / "Cropsphere_Real_Test_Dataset.csv", encoding="latin-1")
    bands = pd.read_csv(
        files / "CropSphere_SL_Synthetic_Weekly.csv", encoding="latin-1", header=1
    )
    derived = {
        d
        for d in set(m2.district.unique()) & set(bands.district.unique())
        if abs(
            m2[m2.district == d].temp_max_c.mean()
            - bands[bands.district == d].temp_max_c.mean()
        )
        > 3.0
    }
    assert derived == set(_UNTRUSTED_FORECAST_DISTRICTS), (
        "weather_service._UNTRUSTED_FORECAST_DISTRICTS is stale — re-run "
        "python -m scripts.check_weather_trust"
    )


@pytest.mark.parametrize("district", ["Nuwara Eliya", "Badulla"])
def test_untrusted_districts_are_labelled_low_confidence(district, scaler):
    from datetime import date

    from app.models.schemas import WeatherForecastRequest
    from app.user.services.weather_service import forecast_weather

    if not model_loader.is_loaded("weather_lstm"):
        pytest.skip("M2 LSTM not available")
    resp = forecast_weather(
        WeatherForecastRequest(
            district=district, start_date=str(date.today()), weeks_ahead=1
        )
    )
    assert resp.forecast_source == "model_low_confidence"


@pytest.mark.parametrize("district", ["Anuradhapura", "Hambantota", "Jaffna"])
def test_trusted_districts_are_not_labelled(district, scaler):
    """Hambantota and Jaffna breach the scaler range but forecast accurately.

    They are the reason the trust gate is not keyed off the range excursion:
    badging them low-confidence would devalue the badge everywhere.
    """
    from datetime import date

    from app.models.schemas import WeatherForecastRequest
    from app.user.services.weather_service import forecast_weather

    if not model_loader.is_loaded("weather_lstm"):
        pytest.skip("M2 LSTM not available")
    resp = forecast_weather(
        WeatherForecastRequest(
            district=district, start_date=str(date.today()), weeks_ahead=1
        )
    )
    assert resp.forecast_source == "model"


# ── Seed-range diagnostic ───────────────────────────────────────────────────


def test_excursion_detects_the_hill_district_temperature(scaler):
    seed = list(_DISTRICT_CLIMATE["Nuwara Eliya"])
    found = _seed_excursions(seed, scaler)
    assert "temp_max_c" in found
    raw, norm = found["temp_max_c"]
    assert raw == 22.0
    assert norm < 0, "a seed below the fitted floor must normalize negative"


def test_excursion_is_empty_for_an_in_range_seed(scaler):
    assert _seed_excursions(list(_DISTRICT_CLIMATE["Anuradhapura"]), scaler) == {}


def test_excursion_covers_more_districts_than_the_trust_gate(scaler):
    """Pins the distinction the two mechanisms exist to express."""
    breached = {
        d for d, c in _DISTRICT_CLIMATE.items() if _seed_excursions(list(c), scaler)
    }
    assert breached == {"Nuwara Eliya", "Badulla", "Hambantota", "Jaffna"}
    assert _UNTRUSTED_FORECAST_DISTRICTS < breached


def test_seed_guard_never_mutates_the_seed(scaler):
    """Detection only. Clamping would assert that Nuwara Eliya is hot."""
    seed = list(_DISTRICT_CLIMATE["Nuwara Eliya"])
    before = list(seed)
    _seed_excursions(seed, scaler)
    assert seed == before


def test_boot_check_warns_and_does_not_raise(scaler, caplog):
    """WARNING, not RuntimeError: two of the four breaching districts are fine."""
    with caplog.at_level(logging.WARNING):
        assert_weather_seeds_in_range()  # must not raise
    text = caplog.text
    assert "OUT OF RANGE" in text
    for district in ("Nuwara Eliya", "Badulla", "Hambantota", "Jaffna"):
        assert district in text


def test_missing_scaler_is_handled(caplog):
    real = model_loader.get_model
    try:
        model_loader.get_model = lambda n: None if n == "weather_scaler" else real(n)
        with caplog.at_level(logging.WARNING):
            assert_weather_seeds_in_range()
        assert "cannot check seed ranges" in caplog.text
    finally:
        model_loader.get_model = real


def test_rainfall_seeds_match_the_training_data():
    """Seeds must stay tied to their source, not drift back to hand-entry.

    They previously held values 2.6-3.7x the per-district weekly means with no
    stated provenance, which is how the inflation went unnoticed.
    """
    import pandas as pd
    from pathlib import Path

    files = Path(__file__).resolve().parents[3] / "models" / "files"
    m2 = pd.read_csv(files / "Cropsphere_Real_Test_Dataset.csv", encoding="latin-1")
    for district, climate in _DISTRICT_CLIMATE.items():
        expected = m2[m2.district == district].rainfall_mm.mean()
        assert climate[0] == pytest.approx(expected, abs=0.05), (
            f"{district} rainfall seed {climate[0]} != training mean "
            f"{expected:.1f} — reseed from the data, do not hand-edit"
        )


def test_temperature_and_humidity_seeds_were_left_alone():
    """Nuwara Eliya's 22 C is correct; it is M2's training data that is wrong.

    Raising it into the scaler's range would assert the hill country is hot.
    """
    assert _DISTRICT_CLIMATE["Nuwara Eliya"][2] == 22.0
    assert _DISTRICT_CLIMATE["Nuwara Eliya"][3] == 80.0


def test_seed_features_match_the_scaler_width(scaler):
    assert len(_SEED_FEATURES) == scaler.n_features_in_ == 6
    for climate in _DISTRICT_CLIMATE.values():
        assert len(climate) == len(_SEED_FEATURES)
