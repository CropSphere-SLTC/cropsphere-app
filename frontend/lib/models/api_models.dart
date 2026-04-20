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
  final String crop;
  final String district;
  final String confidence;
  final String modelUsed;
  final bool isMock;

  YieldResponse({
    required this.predictedYieldKgPerHa,
    required this.crop,
    required this.district,
    required this.confidence,
    required this.modelUsed,
    this.isMock = false,
  });

  factory YieldResponse.fromJson(Map<String, dynamic> json) => YieldResponse(
    predictedYieldKgPerHa: (json['predicted_yield_kg_per_ha'] as num)
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

class WeatherResponse {
  final String district;
  final List<WeatherForecastWeek> forecasts;
  final bool isMock;

  WeatherResponse({
    required this.district,
    required this.forecasts,
    this.isMock = false,
  });

  factory WeatherResponse.fromJson(Map<String, dynamic> json) =>
      WeatherResponse(
        district: json['district'],
        forecasts: (json['forecasts'] as List)
            .map((w) => WeatherForecastWeek.fromJson(w))
            .toList(),
        isMock: json['is_mock'] ?? false,
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

class PriceResponse {
  final String crop;
  final String district;
  final double predictedFarmgatePriceLkrKg;
  final double predictedRetailPriceLkrKg;
  final String confidence;
  final bool isMock;

  PriceResponse({
    required this.crop,
    required this.district,
    required this.predictedFarmgatePriceLkrKg,
    required this.predictedRetailPriceLkrKg,
    required this.confidence,
    this.isMock = false,
  });

  factory PriceResponse.fromJson(Map<String, dynamic> json) => PriceResponse(
    crop: json['crop'],
    district: json['district'],
    predictedFarmgatePriceLkrKg:
        (json['predicted_farmgate_price_lkr_kg'] as num).toDouble(),
    predictedRetailPriceLkrKg: (json['predicted_retail_price_lkr_kg'] as num)
        .toDouble(),
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
  final Map<String, bool> suitabilityFlags;

  CropRecommendation({
    required this.rank,
    required this.crop,
    required this.confidenceScore,
    required this.expectedYieldKgPerHa,
    required this.expectedPriceLkrKg,
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

class ChatRequest {
  final String message;
  final List<ChatMessage> conversationHistory;
  final String userId;
  final String? district;
  final String? crop;

  ChatRequest({
    required this.message,
    required this.conversationHistory,
    required this.userId,
    this.district,
    this.crop,
  });

  Map<String, dynamic> toJson() => {
    'message': message,
    'conversation_history': conversationHistory.map((m) => m.toJson()).toList(),
    'user_id': userId,
    if (district != null) 'district': district,
    if (crop != null) 'crop': crop,
  };
}

class ChatResponse {
  final String reply;
  final List<String> sourcesUsed;
  final List<String> suggestedFollowups;
  final bool isMock;

  ChatResponse({
    required this.reply,
    required this.sourcesUsed,
    required this.suggestedFollowups,
    this.isMock = false,
  });

  factory ChatResponse.fromJson(Map<String, dynamic> json) => ChatResponse(
    reply: json['reply'],
    sourcesUsed: List<String>.from(json['sources_used'] ?? []),
    suggestedFollowups: List<String>.from(json['suggested_followups'] ?? []),
    isMock: json['is_mock'] ?? false,
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
