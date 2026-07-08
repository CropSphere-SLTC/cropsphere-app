"""Unit tests for app.models.loader.ModelLoader.

Exercises load_all across every branch — direct pkl load, keras load, a
missing file, a corrupt file, bundle split with a present and a missing key,
and a missing bundle — plus the get_model / is_loaded / status_report
accessors. joblib and tensorflow are mocked so no real model files or heavy
imports are needed. The singleton's class-level dicts are snapshotted and
restored so this test never bleeds state into the rest of the suite.
"""

import sys
import types
from pathlib import Path
from unittest.mock import MagicMock

import pytest

from app.models import loader as loader_mod
from app.models.loader import ModelLoader


@pytest.fixture
def isolated_loader():
    """Yield the singleton with its state snapshotted and restored after."""
    inst = ModelLoader()
    saved_models = dict(inst._models)
    saved_status = dict(inst._status)
    yield inst
    inst._models.clear()
    inst._models.update(saved_models)
    inst._status.clear()
    inst._status.update(saved_status)


def _touch(base: Path, name: str):
    (base / name).write_bytes(b"x")


def test_singleton_returns_same_instance():
    assert ModelLoader() is ModelLoader()
    assert ModelLoader() is loader_mod.model_loader


def test_get_model_and_is_loaded_for_unknown_keys(isolated_loader):
    assert isolated_loader.get_model("does-not-exist") is None
    assert isolated_loader.is_loaded("does-not-exist") is False


def test_status_report_has_all_status_keys(isolated_loader):
    report = isolated_loader.status_report()
    assert set(report.keys()) == set(loader_mod._STATUS_KEYS)
    assert all(isinstance(v, bool) for v in report.values())


def test_load_all_covers_every_branch(isolated_loader, tmp_path, monkeypatch):
    base = tmp_path

    # Direct files: one pkl loads, one pkl is corrupt, one keras loads.
    _touch(base, "M1_encoders.pkl")  # loads OK (pkl)
    _touch(base, "M1_features.pkl")  # raises on load -> except branch
    _touch(base, "M2_weather_lstm.keras")  # loads OK (keras, status key)
    # Bundle M1 present (splits into per-crop), bundle M4 left missing.
    _touch(base, "M1_per_crop_models.pkl")
    # (M4_demand_xgb_models.pkl deliberately not created)

    def fake_joblib_load(path):
        name = Path(path).name
        if name == "M1_features.pkl":
            raise ValueError("corrupt pickle")
        if name == "M1_per_crop_models.pkl":
            # 'Groundnut' key deliberately missing -> else branch
            return {
                "Carrot": MagicMock(),
                "Maize": MagicMock(),
                "Green gram": MagicMock(),
                "Cowpea": MagicMock(),
                "Finger millet": MagicMock(),
            }
        return {"crop": "encoder"}

    fake_joblib = types.ModuleType("joblib")
    fake_joblib.load = fake_joblib_load
    monkeypatch.setitem(sys.modules, "joblib", fake_joblib)

    # Fake tensorflow so `from tensorflow import keras` needs no real TF.
    fake_tf = types.ModuleType("tensorflow")
    fake_tf.keras = types.SimpleNamespace(
        models=types.SimpleNamespace(load_model=lambda p: MagicMock())
    )
    monkeypatch.setitem(sys.modules, "tensorflow", fake_tf)

    isolated_loader.load_all(str(base))

    # Direct pkl that loaded successfully
    assert isolated_loader.get_model("yield_encoders") is not None
    # Corrupt pkl -> None
    assert isolated_loader.get_model("yield_features") is None
    # Keras direct file loaded -> status True
    assert isolated_loader.is_loaded("weather_lstm") is True
    # Missing direct file -> None + status False
    assert isolated_loader.get_model("recommend_rf") is None
    assert isolated_loader.is_loaded("recommend_rf") is False

    # Bundle M1 split: present keys loaded, missing key is None
    assert isolated_loader.get_model("yield_Carrot") is not None
    assert isolated_loader.is_loaded("yield_Carrot") is True
    assert isolated_loader.get_model("yield_Groundnut") is None
    assert isolated_loader.is_loaded("yield_Groundnut") is False

    # Bundle M4 missing entirely -> all its crops None + status False
    assert isolated_loader.get_model("demand_Carrot") is None
    assert isolated_loader.is_loaded("demand_Carrot") is False


def test_load_all_bundle_load_failure(isolated_loader, tmp_path, monkeypatch):
    """A bundle file that raises on load sets all its crops to None."""
    base = tmp_path
    _touch(base, "M4_demand_xgb_models.pkl")

    def fake_joblib_load(path):
        raise RuntimeError("bundle corrupt")

    fake_joblib = types.ModuleType("joblib")
    fake_joblib.load = fake_joblib_load
    monkeypatch.setitem(sys.modules, "joblib", fake_joblib)

    isolated_loader.load_all(str(base))

    assert isolated_loader.get_model("demand_Maize") is None
    assert isolated_loader.is_loaded("demand_Maize") is False
