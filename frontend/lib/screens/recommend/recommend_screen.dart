// lib/screens/recommend/recommend_screen.dart
// ─────────────────────────────────────────────────────────────────────────────
//  CropSphere — Crop Recommender (v2, farmer-first)
//
//  UPGRADES FROM v1
//  ✅ Full trilingual support (English / Sinhala / Tamil) — no hardcoded text
//  ✅ Shared top nav bar (matches Dashboard/Yield) — "Crop Rec." bolded (index 4)
//  ✅ Live weather auto-fetched by district (Open-Meteo, no API key) instead of
//     asking the farmer to guess rainfall/temperature/humidity
//  ✅ Soil inputs simplified: sensible typical defaults shown by default;
//     raw pH / N-P-K sliders now hidden behind an "I know my soil test
//     results" toggle for farmers who actually have that data
//  ✅ Fixed weekOfYear bug (was hardcoded to 10 — now computed from today's date)
//  ✅ Quick season chips (emoji), matching Dashboard's crop-chip style
//  ✅ Result cards: crop emoji + medal rank + plain-language verdict banner
//     (green "good match" / amber "fair match") instead of bare check/cross
//     icons with no explanation
//  ✅ Cross-navigation: "Predict Yield for this crop" and "Ask AI" buttons on
//     every recommendation
//  ✅ Removed the screen's own Scaffold — this screen is hosted inside the
//     app shell like Dashboard/Yield, so it now returns a bare layout widget
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../../app_lang.dart';
import '../../models/api_models.dart';
import '../../services/service_factory.dart';
import '../../utils/farm_context.dart';
import '../../widgets/animated_lang_text.dart';
import '../../widgets/app_theme.dart';
import '../../widgets/brand_wordmark.dart';
import '../../widgets/language_control.dart';
import '../../widgets/profile_avatar_button.dart';
import '../../widgets/skeleton_loading.dart';
import '../../widgets/theme_toggle_button.dart';

typedef _L = Map<String, String>;


// District display names — official Sinhala/Tamil district names, not a
// literal word-for-word translation. The English key is kept as the value
// sent to the backend; only the label shown to the farmer changes.
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



// ─────────────────────────────────────────────────────────────────────────────
//  Season & irrigation data — trilingual, consistent with Yield screen
// ─────────────────────────────────────────────────────────────────────────────
final List<Map<String, _L>> _seasons = [
  {
    'name': {'en': 'Maha', 'si': 'මහ', 'ta': 'மகா'},
    'emoji': {'en': '🌧️', 'si': '🌧️', 'ta': '🌧️'},
    'months': {
      'en': 'October – March',
      'si': 'ඔක්තෝබර් – මාර්තු',
      'ta': 'அக்டோபர் – மார்ச்',
    },
    'desc': {
      'en': 'Main season, driven by the north-east monsoon.',
      'si': 'උතුරු-නැගෙනහිර මෝසමේ ප්‍රධාන කන්නය.',
      'ta': 'வடகிழக்கு பருவமழையால் இயங்கும் முக்கிய பருவம்.',
    },
  },
  {
    'name': {'en': 'Yala', 'si': 'යල', 'ta': 'யாலா'},
    'emoji': {'en': '☀️', 'si': '☀️', 'ta': '☀️'},
    'months': {
      'en': 'April – September',
      'si': 'අප්‍රේල් – සැප්තැම්බර්',
      'ta': 'ஏப்ரல் – செப்டம்பர்',
    },
    'desc': {
      'en': 'Secondary season, supported by the south-west monsoon.',
      'si': 'දකුණු-බටහිර මෝසමේ ද්විතීය කන්නය.',
      'ta': 'தென்மேற்கு பருவமழையால் ஆதரிக்கப்படும் இரண்டாம் பருவம்.',
    },
  },
  {
    'name': {'en': 'Inter', 'si': 'අන්තර්', 'ta': 'இடை'},
    'emoji': {'en': '🌤️', 'si': '🌤️', 'ta': '🌤️'},
    'months': {
      'en': 'Mar–Apr & Sep–Oct',
      'si': 'මාර්-අප්‍රේල් & සැප්-ඔක්',
      'ta': 'மார்-ஏப் & செப்-அக்',
    },
    'desc': {
      'en': 'Short break between seasons — best for fast-growing crops.',
      'si': 'කන්න අතර කෙටි විරාමය — ඉක්මනින් වැඩෙන භෝග සඳහා වඩාත් සුදුසුයි.',
      'ta':
          'பருவங்களுக்கு இடையிலான குறுகிய இடைவெளி — வேகமாக வளரும் பயிர்களுக்கு சிறந்தது.',
    },
  },
];

final List<Map<String, _L>> _irrigationTypes = [
  {
    'value': {'en': 'drip', 'si': 'drip', 'ta': 'drip'},
    'label': {
      'en': 'Drip Irrigation',
      'si': 'බිංදු ජලනය',
      'ta': 'சொட்டு நீர்ப்பாசனம்',
    },
    'desc': {
      'en': 'Water delivered directly to roots — most water-efficient.',
      'si': 'ජලය කෙලින් මූල වෙත — ඉහළ ජල කාර්යක්ෂමතාව.',
      'ta': 'வேர்களுக்கு நேரடியாக நீர் — அதிக நீர் திறன்.',
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
      'en': 'Water sprayed evenly — good for upland vegetables.',
      'si': 'ජලය සමව ඉසිනු ලැබේ — උස් බිම් එළවළු වගාවට හොඳයි.',
      'ta': 'நீர் சீராக தெளிக்கப்படும் — மேட்டு காய்கறிகளுக்கு நல்லது.',
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
      'en': 'Relies entirely on natural rainfall.',
      'si': 'සම්පූර්ණයෙන් ස්වාභාවික වර්ෂාව මත රඳාපවතී.',
      'ta': 'முற்றிலும் இயற்கை மழையை நம்புகிறது.',
    },
  },
];

// Soil/NPK defaults, district coordinates, the weather fetch and the
// week/season helpers now live in utils/farm_context.dart — the dashboard's
// recommendation hero builds the same M5 request and needs the identical
// values, so they're shared rather than duplicated. Local aliases keep the
// rest of this screen reading exactly as before.
const double _kDefaultSoilPh = kDefaultSoilPh;
const double _kDefaultSoilMoisture = kDefaultSoilMoisture;
const double _kDefaultN = kDefaultNIndex;
const double _kDefaultP = kDefaultPIndex;
const double _kDefaultK = kDefaultKIndex;

SoilTypical _soilDefaultsFor(String district) => soilDefaultsFor(district);

const Map<String, String> _cropEmoji = {
  'Carrot': '🥕',
  'Maize': '🌽',
  'Green gram': '🫘',
  'Cowpea': '🟤',
  'Finger millet': '🌾',
  'Groundnut': '🥜',
};

