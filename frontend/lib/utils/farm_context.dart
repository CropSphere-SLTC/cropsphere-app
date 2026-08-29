// lib/utils/farm_context.dart
// ─────────────────────────────────────────────────────────────────────────────
//  Shared agronomic context for building M5 (/api/recommend) and M3
//  (/api/price/predict) requests.
//
//  Both endpoints require far more than the farmer actually picks on screen:
//  M5 needs 13 fields (weather + soil + NPK + irrigation), M3 needs 14. The
//  Crop Recommendation screen originally owned all of this privately; it was
//  lifted here verbatim so the dashboard's recommendation hero and price
//  comparison can build the same requests without a second, drifting copy of
//  the district coordinates, soil profiles and week/season maths.
//
//  These are sensible STARTING POINTS derived from each district's dominant
//  soil type and agro-climate — not a substitute for an actual soil test.
//  Screens that let the farmer override them (the Crop Recommendation screen)
//  should keep doing so; the dashboard uses them as-is because it has no form
//  to collect better values from.
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:convert';

import 'package:http/http.dart' as http;

// ── Time helpers ─────────────────────────────────────────────────────────────

/// ISO-ish week number, clamped to the 1–52 range every endpoint validates.
///
/// UTC, to share a clock base with [farmCurrentSeason]. Both values ride on
/// the same request (week_of_year and season), so computing one locally and
/// the other in UTC would let them describe different days for a few hours
/// around a month boundary.
int farmWeekOfYear([DateTime? now]) {
  now = (now ?? DateTime.now()).toUtc();
  final soy = DateTime.utc(now.year, 1, 1);
  return (((now.difference(soy).inDays + soy.weekday - 1) / 7).ceil()).clamp(
    1,
    52,
  );
}

/// Sri Lanka's two main cultivation seasons, plus the inter-monsoon gap.
/// Maha Nov–Mar, Yala Apr–Aug, Inter Sep–Oct.
///
/// Month-based and UTC, deliberately identical to the backend's
/// `chatbot_service._season_for_now`. The earlier week-based version put
/// Sep–Oct in Yala and returned 'Inter' for a single week of the year, so
/// the app and the server disagreed about the season for two months
/// annually — and season is stamped on analytics documents by both sides.
///
/// This is the ONLY season helper in the app. Screens must call it rather
/// than keeping a private copy; dashboard_screen.dart had one that was
/// missed when this moved to months, leaving the dashboard showing Yala
/// tips while a widget on that same dashboard sent 'Inter' to the API.
/// [now] is injectable so the UTC decision itself can be tested; asserting
/// against DateTime.now() would only restate the implementation.
String farmCurrentSeason([DateTime? now]) =>
    // UTC, because _season_for_now reads datetime.now(timezone.utc).month.
    // Local time would still disagree with the server for the first 5h30m of
    // the 1st of Nov, Apr and Sep at UTC+5:30 — a small window, but the whole
    // point of this function is that the two sides never disagree.
    farmSeasonForMonth((now ?? DateTime.now()).toUtc().month);

/// The season mapping itself, split from the clock so the boundaries can be
/// tested directly. [month] is 1-12.
String farmSeasonForMonth(int month) {
  if (month >= 11 || month <= 3) return 'Maha';
  if (month >= 4 && month <= 8) return 'Yala';
  return 'Inter';
}

// ── District coordinates ─────────────────────────────────────────────────────

const Map<String, List<double>> kDistrictCoords = {
  'Nuwara Eliya': [6.9497, 80.7891],
  'Badulla': [6.9934, 81.0550],
  'Anuradhapura': [8.3114, 80.4037],
  'Monaragala': [6.8728, 81.3507],
  'Ampara': [7.2985, 81.6724],
  'Hambantota': [6.1241, 81.1185],
  'Batticaloa': [7.7102, 81.6924],
  'Jaffna': [9.6615, 80.0255],
};

// ── Soil defaults ────────────────────────────────────────────────────────────

/// Typical Sri Lankan agricultural-soil fallback (used only if a district is
/// ever missing from the table below).
const double kDefaultSoilPh = 6.2;
const double kDefaultSoilMoisture = 55.0;

const double kDefaultNIndex = 0.55;
const double kDefaultPIndex = 0.55;
const double kDefaultKIndex = 0.55;

