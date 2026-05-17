// lib/services/mock_service.dart
// Returns realistic hardcoded data in exact same shape as real API
// Every method signature matches ApiService — swap is one line in service_factory.dart

import 'dart:math';
import '../models/api_models.dart';

class MockService {
  static final MockService _instance = MockService._internal();
  factory MockService() => _instance;
  MockService._internal();

  final Random _rng = Random();

  // Simulate network delay (makes UI feel real during development)
  Future<void> _delay() =>
      Future.delayed(Duration(milliseconds: 600 + _rng.nextInt(400)));

  Future<YieldResponse> predictYield(YieldRequest request) async {
    await _delay();
    final yields = {
      'Carrot': 21450.0,
      'Maize': 2915.0,
      'Green gram': 1126.0,
      'Cowpea': 1200.0,
      'Finger millet': 949.0,
      'Groundnut': 2200.0,
    };
    final base = yields[request.crop] ?? 1500.0;
    // Add small variance so repeated calls feel real
    final predicted = base * (0.9 + _rng.nextDouble() * 0.2);

    return YieldResponse(
      predictedYieldKgPerHa: predicted,
      averageYieldKgPerHa: base,
      crop: request.crop,
      district: request.district,
      confidence: predicted > base * 0.95 ? 'high' : 'medium',
      modelUsed: 'per_crop_rf (mock)',
      isMock: true,
    );
  }

  Future<WeatherResponse> forecastWeather(WeatherRequest request) async {
    await _delay();

    // Realistic baselines per district
    final baselines = {
      'Nuwara Eliya': (rain: 45.0, tmin: 11.0, tmax: 19.0, hum: 82.0),
      'Badulla': (rain: 35.0, tmin: 16.0, tmax: 26.0, hum: 76.0),
      'Anuradhapura': (rain: 18.0, tmin: 22.0, tmax: 34.0, hum: 68.0),
      'Monaragala': (rain: 22.0, tmin: 21.0, tmax: 33.0, hum: 70.0),
      'Ampara': (rain: 28.0, tmin: 22.0, tmax: 32.0, hum: 74.0),
      'Hambantota': (rain: 14.0, tmin: 24.0, tmax: 33.0, hum: 65.0),
      'Batticaloa': (rain: 30.0, tmin: 23.0, tmax: 32.0, hum: 75.0),
      'Jaffna': (rain: 16.0, tmin: 24.0, tmax: 34.0, hum: 68.0),
    };
    final b =
        baselines[request.district] ??
        (rain: 20.0, tmin: 22.0, tmax: 32.0, hum: 70.0);

    final forecasts = List.generate(request.weeksAhead, (i) {
      return WeatherForecastWeek(
        weekNumber: i + 1,
        date: _addWeeks(request.startDate, i),
        rainfallMm: (b.rain * (0.7 + _rng.nextDouble() * 0.6)).roundToDouble(),
        tempMinC: (b.tmin + (_rng.nextDouble() - 0.5) * 2).roundToDouble(),
        tempMaxC: (b.tmax + (_rng.nextDouble() - 0.5) * 2).roundToDouble(),
        humidityPct: (b.hum + (_rng.nextDouble() - 0.5) * 6).roundToDouble(),
      );
    });

    return WeatherResponse(
      district: request.district,
      forecasts: forecasts,
      isMock: true,
    );
  }

  Future<PriceResponse> predictPrice(PriceRequest request) async {
    await _delay();
    final basePrices = {
      'Carrot': (farmgate: 58.0, retail: 89.0),
      'Maize': (farmgate: 48.0, retail: 72.0),
      'Green gram': (farmgate: 145.0, retail: 198.0),
      'Cowpea': (farmgate: 142.0, retail: 195.0),
      'Finger millet': (farmgate: 98.0, retail: 135.0),
      'Groundnut': (farmgate: 195.0, retail: 260.0),
    };
    final b = basePrices[request.crop] ?? (farmgate: 100.0, retail: 140.0);

    return PriceResponse(
      crop: request.crop,
      district: request.district,
      predictedFarmgatePriceLkrKg:
          (b.farmgate *
                  (0.95 + _rng.nextDouble() * 0.1) *
                  request.inflationIndex)
              .roundToDouble(),
      predictedRetailPriceLkrKg:
          (b.retail * (0.95 + _rng.nextDouble() * 0.1) * request.inflationIndex)
              .roundToDouble(),
      confidence: 'high',
      isMock: true,
    );
  }

  Future<DemandResponse> predictDemand(DemandRequest request) async {
    await _delay();
    // Festival weeks drive demand up
    final festivalBoost = request.festivalFlag == 1 ? 15.0 : 0.0;
    final base = 75.0 + festivalBoost + (_rng.nextDouble() - 0.5) * 10;

    String trend;
    if (base > request.demandLag1 + 5) {
      trend = 'rising';
    } else if (base < request.demandLag1 - 5) {
      trend = 'falling';
    } else {
      trend = 'stable';
    }

    return DemandResponse(
      crop: request.crop,
      predictedDemandIndex: base.roundToDouble(),
      trend: trend,
      confidence: 'medium',
      isMock: true,
    );
  }

