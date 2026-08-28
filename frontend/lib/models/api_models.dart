// lib/models/api_models.dart
// Request and response models matching Pydantic schemas exactly

// ─── YIELD ───────────────────────────────────────────────────────────────────

class YieldRequest {
  final String crop;
  final String district;
  final String season;
  final int weekOfYear;
  final double rainfallMm;
  final double tempMinC;
  final double tempMaxC;
  final double humidityPct;
  final double windSpeedKmh;
  final double solarRadiationMj;
  final double soilPh;
  final double soilMoisturePct;
  final double cultivatedAreaHa;
  final String seedVariety;
  final double fertilizerIndex;
  final double pesticideIndex;
  final String irrigationType;
  final double nIndex;
  final double pIndex;
  final double kIndex;
  final String prevCrop;
  final double demandIndex;
  final double inflationIndex;
  final int holidayFlag;
  final int festivalFlag;

  YieldRequest({
    required this.crop,
    required this.district,
    required this.season,
    required this.weekOfYear,
    required this.rainfallMm,
    required this.tempMinC,
    required this.tempMaxC,
    required this.humidityPct,
    required this.windSpeedKmh,
    required this.solarRadiationMj,
    required this.soilPh,
    required this.soilMoisturePct,
    required this.cultivatedAreaHa,
    required this.seedVariety,
    required this.fertilizerIndex,
    required this.pesticideIndex,
    required this.irrigationType,
    required this.nIndex,
    required this.pIndex,
    required this.kIndex,
    required this.prevCrop,
    required this.demandIndex,
    required this.inflationIndex,
    required this.holidayFlag,
    required this.festivalFlag,
  });

  Map<String, dynamic> toJson() => {
    'crop': crop,
    'district': district,
    'season': season,
    'week_of_year': weekOfYear,
    'rainfall_mm': rainfallMm,
    'temp_min_c': tempMinC,
    'temp_max_c': tempMaxC,
    'humidity_pct': humidityPct,
    'wind_speed_kmh': windSpeedKmh,
    'solar_radiation_mj': solarRadiationMj,
    'soil_ph': soilPh,
    'soil_moisture_pct': soilMoisturePct,
    'cultivated_area_ha': cultivatedAreaHa,
    'seed_variety': seedVariety,
    'fertilizer_index': fertilizerIndex,
    'pesticide_index': pesticideIndex,
    'irrigation_type': irrigationType,
    'N_index': nIndex,
    'P_index': pIndex,
    'K_index': kIndex,
    'prev_crop': prevCrop,
    'demand_index': demandIndex,
    'inflation_index': inflationIndex,
    'holiday_flag': holidayFlag,
    'festival_flag': festivalFlag,
  };
}

class YieldResponse {
  final double predictedYieldKgPerHa;
  final double averageYieldKgPerHa;
  final String crop;
  final String district;
  final String confidence;
  final String modelUsed;
  final bool isMock;

  YieldResponse({
    required this.predictedYieldKgPerHa,
    this.averageYieldKgPerHa = 0.0,
    required this.crop,
    required this.district,
    required this.confidence,
    required this.modelUsed,
    this.isMock = false,
  });

  factory YieldResponse.fromJson(Map<String, dynamic> json) => YieldResponse(
    predictedYieldKgPerHa: (json['predicted_yield_kg_per_ha'] as num)
        .toDouble(),
    averageYieldKgPerHa: (json['average_yield_kg_per_ha'] as num? ?? 0)
        .toDouble(),
    crop: json['crop'],
    district: json['district'],
    confidence: json['confidence'],
    modelUsed: json['model_used'],
    isMock: json['is_mock'] ?? false,
  );
}

// ─── WEATHER ─────────────────────────────────────────────────────────────────

class WeatherRequest {
  final String district;
  final String startDate;
  final int weeksAhead;

  WeatherRequest({
    required this.district,
    required this.startDate,
    required this.weeksAhead,
  });

