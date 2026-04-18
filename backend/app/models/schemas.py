"""Pydantic request/response schemas with strict input validation for all endpoints."""
from enum import Enum
from typing import Any, Dict, List, Optional

from pydantic import BaseModel, Field


# ── Enums ────────────────────────────────────────────────────────────────────

class CropEnum(str, Enum):
    carrot = "Carrot"
    maize = "Maize"
    green_gram = "Green gram"
    cowpea = "Cowpea"
    finger_millet = "Finger millet"
    groundnut = "Groundnut"


class DistrictEnum(str, Enum):
    nuwara_eliya = "Nuwara Eliya"
    badulla = "Badulla"
    anuradhapura = "Anuradhapura"
    monaragala = "Monaragala"
    ampara = "Ampara"
    hambantota = "Hambantota"
    batticaloa = "Batticaloa"
    jaffna = "Jaffna"


class SeasonEnum(str, Enum):
    maha = "Maha"
    yala = "Yala"
    inter = "Inter"


class IrrigationEnum(str, Enum):
    drip = "drip"
    sprinkler = "sprinkler"
    flood = "flood"
    rainfed = "rainfed"


class ConfidenceEnum(str, Enum):
    high = "high"
    medium = "medium"
    low = "low"


class TrendEnum(str, Enum):
    rising = "rising"
    stable = "stable"
    falling = "falling"


# ── Yield ─────────────────────────────────────────────────────────────────────

class YieldPredictRequest(BaseModel):
    crop: CropEnum
    district: DistrictEnum
    season: SeasonEnum
    week_of_year: int = Field(..., ge=1, le=52)
    rainfall_mm: float = Field(..., ge=0, le=500)
    temp_min_c: float = Field(..., ge=-5, le=45)
    temp_max_c: float = Field(..., ge=0, le=50)
    humidity_pct: float = Field(..., ge=0, le=100)
    wind_speed_kmh: float = Field(..., ge=0, le=100)
    solar_radiation_mj: float = Field(..., ge=0, le=35)
    soil_ph: float = Field(..., ge=3.5, le=9.0)
    soil_moisture_pct: float = Field(..., ge=0, le=100)
    cultivated_area_ha: float = Field(..., ge=0.1, le=500)
    seed_variety: str = Field(..., min_length=1, max_length=100)
    fertilizer_index: float = Field(..., ge=0.0, le=1.0)
    pesticide_index: float = Field(..., ge=0.0, le=1.0)
    irrigation_type: IrrigationEnum
    N_index: float = Field(..., ge=0.0, le=1.0)
    P_index: float = Field(..., ge=0.0, le=1.0)
    K_index: float = Field(..., ge=0.0, le=1.0)
    prev_crop: str = Field(..., min_length=1, max_length=100)
    demand_index: float = Field(..., ge=0, le=200)
    inflation_index: float = Field(..., ge=0.5, le=3.0)
    holiday_flag: int = Field(..., ge=0, le=1)
    festival_flag: int = Field(..., ge=0, le=1)


class YieldPredictResponse(BaseModel):
    predicted_yield_kg_per_ha: float
    crop: CropEnum
    district: DistrictEnum
    confidence: ConfidenceEnum
    model_used: str
    is_mock: bool = False


# ── Weather ───────────────────────────────────────────────────────────────────

class WeatherForecastRequest(BaseModel):
    district: DistrictEnum
    start_date: str = Field(..., pattern=r"^\d{4}-\d{2}-\d{2}$")
    weeks_ahead: int = Field(..., ge=1, le=4)


class WeekForecast(BaseModel):
    week_number: int
    date: str
    rainfall_mm: float
    temp_min_c: float
    temp_max_c: float
    humidity_pct: float


class WeatherForecastResponse(BaseModel):
    district: DistrictEnum
    forecasts: List[WeekForecast]
    is_mock: bool = False


# ── Price ──────────────────────────────────────────────────────────────────────

