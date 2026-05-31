// lib/screens/yield/yield_screen.dart
// ─────────────────────────────────────────────────────────────────────────────
//  CropSphere — Yield Predictor (v3)
//
//  CHANGES FROM v2
//  ✅ (i)  Soil Management text (summary, phNote, moistureNote, chemical
//          names/purpose/method/timing/caution) now fully translated to
//          Sinhala (si) and Tamil (ta) — no more English bleed-through.
//  ✅ (ii) Area input: replaced slider with three manual TextFields
//          (Perches / Acres / Hectares) — editing any one auto-converts
//          the other two in real time. Slider removed.
//  ✅ (iii) Yield result: green card + ✅ checkmark when ≥ average;
//           red card + ⚠️ Hazard Warning banner when below average.
//  ✅ (iv) "DOA Guidelines" badge removed from Soil & Management header.
//          Explanation of data source added in code comments below.
//  ✅ (v)  "Ask AI for More Info" button shown after prediction result
//          — calls widget.onNavigate(6) to open AI Chat tab, passing
//          a pre-filled context message via a new optional callback.
// ─────────────────────────────────────────────────────────────────────────────
//
//  ABOUT THE SOIL DATA (was "DOA Guidelines"):
//  The soil pH, moisture, NPK indices, fertilizer products, dosages,
//  application methods and pesticide instructions stored in `_kSoilRecs`
//  are hard-coded agronomic recommendations compiled from Sri Lanka's
//  Department of Agriculture (DOA) crop guides and field extension
//  booklets.  They are NOT fetched from an API — they live entirely in
//  this file as Dart constants.  If you want to update them, edit the
//  `_kSoilRecs` map below.  The "DOA Guidelines" badge was just a label
//  to indicate that origin; it has been removed per (iv).
//
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:http/http.dart' as http;
import '../../app_lang.dart';
import '../../models/api_models.dart';
import '../../services/service_factory.dart';
import '../../widgets/app_theme.dart';

// ─────────────────────────────────────────────────────────────────────────────
//  District → GPS coordinates for Open-Meteo
// ─────────────────────────────────────────────────────────────────────────────
const Map<String, List<double>> _districtCoords = {
  'Nuwara Eliya': [6.9497, 80.7891],
  'Badulla': [6.9934, 81.0550],
  'Anuradhapura': [8.3114, 80.4037],
  'Monaragala': [6.8728, 81.3507],
  'Ampara': [7.2985, 81.6724],
  'Hambantota': [6.1241, 81.1185],
  'Batticaloa': [7.7102, 81.6924],
  'Jaffna': [9.6615, 80.0255],
};

// ─────────────────────────────────────────────────────────────────────────────
//  Area unit helpers
//  1 ha = 2.47105 acres  |  1 acre = 160 perches  |  1 ha = 395.3686 perches
// ─────────────────────────────────────────────────────────────────────────────
double _haToPerches(double ha) => ha * 395.3686;
double _haToAcres(double ha) => ha * 2.47105;
double _perchesToHa(double p) => p / 395.3686;
double _acresToHa(double a) => a / 2.47105;

// ─────────────────────────────────────────────────────────────────────────────
//  Weather data model (from Open-Meteo)
// ─────────────────────────────────────────────────────────────────────────────
class _WeatherData {
  final double rainfallMm;
  final double tempMinC;
  final double tempMaxC;
  final double humidityPct;
  final double windSpeedKmh;
  final double solarRadMj;

  const _WeatherData({
    required this.rainfallMm,
    required this.tempMinC,
    required this.tempMaxC,
    required this.humidityPct,
    required this.windSpeedKmh,
    required this.solarRadMj,
  });
}

