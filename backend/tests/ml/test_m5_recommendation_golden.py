"""Golden tests for the M5 recommendation path — pin *encoding and feature
order*, not just library stability.

test_model_inference_golden.py already pins raw M5 inference: it feeds the
model arbitrary deterministic vectors and checks the probabilities do not move
under a scikit-learn bump. That is necessary but it cannot catch the bug that
actually shipped, because it bypasses the service entirely.

What shipped: `_rf_features` built 15 features against a model expecting 29, in
a different order, using hand-written categorical index maps that disagreed
with the trained LabelEncoders (`Monaragala` encoded as 3 where the encoder
says 6; irrigation `sprinkler`/`flood` mapped to integers outside the model's
vocabulary entirely). Every call raised ValueError, a bare `except Exception`
swallowed it, and the service fell back to a revenue heuristic — so the model
never ran, the endpoint kept returning 200, and the ranking was close to
inverted (Carrot ranked 1st for Monaragala; the model's own answer is Groundnut).

These tests therefore run the real service helpers end to end and pin:
  * the feature row's length AND its per-position values,
  * the probability vector M5 returns for known agronomic inputs,
  * that probabilities map to the right crop names via the trained encoder.

A retrain legitimately changes the probabilities. It does NOT change the
feature *names* the service must supply — if that assertion fails, the schema
moved and `_m5_features` needs updating, not the golden.

Regenerating after a deliberate retrain: re-derive the numbers in the same
environment that will serve them, and say in the commit message which models
were retrained and why. Do not hand-edit them to make a red test green — that
discards the only signal this file provides.
"""

import math
import os
import warnings
from pathlib import Path

import joblib
import pytest

warnings.filterwarnings("ignore")

_CANDIDATES = [
    os.environ.get("GOLDEN_MODEL_DIR"),
    Path(__file__).resolve().parents[2] / "models" / "files",
    Path("/app/models/files"),
]
MODEL_DIR = next((Path(c) for c in _CANDIDATES if c and Path(c).is_dir()), None)

if MODEL_DIR is None:
    raise RuntimeError(
        "model directory not found; looked in " + ", ".join(str(c) for c in _CANDIDATES)
    )

# Same tolerance and rationale as test_model_inference_golden.py: RandomForest
# accumulates trees through joblib.Parallel, so summation order varies with
# thread scheduling and produces ULP-scale jitter. 1e-9 sits far above that
# noise floor and far below any change that would matter.
RTOL = 1e-9
ATOL = 1e-12


@pytest.fixture(scope="module")
def loaded_models():
    """Populate the singleton loader once for the whole module."""
    from app.models.loader import model_loader

    model_loader.load_all(str(MODEL_DIR))
    return model_loader


@pytest.fixture(scope="module")
def probe_request():
    """The Monaragala/Yala scenario this investigation started from.

    Weather is passed explicitly (weather=None path) rather than forecast, so
    the golden does not depend on the LSTM or on today's date.
    """
    from app.models.schemas import RecommendRequest

    return RecommendRequest(
        district="Monaragala",
        season="Yala",
        week_of_year=34,
        rainfall_mm=33.7,
        temp_min_c=19.6,
        temp_max_c=29.8,
        humidity_pct=78.2,
        soil_ph=6.5,
        soil_moisture_pct=40.0,
        N_index=0.5,
        P_index=0.5,
        K_index=0.5,
        irrigation_type="rainfed",
    )


# The 29 feature names M5 was trained on, in order. Pinned independently of the
# pickle so a corrupted or swapped artifact is caught rather than trusted.
GOLDEN_FEATURE_ORDER = [
    "week_of_year",
    "week_of_season",
    "year",
    "district_enc",
    "season_enc",
    "rainfall_mm",
    "temp_min_c",
    "temp_max_c",
    "humidity_pct",
    "wind_speed_kmh",
    "solar_radiation_mj",
    "temp_range",
    "heat_stress_flag",
    "cold_stress_flag",
    "soil_ph",
    "soil_moisture_pct",
    "N_index",
    "P_index",
    "K_index",
    "nutrient_score",
    "fertilizer_index",
    "pesticide_index",
    "irrigation_type_enc",
    "mgmt_score",
    "prev_crop_enc",
    "demand_index",
    "inflation_index",
    "holiday_flag",
    "festival_flag",
]

