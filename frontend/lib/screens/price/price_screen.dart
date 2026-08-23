// lib/screens/price/price_screen.dart
// ─────────────────────────────────────────────────────────────────────────────
//  CropSphere — Price Predictor (v2)
//
//  CHANGES FROM v1
//  ✅ Removed "Economic Conditions" card (Inflation/Fuel/Supply/Demand raw
//     sliders) — meaningless numbers for farmers. Replaced with plain-language
//     Market Supply / Market Demand (Low · Normal · High) choice chips.
//  ✅ Same shell as Dashboard/Yield: top nav bar, language pill, responsive
//     mobile/tablet/web layout, sticky "Predict" bar on mobile/tablet.
//  ✅ Fully trilingual (en/si/ta) throughout.
//  ✅ "Recent price" reference shown transparently to the farmer.
//  ✅ "Quantity to sell" input → estimated total revenue.
//  ✅ Result card: ✅ rising / ⚠️ falling banner vs. recent price.
//  ✅ WhatsApp share button on the result.
//  ✅ "Ask AI for More Info" button — same pattern as Yield screen.
//  ✅ Selling Tips card (collapsible), general farmer market advice.
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../app_lang.dart';
import '../../models/api_models.dart';
import '../../services/service_factory.dart';
import '../../widgets/animated_lang_text.dart';
import '../../widgets/app_theme.dart';
import '../../widgets/brand_wordmark.dart';
import '../../widgets/top_nav_metrics.dart';
import '../../widgets/language_control.dart';
import '../../widgets/profile_avatar_button.dart';
import '../../widgets/skeleton_loading.dart';
import '../../widgets/theme_toggle_button.dart';

typedef _L = Map<String, String>;

// ─────────────────────────────────────────────────────────────────────────────
//  Crop-to-district mapping (kept consistent with Yield screen)
// ─────────────────────────────────────────────────────────────────────────────
const Map<String, List<String>> _cropDistricts = {
  'Carrot': ['Nuwara Eliya', 'Badulla', 'Jaffna'],
  'Maize': ['Anuradhapura', 'Monaragala', 'Ampara'],
  'Green gram': ['Hambantota', 'Monaragala', 'Jaffna'],
  'Cowpea': ['Anuradhapura', 'Monaragala', 'Ampara'],
  'Finger millet': ['Anuradhapura', 'Monaragala', 'Ampara'],
  'Groundnut': ['Monaragala', 'Ampara', 'Batticaloa', 'Jaffna'],
};

const Map<String, String> _cropEmoji = {
  'Carrot': '🥕',
  'Maize': '🌽',
  'Green gram': '🫘',
  'Cowpea': '🟤',
  'Finger millet': '🌾',
  'Groundnut': '🥜',
};

// ─────────────────────────────────────────────────────────────────────────────
//  Trilingual display names — internal keys stay in English (used for API
//  calls, map lookups, etc). Only what's shown on screen gets translated.
// ─────────────────────────────────────────────────────────────────────────────
const Map<String, _L> _cropNames = {
  'Carrot': {'en': 'Carrot', 'si': 'කැරට්', 'ta': 'கேரட்'},
  'Maize': {'en': 'Maize', 'si': 'බඩඉරිඟු', 'ta': 'மக்காச்சோளம்'},
  'Green gram': {'en': 'Green gram', 'si': 'මුං ඇට', 'ta': 'பச்சைப்பயறு'},
  'Cowpea': {'en': 'Cowpea', 'si': 'කව්පි', 'ta': 'காராமணி'},
  'Finger millet': {'en': 'Finger millet', 'si': 'කුරක්කන්', 'ta': 'கேழ்வரகு'},
  'Groundnut': {'en': 'Groundnut', 'si': 'රටකජු', 'ta': 'வேர்க்கடலை'},
};

const Map<String, _L> _districtNames = {
  'Nuwara Eliya': {'en': 'Nuwara Eliya', 'si': 'නුවරඑළිය', 'ta': 'நுவரெலியா'},
  'Badulla': {'en': 'Badulla', 'si': 'බදුල්ල', 'ta': 'பதுளை'},
  'Anuradhapura': {
    'en': 'Anuradhapura',
    'si': 'අනුරාධපුරය',
    'ta': 'அனுராதபுரம்',
  },
  'Monaragala': {'en': 'Monaragala', 'si': 'මොනරාගල', 'ta': 'மொணராகலை'},
  'Ampara': {'en': 'Ampara', 'si': 'අම්පාර', 'ta': 'அம்பாறை'},
  'Hambantota': {'en': 'Hambantota', 'si': 'හම්බන්තොට', 'ta': 'அம்பாந்தோட்டை'},
  'Batticaloa': {'en': 'Batticaloa', 'si': 'මඩකලපුව', 'ta': 'மட்டக்களப்பு'},
  'Jaffna': {'en': 'Jaffna', 'si': 'යාපනය', 'ta': 'யாழ்ப்பாணம்'},
};

/// Look up a crop's display name, falling back to the raw key if a crop
/// isn't in the map yet (keeps the UI from crashing on new/unmapped crops).
String _cropLabel(String langKey, String? crop) {
  if (crop == null) return '';
  final m = _cropNames[crop];
  if (m == null) return crop;
  return m[langKey] ?? m['en'] ?? crop;
}

String _districtLabel(String langKey, String? district) {
  if (district == null) return '';
  final m = _districtNames[district];
  if (m == null) return district;
  return m[langKey] ?? m['en'] ?? district;
}

String _seasonLabel(String langKey, String? season) {
  if (season == null) return '';
  final match = _seasons.firstWhere(
    (s) => s['name']!['en'] == season,
    orElse: () => {
      'name': {'en': season, 'si': season, 'ta': season},
    },
  );
  return match['name']![langKey] ?? match['name']!['en'] ?? season;
}

// Recent farmgate reference price (LKR/kg) — feeds farmgatePriceLag1/2/4.
// Replace with real DB / market-board reads when available.
const Map<String, double> _kRecentPrice = {
  'Carrot': 58.0,
  'Maize': 48.0,
  'Green gram': 145.0,
  'Cowpea': 142.0,
  'Finger millet': 98.0,
  'Groundnut': 195.0,
};

// ─────────────────────────────────────────────────────────────────────────────
//  Season data — trilingual (same framing as Yield screen)
// ─────────────────────────────────────────────────────────────────────────────
final List<Map<String, _L>> _seasons = [
  {
    'name': {'en': 'Maha', 'si': 'මහ', 'ta': 'மகா'},
    'months': {
      'en': 'October – March',
      'si': 'ඔක්තෝබර් – මාර්තු',
      'ta': 'அக்டோபர் – மார்ச்',
    },
  },
  {
    'name': {'en': 'Yala', 'si': 'යල', 'ta': 'யாழ்'},
    'months': {
      'en': 'April – September',
      'si': 'අප්‍රේල් – සැප්තැම්බර්',
      'ta': 'ஏப்ரல் – செப்டம்பர்',
    },
  },
  {
    'name': {'en': 'Inter', 'si': 'අතරිම', 'ta': 'இடை'},
    'months': {
      'en': 'Mar – Apr & Sep – Oct',
      'si': 'මාර්-අප්‍රේල් & සැප්-ඔක්',
      'ta': 'மார்-ஏப் & செப்-அக்',
    },
  },
];

