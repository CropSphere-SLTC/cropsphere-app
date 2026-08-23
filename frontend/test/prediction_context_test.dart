import 'package:flutter_test/flutter_test.dart';
import 'package:cropsphere_app/models/api_models.dart';
import 'package:cropsphere_app/services/prediction_handoff.dart';
import 'package:cropsphere_app/widgets/followup_chip.dart';

// Pins the wire shape of the yield-prediction -> chat handoff. The backend
// schema (app/models/schemas.py :: PredictionContext) is enum-typed, so a
// renamed key or a wrong-cased enum value here is a 422 on every chat call
// made from a prediction — worth pinning independently of Dio/network.

PredictionContext _full() => const PredictionContext(
  crop: 'Carrot',
  district: 'Badulla',
  season: 'Maha',
  irrigation: 'drip',
  areaPerches: 160.0,
  areaHectares: 0.4047,
  predictedYieldKgPerHa: 19612.0,
  averageYieldKgPerHa: 19961.0,
  confidence: 'high',
  weather: PredictionWeather(
    rainfallMm: 45.0,
    tempMinC: 12.0,
    tempMaxC: 22.0,
    humidityPct: 78.0,
    windSpeedKmh: 12.0,
    solarRadiationMj: 16.0,
  ),
);

ChatRequest _req({PredictionContext? ctx}) => ChatRequest(
  message: 'Explain this prediction',
  conversationHistory: const [],
  userId: 'u-1',
  predictionContext: ctx,
);

void main() {
  group('PredictionContext.toJson', () {
    test('uses the backend schema key names', () {
      final json = _full().toJson();
      expect(json['crop'], 'Carrot');
      expect(json['district'], 'Badulla');
      expect(json['season'], 'Maha');
      expect(json['irrigation'], 'drip');
      expect(json['area_perches'], 160.0);
      expect(json['area_hectares'], 0.4047);
      expect(json['predicted_yield_kg_per_ha'], 19612.0);
      expect(json['average_yield_kg_per_ha'], 19961.0);
      expect(json['confidence'], 'high');
      expect(json['weather'], isA<Map<String, dynamic>>());
      expect((json['weather'] as Map)['rainfall_mm'], 45.0);
      expect((json['weather'] as Map)['solar_radiation_mj'], 16.0);
    });

    test('omits unset fields rather than sending nulls', () {
      final json = const PredictionContext(crop: 'Maize').toJson();
      expect(json.keys, ['crop']);
      expect(json.containsKey('district'), isFalse);
      expect(json.containsKey('weather'), isFalse);
    });

    test('summary reads as crop, district and yield', () {
      expect(_full().summary, 'Carrot · Badulla · 19612 kg/ha');
      expect(const PredictionContext().summary, isEmpty);
    });
  });

  group('ChatRequest.toJson', () {
    test('omits prediction_context entirely when there is none', () {
      // Backward compatibility: a chat request with no prediction must be
      // byte-identical to what the app sent before this field existed.
      final json = _req().toJson();
      expect(json.containsKey('prediction_context'), isFalse);
      expect(json['message'], 'Explain this prediction');
    });

    test('nests the context and leaves the message untouched', () {
      final json = _req(ctx: _full()).toJson();
      // The visible message is what chat analytics logs — the prediction
      // must ride beside it, never inside it.
      expect(json['message'], 'Explain this prediction');
      expect(json['message'], isNot(contains('19612')));
      expect(json['message'], isNot(contains('Carrot')));
      final pc = json['prediction_context'] as Map<String, dynamic>;
      expect(pc['crop'], 'Carrot');
      expect(pc['predicted_yield_kg_per_ha'], 19612.0);
    });

    test('every starter chip keeps the message short', () {
      // The four quick questions on the yield result card are sent verbatim
      // as the user's message.
      expect(kPredictionStarters, hasLength(4));
      for (final s in kPredictionStarters) {
        final json = ChatRequest(
          message: s,
          conversationHistory: const [],
          userId: 'u-1',
          predictionContext: _full(),
        ).toJson();
        expect(json['message'], s);
        // Backend caps message at 500 chars.
        expect((json['message'] as String).length, lessThan(500));
      }
    });
  });

  group('predictionHandoff channel', () {
    tearDown(() => predictionHandoff.value = null);

    test('starts empty and notifies on publish', () {
      expect(predictionHandoff.value, isNull);
      var notifications = 0;
      void listener() => notifications++;
      predictionHandoff.addListener(listener);

      predictionHandoff.value = PredictionHandoff(_full());
      expect(notifications, 1);
      expect(predictionHandoff.value?.context.crop, 'Carrot');

      // Consume-once: the subscriber clears the slot so re-entering the chat
      // tab later can't replay a stale prediction into a new conversation.
      predictionHandoff.value = null;
      expect(notifications, 2);
      expect(predictionHandoff.value, isNull);

      predictionHandoff.removeListener(listener);
    });

    test('a quick-question tap carries the question, the button does not', () {
      // Chip tap on the yield result card -> chat auto-sends this on arrival.
      predictionHandoff.value = PredictionHandoff(
        _full(),
        question: kPredictionStarters.first,
      );
      expect(predictionHandoff.value?.question, 'Explain this prediction');

      // Free-form button -> no question, chat waits for the farmer to type.
      predictionHandoff.value = PredictionHandoff(_full());
      expect(predictionHandoff.value?.question, isNull);
      expect(predictionHandoff.value?.context.district, 'Badulla');
    });

    test('clearing an already-empty slot notifies nobody', () {
      // Guards the re-entrant clear in _onPredictionHandoff: the nested call
      // must find null and stop, not loop.
      var notifications = 0;
      void listener() => notifications++;
      predictionHandoff.addListener(listener);
      predictionHandoff.value = null;
      expect(notifications, 0);
      predictionHandoff.removeListener(listener);
    });
  });
}