# Categorical encodings as the TRAINED encoders assign them (alphabetical), not
# as any hand-written map might guess. These three are the exact values the old
# code got wrong.
GOLDEN_ENCODINGS = {
    ("district", "Monaragala"): 6,
    ("district", "Nuwara Eliya"): 7,
    ("season", "Yala"): 2,
    ("season", "Maha"): 1,
    ("irrigation_type", "rainfed"): 2,
    ("irrigation_type", "drip"): 1,
    ("irrigation_type", "canal"): 0,
}


def test_feature_pickle_order_is_stable():
    """The trained schema itself must not drift unnoticed."""
    order = joblib.load(MODEL_DIR / "M5_features.pkl")
    assert list(order) == GOLDEN_FEATURE_ORDER, (
        "M5_features.pkl changed. If M5 was retrained with a new schema, update "
        "_m5_features() in recommend_service.py and regenerate this golden."
    )


def test_model_expects_the_declared_feature_count():
    """M5_features.pkl and the model must agree — the boot assertion's core check."""
    model = joblib.load(MODEL_DIR / "M5_crop_recommendation_model.pkl")
    order = joblib.load(MODEL_DIR / "M5_features.pkl")
    assert model.n_features_in_ == len(order) == 29


@pytest.mark.parametrize("key,expected", sorted(GOLDEN_ENCODINGS.items()))
def test_categorical_encodings_match_trained_encoders(key, expected, loaded_models):
    """Pin the encodings the previous implementation hand-rolled and got wrong."""
    field, value = key
    encoders = joblib.load(MODEL_DIR / "M5_encoders.pkl")
    got = int(encoders[field].transform([value])[0])
    assert got == expected, (
        f"{field}={value!r} encodes to {got}, expected {expected}. "
        "Hand-written index maps must never be used in place of these encoders."
    )


def test_service_builds_exactly_the_declared_features(loaded_models, probe_request):
    """_m5_features() must produce one value per declared feature, in order."""
    from app.user.services.recommend_service import _m5_features

    encoders = loaded_models.get_model("recommend_encoders")
    order = loaded_models.get_model("recommend_features")
    row = _m5_features(probe_request, None, encoders, order)

    assert len(row) == len(order) == 29, (
        f"built {len(row)} features for a model expecting {len(order)} — "
        "this is the exact mismatch that silently disabled M5 in production"
    )


def test_service_feature_values_are_stable(loaded_models, probe_request):
    """Pin the row itself, so a reordering or rescaling cannot pass unnoticed.

    `year` is excluded — it is date.today().year and would make this test fail
    every January for no real reason.
    """
    from app.user.services.recommend_service import _m5_features

    encoders = loaded_models.get_model("recommend_encoders")
    order = loaded_models.get_model("recommend_features")
    row = _m5_features(probe_request, None, encoders, order)
    built = dict(zip(order, row))

    expected = {
        "week_of_year": 34.0,
        "week_of_season": 21.0,
        "district_enc": 6.0,
        "season_enc": 2.0,
        "rainfall_mm": 33.7,
        "temp_min_c": 19.6,
        "temp_max_c": 29.8,
        "humidity_pct": 78.2,
        "wind_speed_kmh": 10.0,
        "solar_radiation_mj": 15.0,
        "temp_range": 29.8 - 19.6,
        "heat_stress_flag": 0.0,
        "cold_stress_flag": 0.0,
        "soil_ph": 6.5,
        "soil_moisture_pct": 40.0,
        "N_index": 0.5,
        "P_index": 0.5,
        "K_index": 0.5,
        "nutrient_score": 0.5,
        "fertilizer_index": 0.5,
        "pesticide_index": 0.5,
        "irrigation_type_enc": 2.0,
        "mgmt_score": 0.5,
        "prev_crop_enc": 6.0,
        "demand_index": 100.0,
        "inflation_index": 100.0,
        "holiday_flag": 0.0,
        "festival_flag": 0.0,
    }

    for name, want in expected.items():
        assert math.isclose(
            built[name], want, rel_tol=RTOL, abs_tol=ATOL
        ), f"feature {name!r}: got {built[name]!r}, expected {want!r}"


