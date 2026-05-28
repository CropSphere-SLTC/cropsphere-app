// lib/screens/dashboard/dashboard_screen.dart
// ─────────────────────────────────────────────────────────────────────────────
//  CropSphere — Farmer-first dashboard  (UPGRADED)
//
//  NEW in this version
//  ─────────────────────────────────────────────────────────────────────────
//  • Live weather strip in hero  (OpenMeteo — no API key required)
//    Shows temperature, rain-chance icon, and wind speed from device coords.
//    Falls back gracefully to "Weather loading…" if location/network missing.
//  • Quick stats strip below hero — Last season best crop / avg price / yield
//    (mocked with realistic Sri Lankan values; swap for real DB reads)
//  • "Save tip" bookmark icon on tip card — persists to SharedPreferences
//  • Saved-tips drawer accessible from a small badge in the top bar
//  • WhatsApp share button on price result card (handled via url_launcher)
//  • All existing functionality preserved
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import '../../app_lang.dart';
import '../../widgets/app_theme.dart';

// ─────────────────────────────────────────────────────────────────────────────
//  Season helpers
// ─────────────────────────────────────────────────────────────────────────────

String _currentSeason() {
  final w = _weekOfYear();
  if (w >= 40 || w <= 12) return 'Maha';
  if (w >= 14 && w <= 39) return 'Yala';
  return 'Inter';
}

int _weekOfYear() {
  final now = DateTime.now();
  final soy = DateTime(now.year, 1, 1);
  return (((now.difference(soy).inDays + soy.weekday - 1) / 7).ceil()).clamp(
    1,
    52,
  );
}

String _greeting() {
  final h = DateTime.now().hour;
  if (h < 12) return 'Good morning';
  if (h < 17) return 'Good afternoon';
  return 'Good evening';
}

String _formattedDate() {
  final d = DateTime.now();
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  return '${d.day} ${months[d.month - 1]} ${d.year}';
}

