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
int farmWeekOfYear() {
  final now = DateTime.now();
  final soy = DateTime(now.year, 1, 1);
  return (((now.difference(soy).inDays + soy.weekday - 1) / 7).ceil()).clamp(
    1,
    52,
  );
}

/// Sri Lanka's two main cultivation seasons, plus the inter-monsoon gap.
/// Maha runs roughly Oct–Mar (weeks 40–12), Yala roughly Apr–Sep.
String farmCurrentSeason() {
  final w = farmWeekOfYear();
  if (w >= 40 || w <= 12) return 'Maha';
  if (w >= 14 && w <= 39) return 'Yala';
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

/// The four weather fields M5 needs, averaged over the past week.
///
/// Distinct from the dashboard's own `_WeatherData` (current conditions —
/// temp/rain-chance/wind, for the weather card). This one is the weekly
/// aggregate the prediction endpoints are trained against.
class FarmWeather {
  final double rainfallMm;
  final double tempMinC;
  final double tempMaxC;
  final double humidityPct;

  const FarmWeather({
    required this.rainfallMm,
    required this.tempMinC,
    required this.tempMaxC,
    required this.humidityPct,
  });
}

/// Past-7-day weather averages for a district, from Open-Meteo (free, no key).
/// Throws on an unknown district, a non-200 response, or timeout — callers
/// decide whether to surface an error or fall back to manual entry.
Future<FarmWeather> fetchFarmWeather(String district) async {
  final coords = kDistrictCoords[district];
  if (coords == null) throw Exception('District coordinates not found');
  final lat = coords[0];
  final lon = coords[1];
  final uri = Uri.parse(
    'https://api.open-meteo.com/v1/forecast'
    '?latitude=$lat&longitude=$lon'
    '&daily=precipitation_sum,temperature_2m_max,temperature_2m_min,'
    'relative_humidity_2m_max'
    '&past_days=7&forecast_days=1&timezone=Asia%2FColombo',
  );
  final res = await http.get(uri).timeout(const Duration(seconds: 15));
  if (res.statusCode != 200) {
    throw Exception('Weather API error ${res.statusCode}');
  }
  final json = jsonDecode(res.body) as Map<String, dynamic>;
  final daily = json['daily'] as Map<String, dynamic>;
  double avg(String key) {
    final vals = (daily[key] as List)
        .whereType<num>()
        .map((e) => e.toDouble())
        .toList();
    if (vals.isEmpty) return 0;
    return vals.reduce((a, b) => a + b) / vals.length;
  }

  return FarmWeather(
    rainfallMm: avg('precipitation_sum').clamp(0, 300),
    tempMinC: avg('temperature_2m_min').clamp(0, 45),
    tempMaxC: avg('temperature_2m_max').clamp(5, 50),
    humidityPct: avg('relative_humidity_2m_max').clamp(0, 100),
  );
}
