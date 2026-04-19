"""Singleton model loader — loads all ML models once on startup and serves them forever."""
import logging
from pathlib import Path
from typing import Any, Dict, Optional

logger = logging.getLogger(__name__)

<<<<<<< HEAD
# Direct file mappings: internal name → (type, filename)
_DIRECT_FILES: Dict[str, tuple] = {
    # M1 auxiliary
    "yield_encoders":        ("pkl",   "M1_encoders.pkl"),
    "yield_features":        ("pkl",   "M1_features.pkl"),
    # M2 Weather
    "weather_lstm":          ("keras", "M2_weather_lstm.keras"),
    "weather_scaler":        ("pkl",   "M2_weather_scaler.pkl"),
    # M3 Price — per-crop LSTM
    "price_Carrot":          ("keras", "M3_Carrot_lstm.keras"),
    "price_Maize":           ("keras", "M3_Maize_lstm.keras"),
    "price_Greengram":       ("keras", "M3_Green_gram_lstm.keras"),
    "price_Cowpea":          ("keras", "M3_Cowpea_lstm.keras"),
    "price_Fingermillet":    ("keras", "M3_Finger_millet_lstm.keras"),
    "price_Groundnut":       ("keras", "M3_Groundnut_lstm.keras"),
    "price_scalers":         ("pkl",   "M3_price_scalers.pkl"),
    # M5 Recommend
    "recommend_rf":          ("pkl",   "M5_crop_recommendation_model.pkl"),
    "recommend_encoders":    ("pkl",   "M5_encoders.pkl"),
    "recommend_features":    ("pkl",   "M5_features.pkl"),
    "recommend_valid_pairs": ("pkl",   "M5_valid_pairs.pkl"),
    # M6 RAG
    "rag_artifacts":         ("pkl",   "M6_rag_artifacts.pkl"),
}

# Bundled files: filename → {bundle_key → internal model name}
_BUNDLE_FILES: Dict[str, Dict[str, str]] = {
    "M1_per_crop_models.pkl": {
        "Carrot":        "yield_Carrot",
        "Maize":         "yield_Maize",
        "Green gram":    "yield_Greengram",
        "Cowpea":        "yield_Cowpea",
        "Finger millet": "yield_Fingermillet",
        "Groundnut":     "yield_Groundnut",
    },
    "M4_demand_xgb_models.pkl": {
        "Carrot":        "demand_Carrot",
        "Maize":         "demand_Maize",
        "Green gram":    "demand_Greengram",
        "Cowpea":        "demand_Cowpea",
        "Finger millet": "demand_Fingermillet",
        "Groundnut":     "demand_Groundnut",
    },
}

# Keys shown in the /api/health status report
_STATUS_KEYS = [
    "yield_Carrot", "yield_Maize", "yield_Greengram", "yield_Cowpea",
    "yield_Fingermillet", "yield_Groundnut",
    "weather_lstm",
    "price_Carrot", "price_Maize", "price_Greengram", "price_Cowpea",
    "price_Fingermillet", "price_Groundnut",
    "demand_Carrot", "demand_Maize", "demand_Greengram", "demand_Cowpea",
    "demand_Fingermillet", "demand_Groundnut",
    "recommend_rf", "rag_artifacts",
]

=======
# Maps internal model name → file name inside MODEL_DIR
_MODEL_FILES: Dict[str, str] = {
    "yield_Carrot": "yield_Carrot.pkl",
    "yield_Maize": "yield_Maize.pkl",
    "yield_Greengram": "yield_Greengram.pkl",
    "yield_Cowpea": "yield_Cowpea.pkl",
    "yield_Fingermillet": "yield_Fingermillet.pkl",
    "yield_Groundnut": "yield_Groundnut.pkl",
    "weather_lstm": "weather_lstm.keras",
    "price_Carrot": "price_Carrot.keras",
    "price_Maize": "price_Maize.keras",
    "price_Greengram": "price_Greengram.keras",
    "price_Cowpea": "price_Cowpea.keras",
    "price_Fingermillet": "price_Fingermillet.keras",
    "price_Groundnut": "price_Groundnut.keras",
    "demand_Carrot": "demand_Carrot.pkl",
    "demand_Maize": "demand_Maize.pkl",
    "demand_Greengram": "demand_Greengram.pkl",
    "demand_Cowpea": "demand_Cowpea.pkl",
    "demand_Fingermillet": "demand_Fingermillet.pkl",
    "demand_Groundnut": "demand_Groundnut.pkl",
    "recommend_rf": "recommend_rf.pkl",
    "rag_artifacts": "rag_artifacts.pkl",
}

