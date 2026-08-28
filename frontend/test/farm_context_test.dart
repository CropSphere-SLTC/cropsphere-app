// Regression tests for lib/utils/farm_context.dart.
//
// Both functions here previously fed wrong inputs into crop recommendations
// without raising anything: the season disagreed with the backend for two
// months a year, and a failed weather fetch was dressed up as real readings.

import 'package:flutter_test/flutter_test.dart';

import 'package:cropsphere_app/utils/farm_context.dart';

void main() {
  group('farmSeasonForMonth', () {
    // Must stay identical to chatbot_service._season_for_now:
    // Nov-Mar Maha, Apr-Aug Yala, Sep-Oct Inter.
    const expected = {
      1: 'Maha',
      2: 'Maha',
      3: 'Maha',
      4: 'Yala',
      5: 'Yala',
      6: 'Yala',
      7: 'Yala',
      8: 'Yala',
      9: 'Inter',
      10: 'Inter',
      11: 'Maha',
      12: 'Maha',
    };

    test('every month matches the backend mapping', () {
      for (final entry in expected.entries) {
        expect(
          farmSeasonForMonth(entry.key),
          entry.value,
          reason: 'month ${entry.key} must be ${entry.value}',
        );
      }
    });

    test('September and October are Inter, not Yala', () {
      // The old week-based version called these Yala while the server called
      // them Inter — the two-month disagreement this replaced.
      expect(farmSeasonForMonth(9), 'Inter');
      expect(farmSeasonForMonth(10), 'Inter');
    });

    test('season boundaries fall between Oct/Nov and Mar/Apr', () {
      expect(farmSeasonForMonth(10), 'Inter');
      expect(farmSeasonForMonth(11), 'Maha');
      expect(farmSeasonForMonth(3), 'Maha');
      expect(farmSeasonForMonth(4), 'Yala');
    });

    test('the clock is injectable and reads the month it is given', () {
      expect(farmCurrentSeason(DateTime.utc(2026, 10, 31, 19)), 'Inter');
      expect(farmCurrentSeason(DateTime.utc(2026, 11, 1, 0, 30)), 'Maha');
      expect(farmCurrentSeason(DateTime.utc(2026, 4, 1)), 'Yala');
    });

    // NOT TESTED, deliberately: that farmCurrentSeason reads the UTC month
    // rather than the local one. Any DateTime this test could construct is
    // either already UTC — in which case .month and .toUtc().month agree and
    // dropping the conversion would still pass — or it depends on the test
    // machine's zone, which makes the test pass or fail by where it runs.
    // The parity that matters (Nov-Mar Maha, Apr-Aug Yala, Sep-Oct Inter,
    // read in UTC to match chatbot_service._season_for_now) is pinned by the
    // mapping tests above plus the CI grep guard against private copies.
  });

  group('farmWeatherFromJson', () {
    Map<String, dynamic> daily({
      List<num>? rain,
      List<num>? tmax,
      List<num>? tmin,
      List<num>? rh,
    }) => {
      // Explicitly dynamic: the real payload is decoded JSON, where a series
      // may legitimately contain nulls.
      'daily': <String, dynamic>{
        'precipitation_sum': rain ?? [1, 2, 3, 4, 5, 6, 7],
        'temperature_2m_max': tmax ?? [30, 30, 30, 30, 30, 30, 30],
        'temperature_2m_min': tmin ?? [20, 20, 20, 20, 20, 20, 20],
        'relative_humidity_2m_mean': rh ?? [70, 70, 70, 70, 70, 70, 70],
      },
    };

    test('rainfall is summed and temperature/humidity averaged', () {
      final w = farmWeatherFromJson(daily());
      expect(w.rainfallMm, 28); // 1+2+..+7, a weekly TOTAL not a daily mean
      expect(w.tempMaxC, 30);
      expect(w.tempMinC, 20);
      expect(w.humidityPct, 70);
    });

    test('an empty series throws instead of fabricating a reading', () {
      // Regression: this used to yield 0mm / 0C / 5C / 0% — a plausible-looking
      // FarmWeather that crop suitability was then graded against.
      expect(() => farmWeatherFromJson(daily(rain: [])), throwsException);
      expect(() => farmWeatherFromJson(daily(tmin: [])), throwsException);
      expect(() => farmWeatherFromJson(daily(tmax: [])), throwsException);
      expect(() => farmWeatherFromJson(daily(rh: [])), throwsException);
    });

    test('an all-null series throws', () {
      final json = daily();
      (json['daily'] as Map<String, dynamic>)['precipitation_sum'] = [
        null,
        null,
      ];
      expect(() => farmWeatherFromJson(json), throwsException);
    });

    test('a missing daily block throws', () {
      expect(() => farmWeatherFromJson(<String, dynamic>{}), throwsException);
    });

    test('yield extras are null unless requested', () {
      final w = farmWeatherFromJson(daily());
      expect(w.windSpeedKmh, isNull);
      expect(w.solarRadMj, isNull);
    });

    test('yield extras are averaged and clamped to the backend bounds', () {
      final json = daily();
      (json['daily'] as Map<String, dynamic>).addAll({
        'wind_speed_10m_max': [10, 20, 30],
        'shortwave_radiation_sum': [15, 25, 35],
      });
      final w = farmWeatherFromJson(json, withYieldExtras: true);
      // Daily maxima averaged — these ARE daily values, unlike rainfall.
      expect(w.windSpeedKmh, 20);
      expect(w.solarRadMj, 25);
      // And rainfall is still a weekly TOTAL, which the yield screen's own
      // copy of this parser got wrong (it used a daily mean, ~7x too small).
      expect(w.rainfallMm, 28);
    });

    test('a missing extras series throws rather than yielding zero', () {
      final json = daily();
      (json['daily'] as Map<String, dynamic>).addAll({
        'wind_speed_10m_max': <num>[],
        'shortwave_radiation_sum': [15, 25, 35],
      });
      expect(
        () => farmWeatherFromJson(json, withYieldExtras: true),
        throwsException,
      );
    });

    test('nulls shorten the window rather than counting as zero', () {
      final json = daily();
      (json['daily'] as Map<String, dynamic>)['temperature_2m_min'] = [
        20,
        null,
        22,
      ];
      // Mean of the two real readings (21), not of three with a zero (14).
      expect(farmWeatherFromJson(json).tempMinC, 21);
    });
  });
}