# One predict_proba call on the probe row, keyed by crop name.
GOLDEN_PROBABILITIES = {
    "Carrot": 0.1460322150255219,
    "Cowpea": 0.0742528150986623,
    "Finger millet": 0.012934310430354552,
    "Green gram": 0.041992047558659165,
    "Groundnut": 0.662763703866125,
    "Maize": 0.062024908020676825,
}


def test_m5_probabilities_are_stable(loaded_models, probe_request):
    """Pin the model's answer for known agronomic inputs, keyed by crop name.

    This is the assertion that would have caught the shipped bug: it exercises
    the real encoding path and names the crop, so a mis-encoded district or a
    scrambled feature order changes the numbers here.
    """
    from app.user.services.recommend_service import _m5_probabilities

    probabilities = _m5_probabilities(probe_request, None)

    assert probabilities is not None, (
        "_m5_probabilities returned None — the model failed to load or the "
        "feature contract broke. Check the logs for the CONTRACT BREAK message."
    )
    assert set(probabilities) == set(
        GOLDEN_PROBABILITIES
    ), f"crop labels changed: got {sorted(probabilities)}"
    assert math.isclose(sum(probabilities.values()), 1.0, rel_tol=1e-9), (
        "probabilities no longer sum to 1 — predict_proba is not being read as "
        "a distribution over crops"
    )

    for crop, want in GOLDEN_PROBABILITIES.items():
        got = probabilities[crop]
        assert math.isclose(got, want, rel_tol=RTOL, abs_tol=ATOL), (
            f"M5 probability for {crop}: got {got!r}, expected {want!r}. "
            "Either encoding/feature order changed — investigate before "
            "shipping — or M5 was retrained, in which case regenerate these "
            "goldens as described in this module's docstring."
        )


def test_model_top_pick_is_agronomically_sane(loaded_models, probe_request):
    """Monaragala is low-country: the model must not pick an up-country crop.

    Guards the regression in plain agronomic terms rather than in float
    comparisons, so the intent survives a legitimate retrain.
    """
    from app.user.services.recommend_service import _m5_probabilities

    probabilities = _m5_probabilities(probe_request, None)
    top = max(probabilities, key=probabilities.get)

    valid = loaded_models.get_model("recommend_valid_pairs")
    assert "Monaragala" in valid[top], (
        f"M5's top pick for Monaragala is {top}, which M5_valid_pairs says is "
        f"grown in {valid[top]} — not Monaragala."
    )
    assert top != "Carrot", "Carrot is an up-country crop; it cannot top Monaragala"


def test_feature_contract_assertion_passes_on_real_artifacts(loaded_models):
    """The boot guard must be green against the artifacts we actually ship."""
    from app.user.services.recommend_service import assert_feature_contract

    assert_feature_contract()


def test_feature_contract_assertion_catches_a_mismatch(loaded_models, monkeypatch):
    """And it must actually fail when the contract breaks — the guard needs teeth."""
    from app.models.loader import model_loader
    from app.user.services import recommend_service

    real = model_loader.get_model

    def truncated(name):
        if name == "recommend_features":
            return list(real(name))[:15]  # the exact 15-vs-29 shape that shipped
        return real(name)

    monkeypatch.setattr(model_loader, "get_model", truncated)

    with pytest.raises(RuntimeError, match="feature contract broken"):
        recommend_service.assert_feature_contract()
