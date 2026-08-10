"""Golden-prediction tests — pin inference output so a library bump cannot
silently change what the models predict.

The models were pickled under scikit-learn 1.6.1; requirements.txt pins 1.8.0.
Loading across that gap raises InconsistentVersionWarning, which reports only
that the version strings differ — it cannot tell you whether behaviour changed.
These tests answer that question, and keep answering it for every future bump.

Measured when this was written (1.6.1 vs 1.8.0, same models, same inputs):
max relative difference 1.03e-15, which is *smaller* than the 1.09e-15 jitter
between two consecutive runs of the SAME version. That jitter is real and
expected — RandomForest.predict accumulates trees through joblib.Parallel, so
summation order varies with thread scheduling. Hence a tolerance of 1e-9:
roughly six orders of magnitude above the noise floor, and far below any
change that would matter. A genuine inference change moves a tree prediction
by the gap between leaf values, which is percent-scale, not ULP-scale.

These are NOT accuracy tests — the inputs are arbitrary deterministic vectors,
not realistic agronomic values, and the expected numbers carry no agronomic
meaning. They pin *stability*, not correctness. test_ml_accuracy.py covers
whether the models are any good.

Regenerating after a deliberate retrain:
    Retraining legitimately changes these numbers. Do not edit them by hand to
    make a red test pass — that discards the only signal this file provides.
    Re-derive them, in the same environment that will serve them, and say in
    the commit message which models were retrained and why.
"""

import math
import os
import warnings
from pathlib import Path

import joblib
import numpy as np
import pytest
import sklearn

warnings.filterwarnings("ignore")

# Resolve the model directory rather than hardcoding the container path.
# test_ml_accuracy.py pins /app/models/files, so on a GitHub runner it skips
# every test in the file; these must actually run in CI, which is the whole
# point of having them.
_CANDIDATES = [
    os.environ.get("GOLDEN_MODEL_DIR"),
    Path(__file__).resolve().parents[2] / "models" / "files",
    Path("/app/models/files"),
]
MODEL_DIR = next(
    (Path(c) for c in _CANDIDATES if c and Path(c).is_dir()),
    None,
)

# Loud, not skipped. A missing or stubbed model file is exactly how mock
# predictions reached production once already: the loader tolerates it by
# design, so the test suite is the layer that must not.
_MIN_TOTAL_BYTES = 50_000_000

if MODEL_DIR is None:
    raise RuntimeError(
        "model directory not found; looked in " + ", ".join(str(c) for c in _CANDIDATES)
    )

_TOTAL = sum(f.stat().st_size for f in MODEL_DIR.glob("*.pkl"))
if _TOTAL < _MIN_TOTAL_BYTES:
    raise RuntimeError(
        f"models in {MODEL_DIR} total {_TOTAL} bytes, expected >{_MIN_TOTAL_BYTES}. "
        "Git LFS pointer stubs or an incomplete checkout, not real models."
    )

RTOL = 1e-9
ATOL = 1e-12


def make_input(n_features: int, variant: int) -> np.ndarray:
    """Deterministic feature row.

    Integer arithmetic only — no RNG. numpy does not guarantee that
    Generator streams stay identical across releases, so seeding one here
    would make the goldens depend on the numpy version as well as sklearn.
    """
    return np.array(
        [[((i * 37 + variant * 101) % 89) / 89.0 for i in range(n_features)]],
        dtype=np.float64,
    )


def assert_close(actual, expected, label: str) -> None:
    """Compare elementwise, naming the worst offender and the library version."""
    actual = [float(x) for x in np.ravel(np.asarray(actual))]
    expected = list(expected)
    assert len(actual) == len(expected), (
        f"{label}: got {len(actual)} values, expected {len(expected)} — "
        "the model's output shape changed, not just its numbers"
    )
    worst_i, worst_rel = -1, 0.0
    for i, (a, e) in enumerate(zip(actual, expected)):
        if math.isclose(a, e, rel_tol=RTOL, abs_tol=ATOL):
            continue
        rel = abs(a - e) / max(abs(e), 1e-30)
        if rel > worst_rel:
            worst_i, worst_rel = i, rel
    if worst_i >= 0:
        pytest.fail(
            f"{label}: inference changed under scikit-learn {sklearn.__version__}.\n"
            f"  index {worst_i}: got {actual[worst_i]!r}, expected "
            f"{expected[worst_i]!r} (relative difference {worst_rel:.3e}, "
            f"tolerance {RTOL:.0e})\n"
            "  Either a library upgrade altered inference — investigate before "
            "shipping — or the models were retrained, in which case regenerate "
            "the goldens as described in this module's docstring."
        )


def load(name: str):
    return joblib.load(MODEL_DIR / name)


