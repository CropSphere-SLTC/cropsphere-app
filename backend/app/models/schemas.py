"""Pydantic request/response schemas with strict input validation for all endpoints."""

from enum import Enum
from typing import Any, Dict, List, Literal, Optional

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


class AveragePriceSourceEnum(str, Enum):
    """Which dataset a crop's average farmgate price was derived from.

    Surfaced in PricePredictResponse so the UI can label the baseline
    honestly rather than presenting a synthetic estimate as observed
    market data — same transparency principle as the chatbot's source
    citations and the confidence badges.
    """

    real = "real"
    synthetic = "synthetic"


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
    average_yield_kg_per_ha: float  # model-derived baseline for this crop
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
    # How much the forecast for THIS district can be trusted. Same honesty
    # contract as PricePredictResponse.average_price_source: provenance
    # travels with the number rather than being inferred by the client.
    #
    #   "model"                — M2 forecast, district within its competence.
    #   "model_low_confidence" — M2 forecast, but its training data is wrong
    #                            for this district (see
    #                            weather_service._UNTRUSTED_FORECAST_DISTRICTS).
    #                            Still the best available: nothing else can
    #                            forecast four weeks forward, and the client's
    #                            Open-Meteo call returns a PAST-7-day average,
    #                            not a forecast, so it cannot substitute here.
    #   "climatology"          — the LSTM was absent; flat seasonal averages.
    forecast_source: Literal["model", "model_low_confidence", "climatology"] = "model"


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
    average_farmgate_price_lkr_kg: float  # static per-crop baseline, see price_service
    # Provenance of that baseline. None when no average was computed at
    # all (model-missing mock response, or price CSVs unreadable) — the
    # UI should omit the badge entirely in that case rather than guess.
    average_price_source: Optional[AveragePriceSourceEnum] = None
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
    # Whether M5_valid_pairs records this crop as grown in this district.
    # Advisory — all six crops are still returned, but unsuitable ones never
    # outrank suitable ones. Additive field; existing clients ignore it.
    district_suitable: bool = True
    suitability_flags: Dict[str, Any]


class RecommendResponse(BaseModel):
    recommendations: List[CropRecommendation]
    is_mock: bool = False


# ── Chat ───────────────────────────────────────────────────────────────────────


class ConversationTurn(BaseModel):
    role: str = Field(..., pattern=r"^(user|assistant)$")
    content: str = Field(..., max_length=500)


class PredictionWeather(BaseModel):
    """Weather snapshot a yield prediction was run against.

    Bounds mirror YieldPredictRequest's so a figure that could never have
    produced a real prediction can't be smuggled into the chat prompt.
    """

    rainfall_mm: Optional[float] = Field(default=None, ge=0, le=500)
    temp_min_c: Optional[float] = Field(default=None, ge=-5, le=45)
    temp_max_c: Optional[float] = Field(default=None, ge=0, le=50)
    humidity_pct: Optional[float] = Field(default=None, ge=0, le=100)
    wind_speed_kmh: Optional[float] = Field(default=None, ge=0, le=100)
    solar_radiation_mj: Optional[float] = Field(default=None, ge=0, le=35)


class PredictionWeatherWeek(BaseModel):
    """One week of a multi-week weather forecast the farmer is asking about.

    Distinct from [PredictionWeather] above: that one is a single snapshot
    fed INTO a yield prediction as a model input; this is one row OUT OF a
    weather forecast itself (weather_screen's "Ask AI about this"), so
    PredictionContext.forecast_weeks below is a short list of these rather
    than reusing the singular model.

    `condition` is a bounded three-way Literal, not the display label the
    client renders — the same reasoning as `average_price_source` below:
    _format_prediction_context maps it to its own English phrase server-side,
    so nothing client-authored reaches the prompt as free text.
    """

    week_number: int = Field(..., ge=1, le=4)
    date: str = Field(..., pattern=r"^\d{4}-\d{2}-\d{2}$")
    rainfall_mm: float = Field(..., ge=0, le=500)
    temp_min_c: float = Field(..., ge=-5, le=45)
    temp_max_c: float = Field(..., ge=0, le=50)
    humidity_pct: float = Field(..., ge=0, le=100)
    condition: Literal["heavy_rain", "dry_hot", "good"]


