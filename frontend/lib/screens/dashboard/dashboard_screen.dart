// lib/screens/dashboard/dashboard_screen.dart
// ─────────────────────────────────────────────────────────────────────────────
//  CropSphere — Farmer-first dashboard  (UPGRADED v2)
//
//  NEW in this version
//  ─────────────────────────────────────────────────────────────────────────
//  • Mobile: slim white app bar (logo + language pill + profile avatar).
//    No more full-width nav-label bar on phones.
//  • Profile avatar (photo or initial) opens a bottom sheet with
//    Profile / Saved Tips / Language / Logout.
//  • Hero replaced with a quiet greeting line + a dedicated, larger
//    weather card. Weather failures are now a tappable
//    "Tap to enable weather" chip instead of vanishing silently.
//  • Body text bumped up across the board (nothing under 12px; action
//    card titles now 14.5–15px) for outdoor/glare readability.
//  • Tip carousel now rotates every 20s and STOPS auto-advancing the
//    moment the user manually taps a dot/arrow (was restarting the
//    timer on every manual nav before).
//  • Saved tips are now keyed by "season#index" instead of a bare index,
//    so a season change can no longer silently repoint a saved tip at
//    the wrong content.
//  • Quick-stats row is explicitly labelled "sample data" until wired
//    to a real source, and the trailing-margin layout bug is fixed.
//  • Action cards: neutral white surface + light border (icon tile still
//    carries the color code) and proper InkWell ripple feedback.
//  • All existing functionality preserved. En / Sinhala / Tamil strings
//    unchanged in meaning, only extended where new UI needed copy.
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import '../../app_lang.dart';
import '../../services/profile_service.dart';
import '../../widgets/animated_lang_text.dart';
import '../../widgets/app_theme.dart';
import '../../widgets/brand_wordmark.dart';
import '../../widgets/top_nav_items.dart';
import '../../widgets/top_nav_metrics.dart';
import '../../widgets/language_control.dart';
import '../../widgets/price_comparison_card.dart';
import '../../widgets/profile_avatar_button.dart';
import '../../widgets/skeleton_loading.dart';
import '../../widgets/theme_toggle_button.dart';
import '../../widgets/todays_recommendation_hero.dart';
import '../profile/account_settings_screen.dart';

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
  static const _tipInterval = Duration(seconds: 20);

  // ── Saved tips (in-memory; swap for SharedPreferences persist) ────────────
  // Keyed by "season#index" so a season change never repoints a saved
  // tip at unrelated content.
  final Set<String> _savedTipKeys = {};

  // ── Weather ───────────────────────────────────────────────────────────────
  _WeatherData? _weather;
  bool _weatherLoading = true;
  // true → user denied/permanently denied location, or service disabled
  bool _locationDenied = false;
  // true → re-requesting won't help; must open device settings
  bool _permanentlyDenied = false;

  // ── Saved tips drawer ─────────────────────────────────────────────────────
  bool _drawerOpen = false;

  // ── Farm preferences ──────────────────────────────────────────────────────
  // Drive the recommendation hero and price comparison. Null until the
  // preferences fetch resolves, or if the farmer hasn't set them — both
  // widgets handle null themselves (prompt card / hidden respectively).
  String? _preferredDistrict;
  String? _preferredCrop;

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
    _loadFarmPreferences();
  }

  /// Farm district/crop for the hero + price comparison. A failure here is
  /// non-fatal: both widgets fall back to their "not set" presentation, so
  /// the rest of the dashboard is unaffected.
  Future<void> _loadFarmPreferences() async {
    try {
      final prefs = await ProfileService().getPreferences();
      if (!mounted) return;
      setState(() {
        _preferredDistrict = prefs.preferredDistrict;
        _preferredCrop = prefs.preferredCrop;
      });
    } catch (e) {
      debugPrint('Failed to load farm preferences: $e');
    }
  }

  /// Opens Account Settings, then re-reads preferences on return so the
  /// hero reflects a change the farmer just saved without a full reload.
  Future<void> _openFarmSettings() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const AccountSettingsScreen()),
    );
    if (mounted) _loadFarmPreferences();
  }

  @override
  void dispose() {
    _tipTimer?.cancel();
    _tipCtrl.dispose();
    super.dispose();
  }

  // ── Weather fetch (with real location permission flow) ───────────────────
  Future<void> _loadWeather() async {
    if (!mounted) return;
    setState(() {
      _weatherLoading = true;
      _locationDenied = false;
      _permanentlyDenied = false;
    });

    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      if (mounted) {
        setState(() {
          _weatherLoading = false;
          _locationDenied = true;
          _permanentlyDenied = true; // needs device settings
        });
      }
      return;
    }

    LocationPermission permission = await Geolocator.checkPermission();

    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    if (permission == LocationPermission.denied) {
      if (mounted) {
        setState(() {
          _weatherLoading = false;
          _locationDenied = true;
          _permanentlyDenied = false; // can ask again
        });
      }
      return;
    }

    if (permission == LocationPermission.deniedForever) {
      if (mounted) {
        setState(() {
          _weatherLoading = false;
          _locationDenied = true;
          _permanentlyDenied = true; // needs device settings
        });
      }
      return;
    }

    try {
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.low,
          timeLimit: Duration(seconds: 8),
        ),
      );

      final data = await _fetchWeather(lat: pos.latitude, lon: pos.longitude);
      if (mounted) {
        setState(() {
          _weather = data;
          _weatherLoading = false;
          _locationDenied = data == null; // network error → tappable retry
          _permanentlyDenied = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _weatherLoading = false;
          _locationDenied = true;
          _permanentlyDenied = false; // just retry
        });
      }
    }
  }

  // ── Tip helpers ───────────────────────────────────────────────────────────
  void _startTipTimer() {
    _tipTimer?.cancel();
    _tipTimer = Timer.periodic(_tipInterval, (_) {
      if (mounted) _moveTip(1);
    });
  }

  // `manual: true` means the user tapped a dot/arrow themselves — stop
  // autoplay for good instead of restarting the timer under them.
  Future<void> _moveTip(int dir, {bool manual = false}) async {
    final season = _currentSeason();
    final tips = _tipsForSeason(season);
    final next = ((_tipIndex + dir) % tips.length + tips.length) % tips.length;
    await _tipCtrl.reverse();
    if (!mounted) return;
    setState(() => _tipIndex = next);
    _tipCtrl.forward();
    if (manual) {
      _tipTimer?.cancel();
    } else {
      _startTipTimer();
    }
  }

  String _tipKey(String season, int index) => '$season#$index';

  void _toggleSaveTip(String season, int index) {
    final key = _tipKey(season, index);
    setState(() {
      if (_savedTipKeys.contains(key)) {
        _savedTipKeys.remove(key);
      } else {
        _savedTipKeys.add(key);
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

    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFDFF3DF), Color(0xFFEFF9EE), Color(0xFFFFFFFF)],
          stops: [0.0, 0.22, 0.55],
        ),
      ),
      child: Stack(
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final w = constraints.maxWidth;
              final h = constraints.maxHeight;

              // Keep accessibility font-scale bumps from blowing up cards
              // that were tuned for ~1.0x — still respects the user's OS
              // text-size preference, just within a safe band.
              final clampedScaler = MediaQuery.textScalerOf(
                context,
              ).clamp(minScaleFactor: 0.9, maxScaleFactor: 1.2);

              // Width alone doesn't "fit any device" — a portrait tablet and
              // a landscape tablet can share the same width class but need
              // very different layouts. So: pick the two-pane layout for
              // anything reasonably wide OR anything in landscape (phones
              // rotated, tablets rotated, laptops, desktops); reserve the
              // single-column layout for narrow/portrait devices only.
              //
              // Mobile itself is split into small / regular / large so a
              // 320px budget phone and a 480px "phablet" both get padding
              // and grid sizing proportional to their own screen instead
              // of one fixed layout stretched or squeezed to fit.
              final Widget content;
              if (w < 600) {
                content = _buildMobile(
                  context,
                  firstName,
                  season,
                  tips,
                  tip,
                  w,
                );
              } else if (w < 900 && h >= w) {
                // Portrait tablet (e.g. iPad portrait ~768–834px wide) —
                // single column, but height-aware so it doesn't strand a
                // block of empty space at the bottom.
                content = _buildTabletPortrait(
                  context,
                  firstName,
                  season,
                  tips,
                  tip,
                  w,
                );
              } else {
                // Landscape tablet, laptop, or desktop — two-pane layout,
                // capped and centred on ultra-wide monitors so the page
                // doesn't stretch into a thin strip of content lost in
                // white space.
                content = _buildWeb(context, firstName, season, tips, tip, w);
              }

              return MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: clampedScaler),
                child: content,
              );
            },
          ),
          // Saved-tips slide-over drawer
          if (_drawerOpen) _buildSavedTipsDrawer(),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  //  Personalised block — recommendation hero + price comparison.
  //  Shared by every breakpoint so the two stay adjacent and in the same
  //  order everywhere. Each child manages its own loading/empty state: the
  //  hero always renders something (hero card or "set your details"
  //  prompt), while the price card collapses to zero height whenever there
  //  is nothing honest to show — which is why the spacer below is tied to
  //  the same condition rather than emitted unconditionally.
  // ─────────────────────────────────────────────────────────────────────────
  List<Widget> _personalisedSection({double gap = 12}) {
    final showPrice = _preferredDistrict != null && _preferredCrop != null;
    return [
      TodaysRecommendationHero(
        preferredDistrict: _preferredDistrict,
        preferredCrop: _preferredCrop,
        langKey: _langKey,
        onOpenSettings: _openFarmSettings,
        onSeeFull: () => widget.onNavigate?.call(4), // Crop Recommendation
      ),
      if (showPrice) ...[
        SizedBox(height: gap),
        PriceComparisonCard(
          preferredDistrict: _preferredDistrict,
          preferredCrop: _preferredCrop,
          langKey: _langKey,
          onSeeFull: () => widget.onNavigate?.call(2), // Price
        ),
      ],
    ];
  }

  // ── MOBILE ────────────────────────────────────────────────────────────────
  // `width` is the real viewport width from the outer LayoutBuilder, so a
  // small phone (< 340px, e.g. an older/budget device), a regular phone
  // (340–420px), and a large phone/phablet (420–600px) each get padding,
  // icon sizing, and grid density scaled to their own screen rather than
  // one fixed 14px-everywhere layout being stretched or cramped.
  Widget _buildMobile(
    BuildContext context,
    String name,
    String season,
    List<_Tip> tips,
    _Tip tip,
    double width,
  ) {
    final bool isSmall = width < 340;
    final bool isLarge = width >= 420;
    final double hPad = isSmall ? 10 : (isLarge ? 16 : 14);

    return Column(
      children: [
        _buildMobileAppBar(context, width),
        Expanded(
          child: RefreshIndicator(
            color: AppTheme.primary,
            onRefresh: () async {
              _moveTip(1);
              _loadWeather();
            },
            child: ListView(
              padding: EdgeInsets.fromLTRB(hPad, 14, hPad, 20),
              children: [
                _buildGreetingLine(name, season),
                const SizedBox(height: 12),
                _buildWeatherCard(compact: true),
                const SizedBox(height: 12),
                ..._personalisedSection(gap: 10),
                const SizedBox(height: 10),
                _buildTipCard(tip, tips, season, compact: true),
                const SizedBox(height: 14),
                _buildChatBox(),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // ── TABLET (PORTRAIT) ────────────────────────────────────────────────────
  // Tuned against the actual portrait widths of common tablets rather than
  // one fixed layout stretched to fit everything 600–1024dp:
  //   Galaxy Tab 7.0 / 7.0+ / Tab 2 7.0      ~600dp
  //   Galaxy Tab 7.7                          ~600–650dp
  //   iPad Mini 4                             ~700dp
  //   iPad / iPad 2 / New iPad / Tab 8.9      ~760–770dp
  //   Galaxy Tab 10.1                         ~800dp
  //   iPad Pro 11" (M2)                       ~830–840dp
  // Below ~700dp the screen is too narrow for a second column without
  // squeezing everything, so content runs full-bleed single-column with
  // only small fixed side padding (no centered narrow strip). From
  // ~700dp up there's enough real width to split into an info rail +
  // action grid — same idea as the web layout — so the extra width is
  // actually used instead of sitting empty on either side of a centered
  // column.
  Widget _buildTabletPortrait(
    BuildContext context,
    String name,
    String season,
    List<_Tip> tips,
    _Tip tip,
    double width,
  ) {
    if (width < 700) {
      return _buildTabletCompact(context, name, season, tips, tip, width);
    }
    return _buildTabletSplit(context, name, season, tips, tip, width);
  }

  // Small/narrow portrait tablets (~600–700dp): single column, full-bleed.
  Widget _buildTabletCompact(
    BuildContext context,
    String name,
    String season,
    List<_Tip> tips,
    _Tip tip,
    double width,
  ) {
    final double hPad = width < 640 ? 16.0 : 20.0;
    const double gap = 13.0;

    return Column(
      children: [
        _buildTopBar(context),
        Expanded(
          child: LayoutBuilder(
            builder: (ctx, bc) {
              return SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(hPad, 16, hPad, 16),
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: bc.maxHeight - 32),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _buildGreetingLine(name, season),
                      const SizedBox(height: gap),
                      _buildWeatherCard(compact: false),
                      const SizedBox(height: gap),
                      ..._personalisedSection(gap: gap),
                      const SizedBox(height: gap),
                      _buildTipCard(tip, tips, season, compact: false),
                      const SizedBox(height: gap + 4),
                      _buildChatBox(),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  // Wider portrait tablets (~700–1024dp): now that the action grid is gone,
  // a two-pane split would leave a bare right-hand pane — so this reflows
  // to a single, centred column (info rail content + chat) instead, capped
  // to a comfortable reading width rather than stretched edge-to-edge.
  Widget _buildTabletSplit(
    BuildContext context,
    String name,
    String season,
    List<_Tip> tips,
    _Tip tip,
    double width,
  ) {
    const double gap = 14.0;

    return Column(
      children: [
        _buildTopBar(context),
        Expanded(
          child: SingleChildScrollView(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
                  child: Column(
                    children: [
                      _buildGreetingLine(name, season),
                      const SizedBox(height: gap),
                      _buildWeatherCard(compact: false),
                      const SizedBox(height: gap),
                      ..._personalisedSection(gap: gap),
                      const SizedBox(height: gap),
                      _buildTipCard(tip, tips, season, compact: false),
                      const SizedBox(height: gap),
                      _buildChatBox(),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ── WEB ───────────────────────────────────────────────────────────────────
  // Now that the action grid (the old right pane's only content) is gone,
  // this reflows to a single centred column instead of a two-pane split —
  // capped to a comfortable reading width so it doesn't stretch thin and
  // wide on desktop monitors.
  Widget _buildWeb(
    BuildContext context,
    String name,
    String season,
    List<_Tip> tips,
    _Tip tip,
    double width,
  ) {
    return Column(
      children: [
        _buildTopBar(context),
        Expanded(
          child: SingleChildScrollView(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 640),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
                  child: Column(
                    children: [
                      _buildGreetingLine(name, season),
                      const SizedBox(height: 12),
                      _buildWeatherCard(compact: false),
                      const SizedBox(height: 12),
                      ..._personalisedSection(),
                      const SizedBox(height: 12),
                      _buildTipCard(tip, tips, season, compact: false),
                      const SizedBox(height: 12),
                      _buildChatBox(),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  //  Slim mobile app bar — logo · saved-tips badge · language pill.
  //  No nav labels here by design (Dashboard/Yield/Price/... only show
  //  on tablet+ where there's room). Navigation on mobile happens via
  //  the action grid / chat / profile sheet.
  // ─────────────────────────────────────────────────────────────────────────
  Widget _buildMobileAppBar(BuildContext context, double width) {
    final bool isSmall = width < 340;
    final double logoSize = isSmall ? 26 : 30;
    return Container(
      height: 56,
      padding: EdgeInsets.symmetric(horizontal: isSmall ? 10 : 14),
      decoration: const BoxDecoration(
        // Faint green tint (not flat white) so the app bar reads as part
        // of the same brand wash as the rest of the screen.
        color: Color(0xFFFAFDFA),
        border: Border(bottom: BorderSide(color: Color(0xFFE4EEE4))),
      ),
      child: Row(
        children: [
          SvgPicture.string(
            _DashIcons.cropSphere,
            width: logoSize,
            height: logoSize,
          ),
          const SizedBox(width: 8),
          Text(
            'CropSphere',
            style: TextStyle(
              color: const Color(0xFF1B4D1B),
              fontSize: isSmall ? 14.5 : 16,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.2,
            ),
          ),
          const Spacer(),
          const LanguageControl(),
          const SizedBox(width: 8),
          const ThemeToggleButton(),
          const SizedBox(width: 8),
          const ProfileAvatarButton(diameter: 32),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  //  Top bar (tablet + web)
  // ─────────────────────────────────────────────────────────────────────────
  Widget _buildTopBar(BuildContext context) {
    final m = TopNavMetrics.of(context);
    final lang = AppLangProvider.lang(context);
    final List<String> navLabels;
    if (lang == AppLang.si) {
      navLabels = ['මුල', 'අස්වැන්න', 'මිල', 'කාලගුණ', 'භෝග', 'ඉල්ලුම', 'AI'];
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
        'Home',
        'Yield',
        'Price',
        'Weather',
        'Crop',
        'Demand',
        'Chat',
      ];
    }

    return Container(
      height: m.barHeight,
      decoration: const BoxDecoration(
        color: Color(0xFFFAFDFA),
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
                width: m.logoSize,
                height: m.logoSize,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFF4CAF50).withValues(alpha: 0.15),
                ),
                child: Center(
                  child: SvgPicture.string(
                    _DashIcons.cropSphere,
                    width: m.logoGlyphSize,
                    height: m.logoGlyphSize,
                  ),
                ),
              ),
              const BrandWordmark(),
            ],
          ),
          // Nav links
          Expanded(
            child: Center(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: TopNavItems(
                  labels: navLabels,
                  activeIndex: 0,
                  activeBg: const Color(0xFFE8F5E9),
                  activeColor: const Color(0xFF1B5E20),
                  onNavigate: widget.onNavigate,
                  metrics: m,
                ),
              ),
            ),
          ),
          const LanguageControl(),
          SizedBox(width: m.clusterGap),
          ThemeToggleButton(size: m.toggleIconSize),
          SizedBox(width: m.clusterGap),
          const ProfileAvatarButton(),
        ],
      ),
    );
  }


  // ─────────────────────────────────────────────────────────────────────────
  //  Greeting line + season/date pills (replaces the old green hero card)
  // ─────────────────────────────────────────────────────────────────────────
  Widget _buildGreetingLine(String name, String season) {
    final lang = AppLangProvider.lang(context);
    final String greet;
    if (lang == AppLang.si) {
      final h = DateTime.now().hour;
      greet =
          'සුභ ${h < 12
              ? "ඊදැසනක්"
              : h < 17
              ? "සන්ධ්‍යාවක්"
              : "රාත්‍රියක්"},';
    } else if (lang == AppLang.ta) {
      greet = 'வணக்கம்,';
    } else {
      greet = '${_greeting()},';
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        RichText(
          text: TextSpan(
            children: [
              TextSpan(
                text: '$greet ',
                style: const TextStyle(
                  color: Color(0xFF6B8F6B),
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
              TextSpan(
                text: name,
                style: const TextStyle(
                  color: Color(0xFF1B4D1B),
                  fontSize: 19,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 7,
          runSpacing: 6,
          children: [
            _pill(
              _seasonPill(season, lang),
              color: const Color(0xFF1B5E20),
              bg: const Color(0xFFE8F5E9),
            ),
            _pill(
              '📅 ${_formattedDate()}',
              color: const Color(0xFF3E5E3E),
              bg: const Color(0xFFF0F4F0),
            ),
          ],
        ),
      ],
    );
  }

  Widget _pill(String label, {required Color color, required Color bg}) =>
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: color,
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
      );

  // ─────────────────────────────────────────────────────────────────────────
  //  Weather card — dedicated real estate instead of tiny hero chips.
  //  • Loading  → small spinner row
  //  • Denied / error → tappable "Tap to enable weather" chip
  //  • Data     → large temp + rain% + wind
  // ─────────────────────────────────────────────────────────────────────────
  Widget _buildWeatherCard({required bool compact}) {
    if (_weatherLoading) {
      // Pulse pattern — this is the app's most-visited screen, so a static
      // block risks reading as frozen rather than loading even for a fast
      // call; the breathing pulse keeps it legibly "in progress". Shaped
      // like the loaded card (icon + temp line + rain/wind line) so the
      // layout doesn't jump once data arrives.
      return PulseFade(
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFFF4F8F4),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFE0EAE0)),
          ),
          child: Row(
            children: [
              const SkeletonBox(width: 32, height: 32, radius: 16),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: const [
                    SkeletonBox(width: 70, height: 18),
                    SizedBox(height: 6),
                    SkeletonBox(height: 12),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (_locationDenied || _weather == null) {
      return Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () {
            if (_permanentlyDenied) {
              Geolocator.openAppSettings();
            } else {
              _loadWeather();
            }
          },
          child: Ink(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF8E1),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFFFE082)),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.location_off_rounded,
                  size: 22,
                  color: Color(0xFFE65100),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    _t({
                      'en': 'Tap to enable weather',
                      'si': 'කාලගුණ ලබාගැනීමට මෙතන ඔබන්න',
                      'ta': 'வானிலை பெற இங்கே தட்டவும்',
                    }),
                    style: const TextStyle(
                      fontSize: 13,
                      color: Color(0xFFE65100),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const Icon(
                  Icons.chevron_right_rounded,
                  color: Color(0xFFE65100),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final w = _weather!;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFE3F2FD),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF90CAF9)),
      ),
      child: Row(
        children: [
          Text(w.weatherEmoji, style: const TextStyle(fontSize: 32)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  w.tempStr,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF0D47A1),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '🌧 ${w.rainStr} rain   💨 ${w.windStr}',
                  style: const TextStyle(
                    fontSize: 13,
                    color: Color(0xFF1565C0),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  //  Tip card  (with bookmark icon)
  // ─────────────────────────────────────────────────────────────────────────
  Widget _buildTipCard(
    _Tip tip,
    List<_Tip> tips,
    String season, {
    required bool compact,
  }) {
    final tipKey = _tipKey(season, _tipIndex);
    final isSaved = _savedTipKeys.contains(tipKey);
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
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          color: tip.color,
                          letterSpacing: 0.6,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _t(tip.text),
                        style: TextStyle(
                          fontSize: compact ? 13 : 14,
                          color: const Color(0xFF1A2B1A),
                          height: 1.5,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
                // Bookmark button
                Material(
                  color: Colors.transparent,
                  shape: const CircleBorder(),
                  child: InkWell(
                    customBorder: const CircleBorder(),
                    onTap: () => _toggleSaveTip(season, _tipIndex),
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
                duration: _tipInterval,
                builder: (_, v, _) => LinearProgressIndicator(
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
                      onTap: () => _moveTip(i - _tipIndex, manual: true),
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

  Widget _tipArrow(bool forward) => Material(
    color: Colors.white,
    shape: const CircleBorder(
      side: BorderSide(color: Color(0xFFD0E8C8), width: 1.5),
    ),
    child: InkWell(
      customBorder: const CircleBorder(),
      onTap: () => _moveTip(forward ? 1 : -1, manual: true),
      child: SizedBox(
        width: 28,
        height: 28,
        child: Icon(
          forward ? Icons.chevron_right_rounded : Icons.chevron_left_rounded,
          size: 17,
          color: const Color(0xFF2E7D32),
        ),
      ),
    ),
  );

  // ─────────────────────────────────────────────────────────────────────────
  //  Saved tips slide-over panel
  // ─────────────────────────────────────────────────────────────────────────
  Widget _buildSavedTipsDrawer() {
    final savedKeys = _savedTipKeys.toList()..sort();
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
                      child: savedKeys.isEmpty
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
                              itemCount: savedKeys.length,
                              separatorBuilder: (_, _) =>
                                  const SizedBox(height: 8),
                              itemBuilder: (_, idx) {
                                final key = savedKeys[idx];
                                final parts = key.split('#');
                                final season = parts[0];
                                final tipIdx =
                                    int.tryParse(
                                      parts.length > 1 ? parts[1] : '0',
                                    ) ??
                                    0;
                                final seasonTips = _tipsForSeason(season);
                                final tip =
                                    seasonTips[tipIdx % seasonTips.length];
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
                                                fontSize: 10,
                                                fontWeight: FontWeight.w800,
                                                color: tip.color,
                                                letterSpacing: 0.6,
                                              ),
                                            ),
                                            const SizedBox(height: 3),
                                            Text(
                                              _t(tip.text),
                                              style: const TextStyle(
                                                fontSize: 13,
                                                color: Color(0xFF1A2B1A),
                                                height: 1.45,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      GestureDetector(
                                        onTap: () =>
                                            _toggleSaveTip(season, tipIdx),
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
                    AnimatedLangText(
                      chatTitle,
                      style: const TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF1B5E20),
                      ),
                    ),
                    AnimatedLangText(
                      chatSub,
                      style: const TextStyle(
                        fontSize: 11.5,
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
    return Padding(
      padding: const EdgeInsets.only(bottom: 7),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(11),
          onTap: onTap,
          child: Ink(
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
                      fontSize: 13,
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
        ),
      ),
    );
  }
}