// ─────────────────────────────────────────────────────────────────────────────
//  Market level choice — Low / Normal / High, trilingual
// ─────────────────────────────────────────────────────────────────────────────
class _MarketLevel {
  final String key; // low / normal / high
  final _L label;
  final double index; // value sent to the model
  const _MarketLevel(this.key, this.label, this.index);
}

const List<_MarketLevel> _supplyLevels = [
  _MarketLevel('low', {'en': 'Low', 'si': 'අඩුයි', 'ta': 'குறைவு'}, 40),
  _MarketLevel('normal', {
    'en': 'Normal',
    'si': 'සාමාන්‍යයි',
    'ta': 'சாதாரணம்',
  }, 85),
  _MarketLevel('high', {'en': 'High', 'si': 'වැඩියි', 'ta': 'அதிகம்'}, 150),
];

const List<_MarketLevel> _demandLevels = [
  _MarketLevel('low', {'en': 'Low', 'si': 'අඩුයි', 'ta': 'குறைவு'}, 40),
  _MarketLevel('normal', {
    'en': 'Normal',
    'si': 'සාමාන්‍යයි',
    'ta': 'சாதாரணம்',
  }, 75),
  _MarketLevel('high', {'en': 'High', 'si': 'වැඩියි', 'ta': 'அதிகம்'}, 140),
];

// ─────────────────────────────────────────────────────────────────────────────
//  General selling tips — trilingual
// ─────────────────────────────────────────────────────────────────────────────
class _Tip {
  final _L title;
  final _L text;
  final IconData icon;
  final Color color;
  const _Tip({
    required this.title,
    required this.text,
    required this.icon,
    required this.color,
  });
}

const _kMarketTips = <_Tip>[
  _Tip(
    title: {
      'en': 'Sell early morning',
      'si': 'උදේම විකුණන්න',
      'ta': 'காலையில் விற்கவும்',
    },
    text: {
      'en':
          'Wholesale buyers pay the best rates at the early morning market — prices often drop by midday.',
      'si':
          'තොග ගැනුම්කරුවන් උදේ වෙළඳපොලේදී හොඳම මිල ගෙවයි — දහවල් වන විට මිල අඩු වේ.',
      'ta':
          'மொத்த வியாபாரிகள் காலை சந்தையில் சிறந்த விலை தருவார்கள் — மதியத்தில் விலை குறையும்.',
    },
    icon: Icons.wb_twilight,
    color: Color(0xFFE65100),
  ),
  _Tip(
    title: {
      'en': 'Compare multiple markets',
      'si': 'වෙළඳපොළ කිහිපයක් සසඳන්න',
      'ta': 'பல சந்தைகளை ஒப்பிடுங்கள்',
    },
    text: {
      'en':
          'Prices can vary 15–20% between nearby towns. Call ahead or check the app before transporting your harvest.',
      'si':
          'ආසන්න නගරවල මිල 15-20% කින් වෙනස් විය හැක. ප්‍රවාහනයට පෙර පරීක්ෂා කරන්න.',
      'ta':
          'அருகிலுள்ள நகரங்களில் விலை 15-20% வேறுபடலாம். கொண்டு செல்வதற்கு முன் சரிபாருங்கள்.',
    },
    icon: Icons.compare_arrows,
    color: Color(0xFF1565C0),
  ),
  _Tip(
    title: {
      'en': 'Use your cooperative',
      'si': 'සමිතිය හරහා විකුණන්න',
      'ta': 'கூட்டுறவு மூலம் விற்கவும்',
    },
    text: {
      'en':
          'Selling through a farmer cooperative reduces middleman cuts and can secure better bulk rates.',
      'si':
          'ගොවි සමිතියක් හරහා විකිණීම මැදිහත්කරු කප්පාදුව අඩු කර හොඳ තොග මිලක් ලබා දෙයි.',
      'ta':
          'விவசாய கூட்டுறவு மூலம் விற்பது இடைத்தரகர் கழிவை குறைத்து சிறந்த மொத்த விலையை தரும்.',
    },
    icon: Icons.groups,
    color: Color(0xFF2E7D32),
  ),
  _Tip(
    title: {
      'en': 'Grading improves price',
      'si': 'ශ්‍රේණිගත කිරීම මිල වැඩි කරයි',
      'ta': 'தரம் பிரித்தல் விலையை அதிகரிக்கும்',
    },
    text: {
      'en':
          'Sorting by size and removing damaged produce before sale can raise your average price by 10%+.',
      'si':
          'විකිණීමට පෙර ප්‍රමාණය අනුව වර්ග කර හානි වූ ඒවා ඉවත් කිරීමෙන් සාමාන්‍ය මිල 10%+ කින් වැඩි විය හැක.',
      'ta':
          'விற்பதற்கு முன் அளவின்படி பிரித்து சேதமான பொருட்களை நீக்குவதால் சராசரி விலை 10%+ அதிகரிக்கும்.',
    },
    icon: Icons.grading,
    color: Color(0xFF7B1FA2),
  ),
  _Tip(
    title: {
      'en': 'Transport in cool hours',
      'si': 'සිසිල් වේලාවක ප්‍රවාහනය කරන්න',
      'ta': 'குளிர்ச்சியான நேரத்தில் கொண்டு செல்லுங்கள்',
    },
    text: {
      'en':
          'Move produce before 9 AM or after 4 PM to reduce spoilage and weight loss from heat.',
      'si':
          'තාපයෙන් හානි හා බර අඩුවීම වළක්වා ගැනීමට උදේ 9ට පෙර හෝ සවස 4ට පසු ප්‍රවාහනය කරන්න.',
      'ta':
          'வெப்பத்தால் சேதம் மற்றும் எடை இழப்பை தவிர்க்க காலை 9 மணிக்கு முன் அல்லது மாலை 4 மணிக்குப் பிறகு கொண்டு செல்லுங்கள்.',
    },
    icon: Icons.local_shipping,
    color: Color(0xFF00695C),
  ),
];