  Map<String, dynamic> toJson() => {
    'district': district,
    'start_date': startDate,
    'weeks_ahead': weeksAhead,
  };
}

class WeatherForecastWeek {
  final int weekNumber;
  final String date;
  final double rainfallMm;
  final double tempMinC;
  final double tempMaxC;
  final double humidityPct;

  WeatherForecastWeek({
    required this.weekNumber,
    required this.date,
    required this.rainfallMm,
    required this.tempMinC,
    required this.tempMaxC,
    required this.humidityPct,
  });

  factory WeatherForecastWeek.fromJson(Map<String, dynamic> json) =>
      WeatherForecastWeek(
        weekNumber: json['week_number'],
        date: json['date'],
        rainfallMm: (json['rainfall_mm'] as num).toDouble(),
        tempMinC: (json['temp_min_c'] as num).toDouble(),
        tempMaxC: (json['temp_max_c'] as num).toDouble(),
        humidityPct: (json['humidity_pct'] as num).toDouble(),
      );
}

/// Where a forecast came from, and how far it can be trusted.
///
/// Same honesty contract as [AveragePriceSource] on the price side:
/// provenance travels with the number instead of being inferred.
enum ForecastSource {
  /// M2 forecast for a district the model handles competently.
  model,

  /// M2 forecast, but its training data is wrong for this district — it
  /// records the hill country as lowland-hot, which collapses the predicted
  /// rainfall. Still shown: nothing else forecasts four weeks ahead, and the
  /// client's own Open-Meteo call returns a PAST-7-day average, not a
  /// forecast. Shown WITH a caveat rather than passed off as reliable.
  modelLowConfidence,

  /// The LSTM was unavailable; these are flat seasonal averages.
  climatology,

  /// Field absent or unrecognised — an older backend. Treated as [model] for
  /// display: an unknown source must not invent a warning we cannot justify.
  unknown,
}

ForecastSource _forecastSourceFromWire(dynamic v) => switch (v) {
  'model' => ForecastSource.model,
  'model_low_confidence' => ForecastSource.modelLowConfidence,
  'climatology' => ForecastSource.climatology,
  _ => ForecastSource.unknown,
};

class WeatherResponse {
  final String district;
  final List<WeatherForecastWeek> forecasts;
  final bool isMock;
  final ForecastSource forecastSource;

  WeatherResponse({
    required this.district,
    required this.forecasts,
    this.isMock = false,
    this.forecastSource = ForecastSource.unknown,
  });

  /// True when the forecast should carry a visible caveat.
  bool get isLowConfidence =>
      forecastSource == ForecastSource.modelLowConfidence;

  factory WeatherResponse.fromJson(Map<String, dynamic> json) =>
      WeatherResponse(
        district: json['district'],
        forecasts: (json['forecasts'] as List)
            .map((w) => WeatherForecastWeek.fromJson(w))
            .toList(),
        isMock: json['is_mock'] ?? false,
        forecastSource: _forecastSourceFromWire(json['forecast_source']),
      );
}

// ─── PRICE ───────────────────────────────────────────────────────────────────

class PriceRequest {
  final String crop;
  final String district;
  final String season;
  final int weekOfYear;
  final double inflationIndex;
  final double fuelPriceIndex;
  final double transportCostIndex;
  final double supplyIndex;
  final double demandIndex;
  final int holidayFlag;
  final int festivalFlag;
  final double farmgatePriceLag1;
  final double farmgatePriceLag2;
  final double farmgatePriceLag4;

  PriceRequest({
    required this.crop,
    required this.district,
    required this.season,
    required this.weekOfYear,
    required this.inflationIndex,
    required this.fuelPriceIndex,
    required this.transportCostIndex,
    required this.supplyIndex,
    required this.demandIndex,
    required this.holidayFlag,
    required this.festivalFlag,
    required this.farmgatePriceLag1,
    required this.farmgatePriceLag2,
    required this.farmgatePriceLag4,
  });