class PredictionCropRecommendation(BaseModel):
    """One row of a crop-recommendation result the farmer is asking about.

    Mirrors CropRecommendation on the response side, minus the display-only
    bits. Every field is an enum or a bounded scalar for the same reason as
    [PredictionWeatherWeek]: _format_prediction_context renders these into the
    prompt, so nothing here may be client-authored free text.

    The four agronomic booleans are spelled out rather than sent as the
    response's `suitability_flags` dict — a dict would let a client invent
    key names that reach the prompt, which is exactly what the flat, typed
    fields prevent.
    """

    rank: int = Field(..., ge=1, le=6)
    crop: CropEnum
    confidence: float = Field(..., ge=0, le=1)
    expected_yield_kg_per_ha: float = Field(..., ge=0, le=1000000)
    expected_price_lkr_kg: float = Field(..., ge=0, le=100000)
    district_suitable: bool
    temp_suitable: bool
    rain_suitable: bool
    humidity_suitable: bool
    ph_suitable: bool


class PredictionContext(BaseModel):
    """A prediction the farmer is asking about, attached to a chat message so
    the LLM can ground its answer in these specific numbers instead of generic
    dataset figures.

    Carries EITHER a yield prediction, a price prediction, or a weather
    forecast. The three share crop/district/season (weather only ever sets
    district) and are otherwise disjoint, so rather than a third model and a
    third request field they live in one optional-everything block: the
    client sends whatever its screen produced, and
    _format_prediction_context renders only the fields that are set.

    Every field is optional — the client sends whatever the prediction
    produced. Crop/district/season/irrigation are ENUMS, not free strings, and
    the price/weather fields below are bounded floats, booleans, or Literals:
    nothing here is client-authored prose, so this block cannot become a
    prompt-injection vector the way an arbitrary text field would.
    """

    crop: Optional[CropEnum] = None
    district: Optional[DistrictEnum] = None
    season: Optional[SeasonEnum] = None

    # ── Yield-side fields ────────────────────────────────────────────────────
    irrigation: Optional[IrrigationEnum] = None
    area_perches: Optional[float] = Field(default=None, ge=0, le=200000)
    area_hectares: Optional[float] = Field(default=None, ge=0, le=500)
    predicted_yield_kg_per_ha: Optional[float] = Field(default=None, ge=0, le=1000000)
    average_yield_kg_per_ha: Optional[float] = Field(default=None, ge=0, le=1000000)

    # ── Price-side fields ────────────────────────────────────────────────────
    predicted_price_lkr_kg: Optional[float] = Field(default=None, ge=0, le=100000)
    average_price_lkr_kg: Optional[float] = Field(default=None, ge=0, le=100000)
    # Omitted when the backend reported no attributable baseline, mirroring the
    # client contract: an unattributed average is not stated at all.
    average_price_source: Optional[Literal["real", "synthetic"]] = None
    quantity_kg: Optional[float] = Field(default=None, ge=0, le=1000000)
    estimated_earnings_lkr: Optional[float] = Field(default=None, ge=0, le=1000000000)
    supply_level: Optional[Literal["low", "normal", "high"]] = None
    demand_level: Optional[Literal["low", "normal", "high"]] = None
    holiday_week: Optional[bool] = None
    festival_week: Optional[bool] = None

    confidence: Optional[ConfidenceEnum] = None
    weather: Optional[PredictionWeather] = None

    # ── Weather-forecast-side fields ─────────────────────────────────────────
    weeks_ahead: Optional[int] = Field(default=None, ge=1, le=4)
    forecast_weeks: Optional[List[PredictionWeatherWeek]] = Field(
        default=None, max_length=4
    )

    # ── Crop-recommendation-side fields ──────────────────────────────────────
    # Set by the recommend screen. `crop` above carries the TOP-ranked crop so
    # _prediction_context_terms and the RAG metadata boost resolve a crop the
    # same way they do for a yield or price handoff; the full ranking lives
    # here. soil_ph/soil_moisture_pct are recommendation inputs the other two
    # screens never collect.
    soil_ph: Optional[float] = Field(default=None, ge=3.5, le=9.0)
    soil_moisture_pct: Optional[float] = Field(default=None, ge=0, le=100)
    recommendations: Optional[List[PredictionCropRecommendation]] = Field(
        default=None, max_length=6
    )

    # ── Demand-forecast-side fields ──────────────────────────────────────────
    # Set by the demand screen. That screen has NO district input, so a demand
    # handoff sets `crop` and leaves `district` None — the reverse of a weather
    # handoff. _should_confirm_saved_context handles that correctly already:
    # the forecast's crop wins over any saved-profile crop, and only the
    # district is confirmed with the farmer.
    #
    # None of the four reuse a price-side field, deliberately. demand_level is
    # a Literal low|normal|high that the PRICE screen sends as an INPUT; the
    # index below is an ML output on a different scale, and collapsing one into
    # the other would let the assistant describe a farmer's own dropdown choice
    # as a prediction. Likewise retail_price_lkr_kg is what the farmer TYPED,
    # not a predicted or average price, so it cannot ride on either of those.
    predicted_demand_index: Optional[float] = Field(default=None, ge=0, le=1000)
    demand_trend: Optional[TrendEnum] = None
    retail_price_lkr_kg: Optional[float] = Field(default=None, ge=0, le=100000)
    # Whether the farmer opened "I have real market data" and supplied actual
    # recent figures, or left the per-crop typical defaults in place. The
    # assistant needs this to know how much weight the index deserves.
    real_market_data: Optional[bool] = None