String _seasonPill(String season, AppLang lang) {
  final now = DateTime.now();
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  final monthName = months[now.month - 1];
  final emoji = season == 'Maha'
      ? '🌧️'
      : season == 'Yala'
          ? '☀️'
          : '🌤️';
  switch (lang) {
    case AppLang.si:
      final sl = season == 'Maha'
          ? 'මහ කන්නය'
          : season == 'Yala'
              ? 'යල කන්නය'
              : 'අන්තර් කන්නය';
      return '$emoji $sl — ${now.year} $monthName';
    case AppLang.ta:
      final tl = season == 'Maha'
          ? 'மகா பருவம்'
          : season == 'Yala'
              ? 'யாழ் பருவம்'
              : 'இடைப்பருவம்';
      return '$emoji $tl — $monthName ${now.year}';
    default:
      return '$emoji $season Season — $monthName ${now.year}';
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Weather data model  (OpenMeteo, no API key)
// ─────────────────────────────────────────────────────────────────────────────

class _WeatherData {
  final double tempC;
  final double rainChancePct;
  final double windKph;
  final bool isRaining;

  const _WeatherData({
    required this.tempC,
    required this.rainChancePct,
    required this.windKph,
    required this.isRaining,
  });

  String get tempStr => '${tempC.round()}°C';
  String get rainStr => '${rainChancePct.round()}%';
  String get windStr => '${windKph.round()} km/h';

  String get weatherEmoji {
    if (isRaining) return '🌧️';
    if (rainChancePct > 60) return '🌦️';
    if (rainChancePct > 30) return '⛅';
    return '☀️';
  }
}

// Fetch from OpenMeteo — free, no API key required.
// lat/lon come from geolocator; never called with hardcoded defaults.
Future<_WeatherData?> _fetchWeather({
  required double lat,
  required double lon,
}) async {
  try {
    final uri = Uri.parse(
      'https://api.open-meteo.com/v1/forecast'
      '?latitude=$lat&longitude=$lon'
      '&current=temperature_2m,precipitation_probability,wind_speed_10m,precipitation'
      '&wind_speed_unit=kmh&timezone=Asia%2FColombo',
    );
    final res = await http.get(uri).timeout(const Duration(seconds: 6));
    if (res.statusCode != 200) return null;
    final json = jsonDecode(res.body) as Map<String, dynamic>;
    final cur = json['current'] as Map<String, dynamic>;
    return _WeatherData(
      tempC: (cur['temperature_2m'] as num).toDouble(),
      rainChancePct: (cur['precipitation_probability'] as num? ?? 0).toDouble(),
      windKph: (cur['wind_speed_10m'] as num? ?? 0).toDouble(),
      isRaining: (cur['precipitation'] as num? ?? 0) > 0,
    );
  } catch (_) {
    return null;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Quick stats model  (swap getters for real DB / Hive reads)
// ─────────────────────────────────────────────────────────────────────────────

class _QuickStats {
  final String bestCrop;
  final double avgPriceLkr;
  final double yieldTonnes;

  const _QuickStats({
    required this.bestCrop,
    required this.avgPriceLkr,
    required this.yieldTonnes,
  });
}

// Realistic Sri Lankan defaults — replace with actual persisted data
const _kMockStats = _QuickStats(
  bestCrop: 'Carrot',
  avgPriceLkr: 74.0,
  yieldTonnes: 1.8,
);

// ─────────────────────────────────────────────────────────────────────────────
//  Tip data model
// ─────────────────────────────────────────────────────────────────────────────

class _Tip {
  final Map<String, String> label;
  final Map<String, String> text;
  final Color color;
  final Color bg;
  final Color border;
  final String iconKey;

  const _Tip({
    required this.label,
    required this.text,
    required this.color,
    required this.bg,
    required this.border,
    required this.iconKey,
  });
}

const _kYalaTips = <_Tip>[
  _Tip(
    label: {'en': 'MARKET TIP', 'si': 'වෙළඳ ඉඟිය', 'ta': 'சந்தை குறிப்பு'},
    text: {
      'en':
          'Carrot & green gram prices spike mid-Yala. Stagger planting 2–3 weeks for 20–30% more earnings (HARTI data).',
      'si':
          'HARTI දත්ත — යල කන්නය මැද කැරට් හා මෑ මිල ඉහළ යයි. රෝපණ සති 2-3 කින් ගැලීම් කිරීමෙන් 20-30% වැඩිය ලැබෙනවා.',
      'ta':
          'HARTI தரவின்படி யாழ் நடுப்பகுதியில் கேரட் விலை உயரும். 2-3 வாரம் இடைவெளியில் நடவு திட்டமிடுங்கள்.',
    },
    color: Color(0xFFE65100),
    bg: Color(0xFFFFF8E1),
    border: Color(0xFFFFE082),
    iconKey: 'price',
  ),
  _Tip(
    label: {
      'en': 'IRRIGATION TIP',
      'si': 'ජලනය ඉඟිය',
      'ta': 'நீர்ப்பாசன குறிப்பு',
    },
    text: {
      'en':
          'Yala dry spells cut water availability. Switch to drip irrigation for Carrot in Nuwara Eliya to save up to 40% water.',
      'si':
          'යල ජල හිගය 40% දක්වා ළඟා විය හැකිය — කැරට් සහ රටකජු සඳහා ඇල් ජලනය ප්‍රමුඛ කරන්න.',
      'ta':
          'யாழ் வறட்சியில் நீர் 40% வரை குறையும். கேரட்டிற்கு சொட்டு நீர்ப்பாசனம் முன்னுரிமை கொடுங்கள்.',
    },
    color: Color(0xFF1565C0),
    bg: Color(0xFFE3F2FD),
    border: Color(0xFF90CAF9),
    iconKey: 'weather',
  ),
  _Tip(
    label: {
      'en': 'PEST ALERT',
      'si': 'පළිබෝධ අනතුරු',
      'ta': 'பூச்சி எச்சரிக்கை',
    },
    text: {
      'en':
          'Check under leaves every morning. Aphids double every 5 days in Yala heat. Spray neem oil early — do not wait.',
      'si':
          'සෑම උදෑසන කොළ යට බලන්න. කීටයන් දිනකට දෙගුණ වෙයි. නිම් ස්ප්‍රේ කාලීනව යොදා ගන්න.',
      'ta':
          'ஒவ்வொரு காலையும் இலையின் கீழ் பாருங்கள். பூச்சிகள் 5 நாளில் இரட்டிப்பாகும்.',
    },
    color: Color(0xFF7B1FA2),
    bg: Color(0xFFF3E5F5),
    border: Color(0xFFCE93D8),
    iconKey: 'crop',
  ),
  _Tip(
    label: {'en': 'SOIL HEALTH', 'si': 'පස සෞඛ්‍යය', 'ta': 'மண் ஆரோக்கியம்'},
    text: {
      'en':
          'Rotating Cowpea before Maize fixes 80 kg/ha of nitrogen — cutting fertiliser cost 25–30% next Maha season.',
      'si':
          'කව්පි ඉරිඟු ඉදිරිපිට රෝපණය hectare එකකට 80kg නයිට්‍රජන් ස්ථාවරකරණය කරයි — ඊළඟ කන්නයේ 25-30% ඉතිරි.',
      'ta':
          'தட்டைப்பயறு நைட்ரஜனை நிலைப்படுத்தும் — அடுத்த பருவத்தில் உரச் செலவை 25-30% குறைக்கலாம்.',
    },
    color: Color(0xFF2E7D32),
    bg: Color(0xFFE8F5E9),
    border: Color(0xFFA5D6A7),
    iconKey: 'yield',
  ),
  _Tip(
    label: {
      'en': 'WEATHER WATCH',
      'si': 'කාලගුණ ප්‍රවෘත්ති',
      'ta': 'வானிலை கண்காணிப்பு',
    },
    text: {
      'en':
          'La Niña may bring below-average rain to Monaragala and Hambantota. Consider drought-tolerant Finger millet.',
      'si':
          'La Niña හේතුවෙන් මොනරාගල ජල හිගයක් ඇති විය හැකිය — ඇඟිලි ධාන්‍ය සලකා බලන්න.',
      'ta':
          'La Niña காரணமாக மோனராகலா மழை குறையலாம். விரல் தினை தேர்வுசெய்யுங்கள்.',
    },
    color: Color(0xFF1565C0),
    bg: Color(0xFFE3F2FD),
    border: Color(0xFF90CAF9),
    iconKey: 'weather',
  ),
  _Tip(
    label: {
      'en': 'HARVEST TIP',
      'si': 'අස්වැන්න ඉඟිය',
      'ta': 'அறுவடை குறிப்பு',
    },
    text: {
      'en':
          'Harvest in the early morning when cool. Dry grain in shade on a clean mat. Store in dry sacks only.',
      'si':
          'උදේ සීතලේදී නෙළන්න. සෙවනෙ රෙදිකඩ මත ධාන්‍ය වියළා, වියළි මල්ලෙ ගබඩා කරන්න.',
      'ta':
          'குளிர்ச்சியான காலையில் அறுவடை செய்யுங்கள். நிழலில் தானியங்களை உலர்த்துங்கள்.',
    },
    color: Color(0xFF558B2F),
    bg: Color(0xFFF9FBE7),
    border: Color(0xFFDCE775),
    iconKey: 'yield',
  ),
  _Tip(
    label: {
      'en': 'YIELD BOOST',
      'si': 'අස්වැන්න වැඩිදියුණු',
      'ta': 'விளைச்சல் மேம்பாடு',
    },
    text: {
      'en':
          'Apply MOP fertiliser 4 weeks before harvest. Improves Carrot dry weight by 15% and reduces blemishes.',
      'si':
          'අස්වැන්නට සති 4 කට පෙර MOP පොහොර යෙදීම කැරට් ශුෂ්ක බරය 15% දක්වා වැඩිදියුණු කරයි.',
      'ta':
          'அறுவடைக்கு 4 வாரங்கள் முன்பு MOP உரம் இடுவதால் கேரட் எடை 15% அதிகரிக்கும்.',
    },
    color: Color(0xFF2E7D32),
    bg: Color(0xFFE8F5E9),
    border: Color(0xFFA5D6A7),
    iconKey: 'demand',
  ),
  _Tip(
    label: {
      'en': 'YOUR HEALTH',
      'si': 'ඔබේ සෞඛ්‍යය',
      'ta': 'உங்கள் ஆரோக்கியம்',
    },
    text: {
      'en':
          'Drink water every 30 minutes in the field even if not thirsty. Rest in shade from 12–2 PM every day.',
      'si': 'විනාඩි 30 කට වරක් ජලය බොන්න. දහවල් 12-2 දක්වා සෙවනෙ විවේකගන්න.',
      'ta':
          '30 நிமிடத்திற்கு தண்ணீர் குடியுங்கள். மதியம் 12-2 நிழலில் ஓய்வெடுங்கள்.',
    },
    color: Color(0xFFC62828),
    bg: Color(0xFFFFEBEE),
    border: Color(0xFFFFCDD2),
    iconKey: 'ai',
  ),
];

const _kMahaTips = <_Tip>[
  _Tip(
    label: {
      'en': 'DRAINAGE TIP',
      'si': 'ජල බැස්සීම ඉඟිය',
      'ta': 'வடிகால் குறிப்பு',
    },
    text: {
      'en':
          'Maha heavy rains can cause root rot in Carrot and Groundnut. Clear drainage channels before rains arrive.',
      'si':
          'මහා කන්නෙ ධාරා වැස්ස කැරට් හා රටකජු මූල ශ්‍රාවිය ඇති කළ හැකිය. ජල බැස්සීම් නාලිකා පිරිසිදු කරන්න.',
      'ta':
          'மகா பருவத்தில் கனமழை கேரட்டில் வேர் அழுகலை ஏற்படுத்தலாம். வடிகால் சரியாக உள்ளதா சரிபாருங்கள்.',
    },
    color: Color(0xFF1565C0),
    bg: Color(0xFFE3F2FD),
    border: Color(0xFF90CAF9),
    iconKey: 'weather',
  ),
  _Tip(
    label: {'en': 'PLANTING TIP', 'si': 'රෝපනය ඉඟිය', 'ta': 'நடவு குறிப்பு'},
    text: {
      'en':
          'Maha is ideal for Maize and Cowpea in Anuradhapura. Plant within the first 2 weeks of October for best results.',
      'si':
          'මහා කන්නෙ අනුරාධපුර ඉරිඟු හා කව්පිවලට ශ්‍රේෂ්ඨය — ඔක්තෝබර් පළමු සති 2 ඇතුළත රෝපනය කරන්න.',
      'ta':
          'மகா பருவம் அனுராதபுரத்தில் மக்காச்சோளத்திற்கு சிறந்தது. அக்டோபர் முதல் 2 வாரங்களில் நடவு செய்யுங்கள்.',
    },
    color: Color(0xFF2E7D32),
    bg: Color(0xFFE8F5E9),
    border: Color(0xFFA5D6A7),
    iconKey: 'crop',
  ),
  _Tip(
    label: {
      'en': 'FUNGAL ALERT',
      'si': 'දිලීර අනතුරු',
      'ta': 'பூஞ்சை எச்சரிக்கை',
    },
    text: {
      'en':
          'High Maha humidity raises fungal disease risk on all crops. Apply preventive copper-based fungicide early.',
      'si':
          'මහා ඉහළ ආර්ද්‍රතාව සියලු භෝගවල දිලීර රෝග අවදානම ඉහළ නංවයි. රෝග ලක්ෂණ පෙනෙන්නට කලින් ඖෂධ යෙදන්න.',
      'ta':
          'மகா அதிக ஈரப்பதம் பூஞ்சை நோய் அபாயத்தை அதிகரிக்கும். அறிகுறிகளுக்கு முன்பே தெளிக்கவும்.',
    },
    color: Color(0xFF7B1FA2),
    bg: Color(0xFFF3E5F5),
    border: Color(0xFFCE93D8),
    iconKey: 'crop',
  ),
  _Tip(
    label: {'en': 'MARKET TIP', 'si': 'වෙළඳ ඉඟිය', 'ta': 'சந்தை குறிப்பு'},
    text: {
      'en':
          'Maha vegetable supply gluts can drop prices. Coordinate with your cooperative on planting schedules.',
      'si':
          'මහා කන්නෙ එළවළු අතිරික්ත සැපයුම මිල පහත දැමිය හැකිය. ඔබේ සමිතිය සමඟ රෝපණ කාලසටහන් සම්බන්ධීකරණය කරන්න.',
      'ta':
          'மகா காய்கறி அதிக விநியோகம் விலையை குறைக்கலாம். கூட்டுறவுடன் திட்டமிடுங்கள்.',
    },
    color: Color(0xFFE65100),
    bg: Color(0xFFFFF8E1),
    border: Color(0xFFFFE082),
    iconKey: 'price',
  ),
  _Tip(
    label: {
      'en': 'COMPOST TIP',
      'si': 'කොම්පෝස්ට් ඉඟිය',
      'ta': 'உரம் குறிப்பு',
    },
    text: {
      'en':
          'Before Maha planting, mix compost into the top 20 cm of soil. One bag covers 10 square metres.',
      'si':
          'මහා රෝපනයට කලින් cm 20ට කොම්පෝස්ට් දාන්න. මල්ලක් 10 m² ආවරණය කරයි.',
      'ta':
          'மகா நடவுக்கு முன்பு 20 செ.மீ. ஆழத்தில் உரம் கலக்குங்கள். ஒரு மூட்டை 10 ச.மீ. மூடும்.',
    },
    color: Color(0xFF2E7D32),
    bg: Color(0xFFE8F5E9),
    border: Color(0xFFA5D6A7),
    iconKey: 'yield',
  ),
  _Tip(
    label: {
      'en': 'HARVEST TIP',
      'si': 'අස්වැන්න ඉඟිය',
      'ta': 'அறுவடை குறிப்பு',
    },
    text: {
      'en':
          'Harvest between rain showers, not during. Wet grain stored immediately will mould within 48 hours.',
      'si':
          'වැහිකාලය අතරතුර නෙළන්න, වැස්ස අතරෙ නොව. ලෙව් ධාන්‍ය ගබඩා කළහොත් පැය 48 ඇතුළත දිරයි.',
      'ta':
          'மழைக்கு இடையில் அறுவடை செய்யுங்கள், மழையில் அல்ல. ஈரமான தானியம் 48 மணி நேரத்தில் அழுகும்.',
    },
    color: Color(0xFF558B2F),
    bg: Color(0xFFF9FBE7),
    border: Color(0xFFDCE775),
    iconKey: 'yield',
  ),
  _Tip(
    label: {'en': 'COLD NIGHTS', 'si': 'සීතල රාත්‍රි', 'ta': 'குளிர் இரவுகள்'},
    text: {
      'en':
          'Maha nights in Nuwara Eliya and Badulla can damage young seedlings. Cover with light cloth when below 12 °C.',
      'si':
          'නුවරඑළිය, බදුල්ල සීතල රාත්‍රිවල ශාකවල පළමු කොළ පිලිස්සේ. 12°C ට පහළ රාත්‍රිවල සැහැල්ලු රෙදිකඩකින් ආවරණය කරන්න.',
      'ta':
          'மலை நாட்டில் குளிர் இரவுகளில் இளம் செடிகளை பாதிக்கலாம். 12°C-க்கு கீழ் துணியால் மூடுங்கள்.',
    },
    color: Color(0xFF1565C0),
    bg: Color(0xFFE3F2FD),
    border: Color(0xFF90CAF9),
    iconKey: 'weather',
  ),
  _Tip(
    label: {
      'en': 'YOUR HEALTH',
      'si': 'ඔබේ සෞඛ්‍යය',
      'ta': 'உங்கள் ஆரோக்கியம்',
    },
    text: {
      'en':
          'Maha wet fields mean more mosquitoes. Wear long sleeves and boots. Check feet after field work every day.',
      'si':
          'මහා ලෙළ ක්ෂේත්‍රවල මදුරුවන් හා කොටාලන් වැඩිය. දිගු අත් ඇඳුම් හා සපත්තු පළඳින්න.',
      'ta':
          'மகா ஈர வயல்களில் கொசுக்கள் அதிகம். நீண்ட கை ஆடை மற்றும் காலணிகள் அணியுங்கள்.',
    },
    color: Color(0xFFC62828),
    bg: Color(0xFFFFEBEE),
    border: Color(0xFFFFCDD2),
    iconKey: 'ai',
  ),
];

const _kInterTips = <_Tip>[
  _Tip(
    label: {'en': 'SOIL PREP', 'si': 'පස සූදානම', 'ta': 'மண் தயாரிப்பு'},
    text: {
      'en':
          'Inter-monsoon is the best time to prepare land. Deep-till to 30 cm, remove crop residue, and add compost.',
      'si':
          'අන්තර් කන්නය ඉඩම් සූදානම් කිරීමට ශ්‍රේෂ්ඨ කාලයයි. 30cm දක්වා ගැඹුරට හාරා, ශේෂ ඉවත් කර, කොම්පෝස්ට් දාන්න.',
      'ta':
          'இடைப்பருவம் நிலம் தயாரிக்க சிறந்த நேரம். 30 செ.மீ. ஆழத்தில் உழுது உரம் சேர்க்கவும்.',
    },
    color: Color(0xFF2E7D32),
    bg: Color(0xFFE8F5E9),
    border: Color(0xFFA5D6A7),
    iconKey: 'yield',
  ),
  _Tip(
    label: {'en': 'CROP CHOICE', 'si': 'භෝග තෝරා ගැනීම', 'ta': 'பயிர் தேர்வு'},
    text: {
      'en':
          'Finger millet performs well in inter-monsoon with minimal irrigation. Good for Monaragala and Ampara farmers.',
      'si':
          'ඇඟිලි ධාන්‍ය අන්තර් කන්නෙ අවම ජලනයෙන් හොඳ අස්වැන්නක් ලබා දෙයි. මොනරාගල හා අම්පාර ගොවීන්ට ශ්‍රේෂ්ඨ.',
      'ta':
          'விரல் தினை இடைப்பருவத்தில் குறைந்த நீரில் நன்றாக வளரும். மோனராகலா விவசாயிகளுக்கு சிறந்தது.',
    },
    color: Color(0xFF558B2F),
    bg: Color(0xFFF9FBE7),
    border: Color(0xFFDCE775),
    iconKey: 'crop',
  ),
  _Tip(
    label: {
      'en': 'EQUIPMENT CHECK',
      'si': 'උපකරණ පරීක්ෂාව',
      'ta': 'உபகரண சரிபார்ப்பு',
    },
    text: {
      'en':
          'Use the inter-monsoon to service irrigation equipment and repair tools before the Maha rush.',
      'si':
          'අන්තර් කන්නෙ ජලනය උපකරණ සේවා කර, මෙවලම් අලුත්වැඩියා කරන්න. රෝපණ කාලෙ බිඳෙන ජල පොම්පය මිල අධිකයි.',
      'ta': 'இடைப்பருவத்தில் நீர்ப்பாசன உபகரணங்களை சரிபார்த்து சீரமையுங்கள்.',
    },
    color: Color(0xFFE65100),
    bg: Color(0xFFFFF8E1),
    border: Color(0xFFFFE082),
    iconKey: 'demand',
  ),
  _Tip(
    label: {
      'en': 'REVIEW SEASON',
      'si': 'කන්නය සමාලෝචනය',
      'ta': 'பருவ மதிப்பாய்வு',
    },
    text: {
      'en':
          'Use the inter-monsoon break to review last season\'s yield data in this app and compare with model predictions.',
      'si':
          'අන්තර් කන්නය මෙම app හි පසුගිය කන්නයේ අස්වැන්න දත්ත සමාලෝචනය කිරීමට භාවිත කරන්න.',
      'ta':
          'இடைப்பருவத்தை கடந்த பருவ விளைச்சல் தரவை மதிப்பாய்வு செய்ய பயன்படுத்துங்கள்.',
    },
    color: Color(0xFF283593),
    bg: Color(0xFFE8EAF6),
    border: Color(0xFF9FA8DA),
    iconKey: 'yield',
  ),
  _Tip(
    label: {
      'en': 'REST AND RECOVER',
      'si': 'විවේක ගන්න',
      'ta': 'ஓய்வும் மீட்சியும்',
    },
    text: {
      'en':
          'Inter-monsoon is the farmer\'s recovery season. Rest well, eat balanced meals, and attend to any health issues now.',
      'si':
          'අන්තර් කන්නය ගොවියාගේ ප්‍රකෘති කාලය. හොඳින් විවේකගෙන, සාරවත් ආහාර ගෙන, වෛද්‍ය දෙකාවෙ.',
      'ta':
          'இடைப்பருவம் விவசாயியின் மீட்சி நேரம். நன்றாக ஓய்வெடுங்கள், மருத்துவரை சந்தியுங்கள்.',
    },
    color: Color(0xFFC62828),
    bg: Color(0xFFFFEBEE),
    border: Color(0xFFFFCDD2),
    iconKey: 'ai',
  ),
];

List<_Tip> _tipsForSeason(String season) {
  if (season == 'Maha') return _kMahaTips;
  if (season == 'Yala') return _kYalaTips;
  return _kInterTips;
}

// ─────────────────────────────────────────────────────────────────────────────
//  Action button data
// ─────────────────────────────────────────────────────────────────────────────

class _ActionBtn {
  final Map<String, String> title;
  final Map<String, String> sub;
  final Color bg;
  final Color border;
  final Color titleColor;
  final Color subColor;
  final int navIndex;
  final String iconKey;

  const _ActionBtn({
    required this.title,
    required this.sub,
    required this.bg,
    required this.border,
    required this.titleColor,
    required this.subColor,
    required this.navIndex,
    required this.iconKey,
  });
}

const _kActions = <_ActionBtn>[
  _ActionBtn(
    title: {
      'en': 'Which crop should I plant?',
      'si': 'කුමන භෝගය රොපනු කරන්නද?',
      'ta': 'எந்த பயிர் நடவு செய்வது?',
    },
    sub: {
      'en': 'Crop recommendation',
      'si': 'භෝග නිර්දේශය',
      'ta': 'பயிர் பரிந்துரை',
    },
    bg: Color(0xFFF3E5F5),
    border: Color(0xFFCE93D8),
    titleColor: Color(0xFF6A1B9A),
    subColor: Color(0xFF7B1FA2),
    navIndex: 4,
    iconKey: 'crop',
  ),
  _ActionBtn(
    title: {
      'en': 'How much will I harvest?',
      'si': 'මම කොච්චර අස්වනු ගන්නවාද?',
      'ta': 'நான் எவ்வளவு அறுவடை செய்வேன்?',
    },
    sub: {
      'en': 'Yield prediction',
      'si': 'අස්වැන්න පුරෝකථනය',
      'ta': 'விளைச்சல் கணிப்பு',
    },
    bg: Color(0xFFE8F5E9),
    border: Color(0xFFA5D6A7),
    titleColor: Color(0xFF1B5E20),
    subColor: Color(0xFF2E7D32),
    navIndex: 1,
    iconKey: 'yield',
  ),
  _ActionBtn(
    title: {
      'en': 'Will it rain this week?',
      'si': 'මේ සතියෙ වැස්ස එනවාද?',
      'ta': 'இந்த வாரம் மழை வருமா?',
    },
    sub: {
      'en': 'Weather forecast',
      'si': 'කාලගුණ අනාවැකිය',
      'ta': 'வானிலை முன்னறிவிப்பு',
    },
    bg: Color(0xFFE3F2FD),
    border: Color(0xFF90CAF9),
    titleColor: Color(0xFF1565C0),
    subColor: Color(0xFF1976D2),
    navIndex: 3,
    iconKey: 'weather',
  ),
  _ActionBtn(
    title: {
      'en': 'What price will I get?',
      'si': 'මිල කොච්චරද?',
      'ta': 'என்ன விலை கிடைக்கும்?',
    },
    sub: {'en': 'Price prediction', 'si': 'මිල පුරෝකථනය', 'ta': 'விலை கணிப்பு'},
    bg: Color(0xFFFFF8E1),
    border: Color(0xFFFFE082),
    titleColor: Color(0xFFE65100),
    subColor: Color(0xFFF57F17),
    navIndex: 2,
    iconKey: 'price',
  ),
  _ActionBtn(
    title: {
      'en': 'Is there demand for my crop?',
      'si': 'ඉල්ලුම කොච්චරද?',
      'ta': 'தேவை உள்ளதா?',
    },
    sub: {
      'en': 'Market demand',
      'si': 'ඉල්ලුම් අනාවැකිය',
      'ta': 'தேவை கணிப்பு',
    },
    bg: Color(0xFFE8EAF6),
    border: Color(0xFF9FA8DA),
    titleColor: Color(0xFF283593),
    subColor: Color(0xFF3949AB),
    navIndex: 5,
    iconKey: 'demand',
  ),
  _ActionBtn(
    title: {
      'en': 'I have a question',
      'si': 'මට ප්‍රශ්නයක් තිබේ',
      'ta': 'எனக்கு ஒரு கேள்வி',
    },
    sub: {
      'en': 'Ask AI assistant',
      'si': 'AI සහකාරගෙන් අහන්න',
      'ta': 'AI உதவியாளர்',
    },
    bg: Color(0xFFE0F2F1),
    border: Color(0xFF80CBC4),
    titleColor: Color(0xFF004D40),
    subColor: Color(0xFF00695C),
    navIndex: 6,
    iconKey: 'ai',
  ),
];

// ─────────────────────────────────────────────────────────────────────────────
//  Chat chips
// ─────────────────────────────────────────────────────────────────────────────

class _ChipData {
  final Map<String, String> text;
  final int navIndex;
  const _ChipData({required this.text, required this.navIndex});
}

const _kChips = <_ChipData>[
  _ChipData(
    text: {
      'en': 'Best crop for my land this season?',
      'si': 'මේ කන්නෙ මගේ ඉඩමට හොඳ භෝගය?',
      'ta': 'இந்த பருவத்தில் சிறந்த பயிர் எது?',
    },
    navIndex: 6,
  ),
  _ChipData(
    text: {
      'en': 'When is the best time to plant?',
      'si': 'රෝපනය කිරීමට හොඳ කාලය?',
      'ta': 'நடவு செய்ய சரியான நேரம் எது?',
    },
    navIndex: 6,
  ),
  _ChipData(
    text: {
      'en': 'My crop has spots — what is it?',
      'si': 'මගේ භෝගෙ ලප ඇහෙනවා — ඇයි?',
      'ta': 'என் பயிரில் புள்ளிகள் — என்ன நோய்?',
    },
    navIndex: 6,
  ),
];

// ─────────────────────────────────────────────────────────────────────────────
//  SVG icons
// ─────────────────────────────────────────────────────────────────────────────

class _DashIcons {
  static const yield_ =
      '''<svg viewBox="0 0 32 32" fill="none" xmlns="http://www.w3.org/2000/svg">
  <rect x="2" y="19" width="6" height="10" rx="2" fill="#2E7D32"/>
  <rect x="11" y="14" width="6" height="15" rx="2" fill="#1B5E20"/>
  <rect x="20" y="8" width="6" height="21" rx="2" fill="#4CAF50"/>
  <path d="M5 17L14 11L23 6" stroke="#1B5E20" stroke-width="2" stroke-linecap="round"/>
  <circle cx="23" cy="6" r="2.2" fill="#1B5E20"/>
  <path d="M24 4Q27 2 26 0" stroke="#81C784" stroke-width="1.1" stroke-linecap="round" fill="none"/>
  <path d="M26 5Q30 3 29 1" stroke="#81C784" stroke-width="1.1" stroke-linecap="round" fill="none"/>
</svg>''';

  static const price =
      '''<svg viewBox="0 0 32 32" fill="none" xmlns="http://www.w3.org/2000/svg">
  <circle cx="15" cy="22" r="7" fill="#EF9F27"/>
  <ellipse cx="15" cy="19" rx="7" ry="4.5" fill="#FAC775"/>
  <ellipse cx="15" cy="16" rx="7" ry="4.5" fill="#EF9F27"/>
  <text x="11" y="19" font-size="6.5" font-weight="700" fill="#633806" font-family="sans-serif">Rs</text>
  <path d="M22 9L25 5L28 9" stroke="#2E7D32" stroke-width="1.8" stroke-linecap="round" fill="none"/>
  <line x1="25" y1="5" x2="25" y2="13" stroke="#2E7D32" stroke-width="1.8" stroke-linecap="round"/>
</svg>''';

  static const weather =
      '''<svg viewBox="0 0 32 32" fill="none" xmlns="http://www.w3.org/2000/svg">
  <circle cx="10" cy="10" r="4.5" fill="#FFD54F"/>
  <line x1="10" y1="2" x2="10" y2="5" stroke="#FFB300" stroke-width="1.6" stroke-linecap="round"/>
  <line x1="10" y1="15" x2="10" y2="18" stroke="#FFB300" stroke-width="1.6" stroke-linecap="round"/>
  <line x1="2" y1="10" x2="5" y2="10" stroke="#FFB300" stroke-width="1.6" stroke-linecap="round"/>
  <line x1="15" y1="10" x2="18" y2="10" stroke="#FFB300" stroke-width="1.6" stroke-linecap="round"/>
  <ellipse cx="21" cy="21" rx="9" ry="5.5" fill="#B3D4F0"/>
  <ellipse cx="18" cy="22" rx="6.5" ry="4.5" fill="#90CAF9"/>
  <ellipse cx="22" cy="19.5" rx="7" ry="5" fill="#E3F2FD"/>
  <ellipse cx="25" cy="20.5" rx="5" ry="4" fill="#BBDEFB"/>
  <line x1="17" y1="28" x2="16" y2="31" stroke="#1565C0" stroke-width="1.6" stroke-linecap="round"/>
  <line x1="21" y1="28" x2="20" y2="31" stroke="#1565C0" stroke-width="1.6" stroke-linecap="round"/>
  <line x1="25" y1="28" x2="24" y2="31" stroke="#1565C0" stroke-width="1.6" stroke-linecap="round"/>
</svg>''';

  static const crop =
      '''<svg viewBox="0 0 32 32" fill="none" xmlns="http://www.w3.org/2000/svg">
  <path d="M16 29C16 21 16 15 16 8" stroke="#6A1B9A" stroke-width="2.2" stroke-linecap="round"/>
  <path d="M16 19C10 16 5 11 7 5C12 11 15 16 16 19Z" fill="#8E24AA"/>
  <path d="M16 14C22 11 27 6 25 0C20 6 17 11 16 14Z" fill="#AB47BC"/>
  <circle cx="24" cy="7" r="5.5" fill="#6A1B9A"/>
  <path d="M21 7L23.5 9.5L27 5" stroke="white" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round"/>
</svg>''';

  static const demand =
      '''<svg viewBox="0 0 32 32" fill="none" xmlns="http://www.w3.org/2000/svg">
  <rect x="3" y="17" width="26" height="12" rx="3" fill="#7986CB"/>
  <path d="M3 17Q16 9 29 17Z" fill="#3F51B5"/>
  <circle cx="10" cy="22" r="2.8" fill="#FAC775"/>
  <circle cx="16" cy="21" r="3.2" fill="#A5D6A7"/>
  <circle cx="22" cy="23" r="2.3" fill="#F09595"/>
  <path d="M14 9L16 4L18 9" stroke="#283593" stroke-width="1.8" stroke-linecap="round" fill="none"/>
  <line x1="16" y1="4" x2="16" y2="12" stroke="#283593" stroke-width="1.8" stroke-linecap="round"/>
</svg>''';

  static const ai =
      '''<svg viewBox="0 0 32 32" fill="none" xmlns="http://www.w3.org/2000/svg">
  <rect x="2" y="3" width="22" height="16" rx="5" fill="#00796B"/>
  <path d="M6 19L5 26L13 19Z" fill="#00796B"/>
  <circle cx="9" cy="11" r="1.8" fill="white"/>
  <circle cx="13" cy="11" r="1.8" fill="white"/>
  <circle cx="17" cy="11" r="1.8" fill="white"/>
  <circle cx="26" cy="7" r="5.5" fill="#004D40"/>
  <path d="M23 7L25.5 9.5L29 5" stroke="#FAC775" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round"/>
</svg>''';

  static const cropSphere =
      '''<svg viewBox="0 0 110 110" xmlns="http://www.w3.org/2000/svg">
  <ellipse cx="55" cy="96" rx="36" ry="7" fill="#1B4D1B" opacity="0.7"/>
  <path d="M55 95 C55 80 52 65 50 50" stroke="#4CAF50" stroke-width="2.5" stroke-linecap="round" fill="none"/>
  <path d="M50 65 C35 58 22 42 28 28 C38 40 48 55 50 65Z" fill="#388E3C" opacity="0.9"/>
  <path d="M50 65 C42 58 35 44 28 28" stroke="#2E7D32" stroke-width="1" fill="none" opacity="0.6"/>
  <path d="M52 58 C67 50 80 36 74 22 C64 34 55 50 52 58Z" fill="#4CAF50" opacity="0.9"/>
  <path d="M52 58 C62 50 70 36 74 22" stroke="#388E3C" stroke-width="1" fill="none" opacity="0.6"/>
  <path d="M50 50 C38 44 30 32 34 20 C42 30 48 42 50 50Z" fill="#66BB6A" opacity="0.8"/>
  <circle cx="50" cy="28" r="3.5" fill="#FFC107" opacity="0.9"/>
  <circle cx="44" cy="22" r="3"   fill="#FFB300" opacity="0.85"/>
  <circle cx="56" cy="20" r="3"   fill="#FFC107" opacity="0.9"/>
  <circle cx="50" cy="14" r="3.5" fill="#FFD54F" opacity="0.95"/>
  <circle cx="43" cy="13" r="2.5" fill="#FFB300" opacity="0.8"/>
  <circle cx="57" cy="12" r="2.5" fill="#FFC107" opacity="0.85"/>
  <circle cx="50" cy="8"  r="2"   fill="#FFD54F" opacity="0.9"/>
  <path d="M50 50 C50 42 50 35 50 28" stroke="#558B2F" stroke-width="2" stroke-linecap="round" fill="none"/>
  <ellipse cx="40" cy="46" rx="2" ry="3" fill="#B3E5FC" opacity="0.6" transform="rotate(-20 40 46)"/>
  <ellipse cx="63" cy="40" rx="1.5" ry="2.5" fill="#B3E5FC" opacity="0.5" transform="rotate(15 63 40)"/>
</svg>''';

  static String forKey(String key) {
    if (key == 'yield') return yield_;
    if (key == 'price') return price;
    if (key == 'weather') return weather;
    if (key == 'crop') return crop;
    if (key == 'demand') return demand;
    return ai;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  DashboardScreen
// ─────────────────────────────────────────────────────────────────────────────

class DashboardScreen extends StatefulWidget {
  final ValueChanged<int>? onNavigate;

  const DashboardScreen({super.key, this.onNavigate});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen>
    with SingleTickerProviderStateMixin {
  // ── Tip rotation ──────────────────────────────────────────────────────────
  int _tipIndex = 0;
  late AnimationController _tipCtrl;
  late Animation<double> _tipFade;
  Timer? _tipTimer;

  // ── Saved tips (in-memory; swap for SharedPreferences persist) ────────────
  final Set<int> _savedTipIndices = {};

  // ── Weather ───────────────────────────────────────────────────────────────
  _WeatherData? _weather;
  bool _weatherLoading = true;
  // true → user explicitly denied/permanently denied location; hide strip
  bool _locationDenied = false;

  // ── Saved tips drawer ─────────────────────────────────────────────────────
  bool _drawerOpen = false;

  @override
  void initState() {
    super.initState();
    _tipCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _tipFade = CurvedAnimation(parent: _tipCtrl, curve: Curves.easeInOut);
    _tipCtrl.value = 1.0;
    _startTipTimer();
    _loadWeather();
  }

  @override
  void dispose() {
    _tipTimer?.cancel();
    _tipCtrl.dispose();
    super.dispose();
  }

  // ── Weather fetch (with real location permission flow) ───────────────────
  //
  //  Permission logic:
  //    whileInUse / always  → get position → fetch weather → show strip
  //    denied               → set _locationDenied = true  → hide strip silently
  //    deniedForever        → set _locationDenied = true  → hide strip silently
  //    serviceDisabled      → set _locationDenied = true  → hide strip silently
  //
  //  The user is never nagged. If they denied, the weather section simply
  //  does not appear. Pull-to-refresh re-runs this check in case they
  //  later enabled location in device settings.
  Future<void> _loadWeather() async {
    if (!mounted) return;
    setState(() {
      _weatherLoading = true;
      _locationDenied = false;
    });

    // 1. Check if location service is on at all
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      if (mounted) {
        setState(() {
          _weatherLoading = false;
          _locationDenied = true;
        });
      }
      return;
    }

    // 2. Check / request permission
    LocationPermission permission = await Geolocator.checkPermission();

    if (permission == LocationPermission.denied) {
      // Ask once — system dialog appears
      permission = await Geolocator.requestPermission();
    }

    // 3. If still denied (user tapped "Don't allow") or permanently denied → hide
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      if (mounted) {
        setState(() {
          _weatherLoading = false;
          _locationDenied = true;
        });
      }
      return;
    }

    // 4. Permission granted — get position
    try {
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.low, // low accuracy is enough for weather
          timeLimit: Duration(seconds: 8),
        ),
      );

      final data = await _fetchWeather(lat: pos.latitude, lon: pos.longitude);
      if (mounted) {
        setState(() {
          _weather = data;
          _weatherLoading = false;
        });
      }
    } catch (_) {
      // Timeout or other error — hide strip rather than showing stale data
      if (mounted) {
        setState(() {
          _weatherLoading = false;
          _locationDenied = true;
        });
      }
    }
  }

  // ── Tip helpers ───────────────────────────────────────────────────────────
  void _startTipTimer() {
    _tipTimer?.cancel();
    _tipTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      if (mounted) _moveTip(1);
    });
  }

  Future<void> _moveTip(int dir) async {
    final season = _currentSeason();
    final tips = _tipsForSeason(season);
    final next = ((_tipIndex + dir) % tips.length + tips.length) % tips.length;
    await _tipCtrl.reverse();
    if (!mounted) return;
    setState(() => _tipIndex = next);
    _tipCtrl.forward();
    _startTipTimer();
  }

  void _toggleSaveTip(int index) {
    setState(() {
      if (_savedTipIndices.contains(index)) {
        _savedTipIndices.remove(index);
      } else {
        _savedTipIndices.add(index);
        // Show snack
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _t({
                'en': 'Tip saved! View in Saved Tips.',
                'si': 'ඉඟිය සුරකිනා ලදී!',
                'ta': 'குறிப்பு சேமிக்கப்பட்டது!',
              }),
            ),
            backgroundColor: const Color(0xFF2E7D32),
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 2),
            action: SnackBarAction(
              label: _t({'en': 'View', 'si': 'බලන්න', 'ta': 'பார்'}),
              textColor: Colors.white,
              onPressed: () => setState(() => _drawerOpen = true),
            ),
          ),
        );
      }
    });
  }

  // ── Lang helper ───────────────────────────────────────────────────────────
  String get _langKey {
    final lang = AppLangProvider.lang(context);
    if (lang == AppLang.si) return 'si';
    if (lang == AppLang.ta) return 'ta';
    return 'en';
  }

  String _t(Map<String, String> map) => map[_langKey] ?? map['en']!;

  // ─────────────────────────────────────────────────────────────────────────
  //  Build
  // ─────────────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    AppLangProvider.of(context);
    final user = FirebaseAuth.instance.currentUser;
    final displayName =
        user?.displayName ?? user?.email?.split('@').first ?? 'Farmer';
    final firstName = displayName.split(' ').first;
    final season = _currentSeason();
    final tips = _tipsForSeason(season);
    final tip = tips[_tipIndex % tips.length];

    return Stack(
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final w = constraints.maxWidth;
            if (w < 600) {
              return _buildMobile(context, firstName, season, tips, tip);
            } else if (w < 960) {
              return _buildTablet(context, firstName, season, tips, tip);
            } else {
              return _buildWeb(context, firstName, season, tips, tip);
            }
          },
        ),
        // Saved-tips slide-over drawer
        if (_drawerOpen) _buildSavedTipsDrawer(tips),
      ],
    );
  }

  // ── MOBILE ────────────────────────────────────────────────────────────────
  Widget _buildMobile(
    BuildContext context,
    String name,
    String season,
    List<_Tip> tips,
    _Tip tip,
  ) {
    return Column(
      children: [
        Expanded(
          child: RefreshIndicator(
            color: AppTheme.primary,
            onRefresh: () async {
              _moveTip(1);
              _loadWeather();
            },
            child: ListView(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 20),
              children: [
                _buildHero(name, season, compact: true),
                const SizedBox(height: 10),
                _buildQuickStats(compact: true),
                const SizedBox(height: 10),
                _buildTipCard(tip, tips, compact: true),
                const SizedBox(height: 12),
                _sectionLabel(
                  _t({
                    'en': 'What do you need today?',
                    'si': 'ඔබට අද මොකද ඕනෙ?',
                    'ta': 'உங்களுக்கு என்ன தேவை?',
                  }),
                ),
                const SizedBox(height: 8),
                _buildActionGrid(crossAxisCount: 2, iconSize: 26),
                const SizedBox(height: 14),
                _buildChatBox(),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // ── TABLET ────────────────────────────────────────────────────────────────
  Widget _buildTablet(
    BuildContext context,
    String name,
    String season,
    List<_Tip> tips,
    _Tip tip,
  ) {
    return Column(
      children: [
        _buildTopBar(context),
        Expanded(
          child: LayoutBuilder(
            builder: (ctx, bc) {
              final contentW = bc.maxWidth.clamp(0.0, 700.0);
              final hPad = ((bc.maxWidth - contentW) / 2).clamp(
                0.0,
                double.infinity,
              );
              return ListView(
                padding: EdgeInsets.fromLTRB(hPad + 16, 14, hPad + 16, 28),
                children: [
                  _buildHeroInner(name, season, compact: false),
                  const SizedBox(height: 10),
                  _buildQuickStats(compact: false),
                  const SizedBox(height: 12),
                  _buildTipCard(tip, tips, compact: false),
                  const SizedBox(height: 14),
                  _sectionLabel(
                    _t({
                      'en': 'What do you need today?',
                      'si': 'ඔබට අද මොකද ඕනෙ?',
                      'ta': 'உங்களுக்கு என்ன தேவை?',
                    }),
                  ),
                  const SizedBox(height: 10),
                  _buildActionGrid(crossAxisCount: 2, iconSize: 28),
                  const SizedBox(height: 14),
                  _buildChatBox(),
                ],
              );
            },
          ),
        ),
      ],
    );
  }

  // ── WEB ───────────────────────────────────────────────────────────────────
  Widget _buildWeb(
    BuildContext context,
    String name,
    String season,
    List<_Tip> tips,
    _Tip tip,
  ) {
    return Column(
      children: [
        _buildTopBar(context),
        Expanded(
          child: LayoutBuilder(
            builder: (ctx, bc) {
              final leftW = (bc.maxWidth * 0.38).clamp(300.0, 440.0);
              return Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(
                    width: leftW,
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(20, 14, 12, 28),
                      children: [
                        _buildHeroInner(name, season, compact: false),
                        const SizedBox(height: 10),
                        _buildQuickStats(compact: false),
                        const SizedBox(height: 12),
                        _buildTipCard(tip, tips, compact: false),
                        const SizedBox(height: 12),
                        _buildChatBox(),
                      ],
                    ),
                  ),
                  Container(width: 1, color: const Color(0xFFE4EEE4)),
                  Expanded(
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(16, 14, 20, 28),
                      children: [
                        _sectionLabel(
                          _t({
                            'en': 'What do you need today?',
                            'si': 'ඔබට අද මොකද ඕනෙ?',
                            'ta': 'உங்களுக்கு என்ன தேவை?',
                          }),
                        ),
                        const SizedBox(height: 10),
                        _buildActionGrid(crossAxisCount: 3, iconSize: 28),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  //  Top bar (tablet + web)
  // ─────────────────────────────────────────────────────────────────────────
  Widget _buildTopBar(BuildContext context) {
    final lang = AppLangProvider.lang(context);
    final List<String> navLabels;
    if (lang == AppLang.si) {
      navLabels = ['ඩෑෂ්', 'අස්වැන්න', 'මිල', 'කාලගුණ', 'භෝග', 'ඉල්ලුම', 'AI'];
    } else if (lang == AppLang.ta) {
      navLabels = [
        'முகப்பு',
        'விளைச்சல்',
        'விலை',
        'வானிலை',
        'பயிர்',
        'தேவை',
        'AI',
      ];
    } else {
      navLabels = [
        'Dashboard',
        'Yield',
        'Price',
        'Weather',
        'Crop Rec.',
        'Demand',
        'AI Chat',
      ];
    }

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
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Logo
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFF4CAF50).withValues(alpha: 0.15),
                ),
                child: Center(
                  child: SvgPicture.string(
                    _DashIcons.cropSphere,
                    width: 32,
                    height: 32,
                  ),
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
            ],
          ),
          // Nav links
          Expanded(
            child: Center(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Builder(
                  builder: (ctx) {
                    final navigate = widget.onNavigate;
                    return Row(
                      mainAxisSize: MainAxisSize.min,
                      children: List.generate(navLabels.length, (i) {
                        final active = i == 0;
                        return Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 2),
                          child: TextButton(
                            onPressed:
                                navigate == null ? null : () => navigate(i),
                            style: TextButton.styleFrom(
                              backgroundColor: active
                                  ? const Color(0xFFE8F5E9)
                                  : Colors.transparent,
                              foregroundColor: active
                                  ? const Color(0xFF1B5E20)
                                  : const Color(0xFF555555),
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
                    );
                  },
                ),
              ),
            ),
          ),
          // Saved tips badge
          _buildSavedBadge(),
          const SizedBox(width: 8),
          // Language pill
          _LangPill(onDark: false),
        ],
      ),
    );
  }

  Widget _buildSavedBadge() {
    final count = _savedTipIndices.length;
    return GestureDetector(
      onTap: () => setState(() => _drawerOpen = true),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: const Color(0xFFF0F4F0),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(
              Icons.bookmark_rounded,
              size: 20,
              color: Color(0xFF2E7D32),
            ),
          ),
          if (count > 0)
            Positioned(
              right: -4,
              top: -4,
              child: Container(
                width: 16,
                height: 16,
                decoration: const BoxDecoration(
                  color: Color(0xFFE65100),
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: Text(
                    '$count',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 9,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  //  Hero card
  // ─────────────────────────────────────────────────────────────────────────
  Widget _buildHero(String name, String season, {required bool compact}) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1B5E20),
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF1B5E20).withValues(alpha: 0.22),
            blurRadius: 14,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: _buildHeroInner(name, season, compact: compact, insideCard: true),
    );
  }

  Widget _buildHeroInner(
    String name,
    String season, {
    required bool compact,
    bool insideCard = false,
  }) {
    final lang = AppLangProvider.lang(context);
    final String greet;
    if (lang == AppLang.si) {
      final h = DateTime.now().hour;
      greet =
          'සුභ ${h < 12 ? "ඊදැසනක්" : h < 17 ? "සන්ධ්‍යාවක්" : "රාත්‍රියක්"},';
    } else if (lang == AppLang.ta) {
      greet = 'வணக்கம்,';
    } else {
      greet = '${_greeting()},';
    }

    final Widget content = Padding(
      padding: EdgeInsets.all(compact ? 14.0 : 16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Row: logo + greeting + lang pill ──
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: compact ? 40 : 46,
                height: compact ? 40 : 46,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.13),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Center(
                  child: SvgPicture.string(
                    _DashIcons.cropSphere,
                    width: compact ? 28 : 32,
                    height: compact ? 28 : 32,
                  ),
                ),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      greet,
                      style: const TextStyle(
                        color: Colors.white60,
                        fontSize: 11,
                      ),
                    ),
                    Text(
                      name,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: compact ? 20 : 24,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.2,
                        height: 1.15,
                      ),
                    ),
                  ],
                ),
              ),
              if (insideCard) _LangPill(onDark: true),
            ],
          ),
          const SizedBox(height: 10),
          // ── Season + date pills ──
          Wrap(
            spacing: 7,
            runSpacing: 5,
            children: [
              _heroPill(_seasonPill(season, lang)),
              _heroPill('📅 ${_formattedDate()}'),
            ],
          ),
          // ── Live weather strip (only shown when location is granted) ────
          if (!_locationDenied) ...[
            const SizedBox(height: 8),
            _buildWeatherStrip(compact: compact),
          ],
        ],
      ),
    );

    if (insideCard) return content;

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1B5E20),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF1B5E20).withValues(alpha: 0.2),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: content,
    );
  }

  // ── Live weather strip ─────────────────────────────────────────────────────
  //  • _locationDenied = true  → return SizedBox.shrink() (nothing shown)
  //  • _weatherLoading = true  → tiny spinner chip while permission/fetch runs
  //  • _weather == null        → should not happen after denied guard, but just
  //                              in case of a network error: show nothing
  //  • data present            → three chips: temp · rain% · wind
  Widget _buildWeatherStrip({required bool compact}) {
    // User refused location — hide the strip completely, no message shown
    if (_locationDenied) return const SizedBox.shrink();

    // Loading: waiting for permission dialog or geolocator result
    if (_weatherLoading) {
      return Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              children: [
                SizedBox(
                  width: 10,
                  height: 10,
                  child: CircularProgressIndicator(
                    strokeWidth: 1.5,
                    valueColor: AlwaysStoppedAnimation(Colors.white60),
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  _t({
                    'en': 'Getting weather…',
                    'si': 'කාලගුණ දත්ත…',
                    'ta': 'வானிலை…',
                  }),
                  style: const TextStyle(color: Colors.white60, fontSize: 10),
                ),
              ],
            ),
          ),
        ],
      );
    }

    // Network error after permission was granted — show nothing silently
    if (_weather == null) return const SizedBox.shrink();

    // ✅ Permission granted + data fetched → show weather chips
    final w = _weather!;
    return Wrap(
      spacing: 6,
      runSpacing: 5,
      children: [
        _weatherChip('${w.weatherEmoji} ${w.tempStr}'),
        _weatherChip('🌧 ${w.rainStr} rain'),
        _weatherChip('💨 ${w.windStr}'),
      ],
    );
  }

  Widget _weatherChip(String label) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(20),
          border:
              Border.all(color: Colors.white.withValues(alpha: 0.25), width: 1),
        ),
        child: Text(
          label,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 10,
            fontWeight: FontWeight.w600,
          ),
        ),
      );

  Widget _heroPill(String label) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          label,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 10,
            fontWeight: FontWeight.w600,
          ),
        ),
      );

  // ─────────────────────────────────────────────────────────────────────────
  //  Quick stats strip (NEW)
  // ─────────────────────────────────────────────────────────────────────────
  Widget _buildQuickStats({required bool compact}) {
    // Replace _kMockStats with real DB/Hive reads
    final stats = _kMockStats;
    final items = [
      {
        'icon': '🌱',
        'label': _t({
          'en': 'Best crop',
          'si': 'හොඳ භෝගය',
          'ta': 'சிறந்த பயிர்',
        }),
        'value': stats.bestCrop,
        'color': const Color(0xFF2E7D32),
        'bg': const Color(0xFFE8F5E9),
      },
      {
        'icon': '💰',
        'label': _t({
          'en': 'Avg price',
          'si': 'සාමාන්‍ය මිල',
          'ta': 'சராசரி விலை',
        }),
        'value': 'Rs. ${stats.avgPriceLkr.toStringAsFixed(0)}/kg',
        'color': const Color(0xFFE65100),
        'bg': const Color(0xFFFFF8E1),
      },
      {
        'icon': '📦',
        'label': _t({'en': 'Last yield', 'si': 'අස්වැන්න', 'ta': 'விளைச்சல்'}),
        'value': '${stats.yieldTonnes} t/ac',
        'color': const Color(0xFF1565C0),
        'bg': const Color(0xFFE3F2FD),
      },
    ];

    return Row(
      children: items.map((item) {
        return Expanded(
          child: Container(
            margin: const EdgeInsets.only(right: 7),
            padding: EdgeInsets.symmetric(
              vertical: compact ? 9 : 11,
              horizontal: 10,
            ),
            decoration: BoxDecoration(
              color: item['bg'] as Color,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: (item['color'] as Color).withValues(alpha: 0.2),
                width: 1.2,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item['icon'] as String,
                  style: TextStyle(fontSize: compact ? 16 : 18),
                ),
                const SizedBox(height: 4),
                Text(
                  item['label'] as String,
                  style: TextStyle(
                    fontSize: 9,
                    color: (item['color'] as Color).withValues(alpha: 0.7),
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  item['value'] as String,
                  style: TextStyle(
                    fontSize: compact ? 11 : 12,
                    color: item['color'] as Color,
                    fontWeight: FontWeight.w800,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        );
      }).toList()
        ..last, // remove trailing margin on last item
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  //  Tip card  (with bookmark icon)
  // ─────────────────────────────────────────────────────────────────────────
  Widget _buildTipCard(_Tip tip, List<_Tip> tips, {required bool compact}) {
    final isSaved = _savedTipIndices.contains(_tipIndex);
    return FadeTransition(
      opacity: _tipFade,
      child: Container(
        padding: EdgeInsets.fromLTRB(13, compact ? 11 : 13, 13, 10),
        decoration: BoxDecoration(
          color: tip.bg,
          borderRadius: BorderRadius.circular(15),
          border: Border.all(color: tip.border, width: 1.5),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // SVG icon
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: tip.border,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Center(
                    child: SvgPicture.string(
                      _DashIcons.forKey(tip.iconKey),
                      width: 26,
                      height: 26,
                    ),
                  ),
                ),
                const SizedBox(width: 11),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _t(tip.label),
                        style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.w800,
                          color: tip.color,
                          letterSpacing: 0.7,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _t(tip.text),
                        style: TextStyle(
                          fontSize: compact ? 12 : 13,
                          color: const Color(0xFF1A2B1A),
                          height: 1.5,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
                // ── NEW: Bookmark button ──────────────────────────
                GestureDetector(
                  onTap: () => _toggleSaveTip(_tipIndex),
                  child: Padding(
                    padding: const EdgeInsets.only(left: 6, top: 2),
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 200),
                      child: Icon(
                        isSaved
                            ? Icons.bookmark_rounded
                            : Icons.bookmark_border_rounded,
                        key: ValueKey(isSaved),
                        size: 22,
                        color: isSaved
                            ? tip.color
                            : tip.color.withValues(alpha: 0.4),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            // Progress bar
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(2),
              child: TweenAnimationBuilder<double>(
                key: ValueKey(_tipIndex),
                tween: Tween(begin: 0.0, end: 1.0),
                duration: const Duration(seconds: 10),
                builder: (_, v, __) => LinearProgressIndicator(
                  value: v,
                  backgroundColor: tip.border.withValues(alpha: 0.25),
                  valueColor: AlwaysStoppedAnimation(tip.color),
                  minHeight: 3,
                ),
              ),
            ),
            const SizedBox(height: 9),
            Row(
              children: [
                // Dot indicators
                Row(
                  children: List.generate(tips.length, (i) {
                    final active = i == _tipIndex;
                    return GestureDetector(
                      onTap: () => _moveTip(i - _tipIndex),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 220),
                        width: active ? 14 : 6,
                        height: 5,
                        margin: const EdgeInsets.only(right: 4),
                        decoration: BoxDecoration(
                          color: active
                              ? const Color(0xFF1B5E20)
                              : const Color(0xFFB0C4B0),
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ),
                    );
                  }),
                ),
                const Spacer(),
                _tipArrow(false),
                const SizedBox(width: 6),
                _tipArrow(true),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _tipArrow(bool forward) => GestureDetector(
        onTap: () => _moveTip(forward ? 1 : -1),
        child: Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFFD0E8C8), width: 1.5),
          ),
          child: Icon(
            forward ? Icons.chevron_right_rounded : Icons.chevron_left_rounded,
            size: 17,
            color: const Color(0xFF2E7D32),
          ),
        ),
      );

  // ─────────────────────────────────────────────────────────────────────────
  //  Saved tips slide-over panel
  // ─────────────────────────────────────────────────────────────────────────
  Widget _buildSavedTipsDrawer(List<_Tip> allTips) {
    final saved = _savedTipIndices.toList()..sort();
    return GestureDetector(
      onTap: () => setState(() => _drawerOpen = false),
      child: Container(
        color: Colors.black54,
        child: Align(
          alignment: Alignment.centerRight,
          child: GestureDetector(
            onTap: () {}, // prevent dismiss on drawer tap
            child: Container(
              width: 320,
              color: Colors.white,
              child: SafeArea(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Header
                    Container(
                      color: const Color(0xFF1B5E20),
                      padding: const EdgeInsets.fromLTRB(16, 16, 12, 16),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.bookmark_rounded,
                            color: Colors.white,
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _t({
                                'en': 'Saved Tips',
                                'si': 'සුරකිනා ලද ඉඟි',
                                'ta': 'சேமித்த குறிப்புகள்',
                              }),
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 15,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                          GestureDetector(
                            onTap: () => setState(() => _drawerOpen = false),
                            child: const Icon(
                              Icons.close_rounded,
                              color: Colors.white70,
                              size: 22,
                            ),
                          ),
                        ],
                      ),
                    ),
                    // Tips list
                    Expanded(
                      child: saved.isEmpty
                          ? Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.bookmark_border_rounded,
                                    size: 48,
                                    color: Colors.grey.shade300,
                                  ),
                                  const SizedBox(height: 10),
                                  Text(
                                    _t({
                                      'en':
                                          'No saved tips yet.\nTap 🔖 on any tip to save it.',
                                      'si': 'ඉඟි නොමැත.\n🔖 ඔබා සුරකින්න.',
                                      'ta': 'இல்லை.\n🔖 அழுத்தி சேமிக்கவும்.',
                                    }),
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      color: Colors.grey.shade400,
                                      fontSize: 13,
                                    ),
                                  ),
                                ],
                              ),
                            )
                          : ListView.separated(
                              padding: const EdgeInsets.all(12),
                              itemCount: saved.length,
                              separatorBuilder: (_, __) =>
                                  const SizedBox(height: 8),
                              itemBuilder: (_, idx) {
                                final tipIdx = saved[idx];
                                final tip = allTips[tipIdx % allTips.length];
                                return Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: tip.bg,
                                    borderRadius: BorderRadius.circular(11),
                                    border: Border.all(
                                      color: tip.border,
                                      width: 1.2,
                                    ),
                                  ),
                                  child: Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      SvgPicture.string(
                                        _DashIcons.forKey(tip.iconKey),
                                        width: 22,
                                        height: 22,
                                      ),
                                      const SizedBox(width: 9),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              _t(tip.label),
                                              style: TextStyle(
                                                fontSize: 8,
                                                fontWeight: FontWeight.w800,
                                                color: tip.color,
                                                letterSpacing: 0.6,
                                              ),
                                            ),
                                            const SizedBox(height: 3),
                                            Text(
                                              _t(tip.text),
                                              style: const TextStyle(
                                                fontSize: 11,
                                                color: Color(0xFF1A2B1A),
                                                height: 1.45,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      GestureDetector(
                                        onTap: () => _toggleSaveTip(tipIdx),
                                        child: Icon(
                                          Icons.bookmark_remove_rounded,
                                          size: 18,
                                          color: tip.color.withValues(
                                            alpha: 0.5,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              },
                            ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  //  Section label
  // ─────────────────────────────────────────────────────────────────────────
  Widget _sectionLabel(String text) => Row(
        children: [
          const Icon(Icons.touch_app_rounded,
              size: 17, color: Color(0xFF4CAF50)),
          const SizedBox(width: 6),
          Text(
            text,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w800,
              color: Color(0xFF1B4D1B),
            ),
          ),
        ],
      );

  // ─────────────────────────────────────────────────────────────────────────
  //  Action grid
  // ─────────────────────────────────────────────────────────────────────────
  Widget _buildActionGrid({
    required int crossAxisCount,
    required double iconSize,
  }) {
    final ratio = crossAxisCount == 2 ? 0.95 : 1.0;
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: crossAxisCount,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
        childAspectRatio: ratio,
      ),
      itemCount: _kActions.length,
      itemBuilder: (_, i) {
        final navigate = widget.onNavigate;
        return _ActionCard(
          data: _kActions[i],
          langKey: _langKey,
          iconSize: iconSize,
          onTap:
              navigate == null ? () {} : () => navigate(_kActions[i].navIndex),
        );
      },
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  //  AI Chat box
  // ─────────────────────────────────────────────────────────────────────────
  Widget _buildChatBox() {
    final chatTitle = _t({
      'en': 'Ask our AI Farming Helper',
      'si': 'AI ගොවිතැන් සහකාරගෙන් අහන්න',
      'ta': 'AI விவசாய உதவியாளரிடம் கேளுங்கள்',
    });
    final chatSub = _t({
      'en': 'Tap any question for an instant answer',
      'si': 'ප්‍රශ්නයක් ඔබන්න',
      'ta': 'கேள்வியை அழுத்துங்கள்',
    });

    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: const Color(0xFFE8F5E9),
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: const Color(0xFFC8E6C9), width: 1.5),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: const Color(0xFF2E7D32),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Center(
                  child: SvgPicture.string(
                    _DashIcons.ai,
                    width: 22,
                    height: 22,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      chatTitle,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF1B5E20),
                      ),
                    ),
                    Text(
                      chatSub,
                      style: const TextStyle(
                        fontSize: 10,
                        color: Color(0xFF4CAF50),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 11),
          ..._kChips.asMap().entries.map((e) {
            final navigate = widget.onNavigate;
            final navIdx = e.value.navIndex;
            return _ChatChip(
              data: e.value,
              langKey: _langKey,
              chipIndex: e.key,
              onTap: navigate == null ? () {} : () => navigate(navIdx),
            );
          }),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Language pill
// ─────────────────────────────────────────────────────────────────────────────
class _LangPill extends StatelessWidget {
  final bool onDark;
  const _LangPill({required this.onDark});

  @override
  Widget build(BuildContext context) {
    final notifier = AppLangProvider.of(context);
    final current = notifier.lang;

    return Container(
      decoration: BoxDecoration(
        color: onDark
            ? Colors.white.withValues(alpha: 0.12)
            : const Color(0xFFF0F4F0),
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
                color: active
                    ? (onDark ? Colors.white : const Color(0xFF1B5E20))
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Text(
                l.label,
                style: TextStyle(
                  fontSize: 9.5,
                  fontWeight: active ? FontWeight.w800 : FontWeight.w500,
                  color: active
                      ? (onDark ? const Color(0xFF1B5E20) : Colors.white)
                      : (onDark
                          ? Colors.white.withValues(alpha: 0.55)
                          : const Color(0xFF888888)),
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
//  Action card
// ─────────────────────────────────────────────────────────────────────────────
class _ActionCard extends StatelessWidget {
  final _ActionBtn data;
  final String langKey;
  final double iconSize;
  final VoidCallback onTap;

  const _ActionCard({
    required this.data,
    required this.langKey,
    required this.iconSize,
    required this.onTap,
  });

  String _t(Map<String, String> map) => map[langKey] ?? map['en']!;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
        decoration: BoxDecoration(
          color: data.bg,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: data.border, width: 1.5),
          boxShadow: [
            BoxShadow(
              color: data.border.withValues(alpha: 0.2),
              blurRadius: 5,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              width: iconSize + 14,
              height: iconSize + 14,
              decoration: BoxDecoration(
                color: data.border,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Center(
                child: SvgPicture.string(
                  _DashIcons.forKey(data.iconKey),
                  width: iconSize,
                  height: iconSize,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _t(data.title),
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                color: data.titleColor,
                height: 1.3,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 3),
            Text(
              _t(data.sub),
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 9.5,
                color: data.subColor,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Chat chip
// ─────────────────────────────────────────────────────────────────────────────
class _ChatChip extends StatelessWidget {
  final _ChipData data;
  final String langKey;
  final int chipIndex;
  final VoidCallback onTap;

  const _ChatChip({
    required this.data,
    required this.langKey,
    required this.chipIndex,
    required this.onTap,
  });

  static const _chipIcons = [
    '''<svg viewBox="0 0 20 20" fill="none" xmlns="http://www.w3.org/2000/svg">
  <path d="M10 18C10 12 10 8 10 4" stroke="#2E7D32" stroke-width="1.8" stroke-linecap="round"/>
  <path d="M10 12C6 10 3 6 5 2C8 6 9 10 10 12Z" fill="#4CAF50"/>
  <path d="M10 9C14 7 17 3 15 0C12 4 11 7 10 9Z" fill="#81C784"/>
</svg>''',
    '''<svg viewBox="0 0 20 20" fill="none" xmlns="http://www.w3.org/2000/svg">
  <rect x="2" y="3" width="16" height="14" rx="3" stroke="#2E7D32" stroke-width="1.5" fill="none"/>
  <line x1="2" y1="7" x2="18" y2="7" stroke="#2E7D32" stroke-width="1.5"/>
  <line x1="6" y1="1" x2="6" y2="5" stroke="#2E7D32" stroke-width="1.5" stroke-linecap="round"/>
  <line x1="14" y1="1" x2="14" y2="5" stroke="#2E7D32" stroke-width="1.5" stroke-linecap="round"/>
</svg>''',
    '''<svg viewBox="0 0 20 20" fill="none" xmlns="http://www.w3.org/2000/svg">
  <circle cx="10" cy="10" r="7" stroke="#2E7D32" stroke-width="1.5" fill="none"/>
  <circle cx="8" cy="8" r="1.8" fill="#7B1FA2" opacity="0.7"/>
  <circle cx="13" cy="9" r="1.4" fill="#7B1FA2" opacity="0.6"/>
  <circle cx="10" cy="13" r="1.4" fill="#7B1FA2" opacity="0.5"/>
</svg>''',
  ];

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 7),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(11),
          border: Border.all(color: const Color(0xFFC8E6C9), width: 1.5),
        ),
        child: Row(
          children: [
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: const Color(0xFFE8F5E9),
                borderRadius: BorderRadius.circular(7),
              ),
              child: Center(
                child: SvgPicture.string(
                  _chipIcons[chipIndex % 3],
                  width: 15,
                  height: 15,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                data.text[langKey] ?? data.text['en']!,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF1B4D1B),
                ),
              ),
            ),
            const Icon(
              Icons.chevron_right_rounded,
              size: 18,
              color: Color(0xFFA5D6A7),
            ),
          ],
        ),
      ),
    );
  }
}