  Map<String, dynamic> toJson() => {
    'crop': crop,
    'district': district,
    'season': season,
    'week_of_year': weekOfYear,
    'inflation_index': inflationIndex,
    'fuel_price_index': fuelPriceIndex,
    'transport_cost_index': transportCostIndex,
    'supply_index': supplyIndex,
    'demand_index': demandIndex,
    'holiday_flag': holidayFlag,
    'festival_flag': festivalFlag,
    'farmgate_price_lag1': farmgatePriceLag1,
    'farmgate_price_lag2': farmgatePriceLag2,
    'farmgate_price_lag4': farmgatePriceLag4,
  };
}

/// Where a crop's average farmgate price came from. Mirrors the backend's
/// AveragePriceSourceEnum, plus `unknown` for the null case.
///
/// `unknown` means the backend reported no source at all (mock response, or
/// the price datasets were unreadable). Callers MUST render nothing for it —
/// no "estimated" fallback, no implied claim about the data's origin.
enum AveragePriceSource { real, synthetic, unknown }

class PriceResponse {
  final String crop;
  final String district;
  final double predictedFarmgatePriceLkrKg;
  final double predictedRetailPriceLkrKg;

  /// Static per-crop baseline the prediction can be compared against.
  /// 0.0 when unavailable (mock response) — pair with [averagePriceSource]
  /// before showing any comparison.
  final double averageFarmgatePriceLkrKg;
  final AveragePriceSource averagePriceSource;

  final String confidence;
  final bool isMock;

  PriceResponse({
    required this.crop,
    required this.district,
    required this.predictedFarmgatePriceLkrKg,
    required this.predictedRetailPriceLkrKg,
    this.averageFarmgatePriceLkrKg = 0.0,
    this.averagePriceSource = AveragePriceSource.unknown,
    required this.confidence,
    this.isMock = false,
  });

  /// True only when there's a real baseline to compare against.
  bool get hasAverage =>
      averageFarmgatePriceLkrKg > 0 &&
      averagePriceSource != AveragePriceSource.unknown;

  static AveragePriceSource _parseSource(dynamic raw) => switch (raw) {
    'real' => AveragePriceSource.real,
    'synthetic' => AveragePriceSource.synthetic,
    // Covers null and any value a future backend adds that this build
    // doesn't know — both mean "don't claim anything about the source".
    _ => AveragePriceSource.unknown,
  };

  factory PriceResponse.fromJson(Map<String, dynamic> json) => PriceResponse(
    crop: json['crop'],
    district: json['district'],
    predictedFarmgatePriceLkrKg:
        (json['predicted_farmgate_price_lkr_kg'] as num).toDouble(),
    predictedRetailPriceLkrKg: (json['predicted_retail_price_lkr_kg'] as num)
        .toDouble(),
    averageFarmgatePriceLkrKg:
        (json['average_farmgate_price_lkr_kg'] as num?)?.toDouble() ?? 0.0,
    averagePriceSource: _parseSource(json['average_price_source']),
    confidence: json['confidence'],
    isMock: json['is_mock'] ?? false,
  );
}

// ─── DEMAND ──────────────────────────────────────────────────────────────────

class DemandRequest {
  final String crop;
  final String season;
  final int weekOfYear;
  final double demandLag1;
  final double demandLag2;
  final double demandLag4;
  final double retailPriceLkrKg;
  final double inflationIndex;
  final int holidayFlag;
  final int festivalFlag;
  final double consumerPrefIndex;
  final double searchTrendIndex;

  DemandRequest({
    required this.crop,
    required this.season,
    required this.weekOfYear,
    required this.demandLag1,
    required this.demandLag2,
    required this.demandLag4,
    required this.retailPriceLkrKg,
    required this.inflationIndex,
    required this.holidayFlag,
    required this.festivalFlag,
    required this.consumerPrefIndex,
    required this.searchTrendIndex,
  });

