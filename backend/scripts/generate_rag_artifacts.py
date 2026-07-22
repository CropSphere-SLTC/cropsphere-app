#!/usr/bin/env python3
"""Build-time generator for the M6 RAG knowledge base from ML predictions.

Runs every valid (crop × district × season) through the yield / price / demand
models, adds per-district weather chunks and per-crop / per-district summary
chunks, PRESERVES the existing non-prediction chunks (requirements, real_price)
and the system_prompt, embeds everything with all-MiniLM-L6-v2, and writes a
drop-in replacement rag_artifacts .pkl with the EXACT structure the chatbot
already loads.

This is a BUILD-TIME tool. It imports the app's own prediction services and
model loader; it does NOT touch retrieval or chatbot code.

Usage:
    python scripts/generate_rag_artifacts.py [--output PATH] [--model-dir PATH]
                                             [--source PATH]
"""

import argparse
import logging
import os
import sys
from datetime import date
from pathlib import Path

# Make `app` importable when run as `python scripts/generate_rag_artifacts.py`.
sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

# Quieten TensorFlow / audit-log noise — this is a batch build tool.
os.environ.setdefault("TF_CPP_MIN_LOG_LEVEL", "3")

# Conversion factors — identical to chatbot_service._FORMATTING_RULES.
_HA_TO_ACRE = 2.471
_HA_TO_PERCH = 395.37

_SEASONS = ["Maha", "Yala", "Inter"]
# Chunk types this script regenerates; anything else in an existing artifact
# (requirements, real_price, general, …) is preserved untouched.
_REGENERATED_TYPES = {"prediction", "summary", "weather"}

logging.basicConfig(level=logging.INFO, format="%(message)s")
logging.getLogger("app.utils.firestore").setLevel(logging.CRITICAL)  # no Firestore
log = logging.getLogger("generate_rag")


def _model_dir(arg):
    if arg:
        return Path(arg)
    if os.environ.get("MODEL_DIR"):
        return Path(os.environ["MODEL_DIR"])
    # Works locally (backend/models/files) and in Docker (/app/models/files).
    return Path(__file__).resolve().parent.parent / "models" / "files"


# ── Request builders — the exact realistic defaults main._warmup_models uses ───
def _yield_req(crop, district, season):
    from app.models.schemas import IrrigationEnum, YieldPredictRequest

    return YieldPredictRequest(
        crop=crop, district=district, season=season, week_of_year=10,
        rainfall_mm=100.0, temp_min_c=10.0, temp_max_c=22.0, humidity_pct=70.0,
        wind_speed_kmh=10.0, solar_radiation_mj=15.0, soil_ph=6.0,
        soil_moisture_pct=55.0, cultivated_area_ha=1.0, seed_variety="Standard",
        fertilizer_index=0.5, pesticide_index=0.5,
        irrigation_type=IrrigationEnum.drip, N_index=0.5, P_index=0.5,
        K_index=0.5, prev_crop="none", demand_index=100.0, inflation_index=1.0,
        holiday_flag=0, festival_flag=0,
    )


def _price_req(crop, district, season):
    from app.models.schemas import PricePredictRequest

    return PricePredictRequest(
        crop=crop, district=district, season=season, week_of_year=10,
        inflation_index=1.2, fuel_price_index=1.1, transport_cost_index=1.0,
        supply_index=100.0, demand_index=110.0, holiday_flag=0, festival_flag=0,
        farmgate_price_lag1=85.0, farmgate_price_lag2=80.0,
        farmgate_price_lag4=75.0,
    )


def _demand_req(crop, season):
    from app.models.schemas import DemandPredictRequest

    return DemandPredictRequest(
        crop=crop, season=season, week_of_year=10, demand_lag1=95.0,
        demand_lag2=90.0, demand_lag4=85.0, retail_price_lkr_kg=120.0,
        inflation_index=1.2, holiday_flag=0, festival_flag=0,
        consumer_pref_index=60.0, search_trend_index=45.0,
    )