const String _cropSphereSvg =
    '''<svg viewBox="0 0 110 110" xmlns="http://www.w3.org/2000/svg">
  <ellipse cx="55" cy="96" rx="36" ry="7" fill="#1B4D1B" opacity="0.7"/>
  <path d="M55 95 C55 80 52 65 50 50" stroke="#4CAF50" stroke-width="2.5" stroke-linecap="round" fill="none"/>
  <path d="M50 65 C35 58 22 42 28 28 C38 40 48 55 50 65Z" fill="#388E3C" opacity="0.9"/>
  <path d="M52 58 C67 50 80 36 74 22 C64 34 55 50 52 58Z" fill="#4CAF50" opacity="0.9"/>
  <path d="M50 50 C38 44 30 32 34 20 C42 30 48 42 50 50Z" fill="#66BB6A" opacity="0.8"/>
  <circle cx="50" cy="28" r="3.5" fill="#FFC107" opacity="0.9"/>
  <circle cx="44" cy="22" r="3" fill="#FFB300" opacity="0.85"/>
  <circle cx="56" cy="20" r="3" fill="#FFC107" opacity="0.9"/>
  <circle cx="50" cy="14" r="3.5" fill="#FFD54F" opacity="0.95"/>
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

// ─────────────────────────────────────────────────────────────────────────────
//  RecommendScreen
// ─────────────────────────────────────────────────────────────────────────────
class RecommendScreen extends StatefulWidget {
  final ValueChanged<int>? onNavigate;

  /// Called with a crop name when the farmer taps "Predict Yield for this
  /// crop" — the Yield screen can use this to pre-select the crop.
  final ValueChanged<String>? onCropSelectedForYield;

  /// Called with a pre-filled context string when the farmer taps
  /// "Ask AI" on a recommendation — mirrors YieldScreen.onAiChatContext.
  final ValueChanged<String>? onAiChatContext;

  const RecommendScreen({
    super.key,
    this.onNavigate,
    this.onCropSelectedForYield,
    this.onAiChatContext,
  });

  @override
  State<RecommendScreen> createState() => _RecommendScreenState();
}

class _RecommendScreenState extends State<RecommendScreen> {
  // ── Selections ────────────────────────────────────────────────────────────
  // Nothing is pre-selected — the farmer must actively choose District,
  // Season and Irrigation Type themselves.
  String? _selectedDistrict;
  String? _selectedSeason;
  String? _selectedIrrigation;

  // 0 = Enter Details tab, 1 = Soil Guide tab
  int _activeTab = 0;

  // ── Weather (auto-fetched) ───────────────────────────────────────────────
  FarmWeather? _weather;
  bool _weatherLoading = false;
  String? _weatherError;
  bool _weatherOverrideOpen = false;
  double _oRainfall = 45.0,
      _oTempMin = 12.0,
      _oTempMax = 22.0,
      _oHumidity = 78.0;

  // ── Soil (simplified — defaults unless farmer opens advanced) ───────────
  bool _soilAdvancedOpen = false;
  // Generic Sri Lankan farmland fallback until a district is picked — then
  // this updates to that district's typical pH/moisture automatically.
  double _soilPh = _kDefaultSoilPh;
  double _soilMoisture = _kDefaultSoilMoisture;
  double _nIndex = _kDefaultN;
  double _pIndex = _kDefaultP;
  double _kIndex = _kDefaultK;
  // Once the farmer manually drags the pH/Moisture sliders themselves, we
  // stop auto-overwriting their input when they switch districts.
  bool _soilManuallyEdited = false;

  // ── Result state ─────────────────────────────────────────────────────────
  bool _isLoading = false;
  RecommendResponse? _result;
  String? _errorMessage;

  final List<String> _districts = [
    'Nuwara Eliya',
    'Badulla',
    'Anuradhapura',
    'Monaragala',
    'Ampara',
    'Hambantota',
    'Batticaloa',
    'Jaffna',
  ];

  FarmWeather get _effectiveWeather => _weatherOverrideOpen || _weather == null
      ? FarmWeather(
          rainfallMm: _oRainfall,
          tempMinC: _oTempMin,
          tempMaxC: _oTempMax,
          humidityPct: _oHumidity,
        )
      : _weather!;

  // ── Language helpers ─────────────────────────────────────────────────────
  String get _langKey {
    final l = AppLangProvider.lang(context);
    if (l == AppLang.si) return 'si';
    if (l == AppLang.ta) return 'ta';
    return 'en';
  }

  String _t(_L m) => m[_langKey] ?? m['en']!;

  /// Translated district name for display — falls back to the raw key
  /// (e.g. a future district not yet added to _districtNames) so nothing
  /// ever silently disappears from the UI.
  String _districtLabel(String englishKey) =>
      _t(_districtNames[englishKey] ?? {'en': englishKey});

  /// Translated season name (Maha/Yala/Inter → මහ/යල/අන්තර් etc.)
  String _seasonLabel(String englishKey) {
    final s = _seasons.firstWhere(
      (s) => s['name']!['en'] == englishKey,
      orElse: () => {
        'name': {'en': englishKey},
      },
    );
    return _t(s['name']!);
  }

  /// Translated irrigation type name (drip/sprinkler/rainfed → localized)
  String _irrigationLabel(String englishKey) {
    final t = _irrigationTypes.firstWhere(
      (t) => t['value']!['en'] == englishKey,
      orElse: () => {
        'label': {'en': englishKey},
      },
    );
    return _t(t['label']!);
  }

  // ── Soil-nutrient labels ─────────────────────────────────────────────────
  // The N/P/K sliders store a plain 0–1 index for the prediction API (this
  // is UNCHANGED — same numbers still go to the model). What changes is how
  // that number is shown to the farmer: instead of a meaningless "0.55", we
  // show the Sri Lanka Dept. of Agriculture-style fertility rating band
  // (Low / Medium / High / Very High) that farmers actually recognise from
  // their soil test reports.
  String _nutrientLevelLabel(double v) {
    if (v < 0.25) {
      return _t({'en': 'Low', 'si': 'අඩු', 'ta': 'குறைவு'});
    } else if (v < 0.5) {
      return _t({'en': 'Medium', 'si': 'මධ්‍යම', 'ta': 'நடுத்தரம்'});
    } else if (v < 0.75) {
      return _t({'en': 'High', 'si': 'ඉහළ', 'ta': 'அதிகம்'});
    }
    return _t({'en': 'Very High', 'si': 'ඉතා ඉහළ', 'ta': 'மிக அதிகம்'});
  }

  String _phLevelLabel(double v) {
    if (v < 5.5) {
      return _t({'en': 'Acidic', 'si': 'අම්ලීය', 'ta': 'அமிலத்தன்மை'});
    } else if (v < 6.5) {
      return _t({
        'en': 'Slightly Acidic',
        'si': 'තරමක් අම්ලීය',
        'ta': 'சிறிது அமிலத்தன்மை',
      });
    } else if (v <= 7.3) {
      return _t({
        'en': 'Neutral (Ideal)',
        'si': 'මධ්‍යස්ථ (සුදුසුම)',
        'ta': 'நடுநிலை (சிறந்தது)',
      });
    }
    return _t({'en': 'Alkaline', 'si': 'ක්ෂාරීය', 'ta': 'கார தன்மை'});
  }

  String _moistureLevelLabel(double v) {
    if (v < 35) {
      return _t({'en': 'Dry', 'si': 'වියළි', 'ta': 'உலர்ந்த'});
    } else if (v <= 70) {
      return _t({
        'en': 'Optimal',
        'si': 'සුදුසු මට්ටම',
        'ta': 'சிறந்த ஈரப்பதம்',
      });
    }
    return _t({'en': 'Wet', 'si': 'තෙත', 'ta': 'ஈரமான'});
  }

  @override
  void initState() {
    super.initState();
    // Nothing is pre-selected, so there's no district to load weather or
    // soil defaults for yet — that happens once the farmer picks one.
  }

  /// Refreshes the pH/Moisture starting values to match the selected
  /// district's typical soil profile — unless the farmer has already
  /// manually adjusted them, in which case we leave their input alone.
  /// Caller is responsible for wrapping in setState() when needed (not
  /// required from initState, since the first build hasn't happened yet).
  void _applyDistrictSoilDefaults(String district) {
    if (_soilManuallyEdited) return;
    final d = _soilDefaultsFor(district);
    _soilPh = d.ph;
    _soilMoisture = d.moisturePct;
  }

  // ── Weather fetch ─────────────────────────────────────────────────────────
  Future<void> _loadWeather(String district) async {
    setState(() {
      _weatherLoading = true;
      _weatherError = null;
      _weather = null;
    });
    try {
      final w = await fetchFarmWeather(district);
      if (mounted) {
        setState(() {
          _weather = w;
          _weatherLoading = false;
          _oRainfall = w.rainfallMm;
          _oTempMin = w.tempMinC;
          _oTempMax = w.tempMaxC;
          _oHumidity = w.humidityPct;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _weatherLoading = false;
          _weatherError = _t({
            'en': 'Could not load live weather. Using manual values.',
            'si':
                'වත්මන් කාලගුණය ලබාගත නොහැකි විය. දැන් ඔබට එය අතින් ඇතුළත් කළ හැක.',
            'ta':
                'நேரடி வானிலை கிடைக்கவில்லை. கைமுறை மதிப்புகள் பயன்படுத்தப்படும்.',
          });
          _weatherOverrideOpen = true;
        });
      }
    }
  }

  // ── Recommend ─────────────────────────────────────────────────────────────
  Future<void> _recommend() async {
    // District, Season and Irrigation Type are required — nothing is
    // pre-selected, so make sure the farmer actually picked all three
    // before calling the API.
    if (_selectedDistrict == null ||
        _selectedSeason == null ||
        _selectedIrrigation == null) {
      setState(() {
        _result = null;
        _errorMessage = _t({
          'en': 'Please select District, Season and Irrigation Type first.',
          'si': 'කරුණාකර පළමුව දිස්ත්‍රික්කය, කන්නය සහ ජලනය වර්ගය තෝරන්න.',
          'ta':
              'முதலில் மாவட்டம், பருவம் மற்றும் நீர்ப்பாசன வகையைத் தேர்ந்தெடுக்கவும்.',
        });
      });
      return;
    }
    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _result = null;
    });
    final w = _effectiveWeather;
    try {
      final service = ServiceFactory.getService();
      final response = await service.recommendCrop(
        RecommendRequest(
          district: _selectedDistrict!,
          season: _selectedSeason!,
          weekOfYear: farmWeekOfYear(),
          rainfallMm: w.rainfallMm,
          tempMinC: w.tempMinC,
          tempMaxC: w.tempMaxC,
          humidityPct: w.humidityPct,
          soilPh: _soilPh,
          soilMoisturePct: _soilMoisture,
          nIndex: _nIndex,
          pIndex: _pIndex,
          kIndex: _kIndex,
          irrigationType: _selectedIrrigation!,
        ),
      );
      if (mounted) setState(() => _result = response);
    } catch (e) {
      if (mounted) {
        setState(
          () => _errorMessage = _t({
            'en': 'Could not get recommendations. Please try again.',
            'si': 'නිර්දේශ ලබාගත නොහැක. නැවත උත්සාහ කරන්න.',
            'ta': 'பரிந்துரைகளைப் பெற முடியவில்லை. மீண்டும் முயற்சிக்கவும்.',
          }),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ══════════════════════════════════════════════════════════════════════════
  //  BUILD
  // ══════════════════════════════════════════════════════════════════════════
  @override
  Widget build(BuildContext context) {
    AppLangProvider.of(context);
    return Container(
      color: AppTheme.background,
      child: Column(
        children: [
          _buildTopBar(context),
          _buildSectionTabs(),
          Expanded(
            child: LayoutBuilder(
              builder: (ctx, bc) {
                final w = bc.maxWidth;
                final isWeb = w >= 960;
                // Same single-column layout on mobile/tablet as before.
                // Web gets its own compact arrangement (see _formColumn)
                // so every input fits without scrolling.
                final maxW = isWeb ? 1000.0 : (w >= 600 ? 700.0 : null);
                return _activeTab == 0
                    ? _buildEnterDetailsTab(maxW, isWeb)
                    : _buildSoilGuideTab(maxW);
              },
            ),
          ),
        ],
      ),
    );
  }

  // ── Section tabs (Enter Details / Soil Guide) ──────────────────────────────
  // Matches the "Enter Details" + guide-tab pattern already used on the
  // Yield/Price screens — replaces the old side-by-side split-screen web
  // layout so nothing is ever squeezed into two half-width panels.
  Widget _buildSectionTabs() {
    final tabs = [
      _t({
        'en': 'Enter Details',
        'si': 'විස්තර ඇතුළත් කරන්න',
        'ta': 'விவரங்களை உள்ளிடவும்',
      }),
      _t({'en': 'Soil Guide', 'si': 'පස් මාර්ගෝපදේශය', 'ta': 'மண் வழிகாட்டி'}),
    ];
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 10),
      child: Row(
        children: List.generate(tabs.length, (i) {
          final active = _activeTab == i;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: GestureDetector(
              onTap: () => setState(() => _activeTab = i),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 9,
                ),
                decoration: BoxDecoration(
                  color: active
                      ? const Color(0xFF00695C)
                      : const Color(0xFFF1F7F1),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: active
                        ? const Color(0xFF00695C)
                        : const Color(0xFFD0E8C8),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      i == 0 ? Icons.edit_note : Icons.eco_outlined,
                      size: 15,
                      color: active ? Colors.white : AppTheme.textSecondary,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      tabs[i],
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: active ? Colors.white : AppTheme.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }),
      ),
    );
  }

  // ── "Enter Details" tab ─────────────────────────────────────────────────
  // Mobile/tablet: single stacked column with a sticky bottom button.
  // Web: a compact 2-column grid (see _formColumn) so every input is
  // visible without scrolling — the button sits inline instead of sticky.
  Widget _buildEnterDetailsTab(double? maxW, bool isWeb) {
    if (isWeb) {
      return LayoutBuilder(
        builder: (ctx, bc) {
          final hPad = maxW == null
              ? 14.0
              : ((bc.maxWidth - maxW) / 2).clamp(14.0, 120.0);
          return SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(hPad, 14, hPad, 24),
            child: _formColumn(isWeb: true),
          );
        },
      );
    }
    return Stack(
      children: [
        LayoutBuilder(
          builder: (ctx, bc) {
            final hPad = maxW == null
                ? 14.0
                : ((bc.maxWidth - maxW) / 2).clamp(14.0, 200.0);
            return SingleChildScrollView(
              // extra bottom padding so content never hides behind the
              // sticky button — same trick used in YieldScreen
              padding: EdgeInsets.fromLTRB(hPad, 14, hPad, 100),
              child: _formColumn(isWeb: false),
            );
          },
        ),
        _stickyRecommendButton(),
      ],
    );
  }

  // ── Sticky bottom action button ─────────────────────────────────────────
  Widget _stickyRecommendButton() => Positioned(
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
      child: SafeArea(top: false, child: _recommendButton()),
    ),
  );

  Widget _formColumn({required bool isWeb}) {
    final seasonBlock = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle(
          _t({'en': 'Season', 'si': 'කන්නය', 'ta': 'பருவம்'}),
          Icons.calendar_month,
        ),
        const SizedBox(height: 10),
        _seasonChips(),
      ],
    );

    final locationBlock = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle(
          _t({
            'en': 'Location & Irrigation',
            'si': 'ස්ථානය හා ජලනය',
            'ta': 'இடம் மற்றும் நீர்ப்பாசனம்',
          }),
          Icons.location_on,
        ),
        const SizedBox(height: 10),
        _locationCard(),
      ],
    );

    final weatherBlock = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle(
          _t({'en': 'Weather', 'si': 'කාලගුණය', 'ta': 'வானிலை'}),
          Icons.cloud,
        ),
        const SizedBox(height: 10),
        _weatherCard(),
      ],
    );

    final soilBlock = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle(
          _t({'en': 'Soil', 'si': 'පස', 'ta': 'மண்'}),
          Icons.science,
        ),
        const SizedBox(height: 10),
        _soilCard(),
      ],
    );

    // ── Mobile / tablet: unchanged single-column stack ─────────────────────
    if (!isWeb) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _pageHeader(),
          const SizedBox(height: 16),
          seasonBlock,
          const SizedBox(height: 20),
          locationBlock,
          const SizedBox(height: 20),
          weatherBlock,
          const SizedBox(height: 20),
          soilBlock,
          const SizedBox(height: 20),
          if (_isLoading) _resultSkeleton(),
          if (_errorMessage != null) _errorCard(),
          if (_result != null) _resultSection(),
          if (_result == null && _errorMessage == null && !_isLoading)
            _emptyPlaceholder(),
        ],
      );
    }

    // ── Web: compact 2-column grid so every input is visible without
    //    scrolling — Season+Location alongside Weather, then Soil alongside
    //    the button/result. This mirrors the "Enter Details" form fitting
    //    the viewport on Yield/Price, just laid out as a proper grid
    //    instead of one long stack. No IntrinsicHeight is used anywhere
    //    here, so it stays compatible with the Weather grid/GridView. ──────
    final resultBlock = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _recommendButton(),
        const SizedBox(height: 14),
        if (_isLoading) _resultSkeleton(),
        if (_errorMessage != null) _errorCard(),
        if (_result != null) _resultSection(),
        if (_result == null && _errorMessage == null && !_isLoading)
          _emptyPlaceholder(),
      ],
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _pageHeader(),
        const SizedBox(height: 14),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 5,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  seasonBlock,
                  const SizedBox(height: 14),
                  locationBlock,
                ],
              ),
            ),
            const SizedBox(width: 16),
            Expanded(flex: 4, child: weatherBlock),
          ],
        ),
        const SizedBox(height: 14),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(flex: 5, child: soilBlock),
            const SizedBox(width: 16),
            Expanded(flex: 4, child: resultBlock),
          ],
        ),
      ],
    );
  }

  // ── "Soil Guide" tab — how to read the fertility ratings, plus a
  //    per-district reference for typical pH & moisture. Tapping a district
  //    card selects it and jumps back to Enter Details, tying the two tabs
  //    together. ───────────────────────────────────────────────────────────
  Widget _buildSoilGuideTab(double? maxW) => LayoutBuilder(
    builder: (ctx, bc) {
      final hPad = maxW == null
          ? 14.0
          : ((bc.maxWidth - maxW) / 2).clamp(14.0, 200.0);
      return SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(hPad, 16, hPad, 28),
        child: _soilGuideContent(),
      );
    },
  );

  Widget _soilGuideContent() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        _t({
          'en': 'Understanding Your Soil Results',
          'si': 'ඔබේ පස් ප්‍රතිඵල තේරුම් ගැනීම',
          'ta': 'உங்கள் மண் முடிவுகளைப் புரிந்துகொள்ளுதல்',
        }),
        style: const TextStyle(
          fontSize: 17,
          fontWeight: FontWeight.w800,
          color: AppTheme.textPrimary,
        ),
      ),
      const SizedBox(height: 10),
      _infoBox(
        _t({
          'en':
              'N (Nitrogen), P (Phosphorus) and K (Potassium) ratings follow the same Low / Medium / High / Very High scale used on Dept. of Agriculture soil-test reports. Most home garden and small-plot soils fall in the Medium range — if you have not tested, leaving these on Medium is a safe starting point.',
          'si':
              'N (නයිට්‍රජන්), P (පොස්පරස්) සහ K (පොටෑසියම්) මට්ටම් කෘෂිකර්ම දෙපාර්තමේන්තුවේ පස් පරීක්ෂණ වාර්තාවල භාවිත වන අඩු/මධ්‍යම/ඉහළ/ඉතා ඉහළ පරිමාණයම අනුගමනය කරයි. පරීක්ෂා කර නොමැති නම් මධ්‍යම මට්ටමේ තැබීම ආරක්ෂිතයි.',
          'ta':
              'N (நைட்ரஜன்), P (பாஸ்பரஸ்) மற்றும் K (பொட்டாசியம்) மதிப்பீடுகள் விவசாயத் திணைக்கள மண் பரிசோதனை அறிக்கைகளில் பயன்படுத்தப்படும் குறைவு/நடுத்தரம்/அதிகம்/மிக அதிகம் அளவைப் பின்பற்றுகின்றன. பரிசோதிக்கவில்லை என்றால் நடுத்தரத்தில் விடுவது பாதுகாப்பானது.',
        }),
        color: AppTheme.info,
        icon: Icons.info_outline,
      ),
      const SizedBox(height: 10),
      _infoBox(
        _t({
          'en':
              'Soil pH between 6.0–7.0 (Neutral) suits most Sri Lankan food crops. Soil moisture of 50–65% is generally ideal for upland crops — drier for rainfed dry-zone crops, wetter for paddy.',
          'si':
              'pH 6.0–7.0 (මධ්‍යස්ථ) බොහෝ ශ්‍රී ලංකා ආහාර බෝගවලට සුදුසුයි. උස්බිම් බෝග සඳහා පස ආර්ද්‍රතාව 50–65% පොදුවේ සුදුසුයි — වියළි කලාපයේ වර්ෂාපෝෂිත බෝග සඳහා තරමක් වියළි, වී සඳහා තෙත් අවශ්‍යයි.',
          'ta':
              'pH 6.0–7.0 (நடுநிலை) பெரும்பாலான இலங்கை உணவுப் பயிர்களுக்கு ஏற்றது. மேட்டு பயிர்களுக்கு 50–65% மண் ஈரப்பதம் பொதுவாக சிறந்தது — வறண்ட வலய மழையை நம்பிய பயிர்களுக்கு உலர்வாகவும், நெல்லுக்கு ஈரமாகவும் இருக்கும்.',
        }),
        color: AppTheme.success,
        icon: Icons.water_drop_outlined,
      ),
      const SizedBox(height: 20),
      _sectionTitle(
        _t({
          'en': 'Typical Soil by District',
          'si': 'දිස්ත්‍රික්කය අනුව සාමාන්‍ය පස',
          'ta': 'மாவட்டம் வாரியாக வழக்கமான மண்',
        }),
        Icons.map_outlined,
      ),
      const SizedBox(height: 4),
      Text(
        _t({
          'en':
              'Tap a district to use it — its typical pH & moisture will fill in automatically on the Enter Details tab.',
          'si':
              'භාවිතා කිරීමට දිස්ත්‍රික්කයක් ඔබන්න — එහි සාමාන්‍ය pH සහ ආර්ද්‍රතාව විස්තර ඇතුළත් කිරීමේ පටිත්තෙහි ස්වයංක්‍රීයව පිරෙනු ඇත.',
          'ta':
              'பயன்படுத்த ஒரு மாவட்டத்தைத் தட்டவும் — அதன் வழக்கமான pH மற்றும் ஈரப்பதம் விவரங்களை உள்ளிடும் தாவலில் தானாக நிரம்பும்.',
        }),
        style: const TextStyle(
          fontSize: 11.5,
          color: AppTheme.textMuted,
          height: 1.4,
        ),
      ),
      const SizedBox(height: 12),
      ..._districts.map((d) => _districtSoilGuideCard(d)),
    ],
  );

  Widget _districtSoilGuideCard(String district) {
    final d = _soilDefaultsFor(district);
    final selected = district == _selectedDistrict;
    return GestureDetector(
      onTap: () {
        setState(() {
          _selectedDistrict = district;
          _result = null;
          _applyDistrictSoilDefaults(district);
          _activeTab = 0;
        });
        _loadWeather(district);
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: selected
              ? AppTheme.primary.withValues(alpha: 0.06)
              : AppTheme.surfaceCard,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? AppTheme.primary : const Color(0xFFE0EBE0),
            width: selected ? 1.6 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  _districtLabel(district),
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: selected
                        ? AppTheme.primaryDark
                        : AppTheme.textPrimary,
                  ),
                ),
                if (selected) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: AppTheme.primary,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      _t({
                        'en': 'Selected',
                        'si': 'තෝරා ඇත',
                        'ta': 'தேர்ந்தெடுக்கப்பட்டது',
                      }),
                      style: const TextStyle(
                        fontSize: 9.5,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ],
                const Spacer(),
                Icon(
                  Icons.chevron_right,
                  size: 18,
                  color: AppTheme.textMuted.withValues(alpha: 0.6),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                _guideStatChip(
                  'pH ${d.ph.toStringAsFixed(1)}',
                  _phLevelLabel(d.ph),
                  Colors.purple,
                ),
                _guideStatChip(
                  '${_t({'en': 'Moisture', 'si': 'ආර්ද්‍රතාව', 'ta': 'ஈரம்'})} ${d.moisturePct.toStringAsFixed(0)}%',
                  _moistureLevelLabel(d.moisturePct),
                  Colors.cyan,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// Small content-sized stat pill (e.g. "pH 6.8 · Neutral (Ideal)") used
  /// on the district reference cards — unlike _readonlyChip, this doesn't
  /// need an Expanded parent to size correctly.
  Widget _guideStatChip(String primary, String levelText, Color color) =>
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withValues(alpha: 0.22)),
        ),
        child: Text(
          '$primary · $levelText',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: color,
          ),
        ),
      );

  // ── Top bar (shared pattern — "Crop Rec." bolded at index 4) ──────────────
  Widget _buildTopBar(BuildContext context) {
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

    const activeBg = Color(0xFFE8F5E9);
    const activeColor = Color(0xFF2E7D32);
    const activeIndex = 4; // Crop Rec.

    return Container(
      height: 66,
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
      child: LayoutBuilder(
        builder: (ctx, bc) {
          // Below 600px (mobile) the text nav labels are dropped entirely —
          // just logo + language pill remain. Tablet/web (>=600px) keep the
          // full nav bar.
          final isMobile = bc.maxWidth < 600;
          return Row(
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
                    _cropSphereSvg,
                    width: 32,
                    height: 32,
                  ),
                ),
              ),
              const BrandWordmark(),
              if (!isMobile)
                Expanded(
                  child: Center(
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: List.generate(navLabels.length, (i) {
                          final active = i == activeIndex;
                          return Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 3),
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
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 15,
                                  vertical: 9,
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
                                  fontSize: 13,
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
              if (isMobile) const Spacer(),
              const SizedBox(width: 8),
              const LanguageControl(),
              const SizedBox(width: 8),
              const ThemeToggleButton(),
              const SizedBox(width: 8),
              const ProfileAvatarButton(diameter: 32),
            ],
          );
        },
      ),
    );
  }

  // ── Page header ────────────────────────────────────────────────────────────
  Widget _pageHeader() => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      gradient: const LinearGradient(
        colors: [Color(0xFF00695C), Color(0xFF00897B)],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
      borderRadius: BorderRadius.circular(14),
      boxShadow: [
        BoxShadow(
          color: const Color(0xFF00695C).withValues(alpha: 0.3),
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
            _navSvg(4, Colors.white),
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
                  'en': 'Crop Recommender',
                  'si': 'භෝග නිර්දේශකය',
                  'ta': 'பயிர் பரிந்துரையாளர்',
                }),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              AnimatedLangText(
                _t({
                  'en': 'Find the best crop for your land, right now',
                  'si': 'ඔබේ ඉඩමට වඩාත් සුදුසු භෝගය දැන් සොයන්න',
                  'ta': 'உங்கள் நிலத்திற்கு சிறந்த பயிரை இப்போது கண்டறியுங்கள்',
                }),
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.8),
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
            _t({
              'en': 'Week ${farmWeekOfYear()}',
              'si': 'සති ${farmWeekOfYear()}',
              'ta': 'வாரம் ${farmWeekOfYear()}',
            }),
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

  // ── Season quick chips ────────────────────────────────────────────────────
  Widget _seasonChips() => Wrap(
    spacing: 8,
    runSpacing: 8,
    children: _seasons.map((s) {
      final key = s['name']!['en']!;
      final active = _selectedSeason == key;
      return GestureDetector(
        onTap: () => setState(() {
          _selectedSeason = key;
          _result = null;
        }),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: active ? AppTheme.primary : Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: active ? AppTheme.primary : const Color(0xFFD0E8C8),
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
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${_t(s['emoji']!)}  ${_t(s['name']!)}',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: active ? Colors.white : AppTheme.textPrimary,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                _t(s['months']!),
                style: TextStyle(
                  fontSize: 10.5,
                  color: active
                      ? Colors.white.withValues(alpha: 0.85)
                      : AppTheme.textMuted,
                ),
              ),
            ],
          ),
        ),
      );
    }).toList(),
  );

  // ── Location & irrigation card ─────────────────────────────────────────────
  Widget _locationCard() {
    final selIrrigation = _selectedIrrigation == null
        ? null
        : _irrigationTypes.firstWhere(
            (t) => t['value']!['en'] == _selectedIrrigation,
            orElse: () => _irrigationTypes[0],
          );
    return _card(
      child: Column(
        children: [
          DropdownButtonFormField<String>(
            initialValue: _selectedDistrict,
            hint: Text(
              _t({
                'en': 'Select District',
                'si': 'දිස්ත්‍රික්කය තෝරන්න',
                'ta': 'மாவட்டத்தைத் தேர்ந்தெடுக்கவும்',
              }),
            ),
            decoration: InputDecoration(
              labelText: _t({
                'en': 'District',
                'si': 'දිස්ත්‍රික්කය',
                'ta': 'மாவட்டம்',
              }),
              prefixIcon: const Icon(
                Icons.location_on,
                color: AppTheme.primary,
                size: 20,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 10,
              ),
            ),
            items: _districts
                .map(
                  (e) => DropdownMenuItem(
                    value: e,
                    child: Text(_districtLabel(e)),
                  ),
                )
                .toList(),
            onChanged: (v) {
              if (v == null) return;
              setState(() {
                _selectedDistrict = v;
                _result = null;
                _applyDistrictSoilDefaults(v);
              });
              _loadWeather(v);
            },
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _selectedIrrigation,
            hint: Text(
              _t({
                'en': 'Select Irrigation Type',
                'si': 'ජලනය වර්ගය තෝරන්න',
                'ta': 'நீர்ப்பாசன வகையைத் தேர்ந்தெடுக்கவும்',
              }),
            ),
            decoration: InputDecoration(
              labelText: _t({
                'en': 'Irrigation Type',
                'si': 'ජලනය වර්ගය',
                'ta': 'நீர்ப்பாசன வகை',
              }),
              prefixIcon: const Icon(
                Icons.water_drop,
                color: AppTheme.primary,
                size: 20,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 10,
              ),
            ),
            items: _irrigationTypes
                .map(
                  (t) => DropdownMenuItem(
                    value: t['value']!['en'],
                    child: Text(_t(t['label']!)),
                  ),
                )
                .toList(),
            onChanged: (v) => setState(() {
              _selectedIrrigation = v;
              _result = null;
            }),
          ),
          if (selIrrigation != null) ...[
            const SizedBox(height: 8),
            _infoBox(
              _t(selIrrigation['desc']!),
              color: Colors.blue,
              icon: Icons.water_drop_outlined,
            ),
          ],
        ],
      ),
    );
  }

  // ── Weather card (auto-fetched, matches Yield screen) ──────────────────────
  Widget _weatherCard() {
    if (_selectedDistrict == null) {
      return _card(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(
              Icons.location_off_outlined,
              size: 18,
              color: AppTheme.textMuted,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                _t({
                  'en':
                      'Select a district first — live weather will load automatically.',
                  'si':
                      'පළමුව දිස්ත්‍රික්කයක් තෝරන්න — වත්මන් කාලගුණය ස්වයංක්‍රීයව පූරණය වේ.',
                  'ta':
                      'முதலில் ஒரு மாவட்டத்தைத் தேர்ந்தெடுக்கவும் — நேரடி வானிலை தானாக ஏற்றப்படும்.',
                }),
                style: const TextStyle(
                  fontSize: 13,
                  color: AppTheme.textSecondary,
                  height: 1.4,
                ),
              ),
            ),
          ],
        ),
      );
    }
    final dLabel = _districtLabel(_selectedDistrict!);
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
                _t({
                  'en': 'Loading live weather for $_selectedDistrict...',
                  'si': '$dLabel හි කාලගුණ තොරතුරු ලබාගනිමින්...',
                  'ta': '$dLabel வானிலை தகவல்களைப் பெறுகிறோம்...',
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
                        _t({
                          'en':
                              'Live weather auto-loaded for $_selectedDistrict',
                          'si':
                              '$dLabel හි වත්මන් කාලගුණය ස්වයංක්‍රීයව ලබාගෙන ඇත',
                          'ta':
                              '$dLabel-க்கான தற்போதைய வானிலை தானாகப் பெறப்பட்டது',
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
                      ? _t({
                          'en': 'Hide manual override',
                          'si': 'අතින් ඇතුළත් කිරීම සඟවන්න',
                          'ta': 'கைமுறை மேலெழுத்தை மறைக்கவும்',
                        })
                      : _t({
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
            const SizedBox(height: 10),
            _slider(
              _t({'en': 'Rainfall', 'si': 'වර්ෂාපතනය', 'ta': 'மழை'}),
              _oRainfall,
              0,
              300,
              'mm',
              Colors.blue,
              (v) => setState(() => _oRainfall = v),
            ),
            _slider(
              _t({
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
            _slider(
              _t({
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
            _slider(
              _t({'en': 'Humidity', 'si': 'ආර්ද්‍රතාව', 'ta': 'ஈரப்பதம்'}),
              _oHumidity,
              20,
              100,
              '%',
              Colors.teal,
              (v) => setState(() => _oHumidity = v),
            ),
          ],
        ],
      ),
    );
  }

  Widget _weatherGrid(FarmWeather w) {
    final tiles = [
      (
        '🌧',
        _t({'en': 'Rain', 'si': 'වර්ෂාව', 'ta': 'மழை'}),
        '${w.rainfallMm.toStringAsFixed(1)} mm',
        Colors.blue,
      ),
      (
        '🌡',
        _t({'en': 'Min Temp', 'si': 'අවම', 'ta': 'குறை'}),
        '${w.tempMinC.toStringAsFixed(1)}°C',
        Colors.lightBlue,
      ),
      (
        '☀️',
        _t({'en': 'Max Temp', 'si': 'උපරිම', 'ta': 'அதிக'}),
        '${w.tempMaxC.toStringAsFixed(1)}°C',
        Colors.orange,
      ),
      (
        '💧',
        _t({'en': 'Humidity', 'si': 'ආර්ද්‍රතා', 'ta': 'ஈரம்'}),
        '${w.humidityPct.toStringAsFixed(0)}%',
        Colors.teal,
      ),
    ];
    return LayoutBuilder(
      builder: (ctx, bc) {
        // Narrow phones (< ~360 available width inside the card) get 2
        // columns so labels/values stay readable instead of squeezed into 4.
        final cols = bc.maxWidth < 360 ? 2 : 4;
        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: cols,
            crossAxisSpacing: 8,
            mainAxisSpacing: 8,
            childAspectRatio: cols == 2 ? 1.7 : 0.95,
          ),
          itemCount: tiles.length,
          itemBuilder: (_, i) {
            final t = tiles[i];
            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
              decoration: BoxDecoration(
                color: t.$4.withValues(alpha: 0.07),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: t.$4.withValues(alpha: 0.2)),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(t.$1, style: const TextStyle(fontSize: 15)),
                  const SizedBox(height: 3),
                  Text(
                    t.$3,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: t.$4,
                    ),
                  ),
                  Text(
                    t.$2,
                    style: TextStyle(
                      fontSize: 8.5,
                      color: t.$4.withValues(alpha: 0.8),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  // ── Soil card — simplified with sensible, district-aware defaults ─────────
  Widget _soilCard() => _card(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (!_soilAdvancedOpen) ...[
          _infoBox(
            _soilManuallyEdited
                ? _t({
                    'en':
                        'Using the pH & moisture you entered manually. Tap below to change them.',
                    'si':
                        'ඔබ අතින් ඇතුළත් කළ pH සහ ආර්ද්‍රතාව භාවිතා වේ. වෙනස් කිරීමට පහත ඔබන්න.',
                    'ta':
                        'நீங்கள் கைமுறையாக உள்ளிட்ட pH மற்றும் ஈரப்பதம் பயன்படுத்தப்படுகிறது. மாற்ற கீழே தட்டவும்.',
                  })
                : _selectedDistrict == null
                ? _t({
                    'en':
                        'Using general Sri Lankan farmland averages — select a district above for values typical to your area, or tap below to enter your own soil test results.',
                    'si':
                        'සාමාන්‍ය ශ්‍රී ලංකා ගොවිබිම් අගයන් භාවිතා වේ — ඔබේ ප්‍රදේශයට ගැලපෙන අගයන් සඳහා ඉහත දිස්ත්‍රික්කයක් තෝරන්න, නැතහොත් ඔබේම පස් පරීක්ෂණ ප්‍රතිඵල ඇතුළත් කිරීමට පහත ඔබන්න.',
                    'ta':
                        'பொது இலங்கை பண்ணை நில சராசரிகள் பயன்படுத்தப்படுகின்றன — உங்கள் பகுதிக்கு ஏற்ற மதிப்புகளுக்கு மேலே ஒரு மாவட்டத்தைத் தேர்ந்தெடுக்கவும், அல்லது உங்கள் சொந்த மண் பரிசோதனை முடிவுகளை உள்ளிட கீழே தட்டவும்.',
                  })
                : _t({
                    'en':
                        'Typical soil values for ${_districtLabel(_selectedDistrict!)}. Tap below if you have your own soil test results.',
                    'si':
                        '${_districtLabel(_selectedDistrict!)} සඳහා සාමාන්‍ය පස් අගයන් මෙහි යොදා ඇත. ඔබ සතුව පස් පරීක්ෂණ ප්‍රතිඵල තිබේ නම්, පහත ඔබන්න.',
                    'ta':
                        '${_districtLabel(_selectedDistrict!)}-க்கான வழக்கமான மண் மதிப்புகள் இங்கு பயன்படுத்தப்பட்டுள்ளன. உங்களிடம் சொந்த மண் பரிசோதனை முடிவுகள் இருந்தால், கீழே தட்டவும்.',
                  }),
            color: AppTheme.info,
            icon: Icons.info_outline,
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _readonlyChip(
                  'pH',
                  '${_soilPh.toStringAsFixed(1)} · ${_phLevelLabel(_soilPh)}',
                  Colors.purple,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _readonlyChip(
                  _t({'en': 'Moisture', 'si': 'ආර්ද්‍රතාව', 'ta': 'ஈரம்'}),
                  '${_soilMoisture.toStringAsFixed(0)}% · ${_moistureLevelLabel(_soilMoisture)}',
                  Colors.cyan,
                ),
              ),
            ],
          ),
          if (_soilManuallyEdited && _selectedDistrict != null) ...[
            const SizedBox(height: 8),
            GestureDetector(
              onTap: () => setState(() {
                _soilManuallyEdited = false;
                _applyDistrictSoilDefaults(_selectedDistrict!);
              }),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.refresh,
                    size: 13,
                    color: AppTheme.primaryDark,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    _t({
                      'en':
                          'Reset to ${_districtLabel(_selectedDistrict!)} typical',
                      'si':
                          '${_districtLabel(_selectedDistrict!)} සාමාන්‍ය අගයට යළි සකසන්න',
                      'ta':
                          '${_districtLabel(_selectedDistrict!)} வழக்கமான மதிப்புக்கு மீட்டமை',
                    }),
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.primaryDark,
                      decoration: TextDecoration.underline,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
        const SizedBox(height: 10),
        GestureDetector(
          onTap: () => setState(() => _soilAdvancedOpen = !_soilAdvancedOpen),
          child: Row(
            children: [
              Icon(
                _soilAdvancedOpen ? Icons.expand_less : Icons.tune,
                size: 15,
                color: AppTheme.textSecondary,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  _soilAdvancedOpen
                      ? _t({
                          'en': 'Hide soil test details',
                          'si': 'පස පරීක්ෂණ විස්තර සඟවන්න',
                          'ta': 'மண் பரிசோதனை விவரங்களை மறைக்கவும்',
                        })
                      : _t({
                          'en': 'I know my soil test results',
                          'si': 'මගේ පස් පරීක්ෂණ ප්‍රතිඵල මා සතුව තිබේ',
                          'ta': 'எனது மண் பரிசோதனை முடிவுகள் என்னிடம் உள்ளன',
                        }),
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppTheme.textSecondary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
        if (_soilAdvancedOpen) ...[
          const SizedBox(height: 10),
          _slider(
            _t({'en': 'Soil pH', 'si': 'පස pH', 'ta': 'மண் pH'}),
            _soilPh,
            3.5,
            9.0,
            'pH',
            Colors.purple,
            (v) => setState(() {
              _soilPh = v;
              _soilManuallyEdited = true;
            }),
            levelLabel: _phLevelLabel,
            helperText: _t({
              'en': 'Most Sri Lankan crops prefer pH 6.0–7.0 (near neutral).',
              'si':
                  'බොහෝ ශ්‍රී ලංකා බෝග pH 6.0–7.0 (මධ්‍යස්ථ) ට ආසන්න මට්ටමක් කැමති වේ.',
              'ta':
                  'பெரும்பாலான இலங்கை பயிர்கள் pH 6.0–7.0 (நடுநிலைக்கு அருகில்) விரும்புகின்றன.',
            }),
          ),
          _slider(
            _t({
              'en': 'Soil Moisture',
              'si': 'පස ආර්ද්‍රතාව',
              'ta': 'மண் ஈரம்',
            }),
            _soilMoisture,
            10,
            100,
            '%',
            Colors.cyan,
            (v) => setState(() {
              _soilMoisture = v;
              _soilManuallyEdited = true;
            }),
            levelLabel: _moistureLevelLabel,
            helperText: _t({
              'en': 'Field capacity for most upland crops is around 50–65%.',
              'si': 'බොහෝ උස්බිම් බෝග සඳහා සුදුසු ආර්ද්‍රතාව 50–65% පමණි.',
              'ta': 'பெரும்பாலான மேட்டு பயிர்களுக்கு 50–65% ஈரப்பதம் ஏற்றது.',
            }),
          ),
          _slider(
            _t({
              'en': 'Nitrogen (N) fertility',
              'si': 'නයිට්‍රජන් (N) සරුබව',
              'ta': 'நைட்ரஜன் (N) வளம்',
            }),
            _nIndex,
            0,
            1,
            '',
            Colors.indigo,
            (v) => setState(() => _nIndex = v),
            levelLabel: _nutrientLevelLabel,
            divisions: 3,
            helperText: _t({
              'en':
                  'Dept. of Agriculture soil-test rating: Low / Medium / High / Very High. Not sure? Leave on Medium.',
              'si':
                  'කෘෂිකර්ම දෙපාර්තමේන්තුවේ පස් පරීක්ෂණ මට්ටම: අඩු / මධ්‍යම / ඉහළ / ඉතා ඉහළ. විශ්වාස නැත්නම් මධ්‍යම මට්ටමේ තබන්න.',
              'ta':
                  'விவசாயத் திணைக்கள மண் பரிசோதனை மதிப்பீடு: குறைவு / நடுத்தரம் / அதிகம் / மிக அதிகம். உறுதியில்லையா? நடுத்தரத்தில் விடவும்.',
            }),
          ),
          _slider(
            _t({
              'en': 'Phosphorus (P) fertility',
              'si': 'පොස්පරස් (P) සරුබව',
              'ta': 'பாஸ்பரஸ் (P) வளம்',
            }),
            _pIndex,
            0,
            1,
            '',
            Colors.deepOrange,
            (v) => setState(() => _pIndex = v),
            levelLabel: _nutrientLevelLabel,
            divisions: 3,
            helperText: _t({
              'en':
                  'Dept. of Agriculture soil-test rating: Low / Medium / High / Very High. Not sure? Leave on Medium.',
              'si':
                  'කෘෂිකර්ම දෙපාර්තමේන්තුවේ පස් පරීක්ෂණ මට්ටම: අඩු / මධ්‍යම / ඉහළ / ඉතා ඉහළ. විශ්වාස නැත්නම් මධ්‍යම මට්ටමේ තබන්න.',
              'ta':
                  'விவசாயத் திணைக்கள மண் பரிசோதனை மதிப்பீடு: குறைவு / நடுத்தரம் / அதிகம் / மிக அதிகம். உறுதியில்லையா? நடுத்தரத்தில் விடவும்.',
            }),
          ),
          _slider(
            _t({
              'en': 'Potassium (K) fertility',
              'si': 'පොටෑසියම් (K) සරුබව',
              'ta': 'பொட்டாசியம் (K) வளம்',
            }),
            _kIndex,
            0,
            1,
            '',
            Colors.amber,
            (v) => setState(() => _kIndex = v),
            levelLabel: _nutrientLevelLabel,
            divisions: 3,
            helperText: _t({
              'en':
                  'Dept. of Agriculture soil-test rating: Low / Medium / High / Very High. Not sure? Leave on Medium.',
              'si':
                  'කෘෂිකර්ම දෙපාර්තමේන්තුවේ පස් පරීක්ෂණ මට්ටම: අඩු / මධ්‍යම / ඉහළ / ඉතා ඉහළ. විශ්වාස නැත්නම් මධ්‍යම මට්ටමේ තබන්න.',
              'ta':
                  'விவசாயத் திணைக்கள மண் பரிசோதனை மதிப்பீடு: குறைவு / நடுத்தரம் / அதிகம் / மிக அதிகம். உறுதியில்லையா? நடுத்தரத்தில் விடவும்.',
            }),
          ),
        ],
      ],
    ),
  );

  Widget _readonlyChip(String label, String value, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.07),
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: color.withValues(alpha: 0.2)),
    ),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: color,
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w800,
            color: color,
          ),
        ),
      ],
    ),
  );

  // ── Recommend button ─────────────────────────────────────────────────────
  Widget _recommendButton() => SizedBox(
    width: double.infinity,
    height: 52,
    child: ElevatedButton.icon(
      onPressed: _isLoading ? null : _recommend,
      icon: _isLoading
          ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white,
              ),
            )
          : const Icon(Icons.agriculture),
      label: Text(
        _isLoading
            ? _t({
                'en': 'Analysing...',
                'si': 'විශ්ලේෂණය කරමින්...',
                'ta': 'பகுப்பாய்வு செய்கிறோம்...',
              })
            : _t({
                'en': 'Get Crop Recommendations',
                'si': 'භෝග නිර්දේශ ලබාගන්න',
                'ta': 'பயிர் பரிந்துரைகளைப் பெறவும்',
              }),
        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
      ),
      style: ElevatedButton.styleFrom(
        backgroundColor: const Color(0xFF00695C),
        foregroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        elevation: 2,
      ),
    ),
  );

  // ── Empty placeholder ───────────────────────────────────────────────────
  Widget _emptyPlaceholder() => Container(
    padding: const EdgeInsets.all(24),
    decoration: BoxDecoration(
      color: const Color(0xFFF1F7F1),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: const Color(0xFFD0E8C8)),
    ),
    child: Column(
      children: [
        SvgPicture.string(
          _navSvg(4, const Color(0xFFB0C4B0)),
          width: 48,
          height: 48,
        ),
        const SizedBox(height: 12),
        Text(
          _t({
            'en': 'Your recommended crops will appear here',
            'si': 'ඔබට නිර්දේශිත භෝග මෙතැන දිස්වේ',
            'ta': 'உங்களுக்குப் பரிந்துரைக்கப்பட்ட பயிர்கள் இங்கே தோன்றும்',
          }),
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 13,
            color: AppTheme.textMuted,
            height: 1.5,
          ),
        ),
      ],
    ),
  );

  // ── Result section ────────────────────────────────────────────────────────
  Widget _resultSection() {
    if (_result!.recommendations.isEmpty) {
      return _card(
        child: Text(
          _t({
            'en':
                'No suitable crops found for these conditions. Try changing the season or irrigation type.',
            'si':
                'මෙම තත්ත්ව සඳහා සුදුසු භෝග හමු නොවීය. කන්නය හෝ ජලනය වෙනස් කර බලන්න.',
            'ta':
                'இந்த நிலைமைகளுக்கு ஏற்ற பயிர்கள் கிடைக்கவில்லை. பருவம் அல்லது நீர்ப்பாசனத்தை மாற்றி முயற்சிக்கவும்.',
          }),
          style: const TextStyle(color: AppTheme.textSecondary),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              _t({
                'en': 'Recommended Crops',
                'si': 'නිර්දේශිත භෝග',
                'ta': 'பரிந்துரைக்கப்பட்ட பயிர்கள்',
              }),
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: AppTheme.textPrimary,
              ),
            ),
            const SizedBox(width: 8),
            if (_result!.isMock) const CsMockBadge(),
          ],
        ),
        const SizedBox(height: 12),
        ..._result!.recommendations.map((r) => _recommendationCard(r)),
      ],
    );
  }

  Widget _recommendationCard(CropRecommendation rec) {
    final rankColors = [
      const Color(0xFFFFD700),
      const Color(0xFFC0C0C0),
      const Color(0xFFCD7F32),
    ];
    final rankColor = rec.rank <= 3 ? rankColors[rec.rank - 1] : Colors.grey;
    final suitCount = rec.suitabilityFlags.values.where((v) => v).length;
    final totalFlags = rec.suitabilityFlags.length;
    final isGoodMatch = totalFlags == 0 || suitCount / totalFlags >= 0.7;
    final emoji = _cropEmoji[rec.crop] ?? '🌿';

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: AppTheme.surfaceCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: rankColor.withValues(alpha: 0.5), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: rankColor,
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: Text(
                      '${rec.rank}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '$emoji  ${rec.crop}',
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                          color: AppTheme.textPrimary,
                        ),
                      ),
                      Text(
                        _t({
                          'en':
                              '${(rec.confidenceScore * 100).toStringAsFixed(0)}% confidence',
                          'si':
                              'විශ්වාසය ${(rec.confidenceScore * 100).toStringAsFixed(0)}%',
                          'ta':
                              'நம்பகத்தன்மை ${(rec.confidenceScore * 100).toStringAsFixed(0)}%',
                        }),
                        style: const TextStyle(
                          color: AppTheme.textMuted,
                          fontSize: 11.5,
                        ),
                      ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '${rec.expectedYieldKgPerHa.toInt()} kg/ha',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                    Text(
                      'Rs. ${rec.expectedPriceLkrKg.toInt()}/kg',
                      style: const TextStyle(
                        color: AppTheme.success,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: LinearProgressIndicator(
                value: rec.confidenceScore,
                backgroundColor: Colors.grey[200],
                valueColor: AlwaysStoppedAnimation<Color>(rankColor),
                minHeight: 6,
              ),
            ),
            const SizedBox(height: 12),
            // ── Plain-language verdict banner instead of bare icons ──────────
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: (isGoodMatch ? AppTheme.success : AppTheme.warning)
                    .withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: (isGoodMatch ? AppTheme.success : AppTheme.warning)
                      .withValues(alpha: 0.3),
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    isGoodMatch
                        ? Icons.check_circle_rounded
                        : Icons.info_rounded,
                    size: 17,
                    color: isGoodMatch ? AppTheme.success : AppTheme.warning,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      isGoodMatch
                          ? _t({
                              'en':
                                  'Good match — $suitCount of $totalFlags conditions suit this crop well.',
                              'si':
                                  'හොඳ ගැලපීමකි — කොන්දේසි $totalFlags න් $suitCount ක් මෙම භෝගයට හොඳින් ගැලපේ.',
                              'ta':
                                  'நல்ல பொருத்தம் — $totalFlags நிபந்தனைகளில் $suitCount இந்த பயிருக்கு நன்றாக பொருந்துகிறது.',
                            })
                          : _t({
                              'en':
                                  'Fair match — only $suitCount of $totalFlags conditions are ideal. Consider extra care.',
                              'si':
                                  'මධ්‍යස්ථ ගැලපීමකි — කොන්දේසි $totalFlags න් $suitCount ක් පමණි සුදුසුයි. අමතර සැලකිල්ල අවශ්‍යයි.',
                              'ta':
                                  'மிதமான பொருத்தம் — $totalFlags நிபந்தனைகளில் $suitCount மட்டுமே ஏற்றது. கூடுதல் கவனம் தேவை.',
                            }),
                      style: TextStyle(
                        fontSize: 12,
                        height: 1.4,
                        fontWeight: FontWeight.w600,
                        color: isGoodMatch
                            ? AppTheme.success
                            : AppTheme.warning,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            // ── Action buttons — side-by-side on wide cards, stacked on
            //    narrow phones so longer si/ta labels never get clipped ──────
            LayoutBuilder(
              builder: (ctx, bc) {
                final narrow = bc.maxWidth < 300;
                final yieldBtn = OutlinedButton.icon(
                  onPressed: () {
                    widget.onCropSelectedForYield?.call(rec.crop);
                    widget.onNavigate?.call(1); // Yield tab
                  },
                  icon: const Icon(Icons.bar_chart, size: 16),
                  label: Text(
                    _t({
                      'en': 'Predict Yield',
                      'si': 'අස්වැන්න පුරෝකථනය',
                      'ta': 'விளைச்சல் கணிக்கவும்',
                    }),
                    style: const TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppTheme.primaryDark,
                    side: const BorderSide(color: AppTheme.primary),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                );
                final askBtn = ElevatedButton.icon(
                  onPressed: () {
                    final dLabel = _districtLabel(_selectedDistrict!);
                    final sLabel = _seasonLabel(_selectedSeason!);
                    final iLabel = _irrigationLabel(_selectedIrrigation!);
                    final ctx = _t({
                      'en':
                          'You recommended ${rec.crop} for my land in $_selectedDistrict '
                          '($_selectedSeason season, $_selectedIrrigation irrigation). '
                          'Please give me detailed advice on how to grow it successfully.',
                      'si':
                          'ඔබ $dLabel හි මගේ ඉඩම සඳහා ${rec.crop} නිර්දේශ කළා '
                          '($sLabel කන්නය, $iLabel ජලනය සමඟ). '
                          'මෙය සාර්ථකව වගා කරන ආකාරය ගැන මට විස්තරාත්මක උපදෙස් දෙන්න.',
                      'ta':
                          '$dLabel-இல் உள்ள என் நிலத்திற்கு நீங்கள் ${rec.crop} பரிந்துரைத்தீர்கள் '
                          '($sLabel பருவம், $iLabel முறை). '
                          'இதை வெற்றிகரமாக பயிரிடுவது எப்படி என்று எனக்கு விரிவாக விளக்குங்கள்.',
                    });
                    widget.onAiChatContext?.call(ctx);
                    widget.onNavigate?.call(6); // AI Chat tab
                  },
                  icon: SvgPicture.string(
                    _navSvg(6, Colors.white),
                    width: 15,
                    height: 15,
                  ),
                  label: Text(
                    _t({
                      'en': 'Ask AI',
                      'si': 'AI අසන්න',
                      'ta': 'AI கேளுங்கள்',
                    }),
                    style: const TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF00695C),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                );
                if (narrow) {
                  return Column(
                    children: [
                      SizedBox(width: double.infinity, child: yieldBtn),
                      const SizedBox(height: 8),
                      SizedBox(width: double.infinity, child: askBtn),
                    ],
                  );
                }
                return Row(
                  children: [
                    Expanded(child: yieldBtn),
                    const SizedBox(width: 8),
                    Expanded(child: askBtn),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  // ── Error card ─────────────────────────────────────────────────────────
  Widget _errorCard() => Container(
    margin: const EdgeInsets.only(bottom: 14),
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

  /// Shown in place of the empty placeholder while a recommendation is in
  /// flight — the result card is text-heavy (headline crop pick +
  /// narrative reasoning), so Typewriter fits: bars reveal left-to-right
  /// like the eventual text being "written in".
  Widget _resultSkeleton() => _card(
    child: const TypewriterSkeleton(
      lineWidthFractions: [0.5, 1.0, 0.9, 0.7, 0.85, 0.4],
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
      Icon(icon, size: 16, color: AppTheme.primaryDark),
      const SizedBox(width: 6),
      AnimatedLangText(
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

  Widget _slider(
    String label,
    double value,
    double min,
    double max,
    String unit,
    Color color,
    ValueChanged<double> onChanged, {
    String Function(double)? levelLabel,
    String? helperText,
    int? divisions,
  }) => Padding(
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
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                levelLabel == null
                    ? '${value.toStringAsFixed(max <= 1 ? 2 : 1)} $unit'.trim()
                    : (unit.trim().isEmpty
                          ? levelLabel(value)
                          : '${value.toStringAsFixed(max <= 1 ? 2 : 1)} $unit · ${levelLabel(value)}'),
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
            value: value,
            min: min,
            max: max,
            divisions: divisions,
            onChanged: onChanged,
          ),
        ),
        if (helperText != null) ...[
          const SizedBox(height: 3),
          Text(
            helperText,
            style: TextStyle(
              fontSize: 10,
              color: AppTheme.textMuted.withValues(alpha: 0.9),
              height: 1.3,
            ),
          ),
        ],
      ],
    ),
  );
}