  Map<String, dynamic> toJson() => {
    'crop': crop,
    'season': season,
    'week_of_year': weekOfYear,
    'demand_lag1': demandLag1,
    'demand_lag2': demandLag2,
    'demand_lag4': demandLag4,
    'retail_price_lkr_kg': retailPriceLkrKg,
    'inflation_index': inflationIndex,
    'holiday_flag': holidayFlag,
    'festival_flag': festivalFlag,
    'consumer_pref_index': consumerPrefIndex,
    'search_trend_index': searchTrendIndex,
  };
}

class DemandResponse {
  final String crop;
  final double predictedDemandIndex;
  final String trend;
  final String confidence;
  final bool isMock;

  DemandResponse({
    required this.crop,
    required this.predictedDemandIndex,
    required this.trend,
    required this.confidence,
    this.isMock = false,
  });

  factory DemandResponse.fromJson(Map<String, dynamic> json) => DemandResponse(
    crop: json['crop'],
    predictedDemandIndex: (json['predicted_demand_index'] as num).toDouble(),
    trend: json['trend'],
    confidence: json['confidence'],
    isMock: json['is_mock'] ?? false,
  );
}

// ─── RECOMMEND ───────────────────────────────────────────────────────────────

class RecommendRequest {
  final String district;
  final String season;
  final int weekOfYear;
  final double rainfallMm;
  final double tempMinC;
  final double tempMaxC;
  final double humidityPct;
  final double soilPh;
  final double soilMoisturePct;
  final double nIndex;
  final double pIndex;
  final double kIndex;
  final String irrigationType;

  RecommendRequest({
    required this.district,
    required this.season,
    required this.weekOfYear,
    required this.rainfallMm,
    required this.tempMinC,
    required this.tempMaxC,
    required this.humidityPct,
    required this.soilPh,
    required this.soilMoisturePct,
    required this.nIndex,
    required this.pIndex,
    required this.kIndex,
    required this.irrigationType,
  });

  Map<String, dynamic> toJson() => {
    'district': district,
    'season': season,
    'week_of_year': weekOfYear,
    'rainfall_mm': rainfallMm,
    'temp_min_c': tempMinC,
    'temp_max_c': tempMaxC,
    'humidity_pct': humidityPct,
    'soil_ph': soilPh,
    'soil_moisture_pct': soilMoisturePct,
    'N_index': nIndex,
    'P_index': pIndex,
    'K_index': kIndex,
    'irrigation_type': irrigationType,
  };
}

class CropRecommendation {
  final int rank;
  final String crop;
  final double confidenceScore;
  final double expectedYieldKgPerHa;
  final double expectedPriceLkrKg;

  /// Whether M5_valid_pairs records this crop as grown in this district.
  /// Advisory — the backend still returns all six crops, but sorts
  /// district-unsuitable ones below every suitable one regardless of their
  /// probability. Defaults to true so an older backend that omits the field
  /// degrades to "no district objection" rather than flagging everything.
  final bool districtSuitable;

  /// The four agronomic conditions: temp_suitable, rain_suitable,
  /// humidity_suitable, ph_suitable. Read generically so a backend that adds
  /// a fifth condition needs no client change.
  final Map<String, bool> suitabilityFlags;

  CropRecommendation({
    required this.rank,
    required this.crop,
    required this.confidenceScore,
    required this.expectedYieldKgPerHa,
    required this.expectedPriceLkrKg,
    this.districtSuitable = true,
    required this.suitabilityFlags,
  });

  factory CropRecommendation.fromJson(
    Map<String, dynamic> json,
  ) => CropRecommendation(
    rank: json['rank'],
    crop: json['crop'],
    confidenceScore: (json['confidence_score'] as num).toDouble(),
    expectedYieldKgPerHa: (json['expected_yield_kg_per_ha'] as num).toDouble(),
    expectedPriceLkrKg: (json['expected_price_lkr_kg'] as num).toDouble(),
    districtSuitable: json['district_suitable'] as bool? ?? true,
    suitabilityFlags: Map<String, bool>.from(json['suitability_flags'] ?? {}),
  );
}

class RecommendResponse {
  final List<CropRecommendation> recommendations;
  final bool isMock;