>>>>>>> 0c9c358 (chore: initial repository setup)

class ModelLoader:
    """Thread-safe singleton holding all loaded ML models in memory."""

    _instance: Optional["ModelLoader"] = None
    _models: Dict[str, Any] = {}
<<<<<<< HEAD
    _status: Dict[str, bool] = {k: False for k in _STATUS_KEYS}
=======
    _status: Dict[str, bool] = {}
>>>>>>> 0c9c358 (chore: initial repository setup)

    def __new__(cls) -> "ModelLoader":
        if cls._instance is None:
            cls._instance = super().__new__(cls)
        return cls._instance

    def load_all(self, model_dir: str) -> None:
        """Load all models from model_dir.

        Missing or failed files are set to None; the service layer returns mock
        responses in that case rather than crashing.
        """
        import joblib

        base = Path(model_dir)

<<<<<<< HEAD
        # Load direct files
        for name, (ftype, filename) in _DIRECT_FILES.items():
            filepath = base / filename
            if not filepath.exists():
                logger.warning("Model file not found: %s — %s will return mock responses", filepath, name)
                self._models[name] = None
                if name in _STATUS_KEYS:
                    self._status[name] = False
                continue
            try:
                if ftype == "pkl":
                    self._models[name] = joblib.load(filepath)
                elif ftype == "keras":
                    from tensorflow import keras  # type: ignore
                    self._models[name] = keras.models.load_model(filepath)
                if name in _STATUS_KEYS:
                    self._status[name] = True
=======
        for name, filename in _MODEL_FILES.items():
            filepath = base / filename

            if not filepath.exists():
                logger.warning(
                    "Model file not found: %s — %s will return mock responses",
                    filepath,
                    name,
                )
                self._models[name] = None
                self._status[name] = False
                continue

            try:
                if filename.endswith(".pkl"):
                    self._models[name] = joblib.load(filepath)
                elif filename.endswith(".keras"):
                    from tensorflow import keras  # type: ignore
                    self._models[name] = keras.models.load_model(filepath)
                self._status[name] = True
>>>>>>> 0c9c358 (chore: initial repository setup)
                logger.info("Loaded model: %s", name)
            except Exception as exc:
                logger.error("Failed to load %s: %s", name, exc)
                self._models[name] = None
<<<<<<< HEAD
                if name in _STATUS_KEYS:
                    self._status[name] = False

        # Load bundled files and split into per-crop entries
        for filename, key_map in _BUNDLE_FILES.items():
            filepath = base / filename
            if not filepath.exists():
                logger.warning("Bundle file not found: %s", filepath)
                for internal_name in key_map.values():
                    self._models[internal_name] = None
                    self._status[internal_name] = False
                continue
            try:
                bundle = joblib.load(filepath)
                for bundle_key, internal_name in key_map.items():
                    if bundle_key in bundle:
                        self._models[internal_name] = bundle[bundle_key]
                        self._status[internal_name] = True
                        logger.info("Loaded model: %s (from %s)", internal_name, filename)
                    else:
                        logger.warning("Key '%s' missing in %s", bundle_key, filename)
                        self._models[internal_name] = None
                        self._status[internal_name] = False
            except Exception as exc:
                logger.error("Failed to load bundle %s: %s", filename, exc)
                for internal_name in key_map.values():
                    self._models[internal_name] = None
                    self._status[internal_name] = False
=======
                self._status[name] = False
>>>>>>> 0c9c358 (chore: initial repository setup)

    def get_model(self, name: str) -> Optional[Any]:
        """Return the loaded model object, or None if not loaded."""
        return self._models.get(name)

    def is_loaded(self, name: str) -> bool:
        """Return True if the named model is loaded and ready."""
        return self._status.get(name, False)

    def status_report(self) -> Dict[str, bool]:
        """Return {model_name: is_loaded} dict for the health endpoint."""
<<<<<<< HEAD
        return {k: self._status.get(k, False) for k in _STATUS_KEYS}
=======
        return dict(self._status)
>>>>>>> 0c9c358 (chore: initial repository setup)


# Module-level singleton — import this everywhere
model_loader = ModelLoader()
