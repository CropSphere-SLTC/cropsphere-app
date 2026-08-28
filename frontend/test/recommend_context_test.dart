// Covers the two pieces of the Crop Recommendation redesign that carry real
// logic rather than layout: the dynamic top-crop starter chip, and the
// district_suitable / agronomic-flag plumbing into the chat handoff.
import 'package:flutter_test/flutter_test.dart';
import 'package:cropsphere_app/models/api_models.dart';
import 'package:cropsphere_app/widgets/followup_chip.dart';

CropRecommendation _rec({
  int rank = 1,
  String crop = 'Groundnut',
  double confidence = 0.66,
  bool districtSuitable = true,
  Map<String, bool>? flags,
}) => CropRecommendation(
  rank: rank,
  crop: crop,
  confidenceScore: confidence,
  expectedYieldKgPerHa: 1307,
  expectedPriceLkrKg: 50,
  districtSuitable: districtSuitable,
  suitabilityFlags:
      flags ??
      const {
        'temp_suitable': true,
        'rain_suitable': true,
        'humidity_suitable': true,
        'ph_suitable': true,
      },
);

void main() {
  group('recommendation starter chips', () {
    test('names whichever crop actually ranked first', () {
      expect(
        recommendStarters('Groundnut'),
        contains('Why is Groundnut ranked first?'),
      );
      expect(
        recommendStarters('Cowpea'),
        contains('Why is Cowpea ranked first?'),
      );
    });

    test('offers five chips with the dynamic one second', () {
      final chips = recommendStarters('Groundnut');
      expect(chips, hasLength(5));
      expect(chips.first, 'Explain these recommendations');
      expect(chips[1], 'Why is Groundnut ranked first?');
    });

    test('falls back to four chips when there is no result yet', () {
      final chips = recommendStarters(null);
      expect(chips, hasLength(4));
      expect(chips.any((c) => c.contains('ranked first')), isFalse);
    });
  });

  group('CropRecommendation.fromJson', () {
    test('reads district_suitable and all four agronomic flags', () {
      final r = CropRecommendation.fromJson(const {
        'rank': 6,
        'crop': 'Carrot',
        'confidence_score': 0.146,
        'expected_yield_kg_per_ha': 18409.1,
        'expected_price_lkr_kg': 53.03,
        'district_suitable': false,
        'suitability_flags': {
          'temp_suitable': false,
          'rain_suitable': true,
          'humidity_suitable': true,
          'ph_suitable': true,
        },
      });
      expect(r.districtSuitable, isFalse);
      expect(r.suitabilityFlags['temp_suitable'], isFalse);
      expect(r.suitabilityFlags.values.where((v) => v).length, 3);
    });

    test('defaults district_suitable to true when the backend omits it', () {
      // An older backend must degrade to "no district objection" rather than
      // flagging every crop as not grown here.
      final r = CropRecommendation.fromJson(const {
        'rank': 1,
        'crop': 'Maize',
        'confidence_score': 0.06,
        'expected_yield_kg_per_ha': 2836.2,
        'expected_price_lkr_kg': 43.11,
        'suitability_flags': {'temp_suitable': true},
      });
      expect(r.districtSuitable, isTrue);
    });
  });

  group('PredictionCropRecommendation.fromRecommendation', () {
    test('flattens the flag map into named booleans', () {
      final p = PredictionCropRecommendation.fromRecommendation(
        _rec(
          crop: 'Carrot',
          districtSuitable: false,
          flags: const {
            'temp_suitable': false,
            'rain_suitable': true,
            'humidity_suitable': true,
            'ph_suitable': true,
          },
        ),
      );
      expect(p.tempSuitable, isFalse);
      expect(p.rainSuitable, isTrue);
      expect(p.districtSuitable, isFalse);
    });

    test('a renamed or missing flag reads false instead of throwing', () {
      final p = PredictionCropRecommendation.fromRecommendation(
        _rec(flags: const {'temperature_ok': true}),
      );
      expect(p.tempSuitable, isFalse);
      expect(p.phSuitable, isFalse);
    });
  });

  group('humidity caveat trigger', () {
    // The caveat is gated on any crop failing humidity. The gate is the whole
    // behaviour worth testing — the widget itself is a static string.
    bool anyFails(List<CropRecommendation> recs) =>
        recs.any((r) => r.suitabilityFlags['humidity_suitable'] == false);

    test('fires when any crop fails humidity', () {
      expect(
        anyFails([
          _rec(),
          _rec(
            crop: 'Carrot',
            flags: const {
              'temp_suitable': true,
              'rain_suitable': true,
              'humidity_suitable': false,
              'ph_suitable': true,
            },
          ),
        ]),
        isTrue,
      );
    });

    test('stays hidden when humidity passes for every crop', () {
      expect(anyFails([_rec(), _rec(crop: 'Maize')]), isFalse);
    });

    test('stays hidden when the flag is absent entirely', () {
      // An older backend that never sends humidity_suitable must not trigger
      // a caveat about a condition it is not reporting.
      expect(
        anyFails([
          _rec(flags: const {'temp_suitable': true, 'rain_suitable': true}),
        ]),
        isFalse,
      );
    });
  });

  group('PredictionContext.toJson', () {
    test('carries soil, weather and the full ranking on the wire', () {
      final ctx = PredictionContext(
        crop: 'Groundnut',
        district: 'Monaragala',
        season: 'Yala',
        irrigation: 'rainfed',
        soilPh: 6.5,
        soilMoisturePct: 40,
        recommendations: [
          PredictionCropRecommendation.fromRecommendation(_rec()),
          PredictionCropRecommendation.fromRecommendation(
            _rec(rank: 6, crop: 'Carrot', districtSuitable: false),
          ),
        ],
      );
      final json = ctx.toJson();
      expect(json['soil_ph'], 6.5);
      expect(json['soil_moisture_pct'], 40);
      expect(json['crop'], 'Groundnut');
      final recs = json['recommendations'] as List;
      expect(recs, hasLength(2));
      expect((recs.last as Map)['district_suitable'], isFalse);
      expect((recs.first as Map)['temp_suitable'], isTrue);
    });

    test('omits the recommendation fields entirely for a price handoff', () {
      // One model serves all four screens; a price context must not start
      // announcing empty recommendation keys to the backend.
      final json = PredictionContext(
        crop: 'Carrot',
        predictedPriceLkrKg: 90,
      ).toJson();
      expect(json.containsKey('recommendations'), isFalse);
      expect(json.containsKey('soil_ph'), isFalse);
    });
  });
}