class PricePredictRequest(BaseModel):
    crop: CropEnum
    district: DistrictEnum
    season: SeasonEnum
    week_of_year: int = Field(..., ge=1, le=52)
    inflation_index: float = Field(..., ge=0.5, le=3.0)
    fuel_price_index: float = Field(..., ge=0.5, le=3.0)
    transport_cost_index: float = Field(..., ge=0.5, le=2.0)
    supply_index: float = Field(..., ge=20, le=200)
    demand_index: float = Field(..., ge=0, le=200)
    holiday_flag: int = Field(..., ge=0, le=1)
    festival_flag: int = Field(..., ge=0, le=1)
    farmgate_price_lag1: float = Field(..., gt=0)
    farmgate_price_lag2: float = Field(..., gt=0)
    farmgate_price_lag4: float = Field(..., gt=0)


class PricePredictResponse(BaseModel):
    crop: CropEnum
    district: DistrictEnum
    predicted_farmgate_price_lkr_kg: float
    predicted_retail_price_lkr_kg: float
    confidence: ConfidenceEnum
    is_mock: bool = False


# ── Demand ─────────────────────────────────────────────────────────────────────

class DemandPredictRequest(BaseModel):
    crop: CropEnum
    season: SeasonEnum
    week_of_year: int = Field(..., ge=1, le=52)
    demand_lag1: float = Field(..., ge=0, le=200)
    demand_lag2: float = Field(..., ge=0, le=200)
    demand_lag4: float = Field(..., ge=0, le=200)
    retail_price_lkr_kg: float = Field(..., gt=0)
    inflation_index: float = Field(..., ge=0.5, le=3.0)
    holiday_flag: int = Field(..., ge=0, le=1)
    festival_flag: int = Field(..., ge=0, le=1)
    consumer_pref_index: float = Field(..., ge=0, le=100)
    search_trend_index: float = Field(..., ge=0, le=100)


class DemandPredictResponse(BaseModel):
    crop: CropEnum
    predicted_demand_index: float
    trend: TrendEnum
    confidence: ConfidenceEnum
    is_mock: bool = False


# ── Recommend ──────────────────────────────────────────────────────────────────

class RecommendRequest(BaseModel):
    district: DistrictEnum
    season: SeasonEnum
    week_of_year: int = Field(..., ge=1, le=52)
    rainfall_mm: float = Field(..., ge=0, le=500)
    temp_min_c: float = Field(..., ge=-5, le=45)
    temp_max_c: float = Field(..., ge=0, le=50)
    humidity_pct: float = Field(..., ge=0, le=100)
    soil_ph: float = Field(..., ge=3.5, le=9.0)
    soil_moisture_pct: float = Field(..., ge=0, le=100)
    N_index: float = Field(..., ge=0.0, le=1.0)
    P_index: float = Field(..., ge=0.0, le=1.0)
    K_index: float = Field(..., ge=0.0, le=1.0)
    irrigation_type: IrrigationEnum
    farmgate_price_context: Optional[float] = Field(None, gt=0)
    demand_context: Optional[float] = Field(None, ge=0)


class CropRecommendation(BaseModel):
    rank: int
    crop: CropEnum
    confidence_score: float = Field(..., ge=0, le=1)
    expected_yield_kg_per_ha: float
    expected_price_lkr_kg: float
    suitability_flags: Dict[str, Any]


class RecommendResponse(BaseModel):
    recommendations: List[CropRecommendation]
    is_mock: bool = False


# ── Chat ───────────────────────────────────────────────────────────────────────

class ConversationTurn(BaseModel):
    role: str = Field(..., pattern=r"^(user|assistant)$")
    content: str = Field(..., max_length=500)


class ChatRequest(BaseModel):
    message: str = Field(..., max_length=500)
    conversation_history: List[ConversationTurn] = Field(default_factory=list, max_length=10)
    user_id: str = Field(..., min_length=1, max_length=128)
    district: Optional[DistrictEnum] = None
    crop: Optional[CropEnum] = None


class ChatResponse(BaseModel):
    reply: str
    sources_used: List[str]
    suggested_followups: List[str]
    is_mock: bool = False