  RecommendResponse({required this.recommendations, this.isMock = false});

  factory RecommendResponse.fromJson(Map<String, dynamic> json) =>
      RecommendResponse(
        recommendations: (json['recommendations'] as List)
            .map((r) => CropRecommendation.fromJson(r))
            .toList(),
        isMock: json['is_mock'] ?? false,
      );
}

// ─── CHAT ────────────────────────────────────────────────────────────────────

class ChatMessage {
  final String role; // 'user' or 'assistant'
  final String content;

  ChatMessage({required this.role, required this.content});

  Map<String, dynamic> toJson() => {'role': role, 'content': content};
}

/// Weather snapshot a yield prediction was run against. Field names match
/// the backend's `PredictionWeather` schema exactly.
class PredictionWeather {
  final double? rainfallMm;
  final double? tempMinC;
  final double? tempMaxC;
  final double? humidityPct;
  final double? windSpeedKmh;
  final double? solarRadiationMj;

  const PredictionWeather({
    this.rainfallMm,
    this.tempMinC,
    this.tempMaxC,
    this.humidityPct,
    this.windSpeedKmh,
    this.solarRadiationMj,
  });

  Map<String, dynamic> toJson() => {
    if (rainfallMm != null) 'rainfall_mm': rainfallMm,
    if (tempMinC != null) 'temp_min_c': tempMinC,
    if (tempMaxC != null) 'temp_max_c': tempMaxC,
    if (humidityPct != null) 'humidity_pct': humidityPct,
    if (windSpeedKmh != null) 'wind_speed_kmh': windSpeedKmh,
    if (solarRadiationMj != null) 'solar_radiation_mj': solarRadiationMj,
  };
}

/// One week of a multi-week weather forecast the farmer is asking about.
/// Field names match the backend's `PredictionWeatherWeek` schema exactly.
///
/// Distinct from [PredictionWeather] above: that one is a single snapshot
/// fed INTO a yield prediction; this is one row OUT OF a weather forecast
/// itself (weather_screen's "Ask AI about this").
///
/// [condition] is 'heavy_rain' | 'dry_hot' | 'good' — the same three-way
/// split as weather_screen's `_adviceFor`, expressed as a bounded token
/// rather than display text; the backend maps it to its own English phrase.
class PredictionWeatherWeek {
  final int weekNumber;
  final String date;
  final double rainfallMm;
  final double tempMinC;
  final double tempMaxC;
  final double humidityPct;
  final String condition;

  const PredictionWeatherWeek({
    required this.weekNumber,
    required this.date,
    required this.rainfallMm,
    required this.tempMinC,
    required this.tempMaxC,
    required this.humidityPct,
    required this.condition,
  });

  Map<String, dynamic> toJson() => {
    'week_number': weekNumber,
    'date': date,
    'rainfall_mm': rainfallMm,
    'temp_min_c': tempMinC,
    'temp_max_c': tempMaxC,
    'humidity_pct': humidityPct,
    'condition': condition,
  };
}

/// A yield prediction, price prediction, or weather forecast the farmer is
/// asking the AI about.
///
/// Sent on [ChatRequest.predictionContext] so the backend can inject these
/// specific figures into the LLM's context (see the backend's
/// `chatbot_service._format_prediction_context`). It rides ALONGSIDE the
/// user's message and is never merged into it — the visible message stays the
/// farmer's own short question, which is what chat analytics records.
///
/// crop/district/season/irrigation/confidence must match the backend enums —
/// they come straight from the yield screen's own constant lists, which are
/// the same values.
/// One row of a crop-recommendation result, sent to chat as context.
///
/// Mirrors [CropRecommendation] minus the display-only parts. The four
/// agronomic conditions are flattened into named booleans rather than sent as
/// the response's `suitability_flags` map: the backend renders these straight
/// into the prompt, and flat typed fields mean a client cannot invent key
/// names that reach it.
class PredictionCropRecommendation {
  final int rank;
  final String crop;
  final double confidence;
  final double expectedYieldKgPerHa;
  final double expectedPriceLkrKg;
  final bool districtSuitable;
  final bool tempSuitable;
  final bool rainSuitable;
  final bool humiditySuitable;
  final bool phSuitable;