def _generate_predictions(valid_pairs):
    """One 'prediction' chunk per valid (crop, district, season). Returns
    (chunks, metas, records) where records feed the summary chunks."""
    from app.models.schemas import CropEnum, DistrictEnum, SeasonEnum
    from app.user.services.demand_service import predict_demand
    from app.user.services.price_service import predict_price_internal
    from app.user.services.yield_service import predict_yield

    total = sum(len(ds) for ds in valid_pairs.values()) * len(_SEASONS)
    chunks, metas, records = [], [], []
    i, mocked = 0, 0
    for crop_name, districts in valid_pairs.items():
        crop = CropEnum(crop_name)
        for district_name in districts:
            district = DistrictEnum(district_name)
            for season_name in _SEASONS:
                season = SeasonEnum(season_name)
                i += 1
                print(f"\rGenerating chunks... {i}/{total}", end="", flush=True)

                y = predict_yield(_yield_req(crop, district, season), "system")
                p = predict_price_internal(_price_req(crop, district, season))
                d = predict_demand(_demand_req(crop, season), "system")
                if y.is_mock or p.is_mock or d.is_mock:
                    mocked += 1

                yield_ha = y.predicted_yield_kg_per_ha
                y_acre = yield_ha / _HA_TO_ACRE
                y_perch = yield_ha / _HA_TO_PERCH
                farmgate = p.predicted_farmgate_price_lkr_kg
                retail = p.predicted_retail_price_lkr_kg
                demand = d.predicted_demand_index
                earnings = y_acre * farmgate

                chunks.append(
                    f"{crop_name} cultivation in {district_name} during "
                    f"{season_name} season: The predicted yield is "
                    f"{round(yield_ha):,} kg/ha ({round(y_acre):,} kg/acre; "
                    f"{round(y_perch):,} kg/perch). The average farmgate price "
                    f"(selling price at the farm) is {round(farmgate)} LKR/kg, "
                    f"and the retail price is {round(retail)} LKR/kg. The demand "
                    f"index is {round(demand)}. Estimated earnings per acre: "
                    f"{round(earnings):,} LKR."
                )
                metas.append({"crop": crop_name, "district": district_name,
                              "season": season_name, "type": "prediction"})
                records.append({"crop": crop_name, "district": district_name,
                                "season": season_name, "yield_ha": yield_ha,
                                "farmgate": farmgate, "earnings": earnings})
    print()
    if mocked:
        log.warning("  ! %d/%d combos returned MOCK data — check models loaded",
                    mocked, total)
    return chunks, metas, records


def _generate_summaries(records):
    """Per-crop and per-district 'summary' chunks derived from the predictions."""
    chunks, metas = [], []
    crops = sorted({r["crop"] for r in records})
    districts = sorted({r["district"] for r in records})

    for crop in crops:
        rs = [r for r in records if r["crop"] == crop]
        ds = sorted({r["district"] for r in rs})
        best = max(rs, key=lambda r: r["yield_ha"])
        lo = min(r["farmgate"] for r in rs)
        hi = max(r["farmgate"] for r in rs)
        chunks.append(
            f"{crop} is grown in the following districts: {', '.join(ds)}. "
            f"The highest yield is in {best['district']} during {best['season']} "
            f"({round(best['yield_ha']):,} kg/ha). Prices range from "
            f"{round(lo)} to {round(hi)} LKR/kg."
        )
        metas.append({"crop": crop, "district": "all", "season": "all",
                      "type": "summary"})

    for district in districts:
        rs = [r for r in records if r["district"] == district]
        cs = sorted({r["crop"] for r in rs})
        best = max(rs, key=lambda r: r["earnings"])
        chunks.append(
            f"In {district}, the following crops are cultivated: {', '.join(cs)}. "
            f"The most profitable crop is {best['crop']} with estimated earnings "
            f"of {round(best['earnings']):,} LKR/acre."
        )
        metas.append({"crop": "all", "district": district, "season": "all",
                      "type": "summary"})
    return chunks, metas


