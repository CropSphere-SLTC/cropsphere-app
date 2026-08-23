import 'package:flutter_test/flutter_test.dart';
import 'package:cropsphere_app/services/profile_service.dart';

// Mirrors ProfileService.updatePreferences' echo check so the rule is
// pinned independently of Dio/network.
List<PreferenceField> unconfirmedFor({
  required String? sentDistrict,
  required String? sentCrop,
  required Map<String, dynamic> serverEcho,
}) {
  final out = <PreferenceField>[];
  if (sentDistrict != null && serverEcho['preferred_district'] != sentDistrict) {
    out.add(PreferenceField.district);
  }
  if (sentCrop != null && serverEcho['preferred_crop'] != sentCrop) {
    out.add(PreferenceField.crop);
  }
  return out;
}

void main() {
  test('old backend silently drops both fields -> both flagged', () {
    // Real deployed response shape: no preferred_* keys at all.
    final r = unconfirmedFor(
      sentDistrict: 'Jaffna',
      sentCrop: 'Green gram',
      serverEcho: {'message': 'Preferences updated', 'language': 'en'},
    );
    expect(r, [PreferenceField.district, PreferenceField.crop]);
    expect(PreferencesSaveResult(r).fullyConfirmed, isFalse);
  });

  test('new backend echoes both -> nothing flagged', () {
    final r = unconfirmedFor(
      sentDistrict: 'Jaffna',
      sentCrop: 'Green gram',
      serverEcho: {
        'preferred_district': 'Jaffna',
        'preferred_crop': 'Green gram',
      },
    );
    expect(r, isEmpty);
    expect(PreferencesSaveResult(r).fullyConfirmed, isTrue);
  });

  test('fields not sent are never flagged', () {
    final r = unconfirmedFor(
      sentDistrict: null,
      sentCrop: null,
      serverEcho: {'preferred_district': null, 'preferred_crop': null},
    );
    expect(r, isEmpty);
  });

  test('partial store is flagged per-field', () {
    final r = unconfirmedFor(
      sentDistrict: 'Jaffna',
      sentCrop: 'Green gram',
      serverEcho: {'preferred_district': 'Jaffna'},
    );
    expect(r, [PreferenceField.crop]);
  });
}