  const PredictionCropRecommendation({
    required this.rank,
    required this.crop,
    required this.confidence,
    required this.expectedYieldKgPerHa,
    required this.expectedPriceLkrKg,
    required this.districtSuitable,
    required this.tempSuitable,
    required this.rainSuitable,
    required this.humiditySuitable,
    required this.phSuitable,
  });

  /// Built straight from an API [CropRecommendation]. Missing flags read as
  /// false rather than throwing — a backend that renames one degrades to
  /// "condition not met" instead of breaking the whole handoff.
  factory PredictionCropRecommendation.fromRecommendation(
    CropRecommendation r,
  ) => PredictionCropRecommendation(
    rank: r.rank,
    crop: r.crop,
    confidence: r.confidenceScore.clamp(0.0, 1.0),
    expectedYieldKgPerHa: r.expectedYieldKgPerHa,
    expectedPriceLkrKg: r.expectedPriceLkrKg,
    districtSuitable: r.districtSuitable,
    tempSuitable: r.suitabilityFlags['temp_suitable'] ?? false,
    rainSuitable: r.suitabilityFlags['rain_suitable'] ?? false,
    humiditySuitable: r.suitabilityFlags['humidity_suitable'] ?? false,
    phSuitable: r.suitabilityFlags['ph_suitable'] ?? false,
  );

  Map<String, dynamic> toJson() => {
    'rank': rank,
    'crop': crop,
    'confidence': confidence,
    'expected_yield_kg_per_ha': expectedYieldKgPerHa,
    'expected_price_lkr_kg': expectedPriceLkrKg,
    'district_suitable': districtSuitable,
    'temp_suitable': tempSuitable,
    'rain_suitable': rainSuitable,
    'humidity_suitable': humiditySuitable,
    'ph_suitable': phSuitable,
  };
}

class PredictionContext {
  final String? crop;
  final String? district;
  final String? season;
  final String? irrigation;
  final double? areaPerches;
  final double? areaHectares;
  final double? predictedYieldKgPerHa;
  final double? averageYieldKgPerHa;

  // ── Price-side fields ──────────────────────────────────────────────────────
  // Set by the price screen instead of the yield fields above. One model
  // carries either prediction; the backend renders only what is set.
  final double? predictedPriceLkrKg;
  final double? averagePriceLkrKg;

  /// 'real' | 'synthetic', or null. Null is NOT a fallback label — it means
  /// the backend attributed no baseline, so neither the card nor the chat
  /// context says anything about where the average came from.
  final String? averagePriceSource;
  final double? quantityKg;
  final double? estimatedEarningsLkr;
  final String? supplyLevel; // low | normal | high
  final String? demandLevel; // low | normal | high
  final bool? holidayWeek;
  final bool? festivalWeek;

  final String? confidence;
  final PredictionWeather? weather;

  // ── Weather-forecast-side fields ──────────────────────────────────────────
  // Set by the weather screen instead of the yield/price fields above.
  final int? weeksAhead;
  final List<PredictionWeatherWeek>? forecastWeeks;

  // ── Crop-recommendation-side fields ───────────────────────────────────────
  // Set by the recommend screen. `crop` above carries the TOP-ranked crop, so
  // the backend's saved-context confirmation gate and RAG metadata boost
  // resolve a crop exactly as they do for a yield or price handoff; the full
  // ranking rides in [recommendations].
  final double? soilPh;
  final double? soilMoisturePct;
  final List<PredictionCropRecommendation>? recommendations;