// ─────────────────────────────────────────────────────────────────────────────
//  SVG icons (matching Dashboard / Yield)
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
    2 =>
      '<svg viewBox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg">'
          '<ellipse cx="11" cy="18" rx="6" ry="3.5" fill="$c" opacity="0.35"/>'
          '<ellipse cx="11" cy="15.5" rx="6" ry="3.5" fill="$c" opacity="0.6"/>'
          '<ellipse cx="11" cy="13" rx="6" ry="3.5" fill="$c"/>'
          '<path d="M19 8L21 5L23 8" stroke="$c" stroke-width="1.6" stroke-linecap="round" fill="none"/>'
          '<line x1="21" y1="5" x2="21" y2="11" stroke="$c" stroke-width="1.6" stroke-linecap="round"/>'
          '</svg>',
    3 =>
      '<svg viewBox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg">'
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
    4 =>
      '<svg viewBox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg">'
          '<path d="M12 22C12 16 12 11 12 6" stroke="$c" stroke-width="2" stroke-linecap="round"/>'
          '<path d="M12 15C8 13 4 9 6 4C10 8 11 12 12 15Z" fill="$c" opacity="0.65"/>'
          '<path d="M12 11C16 9 20 5 18 0C14 5 12 9 12 11Z" fill="$c"/>'
          '<circle cx="18" cy="5" r="4.5" fill="$c"/>'
          '<path d="M16 5L17.5 7L20 3.5" stroke="white" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round"/>'
          '</svg>',
    5 =>
      '<svg viewBox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg">'
          '<rect x="2" y="13" width="20" height="9" rx="2" fill="$c" opacity="0.35"/>'
          '<path d="M2 13Q12 7 22 13Z" fill="$c"/>'
          '<circle cx="7.5" cy="17" r="2" fill="$c" opacity="0.7"/>'
          '<circle cx="12" cy="16.5" r="2.3" fill="$c" opacity="0.55"/>'
          '<circle cx="16.5" cy="17.5" r="1.8" fill="$c" opacity="0.7"/>'
          '<path d="M10 7L12 3L14 7" stroke="$c" stroke-width="1.6" stroke-linecap="round" fill="none"/>'
          '<line x1="12" y1="3" x2="12" y2="9" stroke="$c" stroke-width="1.6" stroke-linecap="round"/>'
          '</svg>',
    _ =>
      '<svg viewBox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg">'
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
//  PriceScreen
// ─────────────────────────────────────────────────────────────────────────────
class PriceScreen extends StatefulWidget {
  final ValueChanged<int>? onNavigate;

  /// Optional callback to pre-fill a message in the AI Chat tab.
  final ValueChanged<String>? onAiChatContext;

  const PriceScreen({super.key, this.onNavigate, this.onAiChatContext});

  @override
  State<PriceScreen> createState() => _PriceScreenState();
}