def _generate_weather(districts):
    """One 'weather' chunk per district from forecast_weather()."""
    from app.models.schemas import DistrictEnum, WeatherForecastRequest
    from app.user.services.weather_service import forecast_weather

    chunks, metas = [], []
    today = date.today().isoformat()
    for name in districts:
        resp = forecast_weather(WeatherForecastRequest(
            district=DistrictEnum(name), start_date=today, weeks_ahead=1))
        f = resp.forecasts[0]
        chunks.append(
            f"Weather forecast for {name}: Expected rainfall "
            f"{round(f.rainfall_mm)}mm, temperature range "
            f"{round(f.temp_min_c)}-{round(f.temp_max_c)}°C, "
            f"humidity {round(f.humidity_pct)}%."
        )
        metas.append({"crop": "all", "district": name, "season": "all",
                      "type": "weather"})
    return chunks, metas


def _load_kept(source):
    """Preserve non-regenerated chunks (requirements/real_price/…) and the
    system_prompt from an existing artifact. Returns (chunks, metas, prompt)."""
    if not source.exists():
        log.warning("  ! no existing artifact at %s — 0 chunks preserved", source)
        return [], [], None
    import joblib

    old = joblib.load(source)
    chunks, metas = [], []
    for text, meta in zip(old.get("knowledge_chunks", []),
                          old.get("chunk_metadata", [])):
        if meta.get("type") not in _REGENERATED_TYPES:
            chunks.append(text)
            metas.append(meta)
    return chunks, metas, old.get("system_prompt")


def main():
    ap = argparse.ArgumentParser(description="Generate the M6 RAG artifacts.")
    ap.add_argument("--model-dir", default=None,
                    help="Directory with the ML model files.")
    ap.add_argument("--output", default=None,
                    help="Output .pkl (default: <model-dir>/M6_rag_artifacts.pkl).")
    ap.add_argument("--source", default=None,
                    help="Existing .pkl to preserve non-prediction chunks from "
                         "(default: same as --output).")
    args = ap.parse_args()

    model_dir = _model_dir(args.model_dir)
    output = Path(args.output) if args.output else model_dir / "M6_rag_artifacts.pkl"
    source = Path(args.source) if args.source else output

    log.info("Model dir: %s", model_dir)
    log.info("Loading ML models...")
    from app.models.loader import model_loader

    model_loader.load_all(str(model_dir))
    valid_pairs = model_loader.get_model("recommend_valid_pairs")
    if not valid_pairs:
        log.error("recommend_valid_pairs not loaded (M5_valid_pairs.pkl missing?)")
        return 1

    pred_chunks, pred_metas, records = _generate_predictions(valid_pairs)
    sum_chunks, sum_metas = _generate_summaries(records)
    districts = sorted({r["district"] for r in records})
    wx_chunks, wx_metas = _generate_weather(districts)
    kept_chunks, kept_metas, system_prompt = _load_kept(source)

    chunks = pred_chunks + sum_chunks + wx_chunks + kept_chunks
    metas = pred_metas + sum_metas + wx_metas + kept_metas

    log.info("Embedding %d chunks with all-MiniLM-L6-v2...", len(chunks))
    from sentence_transformers import SentenceTransformer

    encoder = SentenceTransformer(
        "all-MiniLM-L6-v2",
        cache_folder=os.environ.get("SENTENCE_TRANSFORMERS_HOME"),
    )
    embeddings = encoder.encode(chunks, convert_to_numpy=True,
                                show_progress_bar=False).astype("float32")

    artifacts = {
        "knowledge_chunks": chunks,
        "chunk_metadata": metas,
        "chunk_embeddings": embeddings,
    }
    if system_prompt is not None:
        artifacts["system_prompt"] = system_prompt  # preserved from source

    import joblib

    output.parent.mkdir(parents=True, exist_ok=True)
    joblib.dump(artifacts, output)

    log.info(
        "Generated %d prediction chunks + %d summary chunks + %d weather "
        "chunks + %d kept chunks = %d total chunks",
        len(pred_chunks), len(sum_chunks), len(wx_chunks), len(kept_chunks),
        len(chunks),
    )
    log.info("Embeddings: %s %s | Saved: %s",
             embeddings.shape, embeddings.dtype, output)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