/// Irrigation assumed when no form collected one. Rainfed is the safe
/// default: it's the most common smallholder case in Sri Lanka and never
/// overstates the water available to a crop.
const String kDefaultIrrigation = 'rainfed';

/// A district's typical soil pH & moisture.
class SoilTypical {
  final double ph;
  final double moisturePct;
  const SoilTypical(this.ph, this.moisturePct);
}

/// Typical soil pH & moisture per district — approximate values based on the
/// dominant soil types/agro-climate of each district (upcountry wet-zone
/// districts trend more acidic & moist; dry-zone districts trend closer to
/// neutral/slightly alkaline & drier).
const Map<String, SoilTypical> kDistrictSoilDefaults = {
  'Nuwara Eliya': SoilTypical(5.6, 62.0), // upcountry, red-yellow podzolic
  'Badulla': SoilTypical(5.8, 58.0), // mid-country, similar upcountry profile
  'Anuradhapura': SoilTypical(6.8, 42.0), // dry zone, reddish brown earths
  'Monaragala': SoilTypical(6.5, 40.0), // dry zone / intermediate
  'Ampara': SoilTypical(6.6, 38.0), // dry zone, reddish brown earths
  'Hambantota': SoilTypical(7.0, 36.0), // dry zone, low rainfall
  'Batticaloa': SoilTypical(7.1, 40.0), // dry zone, coastal alluvial
  'Jaffna': SoilTypical(7.4, 35.0), // limestone-influenced, mildly alkaline
};

SoilTypical soilDefaultsFor(String district) =>
    kDistrictSoilDefaults[district] ??
    const SoilTypical(kDefaultSoilPh, kDefaultSoilMoisture);

// ── Weather ──────────────────────────────────────────────────────────────────

/// The four weather fields M5 needs, aggregated over the past week.
///
/// NOT all averages: rainfallMm is a weekly TOTAL (rain accumulates), the
/// other three are weekly means. See [fetchFarmWeather] — treating rainfall
/// as a mean is the bug that made the rainfall suitability condition fail for
/// every crop in almost every week.
///
/// Distinct from the dashboard's own `_WeatherData` (current conditions —
/// temp/rain-chance/wind, for the weather card). This one is the weekly
/// aggregate the prediction endpoints are trained against.
class FarmWeather {
  final double rainfallMm;
  final double tempMinC;
  final double tempMaxC;
  final double humidityPct;

  /// Only populated when the caller asked for [withYieldExtras]; the yield
  /// model takes these two, no other screen does. Null means "not requested",
  /// never "zero".
  final double? windSpeedKmh;
  final double? solarRadMj;

  const FarmWeather({
    required this.rainfallMm,
    required this.tempMinC,
    required this.tempMaxC,
    required this.humidityPct,
    this.windSpeedKmh,
    this.solarRadMj,
  });
}