// ─────────────────────────────────────────────────────────────────────────────
//  Open-Meteo fetch helper
// ─────────────────────────────────────────────────────────────────────────────
Future<_WeatherData> _fetchWeather(String district) async {
  final coords = _districtCoords[district];
  if (coords == null) throw Exception('District coordinates not found');

  final lat = coords[0];
  final lon = coords[1];

  final uri = Uri.parse(
    'https://api.open-meteo.com/v1/forecast'
    '?latitude=$lat&longitude=$lon'
    '&daily=precipitation_sum,temperature_2m_max,temperature_2m_min,'
    'relative_humidity_2m_max,wind_speed_10m_max,shortwave_radiation_sum'
    '&past_days=7&forecast_days=1&timezone=Asia%2FColombo',
  );

  final res = await http.get(uri).timeout(const Duration(seconds: 15));
  if (res.statusCode != 200) {
    throw Exception('Weather API error ${res.statusCode}');
  }

  final json = jsonDecode(res.body) as Map<String, dynamic>;
  final daily = json['daily'] as Map<String, dynamic>;

  double avg(String key) {
    final vals =
        (daily[key] as List).whereType<num>().map((e) => e.toDouble()).toList();
    if (vals.isEmpty) return 0;
    return vals.reduce((a, b) => a + b) / vals.length;
  }

  return _WeatherData(
    rainfallMm: avg('precipitation_sum').clamp(0, 300),
    tempMinC: avg('temperature_2m_min').clamp(0, 45),
    tempMaxC: avg('temperature_2m_max').clamp(5, 50),
    humidityPct: avg('relative_humidity_2m_max').clamp(0, 100),
    windSpeedKmh: avg('wind_speed_10m_max').clamp(0, 100),
    solarRadMj: avg('shortwave_radiation_sum').clamp(0, 35),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
//  Trilingual string helper type
// ─────────────────────────────────────────────────────────────────────────────
typedef _L = Map<String, String>;

// ─────────────────────────────────────────────────────────────────────────────
//  Practical soil & management data — fully trilingual
// ─────────────────────────────────────────────────────────────────────────────
class _SoilRec {
  final double soilPh;
  final double soilMoisturePct;
  final double fertilizerIndex;
  final double pesticideIndex;
  final double nIndex;
  final double pIndex;
  final double kIndex;
  final _L summary;
  final _L phNote;
  final _L moistureNote;
  final List<_ChemicalInstruction> fertilizers;
  final List<_ChemicalInstruction> pesticides;

  const _SoilRec({
    required this.soilPh,
    required this.soilMoisturePct,
    required this.fertilizerIndex,
    required this.pesticideIndex,
    required this.nIndex,
    required this.pIndex,
    required this.kIndex,
    required this.summary,
    required this.phNote,
    required this.moistureNote,
    required this.fertilizers,
    required this.pesticides,
  });
}

class _ChemicalInstruction {
  final String name; // product name — kept in English (scientific)
  final _L purpose;
  final _L dose;
  final _L method;
  final _L timing;
  final _L caution;
  final Color color;
  final IconData icon;

  const _ChemicalInstruction({
    required this.name,
    required this.purpose,
    required this.dose,
    required this.method,
    required this.timing,
    required this.caution,
    required this.color,
    required this.icon,
  });
}

// ─────────────────────────────────────────────────────────────────────────────
//  Per-crop soil & management data — all user-visible strings trilingual
// ─────────────────────────────────────────────────────────────────────────────
const Map<String, _SoilRec> _kSoilRecs = {
  // ── CARROT ────────────────────────────────────────────────────────────────
  'Carrot': _SoilRec(
    soilPh: 6.2,
    soilMoisturePct: 60,
    fertilizerIndex: 0.80,
    pesticideIndex: 0.60,
    nIndex: 0.55,
    pIndex: 0.70,
    kIndex: 0.65,
    summary: {
      'en': 'Carrot needs loose, well-drained sandy loam. '
          'Good phosphorus and moderate nitrogen gives straight, long roots and high yield.',
      'si': 'කැරට් සඳහා ලිහිල්, හොඳ ජල ඌරණ ගති ඇති වැලි-ලෝම් පස අවශ්‍ය. '
          'ප්‍රමාණවත් පොස්පරස් සහ මධ්‍යස්ථ නයිට්‍රජන් සෘජු, දිගු මූල හා ඉහළ අස්වැන්නක් ලබාදේ.',
      'ta': 'கேரட்டிற்கு தளர்வான, நல்ல வடிகால் கொண்ட மணல் மண் தேவை. '
          'நல்ல பாஸ்பரஸும் மிதமான நைட்ரஜனும் நேரான, நீண்ட வேர்களையும் அதிக விளைச்சலையும் தரும்.',
    },
    phNote: {
      'en': 'Keep pH 5.8–6.5 for best root development.',
      'si': 'හොඳ මූල වර්ධනය සඳහා pH 5.8–6.5 ශ්‍රේණියේ තබා ගන්න.',
      'ta': 'சிறந்த வேர் வளர்ச்சிக்கு pH 5.8–6.5 ஆக பராமரிக்கவும்.',
    },
    moistureNote: {
      'en':
          'Keep at 55–65% — too wet causes root rot, too dry causes cracking.',
      'si':
          '55–65% ආර්ද්‍රතාව පවත්වන්න — වැඩිපුර තෙත් වීම මූල කුණු වීමට, වැඩිපුර වියළීම බිඳ දැමීමට හේතු වේ.',
      'ta':
          '55–65% ஈரப்பதம் பராமரிக்கவும் — அதிக ஈரம் வேர் அழுகலையும், அதிக வறட்சி விரிசலையும் ஏற்படுத்தும்.',
    },
    fertilizers: [
      _ChemicalInstruction(
        name: 'TSP (Triple Super Phosphate)',
        purpose: {
          'en': 'Root elongation & early growth',
          'si': 'මූල දිගු වීම හා මුල් වර්ධනය',
          'ta': 'வேர் நீட்சி மற்றும் ஆரம்ப வளர்ச்சி',
        },
        dose: {
          'en': '100 g per 10 m² soil area',
          'si': '10 m² පස් ප්‍රදේශයට ග්‍රෑ. 100',
          'ta': '10 m² மண் பரப்பிற்கு 100 கி',
        },
        method: {
          'en':
              'Mix dry into top 10 cm of soil before planting. Do NOT dissolve in water — TSP works better dry.',
          'si':
              'රෝපණයට පෙර පස් ස්ථරයේ ඉහළ සෙ.මී. 10 ට වියළිව මිශ්‍ර කරන්න. ජලයේ දිය නොකරන්න — TSP වියළිව ක්‍රියා කරයි.',
          'ta':
              'நடவு செய்வதற்கு முன் மண்ணின் மேல் 10 செமீ-ல் உலர்வாக கலக்கவும். தண்ணீரில் கரைக்காதீர்கள் — TSP உலர்வாக சிறப்பாக செயல்படும்.',
        },
        timing: {
          'en': 'Apply at land preparation, 1 week before planting.',
          'si': 'ඉඩම් සකස් කිරීමේදී, රෝපණයට සති 1 කට පෙර යොදන්න.',
          'ta':
              'நிலம் தயார் செய்யும்போது, நடவுக்கு 1 வாரம் முன்பு பயன்படுத்தவும்.',
        },
        caution: {
          'en': 'Wear gloves. Avoid direct skin contact. Store in a dry place.',
          'si':
              'අත් වැසුම් පළඳින්න. සමට කෙලින් ස්පර්ශ නොකරන්න. වියළි ස්ථානයක ගබඩා කරන්න.',
          'ta':
              'கையுறை அணியுங்கள். தோலில் நேரடியாக படாமல் தவிர்க்கவும். உலர் இடத்தில் சேமிக்கவும்.',
        },
        color: Color(0xFFE65100),
        icon: Icons.grass,
      ),
      _ChemicalInstruction(
        name: 'Urea (Nitrogen)',
        purpose: {
          'en': 'Leaf growth & plant establishment',
          'si': 'කොළ වර්ධනය හා ශාක ස්ථාපනය',
          'ta': 'இலை வளர்ச்சி மற்றும் செடி நிலைபேறு',
        },
        dose: {
          'en': '30 g dissolved in 10 L water — apply to 10 m²',
          'si': 'ජල ලිටර් 10 ක ග්‍රෑ. 30 දිය කර 10 m² ට යොදන්න',
          'ta': '10 லி தண்ணீரில் 30 கி கரைத்து 10 m²-க்கு பயன்படுத்தவும்',
        },
        method: {
          'en':
              'Dissolve fully in water. Apply as a drench at the base of plants, not on leaves.',
          'si':
              'ජලයේ සම්පූර්ණයෙන් දිය කරන්න. ශාකයේ පාමූලේ ද්‍රාවණය ලෙස යොදන්න, කොළ මත නොදමන්න.',
          'ta':
              'தண்ணீரில் முழுமையாக கரைக்கவும். செடியின் அடியில் நீர் ஊற்றும் முறையில் பயன்படுத்தவும், இலைகளில் தெளிக்காதீர்கள்.',
        },
        timing: {
          'en': 'Apply 3 weeks after planting. Do NOT apply during flowering.',
          'si': 'රෝපණයෙන් සති 3 කට පසු යොදන්න. මල් පිපීමේ කාලයේ නොයොදන්න.',
          'ta':
              'நடவுக்கு 3 வாரங்கள் பிறகு பயன்படுத்தவும். பூக்கும் காலத்தில் பயன்படுத்தாதீர்கள்.',
        },
        caution: {
          'en':
              'Excess urea causes forked, hairy roots in carrot. Use sparingly.',
          'si':
              'අතිරික්ත යූරියා කැරට්හි ශාඛා ශාඛා, රූකඩ මූල ඇති කරයි. ප්‍රවේශමෙන් යොදන්න.',
          'ta':
              'அதிக யூரியா கேரட்டில் கிளைத்த, மயிரான வேர்களை ஏற்படுத்தும். குறைவாக பயன்படுத்தவும்.',
        },
        color: Color(0xFF2E7D32),
        icon: Icons.water_drop,
      ),
      _ChemicalInstruction(
        name: 'MOP (Muriate of Potash)',
        purpose: {
          'en': 'Root quality & sweetness',
          'si': 'මූල ගුණාත්මකභාවය හා මිහිරිකම',
          'ta': 'வேர் தரம் மற்றும் இனிப்பு',
        },
        dose: {
          'en': '75 g dissolved in 10 L water — apply to 10 m²',
          'si': 'ජල ලිටර් 10 ක ග්‍රෑ. 75 දිය කර 10 m² ට යොදන්න',
          'ta': '10 லி தண்ணீரில் 75 கி கரைத்து 10 m²-க்கு பயன்படுத்தவும்',
        },
        method: {
          'en': 'Dissolve in water and pour evenly at plant base.',
          'si': 'ජලයේ දිය කර ශාකයේ පාමූලේ සම්ව වත් කරන්න.',
          'ta': 'தண்ணீரில் கரைத்து செடியின் அடியில் சீராக ஊற்றவும்.',
        },
        timing: {
          'en': 'Apply 6 weeks after planting (before roots thicken).',
          'si': 'රෝපණයෙන් සති 6 කට පසු (මූල ඝණ වීමට පෙර) යොදන්න.',
          'ta':
              'நடவுக்கு 6 வாரங்கள் பிறகு (வேர்கள் தடிக்கும் முன்) பயன்படுத்தவும்.',
        },
        caution: {
          'en': 'Do not over-apply — excess potassium causes bitter roots.',
          'si': 'අධිකව නොයොදන්න — අතිරික්ත පොටෑසියම් මූල කටුක කරයි.',
          'ta':
              'அதிகமாக பயன்படுத்தாதீர்கள் — அதிக பொட்டாசியம் வேர்களை கசப்பாக மாற்றும்.',
        },
        color: Color(0xFF7B1FA2),
        icon: Icons.science,
      ),
    ],
    pesticides: [
      _ChemicalInstruction(
        name: 'Chlorpyrifos 20 EC',
        purpose: {
          'en': 'Soil insects & root flies',
          'si': 'පස් කෘමීන් හා මූල මැස්සන්',
          'ta': 'மண் பூச்சிகள் மற்றும் வேர் ஈக்கள்',
        },
        dose: {
          'en': '2 ml per 1 L water',
          'si': 'ජල ලිටර් 1 ට මිලි ලිටර් 2',
          'ta': '1 லி தண்ணீருக்கு 2 மிலி',
        },
        method: {
          'en':
              'Mix well. Spray on soil surface and water in lightly. Do NOT spray on leaves.',
          'si':
              'හොඳින් මිශ්‍ර කරන්න. පස් මතුපිට ස්ප්‍රේ කර සැහැල්ලුවෙන් ජලය දමන්න. කොළ මත ස්ප්‍රේ නොකරන්න.',
          'ta':
              'நன்றாக கலக்கவும். மண் மேற்பரப்பில் தெளித்து லேசாக நீர் பாய்ச்சவும். இலைகளில் தெளிக்காதீர்கள்.',
        },
        timing: {
          'en': 'Apply at land preparation before planting.',
          'si': 'රෝපණයට පෙර ඉඩම් සකස් කිරීමේදී යොදන්න.',
          'ta': 'நடவுக்கு முன் நிலம் தயார் செய்யும்போது பயன்படுத்தவும்.',
        },
        caution: {
          'en':
              'Wear gloves, mask and boots. Do not spray on windy days. Safe harvest gap: 14 days.',
          'si':
              'අත් වැසුම්, වෙස් ආවරණ හා බූට් පළඳින්න. සුළං දිනවල ස්ප්‍රේ නොකරන්න. අස්වනු නෙලීමේ ආරක්ෂිත ගැළපීම: දින 14.',
          'ta':
              'கையுறை, முககவசம், காலணி அணியுங்கள். காற்றுள்ள நாட்களில் தெளிக்காதீர்கள். அறுவடை இடைவெளி: 14 நாட்கள்.',
        },
        color: Color(0xFFC62828),
        icon: Icons.bug_report,
      ),
      _ChemicalInstruction(
        name: 'Mancozeb 80 WP (Fungicide)',
        purpose: {
          'en': 'Leaf blight & early fungal disease',
          'si': 'කොළ විනාශය හා මුල් දිලීර රෝග',
          'ta': 'இலை அழுகல் மற்றும் ஆரம்ப பூஞ்சை நோய்',
        },
        dose: {
          'en': '2.5 g per 1 L water',
          'si': 'ජල ලිටර් 1 ට ග්‍රෑ. 2.5',
          'ta': '1 லி தண்ணீருக்கு 2.5 கி',
        },
        method: {
          'en':
              'Mix powder fully in water. Spray on leaves (top and bottom surfaces) until dripping.',
          'si':
              'කුඩු ජලයේ සම්පූර්ණයෙන් මිශ්‍ර කරන්න. කොළ (ඉහළ සහ යට) තෙත් වන තෙක් ස්ප්‍රේ කරන්න.',
          'ta':
              'தூளை தண்ணீரில் முழுமையாக கலக்கவும். இலைகளில் (மேலும் கீழும்) ஒழுகும் வரை தெளிக்கவும்.',
        },
        timing: {
          'en':
              'Apply preventively every 10–14 days during wet or humid weather.',
          'si':
              'තෙත් හෝ ආර්ද්‍ර කාලගුණයේ දී දින 10–14 ට වරක් වැළැක්වීමේ ස්ප්‍රේ කරන්න.',
          'ta':
              'ஈரமான அல்லது ஈரப்பதமான வானிலையில் 10–14 நாட்களுக்கு ஒருமுறை தடுப்பு நடவடிக்கையாக தெளிக்கவும்.',
        },
        caution: {
          'en':
              'Wear mask. Do not spray in rain or strong wind. Harvest gap: 7 days.',
          'si':
              'முககவசம் அணியுங்கள். மழையில் அல்லது அதிக காற்றில் தெளிக்காதீர்கள். அறுவடை இடைவெளி: 7 நாட்கள்.',
          'ta':
              'முககவசம் அணியுங்கள். மழையில் அல்லது அதிக காற்றில் தெளிக்காதீர்கள். அறுவடை இடைவெளி: 7 நாட்கள்.',
        },
        color: Color(0xFF7B1FA2),
        icon: Icons.spa,
      ),
    ],
  ),

  // ── MAIZE ─────────────────────────────────────────────────────────────────
  'Maize': _SoilRec(
    soilPh: 6.5,
    soilMoisturePct: 65,
    fertilizerIndex: 0.85,
    pesticideIndex: 0.55,
    nIndex: 0.80,
    pIndex: 0.60,
    kIndex: 0.70,
    summary: {
      'en': 'Maize is a high-input crop that responds strongly to nitrogen. '
          'Well-drained fertile loam with high N and good potassium gives the best grain yields.',
      'si': 'බඩිරිඳු ඉහළ ආදාන අවශ්‍ය භෝගයකි; නයිට්‍රජන් සඳහා ප්‍රබල ප්‍රතිචාර දක්වයි. '
          'ඉහළ N සහ හොඳ පොටෑසියම් සහිත ජල ඌරණ සරු ලෝම් පස හොඳම ධාන්‍ය අස්වැන්නක් ලබාදේ.',
      'ta': 'மக்காச்சோளம் அதிக உள்ளீடு தேவைப்படும் பயிர்; நைட்ரஜனுக்கு வலுவாக பதிலளிக்கும். '
          'அதிக N மற்றும் நல்ல பொட்டாசியம் கொண்ட வடிகால் வளமான மண் சிறந்த தானிய விளைச்சலை தரும்.',
    },
    phNote: {
      'en': 'Near-neutral soil pH 6.0–7.0 maximises nutrient uptake.',
      'si': 'pH 6.0–7.0 ශ්‍රේණිය පෝෂ්‍ය ද්‍රව්‍ය අවශෝෂණය උපරිම කරයි.',
      'ta': 'pH 6.0–7.0 ஆனது ஊட்டச்சத்து உறிஞ்சுதலை அதிகரிக்கும்.',
    },
    moistureNote: {
      'en': 'Consistent moisture is critical during tasselling and grain fill.',
      'si':
          'ටැසල් ඇතිවීමේ හා ධාන්‍ය පිරවීමේ කාලයේ ස්ථිර ආර්ද්‍රතාව අත්‍යාවශ්‍ය.',
      'ta': 'தூரல் மற்றும் தானிய நிரப்பல் காலத்தில் நிலையான ஈரப்பதம் அவசியம்.',
    },
    fertilizers: [
      _ChemicalInstruction(
        name: 'Urea (Nitrogen) — Split Application',
        purpose: {
          'en': 'Vegetative growth & grain fill',
          'si': 'ශාකගත වර්ධනය හා ධාන්‍ය පිරවීම',
          'ta': 'தாவர வளர்ச்சி மற்றும் தானிய நிரப்பல்',
        },
        dose: {
          'en':
              '1st dose: 50 g per plant row meter. 2nd dose: 50 g per plant row meter.',
          'si':
              '1 වන මාත්‍රාව: ශාක පේළි මීටරයට ග්‍රෑ. 50. 2 වන මාත්‍රාව: ශාක පේළි මීටරයට ග්‍රෑ. 50.',
          'ta':
              '1வது அளவு: செடி வரிசை மீட்டருக்கு 50 கி. 2வது அளவு: செடி வரிசை மீட்டருக்கு 50 கி.',
        },
        method: {
          'en':
              'Apply dry at base of plants. Cover lightly with soil after application.',
          'si':
              'ශාකයේ පාමූලේ වියළිව යොදන්න. යෙදීමෙන් පසු සැහැල්ලුවෙන් පසින් ආවරණය කරන්න.',
          'ta':
              'செடியின் அடியில் உலர்வாக பயன்படுத்தவும். பயன்படுத்திய பிறகு லேசாக மண்ணால் மூடவும்.',
        },
        timing: {
          'en':
              '1st dose at planting. 2nd dose at 30 days after germination (knee-high stage).',
          'si':
              '1 වන මාත්‍රාව රෝපණ කාලයේ. 2 වන මාත්‍රාව පැළ වීමෙන් දින 30 ට (හිකිලි උස් ස්ථරය).',
          'ta':
              '1வது அளவு நடவு நேரம். 2வது அளவு முளைத்த 30 நாட்களில் (முழங்கால் உயர நிலை).',
        },
        caution: {
          'en':
              'Split application doubles efficiency. Never apply all at once — burns roots.',
          'si':
              'හරස් යෙදීම කාර්යක්ෂමතාව දෙගුණ කරයි. එකවර සියල්ල නොයොදන්න — මූල දහනය කරයි.',
          'ta':
              'பிரித்து பயன்படுத்துவது திறனை இரட்டிப்பாக்கும். ஒரே நேரத்தில் அனைத்தையும் பயன்படுத்தாதீர்கள் — வேர்களை எரிக்கும்.',
        },
        color: Color(0xFF2E7D32),
        icon: Icons.grass,
      ),
      _ChemicalInstruction(
        name: 'TSP (Phosphorus)',
        purpose: {
          'en': 'Root development & early establishment',
          'si': 'මූල වර්ධනය හා මුල් ස්ථාපනය',
          'ta': 'வேர் வளர்ச்சி மற்றும் ஆரம்ப நிலைபேறு',
        },
        dose: {
          'en': '80 g dry per plant row meter',
          'si': 'ශාක පේළි මීටරයට ග්‍රෑ. 80 වියළි',
          'ta': 'செடி வரிசை மீட்டருக்கு 80 கி உலர்',
        },
        method: {
          'en': 'Mix into furrow at planting time before covering seeds.',
          'si':
              'රෝපණ කාලයේ ගෙවල් ස්ථරයේ ඇළෙහි ඇට ආවරණය කිරීමට පෙර මිශ්‍ර කරන්න.',
          'ta': 'விதைகளை மூடுவதற்கு முன் நடவு நேரத்தில் வரப்பில் கலக்கவும்.',
        },
        timing: {
          'en': 'Apply at planting only — basal dose.',
          'si': 'රෝපණ කාලයේ පමණක් — පාදම් මාත්‍රාව.',
          'ta': 'நடவு நேரத்தில் மட்டும் — அடி உரமாக.',
        },
        caution: {
          'en':
              'Store away from moisture. Dry granules only — do not dissolve.',
          'si':
              'ආර්ද්‍රතාවෙන් ඈත ගබඩා කරන්න. වියළි ඇට ස්වරූපයෙන් පමණි — දිය නොකරන්න.',
          'ta':
              'ஈரத்திலிருந்து விலகி சேமிக்கவும். உலர் துகள்கள் மட்டும் — கரைக்காதீர்கள்.',
        },
        color: Color(0xFFE65100),
        icon: Icons.grass,
      ),
      _ChemicalInstruction(
        name: 'MOP (Potassium)',
        purpose: {
          'en': 'Stalk strength & grain fill',
          'si': 'කඳු ශක්තිය හා ධාන්‍ය පිරවීම',
          'ta': 'தண்டு வலிமை மற்றும் தானிய நிரப்பல்',
        },
        dose: {
          'en': '60 g dissolved in 10 L water per 5 m row',
          'si': 'ජල ලිටර් 10 ක ග්‍රෑ. 60 දිය කර 5  මීටර් පේළියකට',
          'ta': '10 லி தண்ணீரில் 60 கி கரைத்து 5 மீ வரிசைக்கு',
        },
        method: {
          'en': 'Dissolve in water. Pour evenly along plant row at base.',
          'si': 'ජලයේ දිය කරන්න. ශාක පේළිය දිගේ පාමූලේ සම්ව වත් කරන්න.',
          'ta':
              'தண்ணீரில் கரைக்கவும். செடி வரிசையில் அடிவாரத்தில் சீராக ஊற்றவும்.',
        },
        timing: {
          'en': 'Apply at 45 days after planting.',
          'si': 'රෝපණයෙන් දින 45 ට පසු යොදන්න.',
          'ta': 'நடவுக்கு 45 நாட்கள் பிறகு பயன்படுத்தவும்.',
        },
        caution: {
          'en': 'Avoid leaf contact — may cause minor leaf burn.',
          'si': 'කොළ ස්පර්ශය වළකින්න — සාමාන්‍ය කොළ දහනය සිදු විය හැකිය.',
          'ta': 'இலை தொடர்பு தவிர்க்கவும் — சிறிய இலை எரிவு ஏற்படலாம்.',
        },
        color: Color(0xFF7B1FA2),
        icon: Icons.science,
      ),
    ],
    pesticides: [
      _ChemicalInstruction(
        name: 'Lambda-cyhalothrin 5 EC',
        purpose: {
          'en': 'Stem borers & leaf armyworm',
          'si': 'කඳ සිදුරු කරන්නන් හා කොළ කිණිත්තා',
          'ta': 'தண்டு துளைப்பான்கள் மற்றும் இலை படைப்புழு',
        },
        dose: {
          'en': '1 ml per 1 L water',
          'si': 'ජල ලිටර් 1 ට මිලි ලිටර් 1',
          'ta': '1 லி தண்ணீருக்கு 1 மிலி',
        },
        method: {
          'en':
              'Mix well. Spray on leaves focusing on inner whorl where borers hide.',
          'si':
              'හොඳින් මිශ්‍ර කරන්න. සිදුරු කරන්නන් සඟවා ගන්නා ඇතුළු වෙළ මතට කොළ ස්ප්‍රේ කරන්න.',
          'ta':
              'நன்றாக கலக்கவும். துளைப்பான்கள் மறையும் உள் சுழலில் கவனம் செலுத்தி இலைகளில் தெளிக்கவும்.',
        },
        timing: {
          'en': 'Apply at first sign of damage. Repeat after 7 days if needed.',
          'si':
              'හානිය ප්‍රථම දකින විට යොදන්න. අවශ්‍ය නම් දින 7 ට පසු නැවත කරන්න.',
          'ta':
              'சேதத்தின் முதல் அறிகுறியில் பயன்படுத்தவும். தேவைப்பட்டால் 7 நாட்கள் பிறகு மீண்டும் செய்யவும்.',
        },
        caution: {
          'en':
              'Highly toxic to bees — spray in evening only. Wear full protective gear. Harvest gap: 21 days.',
          'si':
              'මී මැස්සන්ට ඉතා විෂකාරකය — සවස් කාලයේ පමණක් ස්ප්‍රේ කරන්න. සම්පූර්ණ ආරක්ෂිත ගේන් පළඳින්න. අස්වනු ගැළපීම: දින 21.',
          'ta':
              'தேனீக்களுக்கு மிகவும் நச்சு — மாலையில் மட்டும் தெளிக்கவும். முழு பாதுகாப்பு உடை அணியுங்கள். அறுவடை இடைவெளி: 21 நாட்கள்.',
        },
        color: Color(0xFFC62828),
        icon: Icons.bug_report,
      ),
      _ChemicalInstruction(
        name: 'Atrazine 50 WP (Herbicide)',
        purpose: {
          'en': 'Weed control',
          'si': 'වල් පළිබෝධ පාලනය',
          'ta': 'களை கட்டுப்பாடு',
        },
        dose: {
          'en': '3 g per 1 L water',
          'si': 'ජල ලිටර් 1 ට ග්‍රෑ. 3',
          'ta': '1 லி தண்ணீருக்கு 3 கி',
        },
        method: {
          'en':
              'Spray on moist soil surface before weeds emerge. Do not spray on maize plants.',
          'si':
              'වල් ඇතිවීමට පෙර තෙත් පස් මතුපිට ස්ප්‍රේ කරන්න. බඩිරිඳු ශාක මත ස්ප්‍රේ නොකරන්න.',
          'ta':
              'களைகள் முளைப்பதற்கு முன் ஈரமான மண் மேற்பரப்பில் தெளிக்கவும். மக்காச்சோள செடிகளில் தெளிக்காதீர்கள்.',
        },
        timing: {
          'en': 'Apply within 3 days after planting, before weed emergence.',
          'si': 'රෝපණයෙන් දින 3 ක් ඇතුළත, වල් ඇති වීමට පෙර යොදන්න.',
          'ta':
              'நடவுக்கு 3 நாட்களுக்குள், களை முளைப்பதற்கு முன் பயன்படுத்தவும்.',
        },
        caution: {
          'en':
              'Do not apply near water sources. Wear mask and gloves. Harvest gap: 45 days.',
          'si':
              'ජල ප්‍රභවයන් අසල නොයොදන්න. මාස්ක් හා අත් වැසුම් පළඳින්න. අස්වනු ගැළපීම: දින 45.',
          'ta':
              'நீர் ஆதாரங்களுக்கு அருகில் பயன்படுத்தாதீர்கள். மாஸ்க் மற்றும் கையுறை அணியுங்கள். அறுவடை இடைவெளி: 45 நாட்கள்.',
        },
        color: Color(0xFF1565C0),
        icon: Icons.eco,
      ),
    ],
  ),

  // ── GREEN GRAM ────────────────────────────────────────────────────────────
  'Green gram': _SoilRec(
    soilPh: 6.8,
    soilMoisturePct: 50,
    fertilizerIndex: 0.40,
    pesticideIndex: 0.45,
    nIndex: 0.25,
    pIndex: 0.55,
    kIndex: 0.50,
    summary: {
      'en': 'Green gram is a low-input legume that fixes its own nitrogen. '
          'Minimal fertiliser, well-drained soil and moderate moisture give reliable yields.',
      'si': 'මුං ඇට තමාගේ නයිට්‍රජන් ඇති කරන අඩු ආදාන රනිල ශාකයකි. '
          'අවම පොහොර, හොඳ ජල ඌරණ පස හා මධ්‍යස්ථ ආර්ද්‍රතාව විශ්වාසදායක අස්වැන්නක් ලබාදේ.',
      'ta': 'பச்சைப்பயிறு தனது நைட்ரஜனை தானே நிலைநிறுத்திக் கொள்ளும் குறைந்த உள்ளீடு தேவைப்படும் பயறு வகை. '
          'குறைந்த உரம், நல்ல வடிகால் மண் மற்றும் மிதமான ஈரப்பதம் நம்பகமான விளைச்சலை தரும்.',
    },
    phNote: {
      'en':
          'Near-neutral pH 6.0–7.5 maximises nitrogen fixation by root bacteria.',
      'si':
          'pH 6.0–7.5 ශ්‍රේණිය මූල බැක්ටීරියා මගින් නයිට්‍රජන් ස්ථාවරීකරණය උපරිම කරයි.',
      'ta':
          'pH 6.0–7.5 வேர் பாக்டீரியாவால் நைட்ரஜன் நிலைநிறுத்தலை அதிகரிக்கும்.',
    },
    moistureNote: {
      'en':
          'Drought tolerant — excess moisture causes waterlogging and pod shedding.',
      'si':
          'නියං ඔරොත්තු දෙයි — අතිරික්ත ආර්ද්‍රතාව ජල ගැලීම හා කරල් හැලීමට හේතු වේ.',
      'ta':
          'வறட்சி தாங்கும் — அதிக ஈரம் நீர் தேக்கம் மற்றும் காய் உதிர்வை ஏற்படுத்தும்.',
    },
    fertilizers: [
      _ChemicalInstruction(
        name: 'TSP (Starter Phosphorus)',
        purpose: {
          'en': 'Root nodule development & pod set',
          'si': 'මූල ගැටිති වර්ධනය හා කරල් ඇති වීම',
          'ta': 'வேர் கணிகை வளர்ச்சி மற்றும் காய் உருவாக்கம்',
        },
        dose: {
          'en': '40 g dry per 10 m² soil',
          'si': '10 m² පසට ග්‍රෑ. 40 වියළි',
          'ta': '10 m² மண்ணுக்கு 40 கி உலர்',
        },
        method: {
          'en':
              'Mix into soil at planting — basal dose only. Green gram fixes its own nitrogen so no urea needed.',
          'si':
              'රෝපණ කාලයේ පසේ මිශ්‍ර කරන්න — පාදම් මාත්‍රාව පමණි. මුං ඇට ස්වදේශීය නයිට්‍රජන් ඇති කරයි, යූරියා අවශ්‍ය නැත.',
          'ta':
              'நடவு நேரத்தில் மண்ணில் கலக்கவும் — அடி உரம் மட்டும். பச்சைப்பயிறு தனது நைட்ரஜனை நிலைநிறுத்துவதால் யூரியா தேவையில்லை.',
        },
        timing: {
          'en': 'Apply at land preparation, before planting.',
          'si': 'ඉඩම් සකස් කිරීමේදී, රෝපණයට පෙර යොදන්න.',
          'ta': 'நிலம் தயார் செய்யும்போது, நடவுக்கு முன் பயன்படுத்தவும்.',
        },
        caution: {
          'en':
              'Do not over-fertilise — excess nutrients inhibit natural N-fixation by root bacteria.',
          'si':
              'අධිකව පොහොර නොදමන්න — අතිරික්ත පෝෂ්‍ය ද්‍රව්‍ය මූල බැක්ටීරියාගේ ස්වාභාවික N ස්ථාවරීකරණය අවහිර කරයි.',
          'ta':
              'அதிகமாக உரமிடாதீர்கள் — அதிக ஊட்டச்சத்து வேர் பாக்டீரியாவின் இயற்கை N-நிலைநிறுத்தலை தடுக்கும்.',
        },
        color: Color(0xFFE65100),
        icon: Icons.grass,
      ),
      _ChemicalInstruction(
        name: 'MOP (Potassium)',
        purpose: {
          'en': 'Pod fill & seed quality',
          'si': 'කරල් පිරවීම හා බීජ ගුණාත්මකභාවය',
          'ta': 'காய் நிரப்பல் மற்றும் விதை தரம்',
        },
        dose: {
          'en': '20 g dissolved in 10 L water per 10 m²',
          'si': 'ජල ලිටර් 10 ක ග්‍රෑ. 20 දිය කර 10 m² ට',
          'ta': '10 லி தண்ணீரில் 20 கி கரைத்து 10 m²-க்கு',
        },
        method: {
          'en': 'Dissolve fully. Apply as drench at plant base.',
          'si': 'සම්පූර්ණයෙන් දිය කරන්න. ශාකයේ පාමූලේ ද්‍රාවණය ලෙස යොදන්න.',
          'ta':
              'முழுமையாக கரைக்கவும். செடியின் அடியில் நீர் ஊற்றும் முறையில் பயன்படுத்தவும்.',
        },
        timing: {
          'en': 'Apply at flowering stage (35–40 days after planting).',
          'si': 'මල් පිපෙන අවස්ථාවේ (රෝපණයෙන් දින 35–40) යොදන්න.',
          'ta':
              'பூக்கும் நிலையில் (நடவுக்கு 35–40 நாட்கள் பிறகு) பயன்படுத்தவும்.',
        },
        caution: {
          'en':
              'Green gram needs very low potassium — do not exceed the recommended dose.',
          'si':
              'මුං ඇට ඉතා අඩු පොටෑසියම් අවශ්‍ය කරයි — නිර්දේශිත මාත්‍රාව ඉක්මවන්න එපා.',
          'ta':
              'பச்சைப்பயிருக்கு மிகக் குறைந்த பொட்டாசியம் தேவை — பரிந்துரைக்கப்பட்ட அளவை தாண்டாதீர்கள்.',
        },
        color: Color(0xFF7B1FA2),
        icon: Icons.science,
      ),
    ],
    pesticides: [
      _ChemicalInstruction(
        name: 'Imidacloprid 70 WS',
        purpose: {
          'en': 'Aphids & whitefly',
          'si': 'ඇෆිඩ් හා සුදු මැස්සන්',
          'ta': 'அசுவினிகள் மற்றும் வெள்ளை ஈக்கள்',
        },
        dose: {
          'en': '0.5 ml per 1 L water',
          'si': 'ජල ලිටර් 1 ට මිලි ලිටර් 0.5',
          'ta': '1 லி தண்ணீருக்கு 0.5 மிலி',
        },
        method: {
          'en': 'Mix and spray on leaf undersides where aphids cluster.',
          'si': 'මිශ්‍ර කර ඇෆිඩ් රොද බෙදෙන කොළ යට ස්ප්‍රේ කරන්න.',
          'ta':
              'கலந்து அசுவினிகள் திரளும் இலைகளின் கீழ் பகுதியில் தெளிக்கவும்.',
        },
        timing: {
          'en':
              'Apply at first sign of infestation. Repeat after 10 days if needed.',
          'si':
              'ආක්‍රමණයේ ප්‍රථම ලකුණ දකින විට යොදන්න. අවශ්‍ය නම් දින 10 ට පසු නැවත කරන්න.',
          'ta':
              'தொற்றின் முதல் அறிகுறியில் பயன்படுத்தவும். தேவைப்பட்டால் 10 நாட்கள் பிறகு மீண்டும் செய்யவும்.',
        },
        caution: {
          'en':
              'Do not spray during flowering — harmful to bees. Harvest gap: 14 days.',
          'si':
              'මල් පිපෙන කාලයේ ස්ප්‍රේ නොකරන්න — මී මැස්සන්ට හානිකරයි. අස්වනු ගැළපීම: දින 14.',
          'ta':
              'பூக்கும் காலத்தில் தெளிக்காதீர்கள் — தேனீக்களுக்கு தீங்கு. அறுவடை இடைவெளி: 14 நாட்கள்.',
        },
        color: Color(0xFFC62828),
        icon: Icons.bug_report,
      ),
      _ChemicalInstruction(
        name: 'Carbendazim 50 WP (Fungicide)',
        purpose: {
          'en': 'Powdery mildew & pod blight',
          'si': 'කුඩු ශ්ලේෂ්මල හා කරල් දිලීර රෝගය',
          'ta': 'தூள் பூஞ்சை மற்றும் காய் கருகல் நோய்',
        },
        dose: {
          'en': '1 g per 1 L water',
          'si': 'ජල ලිටර් 1 ට ග්‍රෑ. 1',
          'ta': '1 லி தண்ணீருக்கு 1 கி',
        },
        method: {
          'en':
              'Dissolve powder in small amount of water first, then top up. Spray all leaf surfaces.',
          'si':
              'කුඩු පළමුව ජල ස්වල්පයක දිය කරන්න, ඉන්පසු එකතු කරන්න. කොළ සියලු මතුපිටට ස්ප්‍රේ කරන්න.',
          'ta':
              'முதலில் சிறிய அளவு தண்ணீரில் தூளை கரைக்கவும், பின் நிரப்பவும். அனைத்து இலை மேற்பரப்புகளிலும் தெளிக்கவும்.',
        },
        timing: {
          'en':
              'Apply at pod formation stage. Repeat after 14 days in humid weather.',
          'si':
              'කරල් ඇති වීමේ අවස්ථාවේ යොදන්න. ආර්ද්‍ර කාලගුණයේ දී දින 14 ට පසු නැවත කරන්න.',
          'ta':
              'காய் உருவாகும் நிலையில் பயன்படுத்தவும். ஈரப்பதமான வானிலையில் 14 நாட்கள் பிறகு மீண்டும் செய்யவும்.',
        },
        caution: {
          'en': 'Wear mask. Harvest gap: 7 days.',
          'si': 'මාස්ක් පළඳින්න. අස்வனු ගැළපීම: දින 7.',
          'ta': 'முககவசம் அணியுங்கள். அறுவடை இடைவெளி: 7 நாட்கள்.',
        },
        color: Color(0xFF7B1FA2),
        icon: Icons.spa,
      ),
    ],
  ),

  // ── COWPEA ────────────────────────────────────────────────────────────────
  'Cowpea': _SoilRec(
    soilPh: 6.5,
    soilMoisturePct: 50,
    fertilizerIndex: 0.35,
    pesticideIndex: 0.40,
    nIndex: 0.20,
    pIndex: 0.50,
    kIndex: 0.45,
    summary: {
      'en': 'Cowpea is one of the most drought-tolerant crops in Sri Lanka. '
          'It needs very little fertiliser and thrives in sandy or loamy soils with good drainage.',
      'si': 'කව්පී ශ්‍රී ලංකාවේ නියං ඔරොත්තු දෙන ම භෝගවලින් එකකි. '
          'ඉතා අඩු පොහොර අවශ්‍ය කරන අතර, හොඳ ජල ඌරණ ඇති වැලි හෝ ලෝම් පස්වල හොඳින් වැඩෙයි.',
      'ta': 'அவரை இலங்கையில் மிகவும் வறட்சி தாங்கும் பயிர்களில் ஒன்று. '
          'மிகக் குறைந்த உரம் தேவை; நல்ல வடிகால் கொண்ட மணல் அல்லது கலவை மண்ணில் நன்றாக வளரும்.',
    },
    phNote: {
      'en':
          'Tolerates pH 5.5–7.0 well. Performs across a wide range of soil types.',
      'si':
          'pH 5.5–7.0 ශ්‍රේණිය ඔරොත්තු දෙයි. පස් වර්ග පුළුල් පරාසයක ක්‍රියා කරයි.',
      'ta': 'pH 5.5–7.0 நன்றாக தாங்கும். பரந்த மண் வகைகளில் செயல்படும்.',
    },
    moistureNote: {
      'en':
          'Very drought tolerant once established — avoid waterlogging at all stages.',
      'si':
          'ස්ථාපනය වූ පසු ඉතා නියං ඔරොත්තු දෙයි — සෑම අවස්ථාවකම ජල ගැලීම වළකින්න.',
      'ta':
          'நிலைபெற்ற பிறகு மிகவும் வறட்சி தாங்கும் — அனைத்து நிலைகளிலும் நீர் தேக்கம் தவிர்க்கவும்.',
    },
    fertilizers: [
      _ChemicalInstruction(
        name: 'TSP (Starter Phosphorus)',
        purpose: {
          'en': 'Root nodule formation',
          'si': 'මූල ගැටිති සෑදීම',
          'ta': 'வேர் கணிகை உருவாக்கம்',
        },
        dose: {
          'en': '30 g dry per 10 m² soil',
          'si': '10 m² පසට ග්‍රෑ. 30 වියළි',
          'ta': '10 m² மண்ணுக்கு 30 கி உலர்',
        },
        method: {
          'en':
              'Mix into topsoil before planting. No urea needed — cowpea fixes its own nitrogen.',
          'si':
              'රෝපණයට පෙර ඉහළ පස් ස්ථරය සමඟ මිශ්‍ර කරන්න. යූරියා අවශ්‍ය නැත — කව්පී ස්වදේශීය නයිට්‍රජන් ඇති කරයි.',
          'ta':
              'நடவுக்கு முன் மேல்மண்ணில் கலக்கவும். யூரியா தேவையில்லை — அவரை தனது நைட்ரஜனை நிலைநிறுத்துகிறது.',
        },
        timing: {
          'en': 'Apply at land preparation only.',
          'si': 'ඉඩම් සකස් කිරීමේදී පමණක් යොදන්න.',
          'ta': 'நிலம் தயார் செய்யும்போது மட்டும் பயன்படுத்தவும்.',
        },
        caution: {
          'en':
              'Minimal fertiliser approach. Excess nitrogen suppresses N-fixation.',
          'si':
              'අවම පොහොර ක්‍රමවේදය. අතිරික්ත නයිට්‍රජන් N-ස්ථාවරීකරණය යටපත් කරයි.',
          'ta':
              'குறைந்த உரம் அணுகுமுறை. அதிக நைட்ரஜன் N-நிலைநிறுத்தலை தடுக்கும்.',
        },
        color: Color(0xFFE65100),
        icon: Icons.grass,
      ),
    ],
    pesticides: [
      _ChemicalInstruction(
        name: 'Dimethoate 40 EC',
        purpose: {
          'en': 'Pod borers & thrips',
          'si': 'කරල් සිදුරු කරන්නන් හා ත්‍රිප්ස්',
          'ta': 'காய் துளைப்பான்கள் மற்றும் திரிப்ஸ்',
        },
        dose: {
          'en': '1.5 ml per 1 L water',
          'si': 'ජල ලිටර් 1 ට මිලි ලිටර් 1.5',
          'ta': '1 லி தண்ணீருக்கு 1.5 மிலி',
        },
        method: {
          'en': 'Spray on pods and surrounding leaves. Cover all surfaces.',
          'si': 'කරල් හා ඒවා ඉසව් කොළ ස්ප්‍රේ කරන්න. සියලු මතුපිට ආවරණය කරන්න.',
          'ta':
              'காய்களிலும் சுற்றியுள்ள இலைகளிலும் தெளிக்கவும். அனைத்து மேற்பரப்புகளையும் மூடவும்.',
        },
        timing: {
          'en': 'Apply at pod formation. Do not spray during open flower.',
          'si':
              'කරල් ඇති වීමේ කාලයේ යොදන්න. විවෘත මල් ඇති කාලයේ ස්ප්‍රේ නොකරන්න.',
          'ta':
              'காய் உருவாகும் நேரத்தில் பயன்படுத்தவும். திறந்த பூ நிலையில் தெளிக்காதீர்கள்.',
        },
        caution: {
          'en': 'Moderately toxic — wear gloves and mask. Harvest gap: 7 days.',
          'si':
              'මධ්‍යස්ථ විෂකාරකය — අත් වැසුම් හා මාස්ක් පළඳින්න. අස්වනු ගැළපීම: දින 7.',
          'ta':
              'மிதமான நச்சு — கையுறை மற்றும் முககவசம் அணியுங்கள். அறுவடை இடைவெளி: 7 நாட்கள்.',
        },
        color: Color(0xFFC62828),
        icon: Icons.bug_report,
      ),
    ],
  ),

  // ── FINGER MILLET ─────────────────────────────────────────────────────────
  'Finger millet': _SoilRec(
    soilPh: 6.0,
    soilMoisturePct: 55,
    fertilizerIndex: 0.60,
    pesticideIndex: 0.40,
    nIndex: 0.60,
    pIndex: 0.45,
    kIndex: 0.55,
    summary: {
      'en': 'Finger millet (Kurakkan) is a hardy crop well-adapted to dry zones. '
          'Moderate fertiliser on well-drained red loam or sandy soil gives good yields with minimal inputs.',
      'si': 'කුරක්කන් (ඇඟිලි ධාන්‍ය) වියළි කලාපයේ හොඳින් ගැලෙන ශක්තිමත් භෝගයකි. '
          'හොඳ ජල ඌරණ රතු ලෝම් හෝ වැලි පස්වල මධ්‍යස්ථ පොහොර සමඟ අඩු ආදාන සහිතව හොඳ අස්වැන්නක් ලබාදේ.',
      'ta': 'கேழ்வரகு (குராக்கன்) வறண்ட மண்டலத்திற்கு நன்றாக தகவமைத்துக்கொண்ட வலுவான பயிர். '
          'நல்ல வடிகால் சிவப்பு மண் அல்லது மணல் மண்ணில் மிதமான உரம் குறைந்த உள்ளீடுகளில் நல்ல விளைச்சல் தரும்.',
    },
    phNote: {
      'en':
          'Tolerates slightly acidic soils pH 5.0–7.0 — grows well in red laterite.',
      'si':
          'pH 5.0–7.0 ශ්‍රේණියේ ඉසව් අම්ලිකතා ඔරොත්තු දෙයි — රතු ලැටරයිට් පස්වල හොඳින් වැඩෙයි.',
      'ta':
          'pH 5.0–7.0 சற்று அமில மண்ணை தாங்கும் — சிவப்பு லேட்டரைட் மண்ணில் நன்றாக வளரும்.',
    },
    moistureNote: {
      'en':
          'Moderate moisture needed. Drought tolerant but sensitive to waterlogging.',
      'si':
          'මධ්‍යස්ථ ආර්ද්‍රතාව අවශ්‍ය. නියං ඔරොත්තු දෙයි, නමුත් ජල ගැලීමට සංවේදීය.',
      'ta':
          'மிதமான ஈரப்பதம் தேவை. வறட்சி தாங்கும் ஆனால் நீர் தேக்கத்திற்கு உணர்திறன் உடையது.',
    },
    fertilizers: [
      _ChemicalInstruction(
        name: 'Urea (Nitrogen)',
        purpose: {
          'en': 'Tiller production & grain fill',
          'si': 'ශාඛා නිෂ්පාදනය හා ධාන්‍ය පිරවීම',
          'ta': 'கதிர் உற்பத்தி மற்றும் தானிய நிரப்பல்',
        },
        dose: {
          'en': '40 g dissolved in 10 L water per 10 m²',
          'si': 'ජල ලිටර් 10 ක ග්‍රෑ. 40 දිය කර 10 m² ට',
          'ta': '10 லி தண்ணீரில் 40 கி கரைத்து 10 m²-க்கு',
        },
        method: {
          'en': 'Dissolve in water. Apply as drench at plant base.',
          'si': 'ජලයේ දිය කරන්න. ශාකයේ පාමූලේ ද්‍රාවණය ලෙස යොදන්න.',
          'ta':
              'தண்ணீரில் கரைக்கவும். செடியின் அடியில் நீர் ஊற்றும் முறையில் பயன்படுத்தவும்.',
        },
        timing: {
          'en':
              '1st dose at 2 weeks after planting. 2nd dose at panicle initiation (6 weeks).',
          'si':
              '1 වන මාත්‍රාව රෝපණයෙන් සති 2 ට. 2 වන මාත්‍රාව කිරලි ආරම්භ (සති 6) කාලයේ.',
          'ta':
              '1வது அளவு நடவுக்கு 2 வாரங்கள் பிறகு. 2வது அளவு கதிர் தொடக்க நிலையில் (6 வாரங்கள்).',
        },
        caution: {
          'en':
              'Split the dose for best effect. Apply in the evening when cool.',
          'si': 'හොඳ ප්‍රතිඵල සඳහා මාත්‍රාව බෙදන්න. සිසිල් සවස් කාලයේ යොදන්න.',
          'ta':
              'சிறந்த விளைவுக்கு அளவை பிரிக்கவும். குளிர்ச்சியான மாலை நேரத்தில் பயன்படுத்தவும்.',
        },
        color: Color(0xFF2E7D32),
        icon: Icons.grass,
      ),
      _ChemicalInstruction(
        name: 'MOP (Potassium)',
        purpose: {
          'en': 'Grain quality & disease resistance',
          'si': 'ධාන්‍ය ගුණාත්මකභාවය හා රෝග ඔරොත්තු',
          'ta': 'தானிய தரம் மற்றும் நோய் எதிர்ப்பு',
        },
        dose: {
          'en': '50 g dissolved in 10 L water per 10 m²',
          'si': 'ජල ලිටර් 10 ක ග්‍රෑ. 50 දිය කර 10 m² ට',
          'ta': '10 லி தண்ணீரில் 50 கி கரைத்து 10 m²-க்கு',
        },
        method: {
          'en': 'Dissolve fully. Apply as drench at base of plants.',
          'si': 'සම්පූර්ණයෙන් දිය කරන්න. ශාකයේ පාමූලේ ද්‍රාවණය ලෙස යොදන්න.',
          'ta':
              'முழுமையாக கரைக்கவும். செடியின் அடியில் நீர் ஊற்றும் முறையில் பயன்படுத்தவும்.',
        },
        timing: {
          'en': 'Apply at grain formation stage (8–10 weeks after planting).',
          'si': 'ධාන්‍ය ඇති වීමේ අවස්ථාවේ (රෝපණයෙන් සති 8–10) යොදන්න.',
          'ta':
              'தானிய உருவாக்க நிலையில் (நடவுக்கு 8–10 வாரங்கள் பிறகு) பயன்படுத்தவும்.',
        },
        caution: {
          'en': 'Store in sealed bag away from moisture.',
          'si': 'ආර්ද්‍රතාවෙන් ඈත සද්ධ බෑගයක ගබඩා කරන්න.',
          'ta': 'ஈரத்திலிருந்து விலகி மூடிய பையில் சேமிக்கவும்.',
        },
        color: Color(0xFF7B1FA2),
        icon: Icons.science,
      ),
    ],
    pesticides: [
      _ChemicalInstruction(
        name: 'Malathion 50 EC',
        purpose: {
          'en': 'Shoot fly & leaf aphids',
          'si': 'ශූට් මැස්සන් හා කොළ ඇෆිඩ්',
          'ta': 'தளிர் ஈ மற்றும் இலை அசுவினிகள்',
        },
        dose: {
          'en': '2 ml per 1 L water',
          'si': 'ජල ලිටර් 1 ට මිලි ලිටර් 2',
          'ta': '1 லி தண்ணீருக்கு 2 மிலி',
        },
        method: {
          'en':
              'Spray on all plant parts, especially growing tips where shoot fly attacks.',
          'si':
              'ශාකයේ සියලු කොටස්, විශේෂයෙන් ශූට් මැස්සන් ප්‍රහාර කරන වර්ධනය වන ගොනු ස්ප්‍රේ කරන්න.',
          'ta':
              'அனைத்து தாவர பாகங்களிலும், குறிப்பாக தளிர் ஈ தாக்கும் வளரும் நுனிகளில் தெளிக்கவும்.',
        },
        timing: {
          'en': 'Apply at 2–3 leaf stage if shoot fly is observed.',
          'si': 'ශූට් මැස්සන් දක්නා ලැබේ නම් 2–3 කොළ අවස්ථාවේ යොදන්න.',
          'ta':
              'தளிர் ஈ கண்டுபிடிக்கப்பட்டால் 2–3 இலை நிலையில் பயன்படுத்தவும்.',
        },
        caution: {
          'en':
              'Wear full protective gear. Wash equipment after use. Harvest gap: 7 days.',
          'si':
              'සම්පූර්ණ ආරක්ෂිත ගේන් පළඳින්න. භාවිතයෙන් පසු උපකරණ සෝදන්න. අස්වනු ගැළපීම: දින 7.',
          'ta':
              'முழு பாதுகாப்பு உடை அணியுங்கள். பயன்படுத்திய பிறகு உபகரணங்களை கழுவுங்கள். அறுவடை இடைவெளி: 7 நாட்கள்.',
        },
        color: Color(0xFFC62828),
        icon: Icons.bug_report,
      ),
    ],
  ),

  // ── GROUNDNUT ─────────────────────────────────────────────────────────────
  'Groundnut': _SoilRec(
    soilPh: 6.2,
    soilMoisturePct: 55,
    fertilizerIndex: 0.45,
    pesticideIndex: 0.50,
    nIndex: 0.25,
    pIndex: 0.65,
    kIndex: 0.60,
    summary: {
      'en': 'Groundnut needs loose, well-drained sandy loam so pods can penetrate the soil easily. '
          'Low nitrogen, good phosphorus and calcium-rich soil give the best yield and oil quality.',
      'si': 'රටකජු සඳහා ලිහිල්, හොඳ ජල ඌරණ ගති ඇති වැලි ලෝම් පස අවශ්‍ය — කරල් පහසුවෙන් පස් ඇතුළට ඇතුල් විය හැකිය. '
          'අඩු නයිට්‍රජන්, හොඳ පොස්පරස් හා කැල්සියම් බහුල පස් හොඳ අස්වැන්නක් හා තෙල් ගුණාත්මකභාවය ලබාදේ.',
      'ta': 'வேர்க்கடலைக்கு தளர்வான, நல்ல வடிகால் கொண்ட மணல் மண் தேவை — காய்கள் எளிதாக மண்ணில் நுழைய வேண்டும். '
          'குறைந்த நைட்ரஜன், நல்ல பாஸ்பரஸ் மற்றும் கால்சியம் நிறைந்த மண் சிறந்த விளைச்சலையும் எண்ணெய் தரத்தையும் தரும்.',
    },
    phNote: {
      'en': 'Prefers pH 5.9–7.0. Calcium at this pH prevents pod disorders.',
      'si':
          'pH 5.9–7.0 ශ්‍රේණිය කැමැත්තෙන් ලැබෙයි. මේ pH හි කැල්සියම් කරල් රෝග වළකියි.',
      'ta':
          'pH 5.9–7.0 விரும்புகிறது. இந்த pH-ல் கால்சியம் காய் கோளாறுகளை தடுக்கும்.',
    },
    moistureNote: {
      'en':
          'Good moisture during pegging and pod development is critical. Sandy loam allows peg penetration.',
      'si':
          'කූරු ඇතිවීමේ හා කරල් සංවර්ධනයේ කාලයේ ආර්ද්‍රතාව ඉතා වැදගත්. වැලි ලෝම් කූරු ඇතුල් වීමට ඉඩ සලසයි.',
      'ta':
          'ஆணி மற்றும் காய் வளர்ச்சி காலத்தில் நல்ல ஈரப்பதம் முக்கியம். மணல் மண் ஆணி நுழைவை அனுமதிக்கும்.',
    },
    fertilizers: [
      _ChemicalInstruction(
        name: 'TSP (Phosphorus)',
        purpose: {
          'en': 'Pod development & peg penetration',
          'si': 'කරල් සංවර්ධනය හා කූරු ඇතුල් වීම',
          'ta': 'காய் வளர்ச்சி மற்றும் ஆணி நுழைவு',
        },
        dose: {
          'en': '60 g dry per 10 m² soil',
          'si': '10 m² පසට ග්‍රෑ. 60 වියළි',
          'ta': '10 m² மண்ணுக்கு 60 கி உலர்',
        },
        method: {
          'en':
              'Mix into top 15 cm of soil before planting. Do not dissolve — use dry.',
          'si':
              'රෝපණයට පෙර ඉහළ සෙ.මී. 15 ට මිශ්‍ර කරන්න. දිය නොකරන්න — වියළිව භාවිත කරන්න.',
          'ta':
              'நடவுக்கு முன் மண்ணின் மேல் 15 செமீ-ல் கலக்கவும். கரைக்காதீர்கள் — உலர்வாக பயன்படுத்தவும்.',
        },
        timing: {
          'en': 'Apply at land preparation, 1 week before planting.',
          'si': 'ඉඩම් සකස් කිරීමේදී, රෝපණයට සති 1 කට පෙර යොදන්න.',
          'ta':
              'நிலம் தயார் செய்யும்போது, நடவுக்கு 1 வாரம் முன்பு பயன்படுத்தவும்.',
        },
        caution: {
          'en':
              'Groundnut fixes its own nitrogen — no urea needed at planting.',
          'si':
              'රටකජු ස්වදේශීය නයිට්‍රජන් ඇති කරයි — රෝපණ කාලයේ යූරියා අවශ්‍ය නැත.',
          'ta':
              'வேர்க்கடலை தனது நைட்ரஜனை நிலைநிறுத்துகிறது — நடவு நேரத்தில் யூரியா தேவையில்லை.',
        },
        color: Color(0xFFE65100),
        icon: Icons.grass,
      ),
      _ChemicalInstruction(
        name: 'Gypsum (Calcium Sulfate)',
        purpose: {
          'en': 'Pod fill & prevents hollow heart',
          'si': 'කරල් පිරවීම හා හිස් කරල් වළකීම',
          'ta': 'காய் நிரப்பல் மற்றும் வெற்று இதயம் தடுப்பு',
        },
        dose: {
          'en': '100 g dry per 10 m² soil',
          'si': '10 m² පසට ග්‍රෑ. 100 වියළි',
          'ta': '10 m² மண்ணுக்கு 100 கி உலர்',
        },
        method: {
          'en':
              'Sprinkle evenly on soil surface around plants. Water in lightly.',
          'si': 'ශාක වටේ පස් මතුපිට සමව ඉසින්න. සැහැල්ලුවෙන් ජලය දමන්න.',
          'ta':
              'செடிகளை சுற்றி மண் மேற்பரப்பில் சீராக தூவுங்கள். லேசாக நீர் பாய்ச்சவும்.',
        },
        timing: {
          'en':
              'Apply at early flowering/pegging stage (30–35 days after planting).',
          'si':
              'මුල් මල් පිපීම/කූරු ඇතිවීමේ අවස්ථාවේ (රෝපණයෙන් දින 30–35) යොදන්න.',
          'ta':
              'ஆரம்ப பூக்கும்/ஆணி நிலையில் (நடவுக்கு 30–35 நாட்கள் பிறகு) பயன்படுத்தவும்.',
        },
        caution: {
          'en':
              'Not a fertiliser — do not substitute for TSP or MOP. Critical for groundnut quality.',
          'si':
              'පොහොරක් නොවේ — TSP හෝ MOP ට ආදේශ නොකරන්න. රටකජු ගුණාත්මකභාවයට ඉතා වැදගත්.',
          'ta':
              'இது உரம் அல்ல — TSP அல்லது MOP-ஐ மாற்றாதீர்கள். வேர்க்கடலை தரத்திற்கு முக்கியம்.',
        },
        color: Color(0xFF1565C0),
        icon: Icons.water_drop,
      ),
      _ChemicalInstruction(
        name: 'MOP (Potassium)',
        purpose: {
          'en': 'Oil content & shell quality',
          'si': 'තෙල් ප්‍රමාණය හා කවච ගුණාත්මකභාවය',
          'ta': 'எண்ணெய் உள்ளடக்கம் மற்றும் ஓடு தரம்',
        },
        dose: {
          'en': '50 g dissolved in 10 L water per 10 m²',
          'si': 'ජල ලිටර් 10 ක ග්‍රෑ. 50 දිය කර 10 m² ට',
          'ta': '10 லி தண்ணீரில் 50 கி கரைத்து 10 m²-க்கு',
        },
        method: {
          'en': 'Dissolve and drench at plant base.',
          'si': 'දිය කර ශාකයේ පාමූලේ ද්‍රාවණය ලෙස යොදන්න.',
          'ta': 'கரைத்து செடியின் அடியில் நீர் ஊற்றவும்.',
        },
        timing: {
          'en': 'Apply at 40 days after planting.',
          'si': 'රෝපණයෙන් දින 40 ට පසු යොදන්න.',
          'ta': 'நடவுக்கு 40 நாட்கள் பிறகு பயன்படுத்தவும்.',
        },
        caution: {
          'en':
              'Avoid waterlogging after application — groundnut roots sensitive to excess moisture.',
          'si':
              'යෙදීමෙන් පසු ජල ගැලීම වළකින්න — රටකජු මූල අතිරික්ත ආර්ද්‍රතාවට සංවේදීය.',
          'ta':
              'பயன்படுத்திய பிறகு நீர் தேக்கம் தவிர்க்கவும் — வேர்க்கடலை வேர்கள் அதிக ஈரத்திற்கு உணர்திறன் உடையவை.',
        },
        color: Color(0xFF7B1FA2),
        icon: Icons.science,
      ),
    ],
    pesticides: [
      _ChemicalInstruction(
        name: 'Thiram 75 WP (Seed Treatment)',
        purpose: {
          'en': 'Seed-borne fungal diseases',
          'si': 'බීජ ජනිත දිලීර රෝග',
          'ta': 'விதை பரவும் பூஞ்சை நோய்கள்',
        },
        dose: {
          'en': '3 g per 1 kg seed',
          'si': 'බීජ කිලෝ ග්‍රෑ. 1 ට ග්‍රෑ. 3',
          'ta': '1 கிலோ விதைக்கு 3 கி',
        },
        method: {
          'en':
              'Mix powder with seeds in a bag and shake well until all seeds are coated.',
          'si':
              'කිසිදු දෙයක දී කුඩු සහ බීජ මිශ්‍ර කර හොඳින් සොලවන්න — සියලු බීජ ආවරණය විය යුතුය.',
          'ta':
              'ஒரு பையில் தூள் மற்றும் விதைகளை கலந்து நன்றாக குலுக்கவும் — அனைத்து விதைகளும் மூடப்பட வேண்டும்.',
        },
        timing: {
          'en': 'Treat seeds 1 day before planting. Allow to dry in shade.',
          'si':
              'රෝපණයට දිනකට පෙර බීජ ප්‍රතිකාර කරන්න. සෙවනෙහි වියළීමට ඉඩ දෙන්න.',
          'ta':
              'நடவுக்கு 1 நாள் முன்பு விதைகளை சிகிச்சை செய்யுங்கள். நிழலில் காயவிடுங்கள்.',
        },
        caution: {
          'en':
              'Do not consume treated seeds. Wear gloves. Keep away from children.',
          'si':
              'ප්‍රතිකාර කළ බීජ අනුභව නොකරන්න. අත් වැසුම් පළඳින්න. ළදරුවන්ගෙන් ඈතින් තබන්න.',
          'ta':
              'சிகிச்சை செய்யப்பட்ட விதைகளை சாப்பிடாதீர்கள். கையுறை அணியுங்கள். குழந்தைகளிடமிருந்து விலகி வைக்கவும்.',
        },
        color: Color(0xFF7B1FA2),
        icon: Icons.spa,
      ),
      _ChemicalInstruction(
        name: 'Chlorothalonil 75 WP',
        purpose: {
          'en': 'Late leaf spot & rust',
          'si': 'නිකෙලස් කොළ ලප හා මළ කැකුළු',
          'ta': 'தாமத இலை புள்ளி மற்றும் துரு',
        },
        dose: {
          'en': '2 g per 1 L water',
          'si': 'ජල ලිටර් 1 ට ග්‍රෑ. 2',
          'ta': '1 லி தண்ணீருக்கு 2 கி',
        },
        method: {
          'en': 'Mix in water. Spray on all leaf surfaces, top and bottom.',
          'si':
              'ජලයේ මිශ්‍ර කරන්න. කොළ සියලු මතුපිට (ඉහළ හා යට) ස්ප්‍රේ කරන්න.',
          'ta':
              'தண்ணீரில் கலக்கவும். அனைத்து இலை மேற்பரப்புகளிலும் (மேலும் கீழும்) தெளிக்கவும்.',
        },
        timing: {
          'en':
              'Apply at 40 days and repeat every 14 days until 2 weeks before harvest.',
          'si':
              'දින 40 ට යොදා අස්වනු නෙලීමේ සති 2 ට පෙරට දිනකට 14 ට නැවත කරන්න.',
          'ta':
              'நடவுக்கு 40 நாட்களில் பயன்படுத்தி அறுவடைக்கு 2 வாரங்கள் முன்பு வரை 14 நாட்களுக்கு ஒருமுறை மீண்டும் செய்யவும்.',
        },
        caution: {
          'en': 'Wear mask. Do not spray in rain. Harvest gap: 14 days.',
          'si':
              'மாஸ்க் போடுங்கள். மழையில் தெளிக்காதீர்கள். அறுவடை இடைவெளி: 14 நாட்கள்.',
          'ta':
              'முககவசம் அணியுங்கள். மழையில் தெளிக்காதீர்கள். அறுவடை இடைவெளி: 14 நாட்கள்.',
        },
        color: Color(0xFFC62828),
        icon: Icons.bug_report,
      ),
    ],
  ),
};

// ─────────────────────────────────────────────────────────────────────────────
//  Average yield benchmarks (kg/ha) — for result comparison
// ─────────────────────────────────────────────────────────────────────────────
// _avgYields removed — the average is now returned by the backend in
// average_yield_kg_per_ha and stored in _result['average'].
// This means the threshold automatically stays in sync with the ML model
// even after retraining, with no Flutter changes required.

// ─────────────────────────────────────────────────────────────────────────────
//  Crop-to-district mapping
// ─────────────────────────────────────────────────────────────────────────────
const Map<String, List<String>> _cropDistricts = {
  'Carrot': ['Nuwara Eliya', 'Badulla', 'Jaffna'],
  'Maize': ['Anuradhapura', 'Monaragala', 'Ampara'],
  'Green gram': ['Hambantota', 'Monaragala', 'Jaffna'],
  'Cowpea': ['Anuradhapura', 'Monaragala', 'Ampara'],
  'Finger millet': ['Anuradhapura', 'Monaragala', 'Ampara'],
  'Groundnut': ['Monaragala', 'Ampara', 'Batticaloa', 'Jaffna'],
};

// ─────────────────────────────────────────────────────────────────────────────
//  Irrigation types — trilingual descriptions
// ─────────────────────────────────────────────────────────────────────────────
final List<Map<String, _L>> _irrigationTypes = [
  {
    'value': {'en': 'drip', 'si': 'drip', 'ta': 'drip'},
    'label': {
      'en': 'Drip Irrigation',
      'si': 'බිංදු ජලනය',
      'ta': 'சொட்டு நீர்ப்பாசனம்',
    },
    'desc': {
      'en':
          'Water delivered directly to roots — highest water efficiency. Ideal for Carrot and Groundnut.',
      'si':
          'ජලය කෙලින් මූල වෙත ලබා දේ — ඉහළ ජල කාර්යක්ෂමතාව. කැරට් හා රටකජු සඳහා සුදුසු.',
      'ta':
          'வேர்களுக்கு நேரடியாக நீர் வழங்கப்படும் — அதிக நீர் திறன். கேரட் மற்றும் வேர்க்கடலைக்கு ஏற்றது.',
    },
  },
  {
    'value': {'en': 'sprinkler', 'si': 'sprinkler', 'ta': 'sprinkler'},
    'label': {
      'en': 'Sprinkler Irrigation',
      'si': 'ස්ප්‍රිංකලර් ජලනය',
      'ta': 'தெளிப்பு நீர்ப்பாசனம்',
    },
    'desc': {
      'en':
          'Water sprayed evenly over the crop. Good for upland vegetables needing uniform moisture.',
      'si':
          'ජලය භෝගය පුරා සමව ඉසිනු ලැබේ. ඒකාකාර ආර්ද්‍රතාව අවශ්‍ය නිල් ගොවිතැනට හොඳ.',
      'ta':
          'நீர் பயிரில் சீராக தெளிக்கப்படும். சீரான ஈரம் தேவைப்படும் மேட்டு காய்கறிகளுக்கு நல்லது.',
    },
  },
  {
    'value': {'en': 'rainfed', 'si': 'rainfed', 'ta': 'rainfed'},
    'label': {
      'en': 'Rainfed (No Irrigation)',
      'si': 'වර්ෂාපෝෂිත (ජලනය නැත)',
      'ta': 'மழையை நம்பிய (நீர்ப்பாசனம் இல்லை)',
    },
    'desc': {
      'en':
          'Relies entirely on natural rainfall. Suitable for Maha season in districts with reliable NE monsoon.',
      'si':
          'සම්පූර්ණයෙන් ස්වාභාවික වර්ෂාව මත රඳාපවතී. උතුරු-නැගෙනහිර මෝසමේ දිස්ත්‍රික්ක සඳහා සුදුසු.',
      'ta':
          'முற்றிலும் இயற்கை மழையை நம்புகிறது. நம்பகமான வடகிழக்கு பருவமழை கொண்ட மாவட்டங்களில் மகா பருவத்திற்கு ஏற்றது.',
    },
  },
];

// ─────────────────────────────────────────────────────────────────────────────
//  Season data — trilingual
// ─────────────────────────────────────────────────────────────────────────────
final List<Map<String, _L>> _seasons = [
  {
    'name': {'en': 'Maha', 'si': 'මහ', 'ta': 'மகா'},
    'months': {
      'en': 'October – March',
      'si': 'ඔක්තෝබර් – මාර්තු',
      'ta': 'அக்டோபர் – மார்ச்',
    },
    'desc': {
      'en':
          'The major season driven by the north-east monsoon. Most productive for Carrot, Finger millet and Green gram.',
      'si':
          'උතුරු-නැගෙනහිර මෝසමේ ප්‍රධාන කන්නය. කැරට්, කුරක්කන් හා මුං ඇට සඳහා ඉතා ඵලදායී.',
      'ta':
          'வடகிழக்கு பருவமழையால் இயக்கப்படும் முக்கிய பருவம். கேரட், கேழ்வரகு மற்றும் பச்சைப்பயிருக்கு மிகவும் உற்பத்தி அதிகம்.',
    },
  },
  {
    'name': {'en': 'Yala', 'si': 'යල', 'ta': 'யாழ்'},
    'months': {
      'en': 'April – September',
      'si': 'අප්‍රේල් – සැප්තැම්බර්',
      'ta': 'ஏப்ரல் – செப்டம்பர்',
    },
    'desc': {
      'en':
          'Secondary season supported by the south-west monsoon. Best for Groundnut, Cowpea and Maize.',
      'si':
          'දකුණු-බටහිර මෝසමේ ද්විතීය කන්නය. රටකජු, කව්පී හා බඩිරිඳු සඳහා හොඳ.',
      'ta':
          'தென்மேற்கு பருவமழையால் ஆதரிக்கப்படும் இரண்டாம் பருவம். வேர்க்கடலை, அவரை மற்றும் மக்காச்சோளத்திற்கு சிறந்தது.',
    },
  },
  {
    'name': {'en': 'Inter', 'si': 'අතරිම', 'ta': 'இடை'},
    'months': {
      'en': 'Mar – Apr & Sep – Oct',
      'si': 'මාර්-අප්‍රේල් & සැප්-ඔක්',
      'ta': 'மார்-ஏப் & செப்-அக்',
    },
    'desc': {
      'en':
          'Short inter-monsoon periods. Fast-maturing Green gram and Cowpea can complete a cycle.',
      'si':
          'කෙටි අතරිම කාලය. ශීඝ්‍ර මුං ඇට හා කව්පී චක්‍රයක් සම්පූර්ණ කළ හැකිය.',
      'ta':
          'குறுகிய இடைப்பருவ காலம். விரைவாக முதிர்ச்சியடையும் பச்சைப்பயிறு மற்றும் அவரை ஒரு சுழற்சியை முடிக்கலாம்.',
    },
  },
];

// ─────────────────────────────────────────────────────────────────────────────
//  Crop quick-select emoji
// ─────────────────────────────────────────────────────────────────────────────
const Map<String, String> _cropEmoji = {
  'Carrot': '🥕',
  'Maize': '🌽',
  'Green gram': '🫘',
  'Cowpea': '🟤',
  'Finger millet': '🌾',
  'Groundnut': '🥜',
};

// ─────────────────────────────────────────────────────────────────────────────
//  SVG icon strings (matching Dashboard)
// ─────────────────────────────────────────────────────────────────────────────
const String _cropSphereSvg =
    '''<svg viewBox="0 0 110 110" xmlns="http://www.w3.org/2000/svg">
  <ellipse cx="55" cy="96" rx="36" ry="7" fill="#1B4D1B" opacity="0.7"/>
  <path d="M55 95 C55 80 52 65 50 50" stroke="#4CAF50" stroke-width="2.5" stroke-linecap="round" fill="none"/>
  <path d="M50 65 C35 58 22 42 28 28 C38 40 48 55 50 65Z" fill="#388E3C" opacity="0.9"/>
  <path d="M50 65 C42 58 35 44 28 28" stroke="#2E7D32" stroke-width="1" fill="none" opacity="0.6"/>
  <path d="M52 58 C67 50 80 36 74 22 C64 34 55 50 52 58Z" fill="#4CAF50" opacity="0.9"/>
  <path d="M52 58 C62 50 70 36 74 22" stroke="#388E3C" stroke-width="1" fill="none" opacity="0.6"/>
  <path d="M50 50 C38 44 30 32 34 20 C42 30 48 42 50 50Z" fill="#66BB6A" opacity="0.8"/>
  <circle cx="50" cy="28" r="3.5" fill="#FFC107" opacity="0.9"/>
  <circle cx="44" cy="22" r="3" fill="#FFB300" opacity="0.85"/>
  <circle cx="56" cy="20" r="3" fill="#FFC107" opacity="0.9"/>
  <circle cx="50" cy="14" r="3.5" fill="#FFD54F" opacity="0.95"/>
  <circle cx="43" cy="13" r="2.5" fill="#FFB300" opacity="0.8"/>
  <circle cx="57" cy="12" r="2.5" fill="#FFC107" opacity="0.85"/>
  <circle cx="50" cy="8" r="2" fill="#FFD54F" opacity="0.9"/>
  <path d="M50 50 C50 42 50 35 50 28" stroke="#558B2F" stroke-width="2" stroke-linecap="round" fill="none"/>
</svg>''';

String _navSvg(int i, Color color) {
  final c =
      '#${color.toARGB32().toRadixString(16).padLeft(8, '0').substring(2)}';
  return switch (i) {
    0 =>
      '<svg viewBox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg">'
          '<path d="M3 9.5L12 3L21 9.5V20C21 20.55 20.55 21 20 21H15V15H9V21H4C3.45 21 3 20.55 3 20V9.5Z" stroke="$c" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" fill="none"/>'
          '</svg>',
    1 =>
      '<svg viewBox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg">'
          '<rect x="2" y="14" width="4" height="8" rx="1.5" fill="$c"/>'
          '<rect x="8" y="10" width="4" height="12" rx="1.5" fill="$c"/>'
          '<rect x="14" y="5" width="4" height="17" rx="1.5" fill="$c"/>'
          '<path d="M4 12L10 8L16 4" stroke="$c" stroke-width="1.6" stroke-linecap="round"/>'
          '<circle cx="16" cy="4" r="1.8" fill="$c"/>'
          '</svg>',
    2 => '<svg viewBox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg">'
        '<ellipse cx="11" cy="18" rx="6" ry="3.5" fill="$c" opacity="0.35"/>'
        '<ellipse cx="11" cy="15.5" rx="6" ry="3.5" fill="$c" opacity="0.6"/>'
        '<ellipse cx="11" cy="13" rx="6" ry="3.5" fill="$c"/>'
        '<path d="M19 8L21 5L23 8" stroke="$c" stroke-width="1.6" stroke-linecap="round" fill="none"/>'
        '<line x1="21" y1="5" x2="21" y2="11" stroke="$c" stroke-width="1.6" stroke-linecap="round"/>'
        '</svg>',
    3 => '<svg viewBox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg">'
        '<circle cx="8" cy="8" r="3.5" fill="$c"/>'
        '<line x1="8" y1="2" x2="8" y2="4" stroke="$c" stroke-width="1.5" stroke-linecap="round"/>'
        '<line x1="8" y1="12" x2="8" y2="14" stroke="$c" stroke-width="1.5" stroke-linecap="round"/>'
        '<line x1="2" y1="8" x2="4" y2="8" stroke="$c" stroke-width="1.5" stroke-linecap="round"/>'
        '<line x1="12" y1="8" x2="14" y2="8" stroke="$c" stroke-width="1.5" stroke-linecap="round"/>'
        '<ellipse cx="17.5" cy="15.5" rx="5.5" ry="4" fill="$c"/>'
        '<line x1="13.5" y1="21" x2="13" y2="23" stroke="$c" stroke-width="1.4" stroke-linecap="round"/>'
        '<line x1="17" y1="21" x2="16.5" y2="23" stroke="$c" stroke-width="1.4" stroke-linecap="round"/>'
        '<line x1="20.5" y1="21" x2="20" y2="23" stroke="$c" stroke-width="1.4" stroke-linecap="round"/>'
        '</svg>',
    4 => '<svg viewBox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg">'
        '<path d="M12 22C12 16 12 11 12 6" stroke="$c" stroke-width="2" stroke-linecap="round"/>'
        '<path d="M12 15C8 13 4 9 6 4C10 8 11 12 12 15Z" fill="$c" opacity="0.65"/>'
        '<path d="M12 11C16 9 20 5 18 0C14 5 12 9 12 11Z" fill="$c"/>'
        '<circle cx="18" cy="5" r="4.5" fill="$c"/>'
        '<path d="M16 5L17.5 7L20 3.5" stroke="white" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round"/>'
        '</svg>',
    5 => '<svg viewBox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg">'
        '<rect x="2" y="13" width="20" height="9" rx="2" fill="$c" opacity="0.35"/>'
        '<path d="M2 13Q12 7 22 13Z" fill="$c"/>'
        '<circle cx="7.5" cy="17" r="2" fill="$c" opacity="0.7"/>'
        '<circle cx="12" cy="16.5" r="2.3" fill="$c" opacity="0.55"/>'
        '<circle cx="16.5" cy="17.5" r="1.8" fill="$c" opacity="0.7"/>'
        '<path d="M10 7L12 3L14 7" stroke="$c" stroke-width="1.6" stroke-linecap="round" fill="none"/>'
        '<line x1="12" y1="3" x2="12" y2="9" stroke="$c" stroke-width="1.6" stroke-linecap="round"/>'
        '</svg>',
    _ => '<svg viewBox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg">'
        '<rect x="1" y="2" width="16" height="12" rx="4" fill="$c" opacity="0.85"/>'
        '<path d="M4 14L3 19L9 14Z" fill="$c" opacity="0.85"/>'
        '<circle cx="5.5" cy="8" r="1.4" fill="white"/>'
        '<circle cx="9" cy="8" r="1.4" fill="white"/>'
        '<circle cx="12.5" cy="8" r="1.4" fill="white"/>'
        '<circle cx="19" cy="5.5" r="4.5" fill="$c"/>'
        '<path d="M17 5.5L18.5 7L21 4" stroke="white" stroke-width="1.4" stroke-linecap="round" stroke-linejoin="round"/>'
        '</svg>',
  };
}

int _weekOfYear() {
  final now = DateTime.now();
  final soy = DateTime(now.year, 1, 1);
  return (((now.difference(soy).inDays + soy.weekday - 1) / 7).ceil()).clamp(
    1,
    52,
  );
}

// ─────────────────────────────────────────────────────────────────────────────
//  YieldScreen
// ─────────────────────────────────────────────────────────────────────────────
class YieldScreen extends StatefulWidget {
  final ValueChanged<int>? onNavigate;

  /// Optional callback to pre-fill a message in the AI Chat tab.
  /// Called with the context string before navigating to tab 6.
  final ValueChanged<String>? onAiChatContext;

  const YieldScreen({super.key, this.onNavigate, this.onAiChatContext});

  @override
  State<YieldScreen> createState() => _YieldScreenState();
}

class _YieldScreenState extends State<YieldScreen> {
  // ── Selections ─────────────────────────────────────────────────────────────
  String? _selectedCrop;
  String? _selectedDistrict;
  String? _selectedSeason;
  String? _selectedIrrigation; // raw value key e.g. 'drip'

  // ── Area — stored in perches internally ────────────────────────────────────
  double _areaPerches = 160.0;
  final _perchesCtrl = TextEditingController(text: '160');
  final _acresCtrl = TextEditingController(text: '1.00');
  final _hectCtrl = TextEditingController(text: '0.405');
  bool _areaUpdating = false; // prevents recursive controller updates

  // ── Weather ────────────────────────────────────────────────────────────────
  _WeatherData? _weather;
  bool _weatherLoading = false;
  String? _weatherError;
  bool _weatherOverrideOpen = false;
  double _oRainfall = 45.0, _oTempMin = 12.0, _oTempMax = 22.0;
  double _oHumidity = 78.0, _oWindSpeed = 12.0, _oSolarRad = 16.0;

  // ── Prediction state ───────────────────────────────────────────────────────
  bool _isLoading = false;
  Map<String, dynamic>? _result;
  String? _errorMessage;

  // ── Soil section expand ────────────────────────────────────────────────────
  bool _fertExpanded = false;
  bool _pestExpanded = false;

  // ── Derived ────────────────────────────────────────────────────────────────
  List<String> get _availableDistricts =>
      _selectedCrop != null ? (_cropDistricts[_selectedCrop!] ?? []) : [];

  _SoilRec? get _activeSoilRec =>
      _selectedCrop != null ? _kSoilRecs[_selectedCrop!] : null;

  bool get _canPredict =>
      _selectedCrop != null &&
      _selectedDistrict != null &&
      _selectedSeason != null &&
      _selectedIrrigation != null;

  double get _areaHa => _perchesToHa(_areaPerches);

  _WeatherData get _effectiveWeather => _weatherOverrideOpen || _weather == null
      ? _WeatherData(
          rainfallMm: _oRainfall,
          tempMinC: _oTempMin,
          tempMaxC: _oTempMax,
          humidityPct: _oHumidity,
          windSpeedKmh: _oWindSpeed,
          solarRadMj: _oSolarRad,
        )
      : _weather!;

  // ── Language helpers ───────────────────────────────────────────────────────
  String get _langKey {
    final l = AppLangProvider.lang(context);
    if (l == AppLang.si) return 'si';
    if (l == AppLang.ta) return 'ta';
    return 'en';
  }

  String _t(_L m) => m[_langKey] ?? m['en']!;
  String _ts(Map<String, String> m) => m[_langKey] ?? m['en']!;

  @override
  void initState() {
    super.initState();
    _perchesCtrl.addListener(_onPerchesChanged);
    _acresCtrl.addListener(_onAcresChanged);
    _hectCtrl.addListener(_onHectChanged);
  }

  @override
  void dispose() {
    _perchesCtrl.dispose();
    _acresCtrl.dispose();
    _hectCtrl.dispose();
    super.dispose();
  }

  // ── Area text field listeners ──────────────────────────────────────────────
  void _onPerchesChanged() {
    if (_areaUpdating) return;
    final v = double.tryParse(_perchesCtrl.text);
    if (v == null || v <= 0) return;
    _areaUpdating = true;
    setState(() => _areaPerches = v);
    _acresCtrl.text = _haToAcres(_perchesToHa(v)).toStringAsFixed(3);
    _hectCtrl.text = _perchesToHa(v).toStringAsFixed(4);
    _areaUpdating = false;
  }

  void _onAcresChanged() {
    if (_areaUpdating) return;
    final v = double.tryParse(_acresCtrl.text);
    if (v == null || v <= 0) return;
    _areaUpdating = true;
    final ha = _acresToHa(v);
    setState(() => _areaPerches = _haToPerches(ha));
    _perchesCtrl.text = _haToPerches(ha).toStringAsFixed(1);
    _hectCtrl.text = ha.toStringAsFixed(4);
    _areaUpdating = false;
  }

  void _onHectChanged() {
    if (_areaUpdating) return;
    final v = double.tryParse(_hectCtrl.text);
    if (v == null || v <= 0) return;
    _areaUpdating = true;
    setState(() => _areaPerches = _haToPerches(v));
    _perchesCtrl.text = _haToPerches(v).toStringAsFixed(1);
    _acresCtrl.text = _haToAcres(v).toStringAsFixed(3);
    _areaUpdating = false;
  }

  // ── Weather fetch ──────────────────────────────────────────────────────────
  Future<void> _loadWeather(String district) async {
    setState(() {
      _weatherLoading = true;
      _weatherError = null;
      _weather = null;
    });
    try {
      final w = await _fetchWeather(district);
      if (mounted) {
        setState(() {
          _weather = w;
          _weatherLoading = false;
          _oRainfall = w.rainfallMm;
          _oTempMin = w.tempMinC;
          _oTempMax = w.tempMaxC;
          _oHumidity = w.humidityPct;
          _oWindSpeed = w.windSpeedKmh;
          _oSolarRad = w.solarRadMj;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _weatherLoading = false;
          _weatherError = 'Could not load weather. Using manual values.';
          _weatherOverrideOpen = true;
        });
      }
    }
  }

  // ── Predict ────────────────────────────────────────────────────────────────
  Future<void> _predict() async {
    if (!_canPredict) return;
    final rec = _activeSoilRec!;
    final w = _effectiveWeather;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _result = null;
    });
    try {
      final resp = await ServiceFactory.getService().predictYield(
        YieldRequest(
          crop: _selectedCrop!,
          district: _selectedDistrict!,
          season: _selectedSeason!,
          weekOfYear: _weekOfYear(),
          rainfallMm: w.rainfallMm,
          tempMinC: w.tempMinC,
          tempMaxC: w.tempMaxC,
          humidityPct: w.humidityPct,
          windSpeedKmh: w.windSpeedKmh,
          solarRadiationMj: w.solarRadMj,
          soilPh: rec.soilPh,
          soilMoisturePct: rec.soilMoisturePct,
          cultivatedAreaHa: _areaHa,
          seedVariety: 'standard',
          fertilizerIndex: rec.fertilizerIndex,
          pesticideIndex: rec.pesticideIndex,
          irrigationType: _selectedIrrigation!,
          nIndex: rec.nIndex,
          pIndex: rec.pIndex,
          kIndex: rec.kIndex,
          prevCrop: 'Fallow',
          demandIndex: 85.0,
          inflationIndex: 1.2,
          holidayFlag: 0,
          festivalFlag: 0,
        ),
      );
      setState(
        () => _result = {
          'yield': resp.predictedYieldKgPerHa,
          'average': resp.averageYieldKgPerHa, // from backend — no hardcoding
          'confidence': resp.confidence,
          'isMock': resp.isMock,
        },
      );
    } catch (e) {
      setState(() => _errorMessage = e.toString());
    } finally {
      setState(() => _isLoading = false);
    }
  }

  // ── Interpretation ─────────────────────────────────────────────────────────
  String _interpretation(double yieldVal) {
    final avg = (_result!['average'] as double? ?? yieldVal);
    final pct = ((yieldVal - avg) / avg * 100).round();
    if (pct >= 15) {
      return _ts({
        'en': '$pct% above average — excellent growing conditions.',
        'si': '$pct% සාමාන්‍යයට වඩා — විශිෂ්ට වගා තත්ත්ව.',
        'ta': '$pct% சராசரிக்கு மேல் — சிறந்த வளரும் நிலைமைகள்.',
      });
    }
    if (pct >= 0) {
      return _ts({
        'en': '$pct% above average — good conditions expected.',
        'si': '$pct% සාමාන්‍යයට වඩා — හොඳ තත්ත්ව.',
        'ta': '$pct% சராசரிக்கு மேல் — நல்ல நிலைமைகள் எதிர்பார்க்கப்படுகின்றன.',
      });
    }
    if (pct >= -15) {
      return _ts({
        'en':
            '${pct.abs()}% below average — consider improving soil inputs or irrigation.',
        'si':
            '${pct.abs()}% සාමාන්‍යයට අඩු — පස ආදාන හෝ ජලනය වැඩිදියුණු කිරීම සලකන්න.',
        'ta':
            '${pct.abs()}% சராசரிக்கு கீழ் — மண் உள்ளீடுகள் அல்லது நீர்ப்பாசனம் மேம்படுத்துவதை பரிசீலிக்கவும்.',
      });
    }
    return _ts({
      'en':
          '${pct.abs()}% below average — review your soil, weather and crop management inputs.',
      'si':
          '${pct.abs()}% සාමාන්‍යයට අඩු — පස, කාලගුණ හා භෝග කළමනාකරණ ආදාන සමාලෝචනය කරන්න.',
      'ta':
          '${pct.abs()}% சராசரிக்கு கீழ் — மண், வானிலை மற்றும் பயிர் மேலாண்மை உள்ளீடுகளை மதிப்பாய்வு செய்யுங்கள்.',
    });
  }

  bool get _isAboveAverage {
    if (_result == null) return true;
    final avg = _result!['average'] as double? ?? 0.0;
    return (_result!['yield'] as double) >= avg;
  }

  Color _resultColor(double yieldVal) {
    final avg = _result!['average'] as double? ?? yieldVal;
    final pct = (yieldVal - avg) / avg * 100;
    if (pct >= 10) return AppTheme.success;
    if (pct >= -10) return AppTheme.warning;
    return AppTheme.error;
  }

  Color _confColor(String c) => switch (c.toLowerCase()) {
        'high' => AppTheme.success,
        'medium' => AppTheme.warning,
        _ => AppTheme.error,
      };

  // ── AI Chat context string ─────────────────────────────────────────────────
  String _buildAiContext() {
    final yieldVal = (_result!['yield'] as double).toStringAsFixed(0);
    final avg = (_result!['average'] as double? ?? 0.0).toStringAsFixed(0);
    final conf = _result!['confidence'] as String;
    return 'My yield prediction for $_selectedCrop in $_selectedDistrict '
        '($_selectedSeason season, $_selectedIrrigation irrigation, '
        '${_areaPerches.toStringAsFixed(0)} perches): '
        '$yieldVal kg/ha predicted vs $avg kg/ha average. '
        'Confidence: $conf. '
        'Please give me detailed advice to improve my yield and explain what factors are affecting it.';
  }

  // ══════════════════════════════════════════════════════════════════════════
  //  BUILD
  // ══════════════════════════════════════════════════════════════════════════
  @override
  Widget build(BuildContext context) {
    AppLangProvider.of(context);
    return LayoutBuilder(
      builder: (ctx, bc) {
        final w = bc.maxWidth;
        return Column(
          children: [
            _buildTopBar(context),
            Expanded(
              child: w >= 960
                  ? _buildWebLayout()
                  : w >= 600
                      ? _buildTabletLayout()
                      : _buildMobileLayout(),
            ),
          ],
        );
      },
    );
  }

  // ── Top bar ────────────────────────────────────────────────────────────────
  Widget _buildTopBar(BuildContext context) {
    final lang = AppLangProvider.lang(context);
    final List<String> navLabels = lang == AppLang.si
        ? ['ඩෑෂ්', 'අස්වැන්න', 'මිල', 'කාලගුණ', 'භෝග', 'ඉල්ලුම', 'AI']
        : lang == AppLang.ta
            ? ['முகப்பு', 'விளைச்சல்', 'விலை', 'வானிலை', 'பயிர்', 'தேவை', 'AI']
            : [
                'Dashboard',
                'Yield',
                'Price',
                'Weather',
                'Crop Rec.',
                'Demand',
                'AI Chat',
              ];

    const activeBg = Color(0xFFE8F5E9);
    const activeColor = Color(0xFF2E7D32);

    return Container(
      height: 60,
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Color(0xFFE4EEE4))),
        boxShadow: [
          BoxShadow(
            color: Color(0x0A000000),
            blurRadius: 6,
            offset: Offset(0, 2),
          ),
        ],
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: const Color(0xFF4CAF50).withValues(alpha: 0.15),
            ),
            child: Center(
              child: SvgPicture.string(_cropSphereSvg, width: 32, height: 32),
            ),
          ),
          const SizedBox(width: 10),
          const Text(
            'CropSphere',
            style: TextStyle(
              color: Color(0xFF1B4D1B),
              fontSize: 17,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.3,
            ),
          ),
          Expanded(
            child: Center(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: List.generate(navLabels.length, (i) {
                    final active = i == 1;
                    return Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 2),
                      child: TextButton(
                        onPressed: widget.onNavigate == null
                            ? null
                            : () => widget.onNavigate!(i),
                        style: TextButton.styleFrom(
                          backgroundColor:
                              active ? activeBg : Colors.transparent,
                          foregroundColor:
                              active ? activeColor : const Color(0xFF555555),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 11,
                            vertical: 6,
                          ),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        child: Text(
                          navLabels[i],
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight:
                                active ? FontWeight.w700 : FontWeight.w500,
                          ),
                        ),
                      ),
                    );
                  }),
                ),
              ),
            ),
          ),
          _LangPill(),
        ],
      ),
    );
  }

  // ── Layout helpers ─────────────────────────────────────────────────────────
  Widget _buildMobileLayout() => Stack(
        children: [
          SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 100),
            child: _formColumn(),
          ),
          _stickyPredict(),
        ],
      );

  Widget _buildTabletLayout() => Stack(
        children: [
          LayoutBuilder(
            builder: (ctx, bc) {
              final hPad = ((bc.maxWidth - 700) / 2).clamp(0.0, 200.0);
              return SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(hPad + 16, 14, hPad + 16, 100),
                child: _formColumn(),
              );
            },
          ),
          _stickyPredict(),
        ],
      );

  Widget _buildWebLayout() => LayoutBuilder(
        builder: (ctx, bc) {
          final leftW = (bc.maxWidth * 0.45).clamp(340.0, 520.0);
          return Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                width: leftW,
                child: Stack(
                  children: [
                    SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(20, 14, 12, 100),
                      child: _formColumn(webLeft: true),
                    ),
                    _stickyPredict(),
                  ],
                ),
              ),
              Container(width: 1, color: const Color(0xFFE4EEE4)),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(16, 14, 20, 28),
                  child: _rightPanel(),
                ),
              ),
            ],
          );
        },
      );

  // ── Form column ────────────────────────────────────────────────────────────
  Widget _formColumn({bool webLeft = false}) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _pageHeader(),
          const SizedBox(height: 16),
          _cropQuickChips(),
          const SizedBox(height: 16),
          _sectionTitle(
            _ts({
              'en': 'Crop & Location',
              'si': 'භෝගය හා ස්ථානය',
              'ta': 'பயிர் மற்றும் இடம்',
            }),
            Icons.eco,
          ),
          const SizedBox(height: 10),
          _cropLocationCard(),
          const SizedBox(height: 20),
          _sectionTitle(
            _ts({
              'en': 'Farm Area',
              'si': 'ගොවිපොළ ප්‍රමාණය',
              'ta': 'பண்ணை பரப்பளவு',
            }),
            Icons.crop_square,
          ),
          const SizedBox(height: 10),
          _areaCard(),
          const SizedBox(height: 20),
          _sectionTitle(
            _ts({
              'en': 'Weather Conditions',
              'si': 'කාලගුණ තත්ත්වය',
              'ta': 'வானிலை நிலைமைகள்',
            }),
            Icons.cloud,
          ),
          const SizedBox(height: 10),
          _weatherCard(),
          const SizedBox(height: 20),
          _sectionTitle(
            _ts({
              'en': 'Soil & Management Guide',
              'si': 'පස හා කළමනාකරණ මාර්ගෝපදේශය',
              'ta': 'மண் மற்றும் மேலாண்மை வழிகாட்டி',
            }),
            Icons.science,
          ),
          const SizedBox(height: 10),
          _soilCard(),
          if (!webLeft) ...[
            const SizedBox(height: 16),
            _inputChecklist(),
            const SizedBox(height: 10),
            if (_errorMessage != null) _errorCard(),
            if (_result != null) _resultCard(),
          ],
        ],
      );

  Widget _rightPanel() => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _inputChecklist(),
          const SizedBox(height: 14),
          if (_errorMessage != null) ...[
            _errorCard(),
            const SizedBox(height: 14)
          ],
          if (_result != null) ...[_resultCard(), const SizedBox(height: 14)],
          if (_result == null && _errorMessage == null)
            _emptyResultPlaceholder(),
        ],
      );

  // ── Page header ────────────────────────────────────────────────────────────
  Widget _pageHeader() => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [AppTheme.primaryDark, AppTheme.primary],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: AppTheme.primaryDark.withValues(alpha: 0.3),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: SvgPicture.string(
                _navSvg(1, Colors.white),
                width: 26,
                height: 26,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _ts({
                      'en': 'Yield Predictor',
                      'si': 'අස්වැන්න පුරෝකථකය',
                      'ta': 'விளைச்சல் கணிப்பான்',
                    }),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    _ts({
                      'en': 'AI-powered harvest estimate',
                      'si': 'AI-ශක්තිමත් අස්වැන්න ඇස්තමේන්තුව',
                      'ta': 'AI-சார்ந்த அறுவடை மதிப்பீடு',
                    }),
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.75),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                'Week ${_weekOfYear()}',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      );

  // ── Crop quick chips ───────────────────────────────────────────────────────
  Widget _cropQuickChips() => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _ts({
              'en': 'Quick select:',
              'si': 'ඉක්මන් තේරීම:',
              'ta': 'விரைவு தேர்வு:',
            }),
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: AppTheme.textMuted,
            ),
          ),
          const SizedBox(height: 7),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: CropSphereConstants.crops.map((crop) {
              final active = _selectedCrop == crop;
              final emoji = _cropEmoji[crop] ?? '🌿';
              return GestureDetector(
                onTap: () => setState(() {
                  _selectedCrop = crop;
                  _selectedDistrict = null;
                  _result = null;
                  _fertExpanded = false;
                  _pestExpanded = false;
                }),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                  decoration: BoxDecoration(
                    color: active ? AppTheme.primary : Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color:
                          active ? AppTheme.primary : const Color(0xFFD0E8C8),
                      width: active ? 2 : 1.5,
                    ),
                    boxShadow: active
                        ? [
                            BoxShadow(
                              color: AppTheme.primary.withValues(alpha: 0.2),
                              blurRadius: 6,
                              offset: const Offset(0, 2),
                            ),
                          ]
                        : [],
                  ),
                  child: Text(
                    '$emoji  $crop',
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: active ? Colors.white : AppTheme.textPrimary,
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      );

  // ── Crop & location card ───────────────────────────────────────────────────
  Widget _cropLocationCard() => _card(
        child: Column(
          children: [
            _nullDropdown(
              label: _ts({
                'en': 'Select Crop',
                'si': 'භෝගය තෝරන්න',
                'ta': 'பயிர் தேர்ந்தெடுக்கவும்',
              }),
              value: _selectedCrop,
              items: CropSphereConstants.crops,
              icon: Icons.eco,
              onChanged: (val) => setState(() {
                _selectedCrop = val;
                _selectedDistrict = null;
                _result = null;
                _fertExpanded = false;
                _pestExpanded = false;
              }),
            ),
            const SizedBox(height: 12),
            _nullDropdown(
              label: _ts({
                'en': 'Select District',
                'si': 'දිස්ත්‍රික්කය',
                'ta': 'மாவட்டம்',
              }),
              value: _selectedDistrict,
              items: _availableDistricts,
              icon: Icons.location_on,
              hint: _selectedCrop != null
                  ? _ts({
                      'en': 'Valid districts for $_selectedCrop',
                      'si': '$_selectedCrop සඳහා දිස්ත්‍රික්ක',
                      'ta': '$_selectedCrop-க்கான மாவட்டங்கள்',
                    })
                  : _ts({
                      'en': 'Select a crop first',
                      'si': 'පළමු භෝගය තෝරන්න',
                      'ta': 'முதலில் பயிர் தேர்ந்தெடுக்கவும்',
                    }),
              enabled: _selectedCrop != null,
              onChanged: (val) {
                setState(() {
                  _selectedDistrict = val;
                  _weather = null;
                  _result = null;
                });
                if (val != null) _loadWeather(val);
              },
            ),
            const SizedBox(height: 12),
            _seasonDropdown(),
            const SizedBox(height: 12),
            _irrigationDropdown(),
          ],
        ),
      );

  Widget _seasonDropdown() {
    // find label+desc for selected season
    final sel = _selectedSeason != null
        ? _seasons.firstWhere(
            (s) => s['name']!['en'] == _selectedSeason,
            orElse: () => _seasons[0],
          )
        : null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DropdownButtonFormField<String>(
          initialValue: _selectedSeason,
          hint: Text(
            _ts({'en': 'Select Season', 'si': 'කන්නය', 'ta': 'பருவம்'}),
            style: const TextStyle(color: AppTheme.textMuted),
          ),
          decoration: InputDecoration(
            labelText: _ts({'en': 'Season', 'si': 'කන්නය', 'ta': 'பருவம்'}),
            prefixIcon: const Icon(
              Icons.calendar_month,
              color: AppTheme.primary,
              size: 20,
            ),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 10,
            ),
          ),
          items: _seasons
              .map(
                (s) => DropdownMenuItem<String>(
                  value: s['name']!['en'],
                  child: Text(
                    '${_t(s['name']!)}  ·  ${_t(s['months']!)}',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              )
              .toList(),
          onChanged: (val) => setState(() {
            _selectedSeason = val;
            _result = null;
          }),
        ),
        if (sel != null) ...[
          const SizedBox(height: 8),
          _infoBox(
            _t(sel['desc']!),
            color: AppTheme.primary,
            icon: Icons.info_outline,
          ),
        ],
      ],
    );
  }

  Widget _irrigationDropdown() {
    final sel = _selectedIrrigation != null
        ? _irrigationTypes.firstWhere(
            (t) => t['value']!['en'] == _selectedIrrigation,
            orElse: () => _irrigationTypes[0],
          )
        : null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DropdownButtonFormField<String>(
          initialValue: _selectedIrrigation,
          hint: Text(
            _ts({
              'en': 'Select Irrigation',
              'si': 'ජලනය',
              'ta': 'நீர்ப்பாசனம்',
            }),
            style: const TextStyle(color: AppTheme.textMuted),
          ),
          decoration: InputDecoration(
            labelText: _ts({
              'en': 'Irrigation Type',
              'si': 'ජලනය වර්ගය',
              'ta': 'நீர்ப்பாசன வகை',
            }),
            prefixIcon: const Icon(
              Icons.water_drop,
              color: AppTheme.primary,
              size: 20,
            ),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 10,
            ),
          ),
          items: _irrigationTypes
              .map(
                (t) => DropdownMenuItem<String>(
                  value: t['value']!['en'],
                  child: Text(
                    _t(t['label']!),
                    style: const TextStyle(fontSize: 14),
                  ),
                ),
              )
              .toList(),
          onChanged: (val) => setState(() {
            _selectedIrrigation = val;
            _result = null;
          }),
        ),
        if (sel != null) ...[
          const SizedBox(height: 8),
          _infoBox(
            _t(sel['desc']!),
            color: Colors.blue,
            icon: Icons.water_drop_outlined,
          ),
        ],
      ],
    );
  }

  // ──────────────────────────────────────────────────────────────────────────
  //  (ii) Area card — three manual text fields, no slider
  // ──────────────────────────────────────────────────────────────────────────
  Widget _areaCard() => _card(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.crop_square,
                    size: 15, color: AppTheme.primary),
                const SizedBox(width: 6),
                Text(
                  _ts({
                    'en': 'Cultivated Area',
                    'si': 'වගා කළ ප්‍රදේශය',
                    'ta': 'பயிரிடப்பட்ட பரப்பளவு',
                  }),
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.primaryDark,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              _ts({
                'en': 'Enter any one — the others update automatically.',
                'si':
                    'ඕනෑම එකක් ඇතුළු කරන්න — අනිත් ඒවා ස්වයංක්‍රීයව යාවත්කාලීන වේ.',
                'ta':
                    'ஏதேனும் ஒன்றை உள்ளிடுங்கள் — மற்றவை தானாக புதுப்பிக்கப்படும்.',
              }),
              style: const TextStyle(fontSize: 11, color: AppTheme.textMuted),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: _areaField(
                    controller: _perchesCtrl,
                    label: _ts({'en': 'Perches', 'si': 'පර්ච', 'ta': 'பர்ச்'}),
                    color: AppTheme.primary,
                    isMain: true,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _areaField(
                    controller: _acresCtrl,
                    label: _ts({'en': 'Acres', 'si': 'අක්කර', 'ta': 'ஏக்கர்'}),
                    color: const Color(0xFF1565C0),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _areaField(
                    controller: _hectCtrl,
                    label: _ts({
                      'en': 'Hectares',
                      'si': 'හෙක්ටෙයාර්',
                      'ta': 'ஹெக்டேர்',
                    }),
                    color: const Color(0xFF558B2F),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            _infoBox(
              _ts({
                'en': '1 acre = 160 perches · 1 hectare = 395 perches',
                'si': '1 අක්කර = 160 පර්ච · 1 හෙක්ටෙයාර් = 395 පර්ච',
                'ta': '1 ஏக்கர் = 160 பர்ச் · 1 ஹெக்டேர் = 395 பர்ச்',
              }),
              color: AppTheme.info,
              icon: Icons.info_outline,
            ),
          ],
        ),
      );

  Widget _areaField({
    required TextEditingController controller,
    required String label,
    required Color color,
    bool isMain = false,
  }) =>
      TextField(
        controller: controller,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[\d.]'))],
        style: TextStyle(
          fontSize: isMain ? 20 : 15,
          fontWeight: FontWeight.bold,
          color: color,
        ),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: TextStyle(
            fontSize: 11,
            color: color,
            fontWeight: FontWeight.w600,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(
              color: color.withValues(alpha: 0.3),
              width: isMain ? 2 : 1.2,
            ),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: color, width: 2),
          ),
          filled: true,
          fillColor: color.withValues(alpha: 0.05),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        ),
      );

  // ── Weather card ───────────────────────────────────────────────────────────
  Widget _weatherCard() {
    if (_selectedDistrict == null) {
      return _card(
        child: Row(
          children: [
            Icon(
              Icons.location_on_outlined,
              size: 30,
              color: AppTheme.textMuted.withValues(alpha: 0.4),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                _ts({
                  'en': 'Select a district first to auto-load live weather.',
                  'si':
                      'ජීවිත කාලගුණ ස්වයංක්‍රීයව පූරණය කිරීමට දිස්ත්‍රික්කය තෝරන්න.',
                  'ta': 'நேரடி வானிலை தானாக ஏற்ற மாவட்டம் தேர்ந்தெடுக்கவும்.',
                }),
                style: const TextStyle(
                  fontSize: 13,
                  color: AppTheme.textMuted,
                  height: 1.4,
                ),
              ),
            ),
          ],
        ),
      );
    }

    if (_weatherLoading) {
      return _card(
        child: Row(
          children: [
            const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: AppTheme.primary,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                _ts({
                  'en': 'Loading live weather for $_selectedDistrict...',
                  'si': '$_selectedDistrict හි කාලගුණ පූරණය වෙමින්...',
                  'ta': '$_selectedDistrict வானிலை ஏற்றுகிறோம்...',
                }),
                style: const TextStyle(
                  fontSize: 13,
                  color: AppTheme.textSecondary,
                ),
              ),
            ),
          ],
        ),
      );
    }

    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            decoration: BoxDecoration(
              color: _weatherError != null
                  ? AppTheme.warning.withValues(alpha: 0.08)
                  : AppTheme.success.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: _weatherError != null
                    ? AppTheme.warning.withValues(alpha: 0.25)
                    : AppTheme.success.withValues(alpha: 0.25),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  _weatherError != null
                      ? Icons.warning_amber_rounded
                      : Icons.check_circle_outline,
                  size: 16,
                  color: _weatherError != null
                      ? AppTheme.warning
                      : AppTheme.success,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _weatherError ??
                        _ts({
                          'en':
                              'Live weather auto-loaded for $_selectedDistrict (Open-Meteo)',
                          'si':
                              '$_selectedDistrict ස්වයංක්‍රීයව Open-Meteo වෙතින් කාලගුණ',
                          'ta':
                              '$_selectedDistrict-க்கான நேரடி வானிலை Open-Meteo இல் ஏற்றப்பட்டது',
                        }),
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      color: _weatherError != null
                          ? AppTheme.warning
                          : AppTheme.success,
                    ),
                  ),
                ),
                if (_weatherError == null)
                  GestureDetector(
                    onTap: () => _loadWeather(_selectedDistrict!),
                    child: Container(
                      padding: const EdgeInsets.all(5),
                      decoration: BoxDecoration(
                        color: AppTheme.success.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Icon(
                        Icons.refresh,
                        size: 15,
                        color: AppTheme.success,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          if (_weather != null && !_weatherOverrideOpen) ...[
            const SizedBox(height: 12),
            _weatherGrid(_weather!),
          ],
          const SizedBox(height: 10),
          GestureDetector(
            onTap: () =>
                setState(() => _weatherOverrideOpen = !_weatherOverrideOpen),
            child: Row(
              children: [
                Icon(
                  _weatherOverrideOpen ? Icons.expand_less : Icons.tune,
                  size: 15,
                  color: AppTheme.textSecondary,
                ),
                const SizedBox(width: 6),
                Text(
                  _weatherOverrideOpen
                      ? _ts({
                          'en': 'Hide manual override',
                          'si': 'අතින් ඇතුළත් කිරීම සඟවන්න',
                          'ta': 'கைமுறை மேலெழுத்தை மறைக்கவும்',
                        })
                      : _ts({
                          'en': 'Override weather manually',
                          'si': 'කාලගුණ අතින් වෙනස් කරන්න',
                          'ta': 'கைமுறையாக வானிலை மாற்றவும்',
                        }),
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppTheme.textSecondary,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          if (_weatherOverrideOpen) ...[
            const SizedBox(height: 12),
            _infoBox(
              _ts({
                'en':
                    'You are overriding auto-fetched weather. These values will be used for prediction.',
                'si': 'ස්වයංක්‍රීය කාලගුණ ඉවත් කර ඔබගේ අගයන් භාවිත කෙරේ.',
                'ta':
                    'தானியங்கி வானிலை மேலெழுதப்படுகிறது. இந்த மதிப்புகள் கணிப்பிற்கு பயன்படுத்தப்படும்.',
              }),
              color: AppTheme.warning,
              icon: Icons.warning_amber_rounded,
            ),
            const SizedBox(height: 10),
            _weatherSlider(
              _ts({'en': 'Rainfall', 'si': 'වර්ෂාපතනය', 'ta': 'மழை'}),
              _oRainfall,
              0,
              300,
              'mm',
              Colors.blue,
              (v) => setState(() => _oRainfall = v),
            ),
            _weatherSlider(
              _ts({
                'en': 'Min Temperature',
                'si': 'අවම උෂ්ණත්වය',
                'ta': 'குறைந்தபட்ச வெப்பம்',
              }),
              _oTempMin,
              5,
              35,
              '°C',
              Colors.lightBlue,
              (v) => setState(() => _oTempMin = v),
            ),
            _weatherSlider(
              _ts({
                'en': 'Max Temperature',
                'si': 'උපරිම උෂ්ණත්වය',
                'ta': 'அதிகபட்ச வெப்பம்',
              }),
              _oTempMax,
              10,
              45,
              '°C',
              Colors.orange,
              (v) => setState(() => _oTempMax = v),
            ),
            _weatherSlider(
              _ts({'en': 'Humidity', 'si': 'ආර්ද්‍රතාව', 'ta': 'ஈரப்பதம்'}),
              _oHumidity,
              20,
              100,
              '%',
              Colors.teal,
              (v) => setState(() => _oHumidity = v),
            ),
            _weatherSlider(
              _ts({
                'en': 'Wind Speed',
                'si': 'සුළං වේගය',
                'ta': 'காற்று வேகம்',
              }),
              _oWindSpeed,
              0,
              80,
              'km/h',
              Colors.blueGrey,
              (v) => setState(() => _oWindSpeed = v),
            ),
            _weatherSlider(
              _ts({
                'en': 'Solar Radiation',
                'si': 'සූර්ය විකිරණ',
                'ta': 'சூரிய கதிர்வீச்சு',
              }),
              _oSolarRad,
              5,
              35,
              'MJ',
              Colors.amber,
              (v) => setState(() => _oSolarRad = v),
            ),
          ],
        ],
      ),
    );
  }

  Widget _weatherGrid(_WeatherData w) {
    final tiles = [
      _WTile(
        '🌧',
        _ts({'en': 'Rain', 'si': 'වර්ෂාව', 'ta': 'மழை'}),
        '${w.rainfallMm.toStringAsFixed(1)} mm',
        Colors.blue,
      ),
      _WTile(
        '🌡',
        _ts({'en': 'Min Temp', 'si': 'අවම', 'ta': 'குறை'}),
        '${w.tempMinC.toStringAsFixed(1)}°C',
        Colors.lightBlue,
      ),
      _WTile(
        '☀️',
        _ts({'en': 'Max Temp', 'si': 'උපරිම', 'ta': 'அதிக'}),
        '${w.tempMaxC.toStringAsFixed(1)}°C',
        Colors.orange,
      ),
      _WTile(
        '💧',
        _ts({'en': 'Humidity', 'si': 'ආර්ද්‍රතා', 'ta': 'ஈரம்'}),
        '${w.humidityPct.toStringAsFixed(0)}%',
        Colors.teal,
      ),
      _WTile(
        '🌬',
        _ts({'en': 'Wind', 'si': 'සුළං', 'ta': 'காற்று'}),
        '${w.windSpeedKmh.toStringAsFixed(1)} km/h',
        Colors.blueGrey,
      ),
      _WTile(
        '⚡',
        _ts({'en': 'Solar', 'si': 'සූර්ය', 'ta': 'சூரிய'}),
        '${w.solarRadMj.toStringAsFixed(1)} MJ',
        Colors.amber,
      ),
    ];
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
        childAspectRatio: 1.6,
      ),
      itemCount: tiles.length,
      itemBuilder: (_, i) {
        final t = tiles[i];
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          decoration: BoxDecoration(
            color: t.color.withValues(alpha: 0.07),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: t.color.withValues(alpha: 0.2)),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(t.emoji, style: const TextStyle(fontSize: 16)),
              const SizedBox(height: 3),
              Text(
                t.value,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: t.color,
                ),
              ),
              Text(
                t.label,
                style: TextStyle(
                  fontSize: 9,
                  color: t.color.withValues(alpha: 0.8),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // ── Soil card — DOA Guidelines badge removed (iv) ──────────────────────────
  Widget _soilCard() {
    if (_selectedCrop == null) {
      return _card(
        child: Row(
          children: [
            Icon(
              Icons.eco_outlined,
              size: 30,
              color: AppTheme.textMuted.withValues(alpha: 0.4),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                _ts({
                  'en':
                      'Select a crop to see soil conditions and practical farming instructions.',
                  'si': 'පස තත්ත්වය හා ගොවිතැන් උපදෙස් දැකීමට භෝගය තෝරන්න.',
                  'ta':
                      'மண் நிலைமைகள் மற்றும் விவசாய வழிமுறைகளைக் காண பயிர் தேர்ந்தெடுக்கவும்.',
                }),
                style: const TextStyle(
                  fontSize: 13,
                  color: AppTheme.textMuted,
                  height: 1.4,
                ),
              ),
            ),
          ],
        ),
      );
    }

    final rec = _activeSoilRec!;
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.surfaceCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE0EBE0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header — no DOA badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: AppTheme.primary.withValues(alpha: 0.07),
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(12),
              ),
              border: const Border(
                bottom: BorderSide(color: Color(0xFFE0EBE0)),
              ),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.auto_awesome,
                  size: 16,
                  color: AppTheme.primary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _ts({
                      'en': 'Guide for $_selectedCrop',
                      'si': '$_selectedCrop සඳහා මාර්ගෝපදේශය',
                      'ta': '$_selectedCrop-க்கான வழிகாட்டி',
                    }),
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.primary,
                    ),
                  ),
                ),
                // ── (iv): DOA Guidelines badge removed ──
              ],
            ),
          ),

          Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _t(rec.summary),
                  style: const TextStyle(
                    fontSize: 13,
                    color: AppTheme.textPrimary,
                    height: 1.55,
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _conditionTile(
                        label: _ts({
                          'en': 'Soil pH',
                          'si': 'පස pH',
                          'ta': 'மண் pH',
                        }),
                        value: rec.soilPh.toStringAsFixed(1),
                        unit: 'pH',
                        icon: Icons.science,
                        color: Colors.purple,
                        note: _t(rec.phNote),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _conditionTile(
                        label: _ts({
                          'en': 'Moisture',
                          'si': 'ආර්ද්‍රතාව',
                          'ta': 'ஈரம்',
                        }),
                        value: rec.soilMoisturePct.toStringAsFixed(0),
                        unit: '%',
                        icon: Icons.water_drop_outlined,
                        color: Colors.cyan,
                        note: _t(rec.moistureNote),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                _npkBar(rec),
                const SizedBox(height: 12),
                _collapsibleSection(
                  icon: Icons.grass,
                  color: const Color(0xFF2E7D32),
                  title: _ts({
                    'en': 'Fertilizer Mixing Guide',
                    'si': 'පොහොර මිශ්‍රණ මාර්ගෝපදේශය',
                    'ta': 'உர கலவை வழிகாட்டி',
                  }),
                  badge: '${rec.fertilizers.length} ${_ts({
                        'en': 'fertilizers',
                        'si': 'පොහොර',
                        'ta': 'உரங்கள்'
                      })}',
                  isOpen: _fertExpanded,
                  onToggle: () =>
                      setState(() => _fertExpanded = !_fertExpanded),
                  child: Column(
                    children: rec.fertilizers.map((f) => _chemCard(f)).toList(),
                  ),
                ),
                const SizedBox(height: 10),
                _collapsibleSection(
                  icon: Icons.bug_report,
                  color: const Color(0xFFC62828),
                  title: _ts({
                    'en': 'Pesticide & Spray Guide',
                    'si': 'පළිබෝධනාශක ස්ප්‍රේ මාර්ගෝපදේශය',
                    'ta': 'பூச்சிக்கொல்லி தெளிப்பு வழிகாட்டி',
                  }),
                  badge: '${rec.pesticides.length} ${_ts({
                        'en': 'products',
                        'si': 'නිෂ්පාදන',
                        'ta': 'தயாரிப்புகள்'
                      })}',
                  isOpen: _pestExpanded,
                  onToggle: () =>
                      setState(() => _pestExpanded = !_pestExpanded),
                  child: Column(
                    children: rec.pesticides.map((p) => _chemCard(p)).toList(),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _collapsibleSection({
    required IconData icon,
    required Color color,
    required String title,
    required String badge,
    required bool isOpen,
    required VoidCallback onToggle,
    required Widget child,
  }) =>
      Container(
        decoration: BoxDecoration(
          border: Border.all(color: color.withValues(alpha: 0.2)),
          borderRadius: BorderRadius.circular(10),
          color: color.withValues(alpha: 0.03),
        ),
        child: Column(
          children: [
            InkWell(
              onTap: onToggle,
              borderRadius: BorderRadius.circular(10),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
                child: Row(
                  children: [
                    Container(
                      width: 30,
                      height: 30,
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(icon, size: 16, color: color),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        title,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: color,
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        badge,
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: color,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Icon(
                      isOpen ? Icons.expand_less : Icons.expand_more,
                      size: 18,
                      color: color,
                    ),
                  ],
                ),
              ),
            ),
            if (isOpen)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                child: child,
              ),
          ],
        ),
      );

  Widget _chemCard(_ChemicalInstruction c) => Container(
        margin: const EdgeInsets.only(top: 10),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: c.color.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: c.color.withValues(alpha: 0.18)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: c.color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(c.icon, size: 16, color: c.color),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        c.name,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          color: c.color,
                        ),
                      ),
                      Text(
                        _t(c.purpose),
                        style: const TextStyle(
                          fontSize: 11,
                          color: AppTheme.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            _instrRow(
              icon: Icons.straighten,
              label: _ts({'en': 'Dose', 'si': 'ප්‍රමාණය', 'ta': 'அளவு'}),
              value: _t(c.dose),
              color: c.color,
              highlight: true,
            ),
            const SizedBox(height: 6),
            _instrRow(
              icon: Icons.water_drop_outlined,
              label: _ts({
                'en': 'How to mix & apply',
                'si': 'මිශ්‍ර කර යෙදීම',
                'ta': 'கலந்து பயன்படுத்துவது',
              }),
              value: _t(c.method),
              color: c.color,
            ),
            const SizedBox(height: 6),
            _instrRow(
              icon: Icons.schedule,
              label: _ts({
                'en': 'When to apply',
                'si': 'යෙදිය යුතු කාලය',
                'ta': 'எப்போது பயன்படுத்துவது',
              }),
              value: _t(c.timing),
              color: c.color,
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: AppTheme.error.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(8),
                border:
                    Border.all(color: AppTheme.error.withValues(alpha: 0.2)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.warning_amber_rounded,
                    size: 14,
                    color: AppTheme.error,
                  ),
                  const SizedBox(width: 7),
                  Expanded(
                    child: Text(
                      _t(c.caution),
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppTheme.error,
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );

  Widget _instrRow({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
    bool highlight = false,
  }) =>
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 6),
          Expanded(
            child: RichText(
              text: TextSpan(
                children: [
                  TextSpan(
                    text: '$label: ',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: color,
                    ),
                  ),
                  TextSpan(
                    text: value,
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: highlight ? FontWeight.w800 : FontWeight.w400,
                      color: highlight ? color : AppTheme.textPrimary,
                      height: 1.45,
                      backgroundColor:
                          highlight ? color.withValues(alpha: 0.08) : null,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      );

  Widget _conditionTile({
    required String label,
    required String value,
    required String unit,
    required IconData icon,
    required Color color,
    required String note,
  }) =>
      Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withValues(alpha: 0.2)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 13, color: color),
                const SizedBox(width: 5),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: color,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              '$value $unit',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              note,
              style: const TextStyle(
                fontSize: 10,
                color: AppTheme.textSecondary,
                height: 1.4,
              ),
            ),
          ],
        ),
      );

  Widget _npkBar(_SoilRec rec) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFFF4F9F4),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xFFCCE3CC)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.biotech,
                    size: 14, color: AppTheme.textSecondary),
                const SizedBox(width: 6),
                Text(
                  'NPK',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.textSecondary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: _npkTile(
                    'N',
                    rec.nIndex,
                    Colors.indigo,
                    _ts({
                      'en': 'Nitrogen',
                      'si': 'නයිට්‍රජන්',
                      'ta': 'நைட்ரஜன்'
                    }),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _npkTile(
                    'P',
                    rec.pIndex,
                    Colors.deepOrange,
                    _ts({
                      'en': 'Phosphorus',
                      'si': 'පොස්පරස්',
                      'ta': 'பாஸ்பரஸ்'
                    }),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _npkTile(
                    'K',
                    rec.kIndex,
                    Colors.amber,
                    _ts({
                      'en': 'Potassium',
                      'si': 'පොටෑසියම්',
                      'ta': 'பொட்டாசியம்',
                    }),
                  ),
                ),
              ],
            ),
          ],
        ),
      );

  Widget _npkTile(String sym, double idx, Color color, String name) =>
      Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withValues(alpha: 0.25)),
        ),
        child: Column(
          children: [
            Text(
              sym,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '${(idx * 100).toStringAsFixed(0)}%',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: color,
              ),
            ),
            Text(
              name,
              style: const TextStyle(fontSize: 9, color: AppTheme.textMuted),
            ),
          ],
        ),
      );

  // ── Input checklist ────────────────────────────────────────────────────────
  Widget _inputChecklist() {
    final items = [
      (
        _selectedCrop != null,
        _ts({'en': 'Crop selected', 'si': 'භෝගය', 'ta': 'பயிர்'}),
        _selectedCrop ?? '',
      ),
      (
        _selectedDistrict != null,
        _ts({
          'en': 'District selected',
          'si': 'දිස්ත්‍රික්කය',
          'ta': 'மாவட்டம்',
        }),
        _selectedDistrict ?? '',
      ),
      (
        _selectedSeason != null,
        _ts({'en': 'Season selected', 'si': 'කන්නය', 'ta': 'பருவம்'}),
        _selectedSeason ?? '',
      ),
      (
        _selectedIrrigation != null,
        _ts({'en': 'Irrigation selected', 'si': 'ජලනය', 'ta': 'நீர்ப்பாசனம்'}),
        _selectedIrrigation ?? '',
      ),
    ];
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _canPredict
            ? AppTheme.success.withValues(alpha: 0.06)
            : const Color(0xFFFFF8E1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: _canPredict
              ? AppTheme.success.withValues(alpha: 0.2)
              : const Color(0xFFFFE082),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                _canPredict ? Icons.check_circle : Icons.checklist,
                size: 15,
                color: _canPredict ? AppTheme.success : AppTheme.warning,
              ),
              const SizedBox(width: 7),
              Text(
                _canPredict
                    ? _ts({
                        'en': 'Ready to predict!',
                        'si': 'පුරෝකථනයට සූදානම්!',
                        'ta': 'கணிக்க தயார்!',
                      })
                    : _ts({
                        'en': 'Complete these to predict:',
                        'si': 'පුරෝකථනය සඳහා සම්පූර්ණ කරන්න:',
                        'ta': 'கணிக்க இவற்றை நிறைவு செய்யுங்கள்:',
                      }),
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: _canPredict ? AppTheme.success : AppTheme.warning,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ...items.map(
            (item) => Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                children: [
                  Icon(
                    item.$1 ? Icons.check_circle : Icons.radio_button_unchecked,
                    size: 15,
                    color: item.$1 ? AppTheme.success : const Color(0xFFBDBDBD),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    item.$2,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color:
                          item.$1 ? AppTheme.textPrimary : AppTheme.textMuted,
                    ),
                  ),
                  if (item.$1 && item.$3.isNotEmpty) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: AppTheme.success.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        item.$3,
                        style: const TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.success,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Sticky predict button ──────────────────────────────────────────────────
  Widget _stickyPredict() => Positioned(
        bottom: 0,
        left: 0,
        right: 0,
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
          decoration: BoxDecoration(
            color: Colors.white,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.08),
                blurRadius: 12,
                offset: const Offset(0, -3),
              ),
            ],
          ),
          child: SafeArea(
            top: false,
            child: SizedBox(
              height: 52,
              child: ElevatedButton.icon(
                onPressed: (_isLoading || !_canPredict) ? null : _predict,
                icon: _isLoading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.analytics),
                label: Text(
                  _isLoading
                      ? _ts({
                          'en': 'Predicting...',
                          'si': 'පුරෝකථනය...',
                          'ta': 'கணிக்கிறோம்...',
                        })
                      : _canPredict
                          ? _ts({
                              'en': 'Predict My Yield',
                              'si': 'මගේ අස්වැන්න පුරෝකථනය',
                              'ta': 'எனது விளைச்சலை கணிக்கவும்',
                            })
                          : _ts({
                              'en': 'Complete 4 steps above first',
                              'si': 'ඉහළ පියවර 4 සම්පූර්ණ කරන්න',
                              'ta': 'மேலே 4 படிகள் முடிக்கவும்',
                            }),
                  style: const TextStyle(
                      fontSize: 15, fontWeight: FontWeight.bold),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor:
                      _canPredict ? AppTheme.primaryDark : Colors.grey.shade400,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
          ),
        ),
      );

  // ──────────────────────────────────────────────────────────────────────────
  //  (iii) Result card — green ✅ if above average, red ⚠️ hazard if below
  // ──────────────────────────────────────────────────────────────────────────
  Widget _resultCard() {
    final yieldVal = (_result!['yield'] as double);
    final confidence = _result!['confidence'] as String;
    final isMock = _result!['isMock'] as bool? ?? false;
    final avg = _result!['average'] as double? ?? yieldVal;
    final ratio = (yieldVal / avg).clamp(0.0, 2.0);
    final resultColor = _resultColor(yieldVal);
    final totalKg = yieldVal * _areaHa;
    final isAbove = _isAboveAverage;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── (iii-a) Hazard warning banner when below average ──────────────────
        if (!isAbove)
          Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: const Color(0xFFFFEBEE),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: AppTheme.error.withValues(alpha: 0.45),
                width: 1.5,
              ),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppTheme.error.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.warning_rounded,
                    color: AppTheme.error,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _ts({
                          'en': '⚠️ Hazard Warning — Below Average Yield',
                          'si':
                              '⚠️ අවදානම් අනතුරු ඇඟවීම — සාමාන්‍යයට අඩු අස්වැන්නක්',
                          'ta':
                              '⚠️ அபாய எச்சரிக்கை — சராசரிக்கும் குறைந்த விளைச்சல்',
                        }),
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          color: AppTheme.error,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _ts({
                          'en': 'Your predicted yield is below the district average. '
                              'Review your soil inputs, irrigation, and crop management before planting.',
                          'si': 'ඔබේ පුරෝකථිත අස්වැන්න දිස්ත්‍රික් සාමාන්‍යයට අඩු. '
                              'රෝපණයට පෙර පස ආදාන, ජලනය හා භෝග කළමනාකරණය සමාලෝචනය කරන්න.',
                          'ta': 'உங்கள் கணிக்கப்பட்ட விளைச்சல் மாவட்ட சராசரிக்கும் குறைவாக உள்ளது. '
                              'நடவுக்கு முன் மண் உள்ளீடுகள், நீர்ப்பாசனம் மற்றும் பயிர் மேலாண்மையை மதிப்பாய்வு செய்யுங்கள்.',
                        }),
                        style: const TextStyle(
                          fontSize: 11.5,
                          color: AppTheme.error,
                          height: 1.45,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

        // ── (iii-b) Good result banner when above average ─────────────────────
        if (isAbove)
          Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: const Color(0xFFE8F5E9),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: AppTheme.success.withValues(alpha: 0.45),
                width: 1.5,
              ),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppTheme.success.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.check_circle_rounded,
                    color: AppTheme.success,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _ts({
                          'en': '✅ Good Yield Expected — Above Average',
                          'si': '✅ හොඳ අස්වැන්නක් අපේක්ෂිතය — සාමාන්‍යයට වඩා',
                          'ta':
                              '✅ நல்ல விளைச்சல் எதிர்பார்க்கப்படுகிறது — சராசரிக்கு மேல்',
                        }),
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          color: AppTheme.success,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _ts({
                          'en':
                              'Conditions look favourable. Continue with your current soil and crop management plan.',
                          'si':
                              'තත්ත්ව හිතකරව පෙනේ. ඔබේ දැනට ඇති පස හා භෝග කළමනාකරණ සැලැස්ම දිගටම කරගෙන යන්න.',
                          'ta':
                              'நிலைமைகள் சாதகமாக தெரிகின்றன. உங்கள் தற்போதைய மண் மற்றும் பயிர் மேலாண்மை திட்டத்தை தொடருங்கள்.',
                        }),
                        style: const TextStyle(
                          fontSize: 11.5,
                          color: AppTheme.success,
                          height: 1.45,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

        // ── Main result card ───────────────────────────────────────────────────
        Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [resultColor.withValues(alpha: 0.85), resultColor],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(14),
            boxShadow: [
              BoxShadow(
                color: resultColor.withValues(alpha: 0.35),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    _ts({
                      'en': 'Predicted Yield',
                      'si': 'පුරෝකථිත අස්වැන්න',
                      'ta': 'கணிக்கப்பட்ட விளைச்சல்',
                    }),
                    style: const TextStyle(color: Colors.white70, fontSize: 13),
                  ),
                  Row(
                    children: [
                      if (isMock) ...[
                        const CsMockBadge(),
                        const SizedBox(width: 8),
                      ],
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          _ts({
                            'en': 'AI Prediction',
                            'si': 'AI පුරෝකථනය',
                            'ta': 'AI கணிப்பு',
                          }),
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 10,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                '${yieldVal.toStringAsFixed(0)} kg/ha',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 42,
                  fontWeight: FontWeight.bold,
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.circle, size: 9, color: _confColor(confidence)),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      confidence.toUpperCase() == 'HIGH'
                          ? _ts({
                              'en': 'We\'re quite sure about this estimate',
                              'si': 'මෙම ඇස්තමේන්තුව ගැන හොඳ විශ්වාසයකි',
                              'ta': 'இந்த மதிப்பீட்டில் நம்பிக்கை உள்ளது',
                            })
                          : confidence.toUpperCase() == 'MEDIUM'
                              ? _ts({
                                  'en':
                                      'Fairly confident — conditions may vary',
                                  'si': 'සාධාරණ විශ්වාසයකි',
                                  'ta':
                                      'மிகவும் நம்பகமானது — நிலைமைகள் மாறலாம்',
                                })
                              : _ts({
                                  'en':
                                      'Approximate estimate — verify with your local officer',
                                  'si':
                                      'ආසන්න ඇස්තමේන්තුවකි — දේශීය නිලධාරී සමඟ සත්‍යාපනය',
                                  'ta':
                                      'தோராயமான மதிப்பீடு — உள்ளூர் அதிகாரியுடன் சரிபாருங்கள்',
                                }),
                      style: TextStyle(
                        color: _confColor(confidence),
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        _ts({
                          'en': 'vs. average yield',
                          'si': 'සාමාන්‍ය අස්වැන්නට සාපේක්ෂව',
                          'ta': 'சராசரி விளைச்சலுடன் ஒப்பிடு',
                        }),
                        style: const TextStyle(
                          color: Colors.white60,
                          fontSize: 11,
                        ),
                      ),
                      Text(
                        _ts({
                          'en': 'Avg: ${avg.toStringAsFixed(0)} kg/ha',
                          'si': 'සාමාන්‍ය: ${avg.toStringAsFixed(0)} kg/ha',
                          'ta': 'சராசரி: ${avg.toStringAsFixed(0)} kg/ha',
                        }),
                        style: const TextStyle(
                          color: Colors.white60,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: ratio / 2,
                      minHeight: 8,
                      backgroundColor: Colors.white.withValues(alpha: 0.15),
                      valueColor: const AlwaysStoppedAnimation<Color>(
                        Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _rStat(
                      _ts({'en': 'Crop', 'si': 'භෝගය', 'ta': 'பயிர்'}),
                      _selectedCrop!,
                    ),
                    _vDiv(),
                    _rStat(
                      _ts({'en': 'Area', 'si': 'ප්‍රදේශය', 'ta': 'பரப்பு'}),
                      '${_areaPerches.toStringAsFixed(0)} ${_ts({
                            'en': 'p',
                            'si': 'ප',
                            'ta': 'ப'
                          })}',
                    ),
                    _vDiv(),
                    _rStat(
                      _ts({'en': 'Season', 'si': 'කන්නය', 'ta': 'பருவம்'}),
                      _selectedSeason!,
                    ),
                    _vDiv(),
                    _rStat(
                      _ts({'en': 'Total', 'si': 'සම්පූර්ණ', 'ta': 'மொத்தம்'}),
                      '${totalKg.toStringAsFixed(0)} kg',
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 12),

        // Interpretation box
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppTheme.surfaceCard,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0xFFE0EBE0)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.lightbulb_outline, size: 15, color: resultColor),
                  const SizedBox(width: 6),
                  Text(
                    _ts({
                      'en': 'What this means',
                      'si': 'මෙයින් කියැවෙන්නේ',
                      'ta': 'இதன் அர்த்தம்',
                    }),
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                _interpretation(yieldVal),
                style: const TextStyle(
                  fontSize: 13,
                  color: AppTheme.textPrimary,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _ts({
                  'en':
                      'Total expected harvest: ${totalKg.toStringAsFixed(0)} kg from ${_areaPerches.toStringAsFixed(0)} perches (${_haToAcres(_areaHa).toStringAsFixed(2)} ac)',
                  'si':
                      'සම්පූර්ණ අස්වැන්න: ${totalKg.toStringAsFixed(0)} kg — ${_areaPerches.toStringAsFixed(0)} පර්ච (${_haToAcres(_areaHa).toStringAsFixed(2)} ac)',
                  'ta':
                      'மொத்த அறுவடை: ${totalKg.toStringAsFixed(0)} kg — ${_areaPerches.toStringAsFixed(0)} பர்ச் (${_haToAcres(_areaHa).toStringAsFixed(2)} ஏக்கர்)',
                }),
                style: const TextStyle(
                  fontSize: 13,
                  color: AppTheme.textSecondary,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 14),

        // ── (v) Ask AI for More Info button ───────────────────────────────────
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: () {
              final ctx = _buildAiContext();
              widget.onAiChatContext?.call(ctx);
              widget.onNavigate?.call(6); // navigate to AI Chat tab
            },
            icon: SvgPicture.string(
              _navSvg(6, Colors.white),
              width: 18,
              height: 18,
            ),
            label: Text(
              _ts({
                'en': 'Ask AI for More Info & Tips',
                'si': 'AI වෙතින් තව තොරතුරු හා උපදෙස් ලබා ගන්න',
                'ta':
                    'AI-இடம் கூடுதல் தகவல் மற்றும் உதவிக்குறிப்புகள் கேளுங்கள்',
              }),
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF1B5E20),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              elevation: 2,
            ),
          ),
        ),
      ],
    );
  }

  Widget _emptyResultPlaceholder() => Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: const Color(0xFFF1F7F1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFD0E8C8)),
        ),
        child: Column(
          children: [
            SvgPicture.string(
              _navSvg(1, const Color(0xFFB0C4B0)),
              width: 48,
              height: 48,
            ),
            const SizedBox(height: 12),
            Text(
              _ts({
                'en': 'Your yield prediction will appear here',
                'si': 'ඔබේ අස්වැන්න පුරෝකථනය මෙතැන දිස්වේ',
                'ta': 'உங்கள் விளைச்சல் கணிப்பு இங்கே தோன்றும்',
              }),
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 13,
                color: AppTheme.textMuted,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _ts({
                'en': 'Complete the form and tap Predict',
                'si': 'ආකෘතිය සම්පූර්ණ කර Predict ඔබන්න',
                'ta': 'படிவத்தை பூர்த்தி செய்து கணிக்கவும்',
              }),
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 11, color: AppTheme.textMuted),
            ),
          ],
        ),
      );

  Widget _errorCard() => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.red.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
        ),
        child: Row(
          children: [
            const Icon(Icons.error_outline, color: Colors.red, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                _errorMessage!,
                style: const TextStyle(color: Colors.red, fontSize: 13),
              ),
            ),
          ],
        ),
      );

  // ── Reusable primitives ────────────────────────────────────────────────────
  Widget _card({required Widget child}) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppTheme.surfaceCard,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFE0EBE0)),
        ),
        child: child,
      );

  Widget _sectionTitle(String title, IconData icon) => Row(
        children: [
          Icon(icon, size: 16, color: AppTheme.primaryDark),
          const SizedBox(width: 6),
          Text(
            title,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: AppTheme.primaryDark,
            ),
          ),
        ],
      );

  Widget _infoBox(
    String text, {
    required Color color,
    required IconData icon,
  }) =>
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.07),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withValues(alpha: 0.2)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 7),
            Expanded(
              child: Text(
                text,
                style: TextStyle(fontSize: 11.5, color: color, height: 1.45),
              ),
            ),
          ],
        ),
      );

  Widget _weatherSlider(
    String label,
    double value,
    double min,
    double max,
    String unit,
    Color color,
    ValueChanged<double> onChanged,
  ) =>
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    label,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '${value.toStringAsFixed(1)} $unit',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: color,
                    ),
                  ),
                ),
              ],
            ),
            SliderTheme(
              data: SliderTheme.of(context).copyWith(
                activeTrackColor: color,
                thumbColor: color,
                overlayColor: color.withValues(alpha: 0.12),
                inactiveTrackColor: color.withValues(alpha: 0.15),
                trackHeight: 2.5,
              ),
              child: Slider(
                  value: value, min: min, max: max, onChanged: onChanged),
            ),
          ],
        ),
      );

  Widget _nullDropdown({
    required String label,
    required String? value,
    required List<String> items,
    required IconData icon,
    required ValueChanged<String?> onChanged,
    String? hint,
    bool enabled = true,
  }) =>
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DropdownButtonFormField<String>(
            initialValue: value,
            hint:
                Text(label, style: const TextStyle(color: AppTheme.textMuted)),
            decoration: InputDecoration(
              labelText: label,
              prefixIcon: Icon(
                icon,
                color: enabled ? AppTheme.primary : AppTheme.textMuted,
                size: 20,
              ),
              border:
                  OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 10,
              ),
              fillColor: enabled ? null : Colors.grey.withValues(alpha: 0.04),
            ),
            items: enabled
                ? items
                    .map((e) => DropdownMenuItem(value: e, child: Text(e)))
                    .toList()
                : [],
            onChanged: enabled ? onChanged : null,
          ),
          if (hint != null)
            Padding(
              padding: const EdgeInsets.only(top: 4, left: 4),
              child: Text(
                hint,
                style: const TextStyle(fontSize: 11, color: AppTheme.textMuted),
              ),
            ),
        ],
      );

  Widget _rStat(String l, String v) => Column(
        children: [
          Text(l, style: const TextStyle(color: Colors.white54, fontSize: 10)),
          const SizedBox(height: 3),
          Text(
            v,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      );

  Widget _vDiv() => Container(width: 1, height: 28, color: Colors.white24);
}

// ─────────────────────────────────────────────────────────────────────────────
//  Language pill
// ─────────────────────────────────────────────────────────────────────────────
class _LangPill extends StatelessWidget {
  const _LangPill();
  @override
  Widget build(BuildContext context) {
    final notifier = AppLangProvider.of(context);
    final current = notifier.lang;
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFF0F4F0),
        borderRadius: BorderRadius.circular(20),
      ),
      padding: const EdgeInsets.all(3),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: AppLang.values.map((l) {
          final active = l == current;
          return GestureDetector(
            onTap: () => notifier.setLang(l),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
              decoration: BoxDecoration(
                color: active ? const Color(0xFF1B5E20) : Colors.transparent,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Text(
                l.label,
                style: TextStyle(
                  fontSize: 9.5,
                  fontWeight: active ? FontWeight.w800 : FontWeight.w500,
                  color: active ? Colors.white : const Color(0xFF888888),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Weather tile helper
// ─────────────────────────────────────────────────────────────────────────────
class _WTile {
  final String emoji, label, value;
  final Color color;
  const _WTile(this.emoji, this.label, this.value, this.color);
}