GOLDEN = {
    "M1_per_crop": {
        "Carrot": (15498.397161652234, 15489.601535241598),
        "Cowpea": (929.2419393819135, 937.8230975589216),
        "Finger millet": (1113.0159842472333, 1136.2736040043287),
        "Green gram": (738.841761383987, 757.6022813936066),
        "Groundnut": (1297.321021334221, 1323.0876359686604),
        "Maize": (2883.692487109186, 2933.3899340909084),
    },
    "M1_yield": (14153.836862734963, 13858.836578057953),
    "M2_multioutput": (
        1.4821678535353542,
        7.427889442039444,
        31.805623298275773,
        81.50366358521107,
    ),
    "M5_predict": ("0", "0", "0"),
    "M5_proba": (
        (
            0.32219973956932485,
            0.1646471489951851,
            0.166056333795151,
            0.004062807248675189,
            0.21387287873709632,
            0.12916109165456738,
        ),
        (
            0.34049759368847426,
            0.1439063749386838,
            0.18147798837413845,
            0.008729967424846686,
            0.19764069070023282,
            0.1277473848736238,
        ),
        (
            0.36963336081462306,
            0.16668568689612734,
            0.18739688566466942,
            0.006729967424846686,
            0.10833138940037385,
            0.1612227097993595,
        ),
    ),
    "M2_scaler": (
        0.0,
        -0.3004871756604055,
        -2.0500409822068915,
        -1.8407683464975708,
        -0.07074651574499097,
        -0.27895160929316437,
    ),
    "M3_scalers": {
        "Carrot": (
            -0.672941879575676,
            -0.6427011069638614,
            -0.8682764023480678,
            -0.8097785051649478,
            -0.1655146679079465,
            -1.3348558546623013,
            -1.1056179775280899,
            0.9101123595505618,
            0.3258426966292135,
        ),
        "Cowpea": (
            -0.6140512631384843,
            -0.6043696379063229,
            -0.8453781655112037,
            -0.7891471719259492,
            -0.132800485211767,
            -0.9651538921722435,
            -1.1056179775280899,
            0.9101123595505618,
            0.3258426966292135,
        ),
        "Finger millet": (
            -0.7448156682027649,
            -0.7193542759360514,
            -0.8846799270885055,
            -0.7892621399276823,
            -0.13790528206878758,
            -1.0110389248076779,
            -1.1056179775280899,
            0.9101123595505618,
            0.3258426966292135,
        ),
        "Green gram": (
            -0.6201916495550991,
            -0.6138469202807046,
            -0.8569391487977475,
            -0.8009165286731889,
            -0.13696754959403168,
            -0.7910489907609934,
            -1.1056179775280899,
            0.9101123595505618,
            0.3258426966292135,
        ),
        "Groundnut": (
            -0.685000536078053,
            -0.6754557246567563,
            -0.8636135730509971,
            -0.7966435922190499,
            -0.12733490485766755,
            -0.5955369045351907,
            -1.1056179775280899,
            0.9101123595505618,
            0.3258426966292135,
        ),
        "Maize": (
            -0.6741646647739683,
            -0.5875694476255292,
            -0.8640143668631917,
            -0.7849415118828983,
            -0.12072093052619173,
            -1.1797929474948767,
            -1.1056179775280899,
            0.9101123595505618,
            0.3258426966292135,
        ),
    },
    "M1_encoders": {
        "crop": (
            "Carrot",
            "Cowpea",
            "Finger millet",
            "Green gram",
            "Groundnut",
            "Maize",
        ),
        "district": (
            "Ampara",
            "Anuradhapura",
            "Badulla",
            "Batticaloa",
            "Hambantota",
            "Jaffna",
            "Monaragala",
            "Nuwara Eliya",
        ),
        "irrigation_type": ("canal", "drip", "rainfed"),
        "prev_crop": (
            "Carrot",
            "Cowpea",
            "Finger millet",
            "Green gram",
            "Groundnut",
            "Maize",
            "Unknown",
        ),
        "season": ("Inter", "Maha", "Yala"),
        "seed_variety": (
            "Bushitao",
            "Chantenay",
            "HORDI Maize 1",
            "Harsha",
            "Local",
            "Local Hybrid",
            "MI 5",
            "MI 6",
            "MICP 1",
            "Nantes",
            "Ravana",
            "Ravi",
            "Ruwan",
            "Tissa",
            "Walawa",
        ),
    },
    "M5_encoders": {
        "district": (
            "Ampara",
            "Anuradhapura",
            "Badulla",
            "Batticaloa",
            "Hambantota",
            "Jaffna",
            "Monaragala",
            "Nuwara Eliya",
        ),
        "irrigation_type": ("canal", "drip", "rainfed"),
        "prev_crop": (
            "Carrot",
            "Cowpea",
            "Finger millet",
            "Green gram",
            "Groundnut",
            "Maize",
            "Unknown",
        ),
        "recommended_crop": (
            "Carrot",
            "Cowpea",
            "Finger millet",
            "Green gram",
            "Groundnut",
            "Maize",
        ),
        "season": ("Inter", "Maha", "Yala"),
    },
}