/// Observed weather for a district over the past 7 complete days, aggregated
/// to match what the prediction models and the agronomic suitability bands
/// were trained on.
///
/// AGGREGATION MATTERS HERE, and getting it wrong is not a rounding error.
/// These four values are compared field-by-field against per-crop bands
/// derived from weekly training data (backend/scripts/derive_crop_bands.py).
/// A value on the wrong scale does not degrade the comparison — it fails it
/// every time, for every crop.
///
/// Two such faults were fixed here. Both made their condition fail
/// universally, which is what made every crop read "1 of 4 conditions ideal"
/// no matter the weather:
///
///  * RAINFALL was the MEAN of daily totals, so mm/day, compared against
///    weekly bands whose floors are 8-10mm. Roughly 7x too small;
///    rain_suitable passes 57.7% of the time in training and almost never in
///    production. Now a SUM over the window.
///  * HUMIDITY was the mean of daily PEAKS, which sits near saturation most
///    days. Training humidity_pct runs 52.0-89.1 and its condition passes
///    99.6% of the time; the mean of daily maxima for Nuwara Eliya measures
///    100.0 — above every band ceiling (82-88) and above the training maximum
///    itself. Now relative_humidity_2m_mean, which Open-Meteo exposes
///    directly.
///
/// WINDOW: past_days=7 with forecast_days=0 — exactly 7 complete, OBSERVED
/// days. The previous call added forecast_days=1, giving an 8-day window that
/// mixed a forecast day into a figure presented as observed and inflated a
/// weekly total by ~14%. One window, fully observed, so "rainfall this past
/// week" means precisely that to the farmer being judged on it.
///
/// Throws on an unknown district, a non-200 response, or timeout — callers
/// decide whether to surface an error or fall back to manual entry.
Future<FarmWeather> fetchFarmWeather(
  String district, {
  bool withYieldExtras = false,
}) async {
  final coords = kDistrictCoords[district];
  if (coords == null) throw Exception('District coordinates not found');
  final lat = coords[0];
  final lon = coords[1];
  final uri = Uri.parse(
    'https://api.open-meteo.com/v1/forecast'
    '?latitude=$lat&longitude=$lon'
    '&daily=precipitation_sum,temperature_2m_max,temperature_2m_min,'
    'relative_humidity_2m_mean'
    '${withYieldExtras ? ',wind_speed_10m_max,shortwave_radiation_sum' : ''}'
    '&past_days=7&forecast_days=0&timezone=Asia%2FColombo',
  );
  final res = await http.get(uri).timeout(const Duration(seconds: 15));
  if (res.statusCode != 200) {
    throw Exception('Weather API error ${res.statusCode}');
  }
  final json = jsonDecode(res.body) as Map<String, dynamic>;
  return farmWeatherFromJson(json, withYieldExtras: withYieldExtras);
}

/// The Open-Meteo response -> FarmWeather step, split from the HTTP call so
/// the aggregation and the missing-data behaviour can be tested without a
/// network stub.
FarmWeather farmWeatherFromJson(
  Map<String, dynamic> json, {
  bool withYieldExtras = false,
}) {
  final daily = json['daily'] as Map<String, dynamic>?;
  if (daily == null) throw Exception('Weather API returned no daily data');

  /// Throws rather than returning an empty list. An absent or all-null
  /// series used to collapse to 0, and the clamps below turned that into a
  /// plausible-looking FarmWeather (0mm rain, 0°C min, 5°C max, 0%
  /// humidity) that suitability flags were then graded against — wrong
  /// answers with no error surfaced anywhere. A missing series is a failed
  /// fetch, and callers already handle a thrown Exception.
  List<double> series(String key) {
    final vals = (daily[key] as List? ?? const [])
        .whereType<num>()
        .map((e) => e.toDouble())
        .toList();
    if (vals.isEmpty) {
      throw Exception('Weather API returned no $key readings');
    }
    return vals;
  }

  /// Mean over the window — for quantities that ARE daily values
  /// (temperature, relative humidity).
  double avg(String key) {
    final vals = series(key);
    return vals.reduce((a, b) => a + b) / vals.length;
  }

  /// Total over the window — for quantities that ACCUMULATE (rainfall).
  /// Nulls are dropped rather than read as zero: a missing day should shorten
  /// the window, not silently deflate the total.
  double total(String key) => series(key).reduce((a, b) => a + b);

  return FarmWeather(
    // Ceiling raised 300 -> 500 to match the backend's own bound
    // (RecommendRequest.rainfall_mm is ge=0, le=500). 300 was sized for the
    // daily-mean reading, where it was unreachable anyway — 300mm in one day
    // is close to a national record. As a WEEKLY total it is reachable in a
    // monsoon week, so it would have clipped exactly the extremes a farmer
    // most needs advice about.
    rainfallMm: total('precipitation_sum').clamp(0, 500),
    tempMinC: avg('temperature_2m_min').clamp(0, 45),
    tempMaxC: avg('temperature_2m_max').clamp(5, 50),
    humidityPct: avg('relative_humidity_2m_mean').clamp(0, 100),
    // Daily maxima averaged over the window — these two ARE daily values, so
    // a mean is right where rainfall needed a sum. Bounds match the backend
    // (wind_speed_kmh le=100, solar_radiation_mj le=35).
    windSpeedKmh: withYieldExtras
        ? avg('wind_speed_10m_max').clamp(0, 100)
        : null,
    solarRadMj: withYieldExtras
        ? avg('shortwave_radiation_sum').clamp(0, 35)
        : null,
  );
}