  // ── Demand-forecast-side fields ───────────────────────────────────────────
  // Set by the demand screen. That screen collects NO district, so a demand
  // handoff sets `crop` and leaves `district` null — the reverse of a weather
  // handoff, and handled the same way by the backend's confirmation gate.
  //
  // None of these reuse a price-side field: [demandLevel] is a low|normal|high
  // INPUT the price screen sends, whereas [predictedDemandIndex] is an ML
  // output on a different scale, and [retailPriceLkrKg] is what the farmer
  // typed rather than a predicted or average price.
  final double? predictedDemandIndex;
  final String? demandTrend; // rising | stable | falling
  final double? retailPriceLkrKg;

  /// Whether the farmer opened "I have real market data" and supplied actual
  /// figures, or left the per-crop typical defaults in place. Sent in BOTH
  /// states — "these were typical values" is the caveat that stops the
  /// assistant treating a defaulted forecast as a grounded one.
  final bool? realMarketData;

  const PredictionContext({
    this.crop,
    this.district,
    this.season,
    this.irrigation,
    this.areaPerches,
    this.areaHectares,
    this.predictedYieldKgPerHa,
    this.averageYieldKgPerHa,
    this.predictedPriceLkrKg,
    this.averagePriceLkrKg,
    this.averagePriceSource,
    this.quantityKg,
    this.estimatedEarningsLkr,
    this.supplyLevel,
    this.demandLevel,
    this.holidayWeek,
    this.festivalWeek,
    this.confidence,
    this.weather,
    this.weeksAhead,
    this.forecastWeeks,
    this.soilPh,
    this.soilMoisturePct,
    this.recommendations,
    this.predictedDemandIndex,
    this.demandTrend,
    this.retailPriceLkrKg,
    this.realMarketData,
  });

  /// One-line "Carrot · Badulla · 19612 kg/ha" summary for the chat screen's
  /// prediction empty state, so the farmer can see which prediction the
  /// conversation is about.
  String get summary => [
    ?crop,
    ?district,
    if (predictedYieldKgPerHa != null)
      '${predictedYieldKgPerHa!.toStringAsFixed(0)} kg/ha',
    if (predictedPriceLkrKg != null)
      'Rs. ${predictedPriceLkrKg!.toStringAsFixed(0)}/kg',
    if (weeksAhead != null) '$weeksAhead-week forecast',
    if (predictedDemandIndex != null)
      'demand ${predictedDemandIndex!.toStringAsFixed(0)}',
  ].join(' · ');

  Map<String, dynamic> toJson() => {
    if (crop != null) 'crop': crop,
    if (district != null) 'district': district,
    if (season != null) 'season': season,
    if (irrigation != null) 'irrigation': irrigation,
    if (areaPerches != null) 'area_perches': areaPerches,
    if (areaHectares != null) 'area_hectares': areaHectares,
    if (predictedYieldKgPerHa != null)
      'predicted_yield_kg_per_ha': predictedYieldKgPerHa,
    if (averageYieldKgPerHa != null)
      'average_yield_kg_per_ha': averageYieldKgPerHa,
    if (predictedPriceLkrKg != null)
      'predicted_price_lkr_kg': predictedPriceLkrKg,
    if (averagePriceLkrKg != null) 'average_price_lkr_kg': averagePriceLkrKg,
    if (averagePriceSource != null) 'average_price_source': averagePriceSource,
    if (quantityKg != null) 'quantity_kg': quantityKg,
    if (estimatedEarningsLkr != null)
      'estimated_earnings_lkr': estimatedEarningsLkr,
    if (supplyLevel != null) 'supply_level': supplyLevel,
    if (demandLevel != null) 'demand_level': demandLevel,
    if (holidayWeek != null) 'holiday_week': holidayWeek,
    if (festivalWeek != null) 'festival_week': festivalWeek,
    if (confidence != null) 'confidence': confidence,
    if (weather != null) 'weather': weather!.toJson(),
    if (weeksAhead != null) 'weeks_ahead': weeksAhead,
    if (forecastWeeks != null)
      'forecast_weeks': forecastWeeks!.map((w) => w.toJson()).toList(),
    if (soilPh != null) 'soil_ph': soilPh,
    if (soilMoisturePct != null) 'soil_moisture_pct': soilMoisturePct,
    if (recommendations != null)
      'recommendations': recommendations!.map((r) => r.toJson()).toList(),
    if (predictedDemandIndex != null)
      'predicted_demand_index': predictedDemandIndex,
    if (demandTrend != null) 'demand_trend': demandTrend,
    if (retailPriceLkrKg != null) 'retail_price_lkr_kg': retailPriceLkrKg,
    if (realMarketData != null) 'real_market_data': realMarketData,
  };
}