  Future<RecommendResponse> recommendCrop(RecommendRequest request) async {
    await _delay();
    final validCrops = CropSphereConstants.validCropsForDistrict(
      request.district,
    );

    if (validCrops.isEmpty) {
      return RecommendResponse(recommendations: [], isMock: true);
    }

    // Build ranked recommendations with realistic scores
    final recs = <CropRecommendation>[];
    final shuffled = List<String>.from(validCrops)..shuffle(_rng);

    for (int i = 0; i < shuffled.length && i < 3; i++) {
      final crop = shuffled[i];
      final yields = {
        'Carrot': 21450.0,
        'Maize': 2915.0,
        'Green gram': 1126.0,
        'Cowpea': 1200.0,
        'Finger millet': 949.0,
        'Groundnut': 2200.0,
      };
      final prices = {
        'Carrot': 58.0,
        'Maize': 48.0,
        'Green gram': 145.0,
        'Cowpea': 142.0,
        'Finger millet': 98.0,
        'Groundnut': 195.0,
      };

      recs.add(
        CropRecommendation(
          rank: i + 1,
          crop: crop,
          confidenceScore: (0.95 - i * 0.12 + (_rng.nextDouble() - 0.5) * 0.05)
              .clamp(0.0, 1.0),
          expectedYieldKgPerHa: yields[crop] ?? 1500.0,
          expectedPriceLkrKg: prices[crop] ?? 100.0,
          suitabilityFlags: {
            'temp_suitable': true,
            'rain_suitable': request.rainfallMm > 10,
            'ph_suitable': request.soilPh >= 5.5 && request.soilPh <= 7.5,
            'humidity_suitable': request.humidityPct > 50,
          },
        ),
      );
    }

    // Sort by confidence descending
    recs.sort((a, b) => b.confidenceScore.compareTo(a.confidenceScore));
    for (int i = 0; i < recs.length; i++) {
      recs[i] = CropRecommendation(
        rank: i + 1,
        crop: recs[i].crop,
        confidenceScore: recs[i].confidenceScore,
        expectedYieldKgPerHa: recs[i].expectedYieldKgPerHa,
        expectedPriceLkrKg: recs[i].expectedPriceLkrKg,
        suitabilityFlags: recs[i].suitabilityFlags,
      );
    }

    return RecommendResponse(recommendations: recs, isMock: true);
  }

  Future<ChatResponse> sendChat(ChatRequest request) async {
    await _delay();
    // Realistic context-aware mock responses
    final msg = request.message.toLowerCase();
    String reply;
    List<String> followups;

    if (msg.contains('carrot') || msg.contains('yield')) {
      reply =
          'Based on historical data for ${request.district ?? 'Nuwara Eliya'}, '
          'carrot yield averages around 21,450 kg/ha during Maha season when '
          'rainfall is adequate (35-50mm/week) and temperatures stay between '
          '10-19°C. Soil pH of 5.5-6.5 is optimal. This is mock data — '
          'connect to the real API for live predictions.';
      followups = [
        'What fertilizer is best for carrot?',
        'Which variety gives highest yield?',
        'What is the current farmgate price?',
      ];
    } else if (msg.contains('price') || msg.contains('market')) {
      reply =
          'Current farmgate prices (mock): Carrot ~58 LKR/kg, Green gram '
          '~145 LKR/kg, Groundnut ~195 LKR/kg. Retail prices are typically '
          '30-40% higher. Prices tend to spike during festival weeks '
          '(Avurudu, Vesak) by 15-25%.';
      followups = [
        'Will prices rise next week?',
        'Which crop has the best profit margin?',
        'How does inflation affect prices?',
      ];
    } else if (msg.contains('weather') || msg.contains('rain')) {
      reply =
          'Weather forecast for ${request.district ?? 'your district'}: '
          'Expect moderate rainfall next week. Temperature will remain '
          'within normal seasonal range. Check the Weather Forecast screen '
          'for detailed 4-week predictions.';
      followups = [
        'Is this good weather for planting?',
        'What crops suit dry conditions?',
        'How much irrigation do I need?',
      ];
    } else {
      reply =
          'I can help you with crop recommendations, yield predictions, '
          'market prices, weather forecasts, and farming advice for '
          'Sri Lanka\'s agricultural districts. What would you like to know?';
      followups = [
        'What should I plant this Maha season?',
        'What is the expected yield for Maize?',
        'Which district has best prices for Carrot?',
      ];
    }

    return ChatResponse(
      reply: reply,
      sourcesUsed: [
        'CropSphere synthetic dataset 2021-2025',
        'HARTI price data (mock)',
      ],
      suggestedFollowups: followups,
      isMock: true,
    );
  }

  String _addWeeks(String dateStr, int weeks) {
    try {
      final date = DateTime.parse(dateStr);
      final newDate = date.add(Duration(days: weeks * 7));
      return '${newDate.year}-${newDate.month.toString().padLeft(2, '0')}-${newDate.day.toString().padLeft(2, '0')}';
    } catch (_) {
      return dateStr;
    }
  }
}
