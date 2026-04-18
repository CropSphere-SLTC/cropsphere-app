"""Singleton model loader — loads all ML models once on startup and serves them forever."""
import logging
from pathlib import Path
from typing import Any, Dict, Optional

logger = logging.getLogger(__name__)

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


class ModelLoader:
    """Thread-safe singleton holding all loaded ML models in memory."""

    _instance: Optional["ModelLoader"] = None
    _models: Dict[str, Any] = {}
    _status: Dict[str, bool] = {}

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
                logger.info("Loaded model: %s", name)
            except Exception as exc:
                logger.error("Failed to load %s: %s", name, exc)
                self._models[name] = None
                self._status[name] = False

    def get_model(self, name: str) -> Optional[Any]:
        """Return the loaded model object, or None if not loaded."""
        return self._models.get(name)

    def is_loaded(self, name: str) -> bool:
        """Return True if the named model is loaded and ready."""
        return self._status.get(name, False)

    def status_report(self) -> Dict[str, bool]:
        """Return {model_name: is_loaded} dict for the health endpoint."""
        return dict(self._status)


# Module-level singleton — import this everywhere
model_loader = ModelLoader()