class ChatRequest {
  final String message;
  final List<ChatMessage> conversationHistory;
  final String userId;
  final String? district;
  final String? crop;
  final String model;
  final String language;
  final String? conversationId;

  /// Optional yield prediction this conversation is about. Passed invisibly
  /// in the request body — it is NOT part of [message], so the backend keeps
  /// logging only the farmer's own short question to chat analytics.
  final PredictionContext? predictionContext;

  ChatRequest({
    required this.message,
    required this.conversationHistory,
    required this.userId,
    this.district,
    this.crop,
    this.model = 'accurate',
    this.language = 'auto',
    this.conversationId,
    this.predictionContext,
  });

  Map<String, dynamic> toJson() => {
    'message': message,
    'conversation_history': conversationHistory.map((m) => m.toJson()).toList(),
    'user_id': userId,
    if (district != null) 'district': district,
    if (crop != null) 'crop': crop,
    'model': model,
    'language': language,
    if (conversationId != null) 'conversation_id': conversationId,
    if (predictionContext != null)
      'prediction_context': predictionContext!.toJson(),
  };
}

class ChatResponse {
  final String reply;
  final List<String> sourcesUsed;
  final List<String> suggestedFollowups;
  final String conversationId;
  final bool isMock;
  final String
  confidence; // XAI label: High/Moderate/Low confidence, Out of scope

  ChatResponse({
    required this.reply,
    required this.sourcesUsed,
    required this.suggestedFollowups,
    this.conversationId = '',
    this.isMock = false,
    this.confidence = '',
  });

  factory ChatResponse.fromJson(Map<String, dynamic> json) => ChatResponse(
    reply: json['reply'],
    sourcesUsed: List<String>.from(json['sources_used'] ?? []),
    suggestedFollowups: List<String>.from(json['suggested_followups'] ?? []),
    conversationId: json['conversation_id'] ?? '',
    isMock: json['is_mock'] ?? false,
    confidence: json['confidence'] ?? '',
  );
}

// ─── CONSTANTS ───────────────────────────────────────────────────────────────

class CropSphereConstants {
  static const List<String> crops = [
    'Carrot',
    'Maize',
    'Green gram',
    'Cowpea',
    'Finger millet',
    'Groundnut',
  ];

  static const List<String> districts = [
    'Nuwara Eliya',
    'Badulla',
    'Anuradhapura',
    'Monaragala',
    'Ampara',
    'Hambantota',
    'Batticaloa',
    'Jaffna',
  ];

  static const List<String> seasons = ['Maha', 'Yala', 'Inter'];

  static const List<String> irrigationTypes = [
    'drip',
    'sprinkler',
    'flood',
    'rainfed',
  ];

  // Valid crop-district pairs (from DOA agronomic mapping)
  static const Map<String, List<String>> validCropDistricts = {
    'Carrot': ['Nuwara Eliya', 'Badulla', 'Jaffna'],
    'Maize': ['Anuradhapura', 'Monaragala', 'Ampara'],
    'Green gram': ['Hambantota', 'Monaragala', 'Jaffna'],
    'Cowpea': ['Anuradhapura', 'Monaragala', 'Ampara'],
    'Finger millet': ['Anuradhapura', 'Monaragala', 'Ampara'],
    'Groundnut': ['Monaragala', 'Ampara', 'Batticaloa', 'Jaffna'],
  };

  static List<String> validCropsForDistrict(String district) {
    return validCropDistricts.entries
        .where((e) => e.value.contains(district))
        .map((e) => e.key)
        .toList();
  }
}