class ChatRequest(BaseModel):
    message: str = Field(..., max_length=500)
    conversation_history: List[ConversationTurn] = Field(
        default_factory=list, max_length=10
    )
    user_id: str = Field(..., min_length=1, max_length=128)
    district: Optional[DistrictEnum] = None
    crop: Optional[CropEnum] = None
    model: str = Field(default="accurate", pattern="^(fast|accurate)$")
    conversation_id: Optional[str] = Field(default=None, max_length=128)
    # Optional structured prediction (yield OR price) the farmer is asking
    # about. When
    # present, _build_messages injects it as an extra system context block
    # (see chatbot_service._format_prediction_context). It NEVER touches
    # `message`, so chat_analytics keeps logging only the farmer's own short
    # question. Absent -> the request behaves exactly as it did before.
    prediction_context: Optional[PredictionContext] = None


class ChatResponse(BaseModel):
    reply: str
    sources_used: List[str]
    suggested_followups: List[str]
    conversation_id: str = ""
    is_mock: bool = False
    confidence: str = ""


class ChatFeedbackRequest(BaseModel):
    conversation_id: str = Field("", max_length=128)
    message_index: int = Field(..., ge=0)
    feedback: str = Field(..., pattern="^(up|down)$")
    message_text: str = Field("", max_length=500)


# ── Chat conversation history ─────────────────────────────────────────────────


class ConversationSummary(BaseModel):
    id: str
    title: str
    updated_at: Optional[str] = None
    message_count: int = 0


class ConversationMessage(BaseModel):
    role: str = Field(..., pattern=r"^(user|assistant)$")
    content: str
    timestamp: Optional[str] = None


class ConversationDetail(BaseModel):
    id: str
    title: str
    created_at: Optional[str] = None
    updated_at: Optional[str] = None
    message_count: int = 0
    messages: List[ConversationMessage] = Field(default_factory=list)


class RenameConversationRequest(BaseModel):
    title: str = Field(..., min_length=1, max_length=100)


# ── User profile & preferences ──────────────────────────────────────────────


class UserProfileResponse(BaseModel):
    name: str
    email: str
    photo_url: Optional[str] = None
    role: str
    last_login: Optional[str] = None
    active_sessions: int = 0


class UpdateProfileRequest(BaseModel):
    display_name: str = Field(..., min_length=1, max_length=100)


class NotificationPreferences(BaseModel):
    price_alerts: bool = True
    weather_alerts: bool = True
    yield_recommendations: bool = True


class UserPreferencesResponse(BaseModel):
    language: str = Field(default="en", pattern="^(en|si|ta)$")
    notifications: NotificationPreferences
    preferred_district: Optional[str] = None
    preferred_crop: Optional[str] = None


class UpdatePreferencesRequest(BaseModel):
    language: str = Field(..., pattern="^(en|si|ta)$")
    notifications: NotificationPreferences
    # The farmer's home district / main crop, used to personalise the
    # dashboard (recommendation hero + price comparison). Validated against
    # the same enums the prediction endpoints use so an unknown value can
    # never reach a model call. Optional and None-means-untouched: the
    # chatbot also writes these from conversational context
    # (update_user_context), so a settings save that omits them must leave
    # whatever is already stored alone rather than clearing it.
    preferred_district: Optional[DistrictEnum] = None
    preferred_crop: Optional[CropEnum] = None