# ── RandomForestRegressor × 7 ───────────────────────────────────────────────


@pytest.mark.parametrize("crop", sorted(GOLDEN["M1_per_crop"]))
def test_m1_per_crop_regressor_is_stable(crop):
    """Each per-crop yield forest predicts what it predicted at pin time."""
    model = load("M1_per_crop_models.pkl")[crop]
    got = [float(model.predict(make_input(model.n_features_in_, v))[0]) for v in (0, 1)]
    assert_close(got, GOLDEN["M1_per_crop"][crop], f"M1 {crop}")


def test_m1_aggregate_regressor_is_stable():
    model = load("M1_yield_model.pkl")
    got = [float(model.predict(make_input(model.n_features_in_, v))[0]) for v in (0, 1)]
    assert_close(got, GOLDEN["M1_yield"], "M1 aggregate yield")


def test_m2_multioutput_regressor_is_stable():
    model = load("M2_nuwara_eliya_rf.pkl")
    got = model.predict(make_input(model.n_features_in_, 0))
    assert_close(got, GOLDEN["M2_multioutput"], "M2 multioutput")


# ── RandomForestClassifier ──────────────────────────────────────────────────


def test_m5_classifier_labels_are_stable():
    """Labels must match exactly — a changed class is not a rounding error."""
    model = load("M5_crop_recommendation_model.pkl")
    X = np.vstack([make_input(model.n_features_in_, v) for v in (0, 1, 2)])
    got = tuple(str(p) for p in model.predict(X))
    assert got == GOLDEN["M5_predict"], (
        f"M5 predicted classes changed under scikit-learn {sklearn.__version__}: "
        f"got {got}, expected {GOLDEN['M5_predict']}"
    )


def test_m5_classifier_probabilities_are_stable():
    """predict_proba drives the confidence score the recommendation ranks on,
    so drift here reorders crop recommendations even when labels hold."""
    model = load("M5_crop_recommendation_model.pkl")
    X = np.vstack([make_input(model.n_features_in_, v) for v in (0, 1, 2)])
    proba = model.predict_proba(X)
    for row, (got, expected) in enumerate(zip(proba, GOLDEN["M5_proba"])):
        assert_close(got, expected, f"M5 predict_proba row {row}")


# ── MinMaxScaler ────────────────────────────────────────────────────────────


def test_m2_weather_scaler_is_stable():
    scaler = load("M2_weather_scaler.pkl")
    got = scaler.transform(make_input(scaler.n_features_in_, 0))
    assert_close(got, GOLDEN["M2_scaler"], "M2 weather scaler")


@pytest.mark.parametrize("crop", sorted(GOLDEN["M3_scalers"]))
def test_m3_price_scaler_is_stable(crop):
    scaler = load("M3_price_scalers.pkl")[crop]
    got = scaler.transform(make_input(scaler.n_features_in_, 0))
    assert_close(got, GOLDEN["M3_scalers"][crop], f"M3 scaler {crop}")


# ── LabelEncoder ────────────────────────────────────────────────────────────


@pytest.mark.parametrize("bundle", ["M1", "M5"])
def test_encoder_class_order_is_stable(bundle):
    """Class order IS the encoding. If sorted order ever shifted, every
    categorical would silently encode to a different integer and every
    downstream prediction would be wrong while every test still passed.
    """
    encoders = load(f"{bundle}_encoders.pkl")
    expected = GOLDEN[f"{bundle}_encoders"]
    assert sorted(encoders) == sorted(expected), (
        f"{bundle} encoder columns changed: "
        f"got {sorted(encoders)}, expected {sorted(expected)}"
    )
    for col, classes in expected.items():
        got = tuple(str(c) for c in encoders[col].classes_)
        assert got == classes, (
            f"{bundle}.{col} class order changed under scikit-learn "
            f"{sklearn.__version__}: got {got}, expected {classes}"
        )


@pytest.mark.parametrize("bundle", ["M1", "M5"])
def test_encoder_transform_matches_class_order(bundle):
    """transform must map classes_[i] -> i. Pinned separately from the class
    list because a changed lookup would break encoding without touching it."""
    encoders = load(f"{bundle}_encoders.pkl")
    for col, classes in GOLDEN[f"{bundle}_encoders"].items():
        encoder = encoders[col]
        got = [int(v) for v in encoder.transform(list(encoder.classes_))]
        assert got == list(
            range(len(classes))
        ), f"{bundle}.{col}.transform no longer maps classes_[i] to i: {got}"