class _PriceScreenState extends State<PriceScreen>
    with SingleTickerProviderStateMixin {
  // ── Section tabs: "Enter Details" and "Selling Tips" ───────────────────────
  late final TabController _tabController = TabController(
    length: 2,
    vsync: this,
  );

  // ── Selections ─────────────────────────────────────────────────────────────
  String? _selectedCrop;
  String? _selectedDistrict;
  String? _selectedSeason;
  String _supplyKey = 'normal';
  String _demandKey = 'normal';
  int _holidayFlag = 0;
  int _festivalFlag = 0;

  final _qtyCtrl = TextEditingController(text: '100');

  // ── Prediction state ───────────────────────────────────────────────────────
  bool _isLoading = false;
  PriceResponse? _result;
  String? _errorMessage;

  // ── Derived ────────────────────────────────────────────────────────────────
  List<String> get _availableDistricts =>
      _selectedCrop != null ? (_cropDistricts[_selectedCrop!] ?? []) : [];

  bool get _canPredict =>
      _selectedCrop != null &&
      _selectedDistrict != null &&
      _selectedSeason != null;

  double get _recentPrice => _kRecentPrice[_selectedCrop] ?? 80.0;

  double get _quantity => double.tryParse(_qtyCtrl.text) ?? 0;

  _MarketLevel get _supplyLevel =>
      _supplyLevels.firstWhere((l) => l.key == _supplyKey);
  _MarketLevel get _demandLevel =>
      _demandLevels.firstWhere((l) => l.key == _demandKey);

  // ── Language helpers ───────────────────────────────────────────────────────
  String get _langKey {
    final l = AppLangProvider.lang(context);
    if (l == AppLang.si) return 'si';
    if (l == AppLang.ta) return 'ta';
    return 'en';
  }

  String _t(_L m) => m[_langKey] ?? m['en']!;

  @override
  void dispose() {
    _tabController.dispose();
    _qtyCtrl.dispose();
    super.dispose();
  }

  // ── Predict ────────────────────────────────────────────────────────────────
  Future<void> _predict() async {
    if (!_canPredict) return;
    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _result = null;
    });
    try {
      final base = _recentPrice;
      final service = ServiceFactory.getService();
      final response = await service.predictPrice(
        PriceRequest(
          crop: _selectedCrop!,
          district: _selectedDistrict!,
          season: _selectedSeason!,
          weekOfYear: _weekOfYear(),
          inflationIndex: 1.15,
          fuelPriceIndex: 1.10,
          transportCostIndex: 1.10,
          supplyIndex: _supplyLevel.index,
          demandIndex: _demandLevel.index,
          holidayFlag: _holidayFlag,
          festivalFlag: _festivalFlag,
          farmgatePriceLag1: base,
          farmgatePriceLag2: base * 0.98,
          farmgatePriceLag4: base * 0.95,
        ),
      );
      setState(() => _result = response);
    } catch (e) {
      setState(
        () => _errorMessage = _t({
          'en': 'Prediction failed: ${e.toString()}',
          'si': 'පුරෝකථනය අසාර්ථකයි: ${e.toString()}',
          'ta': 'கணிப்பு தோல்வியடைந்தது: ${e.toString()}',
        }),
      );
    } finally {
      setState(() => _isLoading = false);
    }
  }

  // ── Price trend helpers ────────────────────────────────────────────────────
  /// The figure the prediction is compared against. Prefers the backend's
  /// per-crop average (the same one the dashboard's price comparison uses)
  /// so the two screens can't disagree about whether today's price is above
  /// or below average; falls back to the local _kRecentPrice table only
  /// when the backend reported no baseline at all.
  double get _comparisonBaseline =>
      _result?.hasAverage == true
      ? _result!.averageFarmgatePriceLkrKg
      : _recentPrice;

  double get _pctChange {
    if (_result == null) return 0;
    final predicted = _result!.predictedFarmgatePriceLkrKg;
    final baseline = _comparisonBaseline;
    if (baseline <= 0) return 0;
    return (predicted - baseline) / baseline * 100;
  }

  bool get _isRising => _pctChange >= 0;

  double get _estimatedRevenue =>
      (_result?.predictedFarmgatePriceLkrKg ?? 0) * _quantity;

  Color _confColor(String c) => switch (c.toLowerCase()) {
    'high' => AppTheme.success,
    'medium' => AppTheme.warning,
    _ => AppTheme.error,
  };

  // ── AI Chat context string ─────────────────────────────────────────────────
  String _buildAiContext() {
    final farmgate = _result!.predictedFarmgatePriceLkrKg.toStringAsFixed(0);
    final retail = _result!.predictedRetailPriceLkrKg.toStringAsFixed(0);
    // Quote whichever baseline the on-screen % change was actually computed
    // against, so the assistant's advice can't contradict the figure the
    // farmer is looking at.
    final baseline = _result!.hasAverage
        ? 'The average farmgate price for this crop is Rs. '
              '${_result!.averageFarmgatePriceLkrKg.toStringAsFixed(0)}/kg.'
        : 'Recent price was Rs. ${_recentPrice.toStringAsFixed(0)}/kg.';
    return 'My price prediction for $_selectedCrop in $_selectedDistrict '
        '($_selectedSeason season): farmgate Rs. $farmgate/kg, retail Rs. $retail/kg. '
        '$baseline '
        'Please give me detailed advice on the best time and place to sell, and how to get a better price.';
  }

  // ── WhatsApp share ─────────────────────────────────────────────────────────
  Future<void> _shareOnWhatsApp() async {
    if (_result == null) return;
    final farmgate = _result!.predictedFarmgatePriceLkrKg.toStringAsFixed(0);
    final retail = _result!.predictedRetailPriceLkrKg.toStringAsFixed(0);
    final cropEn = _cropLabel('en', _selectedCrop);
    final cropSi = _cropLabel('si', _selectedCrop);
    final cropTa = _cropLabel('ta', _selectedCrop);
    final distEn = _districtLabel('en', _selectedDistrict);
    final distSi = _districtLabel('si', _selectedDistrict);
    final distTa = _districtLabel('ta', _selectedDistrict);
    final seasonEn = _seasonLabel('en', _selectedSeason);
    final seasonSi = _seasonLabel('si', _selectedSeason);
    final seasonTa = _seasonLabel('ta', _selectedSeason);
    final msg = _t({
      'en':
          'CropSphere Price Estimate\n$cropEn — $distEn ($seasonEn)\n'
          'Farmgate: Rs. $farmgate/kg\nRetail: Rs. $retail/kg\n'
          'Estimated revenue for ${_quantity.toStringAsFixed(0)} kg: Rs. ${_estimatedRevenue.toStringAsFixed(0)}',
      'si':
          'CropSphere මිල ඇස්තමේන්තුව\n$cropSi — $distSi ($seasonSi)\n'
          'ගොවිපොළ මිල: රු. $farmgate/kg\nසිල්ලර මිල: රු. $retail/kg\n'
          'kg ${_quantity.toStringAsFixed(0)} සඳහා ආදායම: රු. ${_estimatedRevenue.toStringAsFixed(0)}',
      'ta':
          'CropSphere விலை மதிப்பீடு\n$cropTa — $distTa ($seasonTa)\n'
          'பண்ணை விலை: Rs. $farmgate/kg\nசில்லறை விலை: Rs. $retail/kg\n'
          '${_quantity.toStringAsFixed(0)} kg-க்கான வருமானம்: Rs. ${_estimatedRevenue.toStringAsFixed(0)}',
    });
    final uri = Uri.parse('https://wa.me/?text=${Uri.encodeComponent(msg)}');
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _t({
                'en': 'Could not open WhatsApp.',
                'si': 'WhatsApp විවෘත කළ නොහැක.',
                'ta': 'WhatsApp-ஐ திறக்க முடியவில்லை.',
              }),
            ),
          ),
        );
      }
    }
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
            _buildTopBar(context, w),
            _buildSectionTabBar(w),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [_buildDetailsTab(w), _buildTipsTab(w)],
              ),
            ),
          ],
        );
      },
    );
  }

  // ── Section tabs — "Enter Details" and "Selling Tips" live side by side ───
  //    so the long tips list doesn't force extra scrolling in the main form.
  Widget _buildSectionTabBar(double width) {
    final compact = width < 380;
    return Container(
      color: Colors.white,
      child: TabBar(
        controller: _tabController,
        labelColor: const Color(0xFFBF360C),
        unselectedLabelColor: AppTheme.textMuted,
        indicatorColor: const Color(0xFFE65100),
        indicatorWeight: 3,
        labelStyle: TextStyle(
          fontSize: compact ? 12 : 13.5,
          fontWeight: FontWeight.w700,
        ),
        unselectedLabelStyle: TextStyle(
          fontSize: compact ? 12 : 13.5,
          fontWeight: FontWeight.w600,
        ),
        tabs: [
          Tab(
            height: 44,
            icon: const Icon(Icons.edit_note_rounded, size: 18),
            iconMargin: const EdgeInsets.only(bottom: 2),
            text: _t({
              'en': 'Enter Details',
              'si': 'විස්තර ඇතුළත් කරන්න',
              'ta': 'விவரங்களை உள்ளிடவும்',
            }),
          ),
          Tab(
            height: 44,
            icon: const Icon(Icons.tips_and_updates_outlined, size: 18),
            iconMargin: const EdgeInsets.only(bottom: 2),
            // Slightly bolder so this tab stands out.
            child: Text(
              _t({
                'en': 'Selling Tips',
                'si': 'විකිණීමේ ඉඟි',
                'ta': 'விற்பனை குறிப்புகள்',
              }),
              style: const TextStyle(fontWeight: FontWeight.w900),
            ),
          ),
        ],
      ),
    );
  }

  // ── Details tab — resizes for mobile / tablet / web ────────────────────────
  Widget _buildDetailsTab(double width) {
    if (width >= 960) return _buildWebDetails(width);
    if (width >= 600) return _buildTabletDetails(width);
    return _buildMobileDetails(width);
  }

  Widget _buildMobileDetails(double width) {
    final bool isSmall = width < 340;
    final double hPad = isSmall ? 12 : 14;
    return Stack(
      children: [
        SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(hPad, 14, hPad, 100),
          child: _formColumn(),
        ),
        _stickyPredict(),
      ],
    );
  }

  // 600–960dp portrait/landscape tablets: content width and side padding
  // scale with the real viewport instead of one fixed max-width.
  Widget _buildTabletDetails(double width) {
    final targetContentW = width < 760 ? width - 32 : 680.0;
    final hPad = ((width - targetContentW) / 2).clamp(16.0, 220.0);
    return Stack(
      children: [
        SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(hPad, 14, hPad, 100),
          child: _formColumn(),
        ),
        _stickyPredict(),
      ],
    );
  }

  // Web (≥960dp): form on the left, checklist/result on the right — with
  // Selling Tips now living in its own tab, this left column is short
  // enough that it fits without scrolling on most desktop viewports.
  Widget _buildWebDetails(double width) {
    final leftW = (width * 0.4).clamp(340.0, 480.0);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          width: leftW,
          child: Stack(
            children: [
              SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 16, 12, 100),
                child: _formColumn(webLeft: true),
              ),
              _stickyPredict(),
            ],
          ),
        ),
        Container(width: 1, color: const Color(0xFFE4EEE4)),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 16, 20, 28),
            child: _rightPanel(),
          ),
        ),
      ],
    );
  }

  // ── Selling Tips tab — its own scroll area, always expanded here ──────────
  Widget _buildTipsTab(double width) {
    final bool isWeb = width >= 960;
    final double maxW = isWeb ? 760 : double.infinity;
    final double hPad = isWeb
        ? ((width - maxW) / 2).clamp(16.0, 400.0)
        : (width < 340 ? 12.0 : (width < 600 ? 16.0 : 24.0));
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(hPad, 16, hPad, 28),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxW),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.tips_and_updates,
                  size: 18,
                  color: Color(0xFFBF360C),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _t({
                      'en': 'Selling Tips',
                      'si': 'විකිණීමේ ඉඟි',
                      'ta': 'விற்பனை குறிப்புகள்',
                    }),
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFFBF360C),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ..._kMarketTips.map(
              (tip) => Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(13),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: tip.color.withValues(alpha: 0.2)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: tip.color.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(9),
                      ),
                      child: Icon(tip.icon, size: 18, color: tip.color),
                    ),
                    const SizedBox(width: 11),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _t(tip.title),
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w800,
                              color: tip.color,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            _t(tip.text),
                            style: const TextStyle(
                              fontSize: 12,
                              color: AppTheme.textSecondary,
                              height: 1.45,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Top bar ────────────────────────────────────────────────────────────────
  Widget _buildTopBar(BuildContext context, double width) {
    if (width < 600) return _buildMobileTopBar(width);
    return _buildFullTopBar(context);
  }

  // ── Mobile top bar — logo + language pill only. ────────────────────────────
  //    Nav labels (Dashboard/Yield/Price/Weather/Crop Rec./Demand/AI Chat)
  //    are dropped here — there's no room, and navigation on mobile happens
  //    through the dashboard's own action grid instead.
  Widget _buildMobileTopBar(double width) {
    final bool isSmall = width < 340;
    return Container(
      height: 56,
      padding: EdgeInsets.symmetric(horizontal: isSmall ? 10 : 14),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Color(0xFFE4EEE4))),
      ),
      child: Row(
        children: [
          Container(
            width: isSmall ? 34 : 38,
            height: isSmall ? 34 : 38,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: const Color(0xFF4CAF50).withValues(alpha: 0.15),
            ),
            child: Center(
              child: SvgPicture.string(
                _cropSphereSvg,
                width: isSmall ? 22 : 26,
                height: isSmall ? 22 : 26,
              ),
            ),
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

  // ── Tablet/web top bar — logo + nav labels + language pill. ────────────────
  Widget _buildFullTopBar(BuildContext context) {
    final m = TopNavMetrics.of(context);
    final lang = AppLangProvider.lang(context);
    final List<String> navLabels = lang == AppLang.si
        ? ['මුල', 'අස්වැන්න', 'මිල', 'කාලගුණ', 'භෝග', 'ඉල්ලුම', 'AI']
        : lang == AppLang.ta
        ? ['முகப்பு', 'விளைச்சல்', 'விலை', 'வானிலை', 'பயிர்', 'தேவை', 'AI']
        : [
            'Home',
            'Yield',
            'Price',
            'Weather',
            'Crop',
            'Demand',
            'Chat',
          ];

    const activeBg = Color(0xFFFFF8E1);
    const activeColor = Color(0xFFE65100);

    return Container(
      height: m.barHeight,
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
            width: m.logoSize,
            height: m.logoSize,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: const Color(0xFF4CAF50).withValues(alpha: 0.15),
            ),
            child: Center(
              child: SvgPicture.string(_cropSphereSvg, width: 32, height: 32),
            ),
          ),
          const BrandWordmark(),
          Expanded(
            child: Center(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: List.generate(navLabels.length, (i) {
                    final active = i == 2;
                    return Padding(
                      padding: EdgeInsets.symmetric(horizontal: m.itemGap),
                      child: TextButton(
                        onPressed: widget.onNavigate == null
                            ? null
                            : () => widget.onNavigate!(i),
                        style: TextButton.styleFrom(
                          backgroundColor: active
                              ? activeBg
                              : Colors.transparent,
                          foregroundColor: active
                              ? activeColor
                              : const Color(0xFF555555),
                          padding: EdgeInsets.symmetric(
                            horizontal: m.itemPadH,
                            vertical: m.itemPadV,
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
                            fontSize: m.labelSize,
                            fontWeight: active
                                ? FontWeight.w700
                                : FontWeight.w500,
                          ),
                        ),
                      ),
                    );
                  }),
                ),
              ),
            ),
          ),
          const LanguageControl(),
          const SizedBox(width: 8),
          ThemeToggleButton(size: m.toggleIconSize),
          const SizedBox(width: 8),
          ProfileAvatarButton(diameter: m.avatarSize),
        ],
      ),
    );
  }

  // ── Form column — Crop/Location, Market Conditions, Quantity only; ────────
  //    Selling Tips now lives in its own tab, which is what keeps this
  //    column short enough to fit without a forced scroll on web/tablet.
  Widget _formColumn({bool webLeft = false}) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _pageHeader(),
      const SizedBox(height: 16),
      _cropQuickChips(),
      const SizedBox(height: 16),
      _sectionTitle(
        _t({
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
        _t({
          'en': 'Market Conditions',
          'si': 'වෙළඳපොළ තත්ත්වය',
          'ta': 'சந்தை நிலைமைகள்',
        }),
        Icons.storefront,
      ),
      const SizedBox(height: 10),
      _marketConditionsCard(),
      const SizedBox(height: 20),
      _sectionTitle(
        _t({
          'en': 'Quantity to Sell',
          'si': 'විකිණීමට ප්‍රමාණය',
          'ta': 'விற்பனை அளவு',
        }),
        Icons.scale,
      ),
      const SizedBox(height: 10),
      _quantityCard(),
      if (!webLeft) ...[
        const SizedBox(height: 16),
        _inputChecklist(),
        const SizedBox(height: 10),
        if (_isLoading) _resultSkeleton(),
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
      if (_isLoading) ...[_resultSkeleton(), const SizedBox(height: 14)],
      if (_errorMessage != null) ...[_errorCard(), const SizedBox(height: 14)],
      if (_result != null) ...[_resultCard(), const SizedBox(height: 14)],
      if (_result == null && _errorMessage == null && !_isLoading)
        _emptyResultPlaceholder(),
    ],
  );

  // ── Page header ────────────────────────────────────────────────────────────
  Widget _pageHeader() => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      gradient: const LinearGradient(
        colors: [Color(0xFFE65100), Color(0xFFFB8C00)],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
      borderRadius: BorderRadius.circular(14),
      boxShadow: [
        BoxShadow(
          color: const Color(0xFFE65100).withValues(alpha: 0.3),
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
            _navSvg(2, Colors.white),
            width: 26,
            height: 26,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AnimatedLangText(
                _t({
                  'en': 'Price Predictor',
                  'si': 'මිල පුරෝකථකය',
                  'ta': 'விலை கணிப்பான்',
                }),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              AnimatedLangText(
                _t({
                  'en': 'AI-powered market price estimate',
                  'si': 'AI-ශක්තිමත් වෙළඳපොළ මිල ඇස්තමේන්තුව',
                  'ta': 'AI-சார்ந்த சந்தை விலை மதிப்பீடு',
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
        _t({
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
        children: _cropDistricts.keys.map((crop) {
          final active = _selectedCrop == crop;
          final emoji = _cropEmoji[crop] ?? '🌿';
          return GestureDetector(
            onTap: () => setState(() {
              _selectedCrop = crop;
              _selectedDistrict = null;
              _result = null;
            }),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              decoration: BoxDecoration(
                color: active ? const Color(0xFFE65100) : Colors.white,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: active
                      ? const Color(0xFFE65100)
                      : const Color(0xFFFFD9A8),
                  width: active ? 2 : 1.5,
                ),
                boxShadow: active
                    ? [
                        BoxShadow(
                          color: const Color(0xFFE65100).withValues(alpha: 0.2),
                          blurRadius: 6,
                          offset: const Offset(0, 2),
                        ),
                      ]
                    : [],
              ),
              child: Text(
                '$emoji  ${_cropLabel(_langKey, crop)}',
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
          label: _t({
            'en': 'Select Crop',
            'si': 'භෝගය තෝරන්න',
            'ta': 'பயிர் தேர்ந்தெடுக்கவும்',
          }),
          value: _selectedCrop,
          items: _cropDistricts.keys.toList(),
          icon: Icons.eco,
          itemLabel: (c) => _cropLabel(_langKey, c),
          onChanged: (val) => setState(() {
            _selectedCrop = val;
            _selectedDistrict = null;
            _result = null;
          }),
        ),
        const SizedBox(height: 12),
        _nullDropdown(
          label: _t({
            'en': 'Select District',
            'si': 'දිස්ත්‍රික්කය',
            'ta': 'மாவட்டம்',
          }),
          value: _selectedDistrict,
          items: _availableDistricts,
          icon: Icons.location_on,
          itemLabel: (d) => _districtLabel(_langKey, d),
          hint: _selectedCrop != null
              ? _t({
                  'en':
                      'Valid districts for ${_cropLabel('en', _selectedCrop)}',
                  'si': '${_cropLabel('si', _selectedCrop)} සඳහා දිස්ත්‍රික්ක',
                  'ta': '${_cropLabel('ta', _selectedCrop)}-க்கான மாவட்டங்கள்',
                })
              : _t({
                  'en': 'Select a crop first',
                  'si': 'පළමු භෝගය තෝරන්න',
                  'ta': 'முதலில் பயிர் தேர்ந்தெடுக்கவும்',
                }),
          enabled: _selectedCrop != null,
          onChanged: (val) => setState(() {
            _selectedDistrict = val;
            _result = null;
          }),
        ),
        const SizedBox(height: 12),
        _seasonDropdown(),
        if (_selectedCrop != null) ...[
          const SizedBox(height: 10),
          _infoBox(
            _t({
              'en':
                  'Recent price for ${_cropLabel('en', _selectedCrop)}: Rs. ${_recentPrice.toStringAsFixed(0)}/kg',
              'si':
                  '${_cropLabel('si', _selectedCrop)} සඳහා මෑත මිල: රු. ${_recentPrice.toStringAsFixed(0)}/kg',
              'ta':
                  '${_cropLabel('ta', _selectedCrop)}-க்கான சமீபத்திய விலை: Rs. ${_recentPrice.toStringAsFixed(0)}/kg',
            }),
            color: const Color(0xFFE65100),
            icon: Icons.history,
          ),
        ],
      ],
    ),
  );

  Widget _seasonDropdown() {
    return DropdownButtonFormField<String>(
      initialValue: _selectedSeason,
      hint: Text(
        _t({'en': 'Select Season', 'si': 'කන්නය', 'ta': 'பருவம்'}),
        style: const TextStyle(color: AppTheme.textMuted),
      ),
      decoration: InputDecoration(
        labelText: _t({'en': 'Season', 'si': 'කන්නය', 'ta': 'பருவம்'}),
        prefixIcon: const Icon(
          Icons.calendar_month,
          color: Color(0xFFE65100),
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
    );
  }

  // ── Market conditions card (replaces "Economic Conditions") ───────────────
  Widget _marketConditionsCard() => _card(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          _t({
            'en': 'How much of this crop is in the market right now?',
            'si': 'මේ භෝගය දැනට වෙළඳපොළේ කොපමණ තිබේද?',
            'ta': 'இந்த பயிர் தற்போது சந்தையில் எவ்வளவு உள்ளது?',
          }),
          style: const TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w700,
            color: AppTheme.textPrimary,
          ),
        ),
        const SizedBox(height: 8),
        _levelChips(
          levels: _supplyLevels,
          selectedKey: _supplyKey,
          color: const Color(0xFF1565C0),
          onChanged: (k) => setState(() => _supplyKey = k),
        ),
        const SizedBox(height: 18),
        Text(
          _t({
            'en': 'How eager are buyers right now?',
            'si': 'ගැනුම්කරුවන්ගේ උනන්දුව දැනට කොපමණද?',
            'ta': 'வாங்குபவர்களின் ஆர்வம் தற்போது எவ்வளவு?',
          }),
          style: const TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w700,
            color: AppTheme.textPrimary,
          ),
        ),
        const SizedBox(height: 8),
        _levelChips(
          levels: _demandLevels,
          selectedKey: _demandKey,
          color: const Color(0xFF2E7D32),
          onChanged: (k) => setState(() => _demandKey = k),
        ),
        const SizedBox(height: 18),
        _toggleRow(
          icon: Icons.celebration_outlined,
          color: const Color(0xFF6A1B9A),
          title: _t({
            'en': 'Holiday Week',
            'si': 'නිවාඩු සතිය',
            'ta': 'விடுமுறை வாரம்',
          }),
          subtitle: _t({
            'en': 'Public holiday falls this week',
            'si': 'මේ සතියේ රජයේ නිවාඩුවක් තිබේ',
            'ta': 'இந்த வாரம் பொது விடுமுறை உள்ளது',
          }),
          value: _holidayFlag == 1,
          onChanged: (v) => setState(() => _holidayFlag = v ? 1 : 0),
        ),
        const SizedBox(height: 10),
        _toggleRow(
          icon: Icons.festival_outlined,
          color: const Color(0xFFE65100),
          title: _t({
            'en': 'Festival Week',
            'si': 'උත්සව සතිය',
            'ta': 'திருவிழா வாரம்',
          }),
          subtitle: _t({
            'en': 'Avurudu, Vesak, or a major festival this week',
            'si': 'අවුරුදු, වෙසක් හෝ ප්‍රධාන උත්සවයක් මේ සතියේ',
            'ta': 'அவுருது, வெசாக் அல்லது பெரும் திருவிழா இவ்வாரம்',
          }),
          value: _festivalFlag == 1,
          onChanged: (v) => setState(() => _festivalFlag = v ? 1 : 0),
        ),
      ],
    ),
  );

  Widget _levelChips({
    required List<_MarketLevel> levels,
    required String selectedKey,
    required Color color,
    required ValueChanged<String> onChanged,
  }) => Row(
    children: levels.map((l) {
      final active = l.key == selectedKey;
      return Expanded(
        child: GestureDetector(
          onTap: () => onChanged(l.key),
          child: Container(
            margin: EdgeInsets.only(right: l.key == levels.last.key ? 0 : 8),
            padding: const EdgeInsets.symmetric(vertical: 10),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: active ? color : color.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: active ? color : color.withValues(alpha: 0.25),
                width: active ? 2 : 1.2,
              ),
            ),
            child: Text(
              _t(l.label),
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: active ? Colors.white : color,
              ),
            ),
          ),
        ),
      );
    }).toList(),
  );

  Widget _toggleRow({
    required IconData icon,
    required Color color,
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.05),
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: color.withValues(alpha: 0.2)),
    ),
    child: Row(
      children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(9),
          ),
          child: Icon(icon, size: 17, color: color),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: color,
                ),
              ),
              Text(
                subtitle,
                style: const TextStyle(
                  fontSize: 10.5,
                  color: AppTheme.textMuted,
                ),
              ),
            ],
          ),
        ),
        Switch(value: value, onChanged: onChanged, activeThumbColor: color),
      ],
    ),
  );

  // ── Quantity card ──────────────────────────────────────────────────────────
  Widget _quantityCard() => _card(
    child: Row(
      children: [
        Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: const Color(0xFFE65100).withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: const Icon(Icons.scale, color: Color(0xFFE65100), size: 22),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _t({
                  'en': 'How much do you plan to sell?',
                  'si': 'ඔබ විකිණීමට සැලසුම් කරන ප්‍රමාණය?',
                  'ta': 'நீங்கள் விற்க திட்டமிடும் அளவு?',
                }),
                style: const TextStyle(
                  fontSize: 11.5,
                  color: AppTheme.textMuted,
                ),
              ),
              const SizedBox(height: 6),
              TextField(
                controller: _qtyCtrl,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[\d.]')),
                ],
                onChanged: (_) => setState(() {}),
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFFE65100),
                ),
                decoration: InputDecoration(
                  suffixText: 'kg',
                  isDense: true,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 10,
                  ),
                ),
              ),
              if (_result != null) ...[
                const SizedBox(height: 6),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.bolt_rounded,
                      size: 13,
                      color: Colors.grey.shade500,
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        _t({
                          'en':
                              'Estimated revenue updates instantly as you change this — the price itself only changes when you tap Predict again.',
                          'si':
                              'මෙය වෙනස් කරන විට ඇස්තමේන්තුගත ආදායම වහාම යාවත්කාලීන වේ — මිල වෙනස් වන්නේ ඔබ නැවත Predict ඔබන විට පමණි.',
                          'ta':
                              'இதை மாற்றும்போது மதிப்பிடப்பட்ட வருமானம் உடனடியாக புதுப்பிக்கப்படும் — நீங்கள் மீண்டும் Predict அழுத்தும்போது மட்டுமே விலை மாறும்.',
                        }),
                        style: TextStyle(
                          fontSize: 10,
                          color: Colors.grey.shade500,
                          height: 1.35,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ],
    ),
  );

  // ── Input checklist ────────────────────────────────────────────────────────
  Widget _inputChecklist() {
    final items = [
      (
        _selectedCrop != null,
        _t({'en': 'Crop selected', 'si': 'භෝගය', 'ta': 'பயிர்'}),
        _cropLabel(_langKey, _selectedCrop),
      ),
      (
        _selectedDistrict != null,
        _t({
          'en': 'District selected',
          'si': 'දිස්ත්‍රික්කය',
          'ta': 'மாவட்டம்',
        }),
        _districtLabel(_langKey, _selectedDistrict),
      ),
      (
        _selectedSeason != null,
        _t({'en': 'Season selected', 'si': 'කන්නය', 'ta': 'பருவம்'}),
        _seasonLabel(_langKey, _selectedSeason),
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
                    ? _t({
                        'en': 'Ready to predict!',
                        'si': 'පුරෝකථනයට සූදානම්!',
                        'ta': 'கணிக்க தயார்!',
                      })
                    : _t({
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
                      color: item.$1
                          ? AppTheme.textPrimary
                          : AppTheme.textMuted,
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
                : const Icon(Icons.price_check),
            label: Text(
              _isLoading
                  ? _t({
                      'en': 'Predicting...',
                      'si': 'පුරෝකථනය...',
                      'ta': 'கணிக்கிறோம்...',
                    })
                  : _canPredict
                  ? _t({
                      'en': 'Predict Price',
                      'si': 'මිල පුරෝකථනය',
                      'ta': 'விலையை கணிக்கவும்',
                    })
                  : _t({
                      'en': 'Complete 3 steps above first',
                      'si': 'ඉහළ පියවර 3 සම්පූර්ණ කරන්න',
                      'ta': 'மேலே 3 படிகள் முடிக்கவும்',
                    }),
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: _canPredict
                  ? const Color(0xFFE65100)
                  : Colors.grey.shade400,
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
  //  Result card — ✅ rising vs ⚠️ falling banner, price boxes, revenue,
  //  WhatsApp share, Ask AI
  // ──────────────────────────────────────────────────────────────────────────
  Widget _resultCard() {
    final farmgate = _result!.predictedFarmgatePriceLkrKg;
    final retail = _result!.predictedRetailPriceLkrKg;
    final confidence = _result!.confidence;
    final isMock = _result!.isMock;
    final rising = _isRising;
    final pct = _pctChange;
    final resultColor = rising ? AppTheme.success : AppTheme.error;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Trend banner ─────────────────────────────────────────────────────
        Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: rising ? const Color(0xFFE8F5E9) : const Color(0xFFFFEBEE),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: resultColor.withValues(alpha: 0.45),
              width: 1.5,
            ),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: resultColor.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  rising
                      ? Icons.trending_up_rounded
                      : Icons.trending_down_rounded,
                  color: resultColor,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      rising
                          ? _t({
                              'en': '✅ Prices Rising — Good Time to Sell',
                              'si': '✅ මිල ඉහළ යනවා — විකිණීමට හොඳ කාලයයි',
                              'ta': '✅ விலை உயர்கிறது — விற்க நல்ல நேரம்',
                            })
                          : _t({
                              'en': '⚠️ Prices Falling — Consider Waiting',
                              'si':
                                  '⚠️ මිල පහත වැටෙනවා — රැඳී සිටීම සලකා බලන්න',
                              'ta':
                                  '⚠️ விலை குறைகிறது — காத்திருக்க பரிசீலிக்கவும்',
                            }),
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: resultColor,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      rising
                          ? _t({
                              'en':
                                  'Predicted price is ${pct.abs().toStringAsFixed(0)}% above your recent price. Good conditions to sell now.',
                              'si':
                                  'පුරෝකථිත මිල ඔබේ මෑත මිලට වඩා ${pct.abs().toStringAsFixed(0)}% ඉහළයි. දැන් විකිණීමට හොඳ කාලයයි.',
                              'ta':
                                  'கணிக்கப்பட்ட விலை உங்கள் சமீபத்திய விலையை விட ${pct.abs().toStringAsFixed(0)}% அதிகம். இப்போது விற்க நல்ல நேரம்.',
                            })
                          : _t({
                              'en':
                                  'Predicted price is ${pct.abs().toStringAsFixed(0)}% below your recent price. Check nearby markets or wait if you can store safely.',
                              'si':
                                  'පුරෝකථිත මිල ඔබේ මෑත මිලට වඩා ${pct.abs().toStringAsFixed(0)}% අඩුයි. ආසන්න වෙළඳපොළ පරීක්ෂා කරන්න හෝ ආරක්ෂිතව ගබඩා කළ හැකි නම් රැඳී සිටින්න.',
                              'ta':
                                  'கணிக்கப்பட்ட விலை உங்கள் சமீபத்திய விலையை விட ${pct.abs().toStringAsFixed(0)}% குறைவு. அருகிலுள்ள சந்தைகளை சரிபார்க்கவும் அல்லது பாதுகாப்பாக சேமிக்க முடிந்தால் காத்திருங்கள்.',
                            }),
                      style: TextStyle(
                        fontSize: 11.5,
                        color: resultColor,
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
            gradient: const LinearGradient(
              colors: [Color(0xFFE65100), Color(0xFFFB8C00)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(14),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFFE65100).withValues(alpha: 0.35),
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
                    _t({
                      'en': 'Price Prediction',
                      'si': 'මිල පුරෝකථනය',
                      'ta': 'விலை கணிப்பு',
                    }),
                    style: const TextStyle(color: Colors.white70, fontSize: 13),
                  ),
                  if (isMock)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.4),
                        ),
                      ),
                      child: const Text(
                        'MOCK DATA',
                        style: TextStyle(color: Colors.white, fontSize: 10),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _priceBox(
                    _t({
                      'en': 'Farmgate Price',
                      'si': 'ගොවිපොළ මිල',
                      'ta': 'பண்ணை விலை',
                    }),
                    farmgate,
                    Colors.white,
                  ),
                  Container(width: 1, height: 60, color: Colors.white24),
                  _priceBox(
                    _t({
                      'en': 'Retail Price',
                      'si': 'සිල්ලර මිල',
                      'ta': 'சில்லறை விலை',
                    }),
                    retail,
                    Colors.white70,
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          _t({
                            'en': 'Estimated revenue',
                            'si': 'ඇස්තමේන්තුගත ආදායම',
                            'ta': 'மதிப்பிடப்பட்ட வருமானம்',
                          }),
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 11,
                          ),
                        ),
                        Text(
                          '${_quantity.toStringAsFixed(0)} kg',
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Rs. ${_estimatedRevenue.toStringAsFixed(0)}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.circle, size: 9, color: _confColor(confidence)),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      confidence.toUpperCase() == 'HIGH'
                          ? _t({
                              'en': 'We\'re quite sure about this estimate',
                              'si': 'මෙම ඇස්තමේන්තුව ගැන හොඳ විශ්වාසයකි',
                              'ta': 'இந்த மதிப்பீட்டில் நம்பிக்கை உள்ளது',
                            })
                          : confidence.toUpperCase() == 'MEDIUM'
                          ? _t({
                              'en': 'Fairly confident — prices may vary',
                              'si': 'සාධාරණ විශ්වාසයකි — මිල වෙනස් විය හැක',
                              'ta': 'மிதமான நம்பிக்கை — விலை மாறலாம்',
                            })
                          : _t({
                              'en':
                                  'Approximate estimate — confirm with your local market',
                              'si':
                                  'ආසන්න ඇස්තමේන්තුවකි — දේශීය වෙළඳපොළෙන් තහවුරු කරන්න',
                              'ta':
                                  'தோராயமான மதிப்பீடு — உள்ளூர் சந்தையில் உறுதிப்படுத்தவும்',
                            }),
                      style: TextStyle(
                        color: _confColor(confidence),
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                      textAlign: TextAlign.center,
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
                      _t({'en': 'Crop', 'si': 'භෝගය', 'ta': 'பயிர்'}),
                      _cropLabel(_langKey, _result!.crop),
                    ),
                    _vDiv(),
                    _rStat(
                      _t({
                        'en': 'District',
                        'si': 'දිස්ත්‍රික්කය',
                        'ta': 'மாவட்டம்',
                      }),
                      _districtLabel(_langKey, _selectedDistrict),
                    ),
                    _vDiv(),
                    _rStat(
                      _t({'en': 'Season', 'si': 'කන්නය', 'ta': 'பருவம்'}),
                      _seasonLabel(_langKey, _selectedSeason),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 12),

        // ── Share + Ask AI buttons ──────────────────────────────────────────────
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _shareOnWhatsApp,
                icon: const Icon(
                  Icons.share,
                  size: 18,
                  color: Color(0xFF2E7D32),
                ),
                label: Text(
                  _t({'en': 'Share', 'si': 'බෙදාගන්න', 'ta': 'பகிரவும்'}),
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF2E7D32),
                  ),
                ),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: Color(0xFF2E7D32), width: 1.5),
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              flex: 2,
              child: ElevatedButton.icon(
                onPressed: () {
                  final ctx = _buildAiContext();
                  widget.onAiChatContext?.call(ctx);
                  widget.onNavigate?.call(6);
                },
                icon: SvgPicture.string(
                  _navSvg(6, Colors.white),
                  width: 18,
                  height: 18,
                ),
                label: Text(
                  _t({
                    'en': 'Ask AI for More Info',
                    'si': 'AI වෙතින් තව තොරතුරු',
                    'ta': 'AI-இடம் கூடுதல் தகவல்',
                  }),
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1B5E20),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  elevation: 2,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _priceBox(String label, double price, Color color) => Column(
    children: [
      Text(label, style: const TextStyle(color: Colors.white70, fontSize: 12)),
      const SizedBox(height: 6),
      Text(
        'Rs. ${price.toStringAsFixed(0)}',
        style: TextStyle(
          color: color,
          fontSize: 26,
          fontWeight: FontWeight.bold,
        ),
      ),
      const Text('/kg', style: TextStyle(color: Colors.white54, fontSize: 12)),
    ],
  );

  Widget _emptyResultPlaceholder() => Container(
    padding: const EdgeInsets.all(24),
    decoration: BoxDecoration(
      color: const Color(0xFFFFF8E1).withValues(alpha: 0.5),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: const Color(0xFFFFE082)),
    ),
    child: Column(
      children: [
        SvgPicture.string(
          _navSvg(2, const Color(0xFFE0B486)),
          width: 48,
          height: 48,
        ),
        const SizedBox(height: 12),
        Text(
          _t({
            'en': 'Your price prediction will appear here',
            'si': 'ඔබේ මිල පුරෝකථනය මෙතැන දිස්වේ',
            'ta': 'உங்கள் விலை கணிப்பு இங்கே தோன்றும்',
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
          _t({
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

  /// Shown in place of the empty placeholder while a prediction is in
  /// flight — the result card is text-heavy (headline price figure +
  /// narrative breakdown), so Typewriter fits: bars reveal left-to-right
  /// like the eventual text being "written in".
  Widget _resultSkeleton() => _card(
    child: TypewriterSkeleton(
      lineWidthFractions: const [0.5, 1.0, 0.9, 0.7, 0.85, 0.4],
      lineHeight: 11,
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
      Icon(icon, size: 16, color: const Color(0xFFE65100)),
      const SizedBox(width: 6),
      AnimatedLangText(
        title,
        style: const TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w700,
          color: Color(0xFFBF360C),
        ),
      ),
    ],
  );

  Widget _infoBox(
    String text, {
    required Color color,
    required IconData icon,
  }) => Container(
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

  Widget _nullDropdown({
    required String label,
    required String? value,
    required List<String> items,
    required IconData icon,
    required ValueChanged<String?> onChanged,
    String? hint,
    bool enabled = true,
    String Function(String)? itemLabel,
  }) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      DropdownButtonFormField<String>(
        initialValue: value,
        hint: Text(label, style: const TextStyle(color: AppTheme.textMuted)),
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: Icon(
            icon,
            color: enabled ? const Color(0xFFE65100) : AppTheme.textMuted,
            size: 20,
          ),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 10,
          ),
          fillColor: enabled ? null : Colors.grey.withValues(alpha: 0.04),
        ),
        // `value` (e) stays the English key used for API calls/lookups —
        // only the label shown to the farmer is translated via itemLabel.
        items: enabled
            ? items
                  .map(
                    (e) => DropdownMenuItem(
                      value: e,
                      child: Text(itemLabel != null ? itemLabel(e) : e),
                    ),
                  )
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
        overflow: TextOverflow.ellipsis,
      ),
    ],
  );

  Widget _vDiv() => Container(width: 1, height: 28, color: Colors.white24);
}
