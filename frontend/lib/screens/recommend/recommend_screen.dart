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
import '../../services/prediction_handoff.dart';
import '../../services/service_factory.dart';
import '../../utils/farm_context.dart';
import '../../widgets/animated_lang_text.dart';
import '../../widgets/app_theme.dart';
import '../../widgets/app_top_bar.dart';
import '../../widgets/followup_chip.dart';
import '../../widgets/skeleton_loading.dart';

typedef _L = Map<String, String>;

/// How well a crop's four agronomic conditions are met. Four tiers rather
/// than one ratio — see _tierFor for why the old >= 0.7 could not
/// distinguish 3 of 4 from 4 of 4.
enum _MatchTier { ideal, good, workable, poor }

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

  // ── Searchable district field ────────────────────────────────────────────
  // RawAutocomplete owns neither of these, so they live here and are disposed
  // with the state — same ownership as price/yield.
  final TextEditingController _districtCtrl = TextEditingController();
  final FocusNode _districtFocus = FocusNode();

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
  @override
  void dispose() {
    _districtCtrl.dispose();
    _districtFocus.dispose();
    super.dispose();
  }

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
          Expanded(
            child: LayoutBuilder(
              builder: (ctx, bc) => _buildDetailsTab(bc.maxWidth),
            ),
          ),
        ],
      ),
    );
  }

  // ── Details layout — resizes for mobile / tablet / web ────────────────────
  // Thresholds and column formula copied from price_screen/yield_screen
  // verbatim rather than re-derived: this page used its own >= 960 break and
  // its own 5:4 grid, so at the same viewport its columns sat at visibly
  // different widths from every other feature page.
  Widget _buildDetailsTab(double width) {
    if (width >= 1024) return _buildWebDetails(width);
    if (width >= 600) return _buildTabletDetails(width);
    return _buildMobileDetails(width);
  }

  // Bottom padding 180 for the same reason as price_screen's: below 1024px
  // MainShell overlays FloatingBottomNav AND this Stack pins its own sticky
  // button to the same bottom:0, so the clearance has to cover both bars.
  Widget _buildMobileDetails(double width) {
    final hPad = width < 340 ? 12.0 : 14.0;
    return Stack(
      children: [
        SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(hPad, 14, hPad, 180),
          child: _formColumn(),
        ),
        _stickyRecommend(),
      ],
    );
  }

  Widget _buildTabletDetails(double width) {
    final targetContentW = width < 760 ? width - 32 : 680.0;
    final hPad = ((width - targetContentW) / 2).clamp(16.0, 220.0);
    return Stack(
      children: [
        SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(hPad, 14, hPad, 180),
          child: _formColumn(),
        ),
        _stickyRecommend(),
      ],
    );
  }

  // Web (>= 1024dp): inputs left, weather + results + chat right.
  //
  // The button moves INTO the left column here and is pinned to its bottom,
  // exactly as price/yield pin theirs. It used to sit at the top of the right
  // column, above the results it produces — so the farmer filled in the left
  // column and then had to cross the page to submit it.
  Widget _buildWebDetails(double width) {
    final leftW = (width * 0.44).clamp(360.0, 560.0);
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
              _stickyRecommend(),
            ],
          ),
        ),
        Container(width: 1, color: AppTheme.login.borderSubtle),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 16, 20, 28),
            child: _rightPanel(),
          ),
        ),
      ],
    );
  }

  // ── Sticky bottom action button ───────────────────────────────────────────
  Widget _stickyRecommend() => Positioned(
    bottom: 0,
    left: 0,
    right: 0,
    child: Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
      decoration: BoxDecoration(
        color: AppTheme.login.background,
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

  // ── Form column (LEFT on web, the whole page below 1024dp) ────────────────
  // Order is fixed: header -> Season -> Location & Irrigation -> Soil, then
  // the sticky button pinned over the bottom of this same column.
  //
  // Weather moved OUT of here to the right panel. It is fetched for the
  // district rather than typed by the farmer, so it is context for reading
  // the results, not an input to fill in — keeping it in the input column
  // was what forced the old 5:4 grid to split Season/Location from Soil.
  Widget _formColumn({bool webLeft = false}) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _pageHeader(),
      const SizedBox(height: 16),
      _sectionTitle(
        _t({'en': 'Season', 'si': 'කන්නය', 'ta': 'பருவம்'}),
        Icons.calendar_month,
      ),
      const SizedBox(height: 10),
      _seasonChips(),
      const SizedBox(height: 20),
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
      const SizedBox(height: 20),
      _sectionTitle(_t({'en': 'Soil', 'si': 'පස', 'ta': 'மண்'}), Icons.science),
      const SizedBox(height: 10),
      _soilCard(),
      // Single column (<1024dp): weather, results and the chat block follow
      // the inputs. The button itself stays pinned in the sticky bar above
      // this scroll view, so it is never scrolled away from.
      if (!webLeft) ...[const SizedBox(height: 20), _rightPanel()],
    ],
  );

  // ── Right panel (RIGHT on web, appended below the inputs on mobile) ───────
  Widget _rightPanel() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _sectionTitle(
        _t({'en': 'Weather', 'si': 'කාලගුණය', 'ta': 'வானிலை'}),
        Icons.cloud,
      ),
      const SizedBox(height: 10),
      _weatherCard(),
      const SizedBox(height: 20),
      if (_isLoading) _resultSkeleton(),
      if (_errorMessage != null) _errorCard(),
      if (_result != null) ...[
        _resultSection(),
        const SizedBox(height: 16),
        _askAiBlock(),
      ],
      if (_result == null && _errorMessage == null && !_isLoading)
        _emptyPlaceholder(),
    ],
  );

  // ── Top bar ───────────────────────────────────────────────────────────────
  // Crop Recommend is nav index 4. See app_top_bar.dart for why this is one
  // shared widget now instead of six independent copies of this same bar.
  //
  // Active colours come from the cropRec accent rather than the hardcoded
  // #E8F5E9/#2E7D32 pair this screen used to carry — same change price and
  // yield already made, so the six bars stay in step when an accent moves.
  Widget _buildTopBar(BuildContext context) => AppTopBar(
    activeIndex: 4,
    activeBg: AppTheme.accents.cropRec.fill.withValues(alpha: 0.16),
    activeColor: AppTheme.accents.cropRec.ink,
    onNavigate: widget.onNavigate,
  );

  // ── Page header ────────────────────────────────────────────────────────────
  // Structurally identical to price_screen's header — same gradient direction
  // (dark top-left -> light bottom-right), same +0.15 HLS light stop, same
  // icon container, glass badge and title/subtitle sizing.
  //
  // It does NOT copy price's colour treatment, deliberately. That header puts
  // WHITE on a terracotta fill and misses AA (2.65:1) as a known, accepted
  // trade-off; white on this olive would be 2.79:1 at the dark anchor and
  // 1.98:1 at the light stop — the same failure, only worse. cropRec's own
  // onFill token is DARK (#1F2A1F) and clears AA at both ends, so the shape
  // is price's and the contrast is this accent's:
  //
  //   #7CA759 (dark anchor, == accents.cropRec.fill)  onFill 5.34:1
  //   #A3C28B (light stop, +0.15 HLS)                 onFill 7.53:1
  //
  // Nothing here is a known-accepted failure; if this is ever re-themed to
  // white text, both numbers above are what it costs.
  static final Color _headerGradientLight = _lighten(
    AppTheme.accents.cropRec.fill,
    0.15,
  );

  /// +delta lightness in HLS, hue and saturation preserved — the same widening
  /// price_screen's light stop uses, kept as code so the relationship to fill
  /// survives a re-theme instead of being a second hardcoded hex.
  static Color _lighten(Color c, double delta) {
    final hsl = HSLColor.fromColor(c);
    return hsl.withLightness((hsl.lightness + delta).clamp(0.0, 1.0)).toColor();
  }

  Widget _pageHeader() => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      gradient: LinearGradient(
        colors: [AppTheme.accents.cropRec.fill, _headerGradientLight],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
      borderRadius: BorderRadius.circular(14),
      boxShadow: [
        BoxShadow(
          color: AppTheme.accents.cropRec.fill.withValues(alpha: 0.3),
          blurRadius: 10,
          offset: const Offset(0, 4),
        ),
      ],
    ),
    child: Row(
      children: [
        _glassBadge(
          borderRadius: 10,
          padding: const EdgeInsets.all(10),
          child: SvgPicture.string(
            _navSvg(4, AppTheme.accents.cropRec.onFill),
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
                style: TextStyle(
                  color: AppTheme.accents.cropRec.onFill, // 5.34-7.53:1
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
                // 0.90, not the 0.8 the other headers use — that is the
                // measured ceiling here, not a style choice. Dark ink on this
                // gradient does have alpha headroom (price's light stop had
                // none at all), but less than it looks: 0.90 holds 4.55:1 at
                // the dark anchor and 6.14:1 at the light stop, while 0.88
                // already drops the dark end to 4.40:1 and price's own 0.8
                // to 3.82:1 — both under the 4.5:1 normal-text floor. Full
                // opacity (5.34:1 / 7.53:1) is the fallback if this ever
                // needs more margin.
                style: TextStyle(
                  color: AppTheme.accents.cropRec.onFill.withValues(
                    alpha: 0.90,
                  ),
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
        _glassBadge(
          borderRadius: 20,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          child: Text(
            _t({
              'en': 'Week ${farmWeekOfYear()}',
              'si': 'සති ${farmWeekOfYear()}',
              'ta': 'வாரம் ${farmWeekOfYear()}',
            }),
            style: TextStyle(
              color: AppTheme.accents.cropRec.onFill, // 6.36-8.43:1
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    ),
  );

  /// Glass panel — the icon badge and "Week N" pill. Same treatment as
  /// price_screen's and yield_screen's (translucent tint + a faint white edge
  /// highlight), tinted WHITE rather than price's black.
  ///
  /// Direction follows the fill, as it does on the other two pages: price's
  /// fill is a light terracotta where darkening is what preserves contrast for
  /// its white content; this page carries DARK content, so lightening is what
  /// preserves it. White@0.15 puts the icon and Week pill at 6.36:1 (dark end)
  /// to 8.43:1 (light end) — comfortably AA, with no trade-off to accept.
  /// Black@0.20 (price's exact value) would drop the same dark content to
  /// 3.56-4.87:1, i.e. failing at the end where this gradient is darkest.
  Widget _glassBadge({
    required double borderRadius,
    required EdgeInsets padding,
    required Widget child,
  }) => Container(
    padding: padding,
    decoration: BoxDecoration(
      color: Colors.white.withValues(alpha: 0.15),
      borderRadius: BorderRadius.circular(borderRadius),
      border: Border.all(color: Colors.white.withValues(alpha: 0.25), width: 1),
    ),
    child: child,
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
          _searchableDropdown(
            label: _t({
              'en': 'District',
              'si': 'දිස්ත්‍රික්කය',
              'ta': 'மாவட்டம்',
            }),
            value: _selectedDistrict,
            items: _districts,
            icon: Icons.location_on,
            controller: _districtCtrl,
            focusNode: _districtFocus,
            itemLabel: _districtLabel,
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
              prefixIcon: Icon(
                Icons.water_drop,
                color: AppTheme.accents.cropRec.ink,
                size: 20,
              ),
              // Same inline tick as the district field above, so both
              // required inputs signal "done" the same way.
              suffixIconConstraints: const BoxConstraints(
                minWidth: 0,
                minHeight: 0,
              ),
              suffixIcon: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _fieldCheck(_selectedIrrigation != null),
                  const Padding(
                    padding: EdgeInsets.only(right: 8),
                    child: Icon(Icons.arrow_drop_down),
                  ),
                ],
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
        // Read BEFORE the badges it qualifies, not after them.
        if (_anyCropFailsHumidity()) ...[
          _humidityCaveat(),
          const SizedBox(height: 12),
        ],
        // The backend already sorts district-unsuitable crops last, so this
        // divider only ever appears once — it is what makes the sort legible
        // instead of looking like the ranking broke partway down.
        ..._result!.recommendations.asMap().entries.expand((e) {
          final rec = e.value;
          final prev = e.key == 0 ? null : _result!.recommendations[e.key - 1];
          final startsUnsuitable =
              !rec.districtSuitable && (prev?.districtSuitable ?? true);
          return [
            if (startsUnsuitable) _districtDivider(),
            _recommendationCard(rec),
          ];
        }),
      ],
    );
  }

  /// True when at least one recommended crop failed the humidity condition.
  ///
  /// Gates [_humidityCaveat]: if humidity passed for everything, the caveat
  /// is noise. Same reasoning as the district divider — shown once, only when
  /// it explains something actually on screen.
  bool _anyCropFailsHumidity() =>
      _result?.recommendations.any(
        (r) => r.suitabilityFlags['humidity_suitable'] == false,
      ) ??
      false;

  /// Plain-language caveat on the humidity condition.
  ///
  /// WHY THIS EXISTS. The humidity bands were derived from a dataset whose
  /// humidity column sits 3.7-16.4 points BELOW observed weather in every one
  /// of the eight districts. The condition passes 99.6% of the time in that
  /// data and roughly 70% (lowland) / 39% (upcountry) against real weather —
  /// so it reports failures that real growing conditions do not warrant,
  /// most often in humid weeks. Full evidence in
  /// backend/docs/known_issues.md item 5.
  ///
  /// This is the disclosure half of a deliberate holding position: no band
  /// value is changed, because the two real fixes (shifting the band, or
  /// rebuilding it from observed weather) both depend on validation against
  /// Department of Meteorology station data that we do not have. Until then
  /// the honest move is to tell the farmer the check is strict rather than
  /// quietly let it mark good crops down.
  ///
  /// Deliberately NOT the amber warning tone. The four badge tiers use colour
  /// to say something about the farmer's land; this says something about OUR
  /// check, so it reads as a footnote rather than a fifth severity.
  ///
  /// Wording is farmer-facing on purpose — no mention of datasets,
  /// calibration or bias. It has one job: do not over-weight this single
  /// condition.
  Widget _humidityCaveat() => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    decoration: BoxDecoration(
      color: AppTheme.textMuted.withValues(alpha: 0.07),
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: AppTheme.textMuted.withValues(alpha: 0.25)),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(
          Icons.info_outline_rounded,
          size: 16,
          color: AppTheme.textSecondary,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: RichText(
            text: TextSpan(
              style: const TextStyle(
                fontSize: 11.5,
                height: 1.45,
                color: AppTheme.textSecondary,
              ),
              children: [
                TextSpan(
                  text: _t({
                    'en':
                        'Humidity: this check is stricter than real growing conditions. ',
                    'si':
                        'ආර්ද්‍රතාවය: මෙම පරීක්ෂාව සැබෑ වගා තත්ත්වවලට වඩා දැඩියි. ',
                    'ta':
                        'ஈரப்பதம்: இந்தச் சோதனை உண்மையான பயிர்ச்செய்கை நிலைமைகளை விட கடுமையானது. ',
                  }),
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                TextSpan(
                  text: _t({
                    'en':
                        'A crop that only misses on humidity will often still grow well — weigh temperature, rainfall and soil more heavily.',
                    'si':
                        'ආර්ද්‍රතාවය පමණක් නොගැලපෙන භෝගයක් බොහෝ විට හොඳින් වැවෙනු ඇත — උෂ්ණත්වය, වර්ෂාපතනය සහ පස වැඩි වශයෙන් සලකා බලන්න.',
                    'ta':
                        'ஈரப்பதத்தில் மட்டும் தவறும் பயிர் பெரும்பாலும் நன்றாக வளரும் — வெப்பநிலை, மழைவீழ்ச்சி மற்றும் மண்ணுக்கு அதிக முக்கியத்துவம் கொடுங்கள்.',
                  }),
                ),
              ],
            ),
          ),
        ),
      ],
    ),
  );

  /// Section rule introducing the crops the district does not normally grow.
  Widget _districtDivider() => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Row(
      children: [
        const Expanded(child: Divider(color: AppTheme.border)),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Text(
            _t({
              'en': 'Not typically grown in this district',
              'si': 'මෙම දිස්ත්‍රික්කයේ සාමාන්‍යයෙන් වගා නොකෙරේ',
              'ta': 'இந்த மாவட்டத்தில் பொதுவாகப் பயிரிடப்படுவதில்லை',
            }),
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: AppTheme.textMuted,
              letterSpacing: 0.2,
            ),
          ),
        ),
        const Expanded(child: Divider(color: AppTheme.border)),
      ],
    ),
  );

  Widget _recommendationCard(CropRecommendation rec) {
    final rankColors = [
      const Color(0xFFFFD700),
      const Color(0xFFC0C0C0),
      const Color(0xFFCD7F32),
    ];
    // A crop the district cannot support never gets a medal colour, however
    // high its probability: the metallic border is the page's "this is a top
    // pick" signal, and Carrot at 15% in Monaragala is not one.
    final rankColor = !rec.districtSuitable
        ? AppTheme.textMuted
        : (rec.rank <= 3 ? rankColors[rec.rank - 1] : Colors.grey);
    final suitCount = rec.suitabilityFlags.values.where((v) => v).length;
    final totalFlags = rec.suitabilityFlags.length;
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
            _suitabilityBanner(rec, suitCount, totalFlags),
            // ── Why this crop sorted where it did ──────────────────────────
            // Without this the ordering looks arbitrary: the backend sorts
            // district-unsuitable crops below every suitable one regardless
            // of probability, so Carrot can show 15% and still sit under
            // Finger millet's 1%. Stated plainly rather than hidden — a
            // farmer who expected Carrot should see it was considered, and
            // why it lost, instead of finding it silently missing.
            if (!rec.districtSuitable) ...[
              const SizedBox(height: 8),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.location_off_outlined,
                    size: 15,
                    color: AppTheme.textMuted,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      _t({
                        'en':
                            'Not usually grown in ${_districtLabel(_selectedDistrict ?? '')} — ranked below crops that are.',
                        'si':
                            '${_districtLabel(_selectedDistrict ?? '')} හි සාමාන්‍යයෙන් වගා නොකෙරේ — එහි වගා කරන භෝගවලට පහළින් ශ්‍රේණිගත කර ඇත.',
                        'ta':
                            '${_districtLabel(_selectedDistrict ?? '')}-இல் பொதுவாகப் பயிரிடப்படுவதில்லை — அங்கு பயிரிடப்படும் பயிர்களுக்குக் கீழே தரவரிசைப்படுத்தப்பட்டுள்ளது.',
                      }),
                      style: const TextStyle(
                        fontSize: 11.5,
                        height: 1.35,
                        color: AppTheme.textMuted,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// Inline validation tick for a required field, shown as its `suffixIcon`.
  ///
  /// The filled state is the yield page's `_fieldCheck` verbatim —
  /// Icons.check_circle at 19px in AppTheme.success — so a farmer moving
  /// between the two forms sees one signal, not two dialects of one.
  ///
  /// Unlike yield's, this returns a widget in BOTH states: an unfilled
  /// outline stands in for the tick when the field is empty. The removed
  /// checklist card used to carry that "still to do" signal; with it gone,
  /// a field that renders nothing until it is satisfied leaves nowhere for
  /// the eye to learn that the tick is the thing to collect.
  ///
  /// Status is never colour-alone here: the two states differ in glyph
  /// (filled disc vs open ring) as well as in tone.
  Widget _fieldCheck(bool done) => Padding(
    padding: const EdgeInsets.only(right: 2),
    child: Icon(
      done ? Icons.check_circle : Icons.radio_button_unchecked,
      size: 19,
      color: done ? AppTheme.success : AppTheme.login.borderSubtle,
    ),
  );

  /// Type-to-filter dropdown — price_screen's `_searchableDropdown`, ported
  /// verbatim with only the accent tokens swapped (price.ink -> cropRec.ink).
  ///
  /// NOTE: this is now the FOURTH copy of this widget (yield, price, weather,
  /// here). Ported rather than extracted because this pass is scoped to one
  /// screen, but it is the same drift app_top_bar.dart was created to end —
  /// worth hoisting into lib/widgets/ next time one of the four is touched.
  ///
  /// Price's own notes, which still apply:
  ///
  /// 1. [itemLabel]. Yield's version shows raw English values; this screen is
  ///    trilingual, so options render through the same label functions the old
  ///    `_nullDropdown` used, and the FILTER matches either the English key or
  ///    the translated label. A Sinhala user can type "කැ" or "car" and reach
  ///    Carrot either way — matching only the display label would strand
  ///    farmers whose keyboard is in the other script.
  /// 2. The accent palette. Structure and behaviour are yield's; only the
  ///    colour tokens differ.
  Widget _searchableDropdown({
    required String label,
    required String? value,
    required List<String> items,
    required IconData icon,
    required ValueChanged<String?> onChanged,
    required TextEditingController controller,
    required FocusNode focusNode,
    required String Function(String) itemLabel,
    String? hint,
    bool enabled = true,
  }) => LayoutBuilder(
    // Captures the field's own width so the options overlay lines up
    // edge-to-edge below it instead of sizing itself to its content.
    builder: (ctx, bc) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        RawAutocomplete<String>(
          textEditingController: controller,
          focusNode: focusNode,
          displayStringForOption: itemLabel,
          optionsBuilder: (TextEditingValue v) {
            if (!enabled) return const Iterable<String>.empty();
            final q = v.text.trim().toLowerCase();
            // Empty, or still showing the committed selection (the farmer
            // reopened the field to change their mind) -> offer everything.
            if (q.isEmpty ||
                q == itemLabel(value ?? '').toLowerCase() ||
                q == (value ?? '').toLowerCase()) {
              return items;
            }
            return items.where(
              (e) =>
                  e.toLowerCase().contains(q) ||
                  itemLabel(e).toLowerCase().contains(q),
            );
          },
          onSelected: (sel) {
            onChanged(sel);
            focusNode.unfocus();
          },
          fieldViewBuilder: (ctx, ctrl, fn, onFieldSubmitted) => TextFormField(
            controller: ctrl,
            focusNode: fn,
            enabled: enabled,
            onFieldSubmitted: (_) => onFieldSubmitted(),
            style: TextStyle(fontSize: 14, color: AppTheme.login.textPrimary),
            decoration: InputDecoration(
              labelText: label,
              hintText: enabled
                  ? _t({
                      'en': 'Type to search',
                      'si': 'සෙවීමට ටයිප් කරන්න',
                      'ta': 'தேட தட்டச்சு செய்க',
                    })
                  : null,
              hintStyle: TextStyle(
                color: AppTheme.login.textSecondary,
                fontSize: 13,
              ),
              labelStyle: TextStyle(color: AppTheme.login.textSecondary),
              prefixIcon: Icon(
                icon,
                color: enabled
                    ? AppTheme.accents.cropRec.ink
                    : AppTheme.login.textSecondary,
                size: 20,
              ),
              // Tick + caret together. mainAxisSize.min keeps the Row from
              // trying to fill the field, and the loosened constraints stop
              // InputDecoration squeezing two icons into one icon's width.
              suffixIconConstraints: const BoxConstraints(
                minWidth: 0,
                minHeight: 0,
              ),
              suffixIcon: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _fieldCheck(value != null),
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: Icon(
                      Icons.arrow_drop_down,
                      color: enabled
                          ? AppTheme.accents.cropRec.ink
                          : AppTheme.login.textSecondary,
                    ),
                  ),
                ],
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: AppTheme.login.borderSubtle),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: AppTheme.login.borderSubtle),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(
                  color: AppTheme.login.focusRing,
                  width: 2,
                ),
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 10,
              ),
              filled: !enabled,
              fillColor: enabled ? null : AppTheme.disabledSurface,
            ),
          ),
          optionsViewBuilder: (ctx, onSelected, options) => Align(
            alignment: Alignment.topLeft,
            child: Material(
              elevation: 4,
              borderRadius: BorderRadius.circular(8),
              color: AppTheme.login.background,
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: 240,
                  maxWidth: bc.maxWidth,
                ),
                child: SizedBox(
                  width: bc.maxWidth,
                  child: ListView.builder(
                    padding: EdgeInsets.zero,
                    shrinkWrap: true,
                    itemCount: options.length,
                    itemBuilder: (c, i) {
                      final opt = options.elementAt(i);
                      final isSelected = opt == value;
                      return InkWell(
                        onTap: () => onSelected(opt),
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 11,
                          ),
                          color: isSelected
                              ? AppTheme.accents.cropRec.fill.withValues(
                                  alpha: 0.14,
                                )
                              : null,
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  itemLabel(opt),
                                  style: TextStyle(
                                    fontSize: 13.5,
                                    fontWeight: isSelected
                                        ? FontWeight.w700
                                        : FontWeight.w500,
                                    color: isSelected
                                        ? AppTheme.accents.cropRec.ink
                                        : AppTheme.login.textPrimary,
                                  ),
                                ),
                              ),
                              if (isSelected)
                                Icon(
                                  Icons.check,
                                  size: 16,
                                  color: AppTheme.accents.cropRec.ink,
                                ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
        ),
        if (hint != null)
          Padding(
            padding: const EdgeInsets.only(top: 4, left: 4),
            child: Text(
              hint,
              style: TextStyle(
                fontSize: 11,
                color: AppTheme.login.textSecondary,
              ),
            ),
          ),
      ],
    ),
  );

  // ── Chat handoff ──────────────────────────────────────────────────────────
  /// The whole recommendation, structured, for the chat screen to reason over.
  ///
  /// `crop` is the TOP-ranked crop, not a farmer selection: the backend's
  /// saved-context confirmation gate and its RAG metadata boost both read
  /// crop/district off prediction_context, and leaving crop null would let a
  /// stale saved profile answer "which crop?" for a page that just ranked six.
  ///
  /// Every crop is sent, not just the winner — the questions offered here are
  /// comparative ("what if I want to grow something else?"), and a model given
  /// only the top crop would have to invent the alternatives.
  PredictionContext _predictionContext() {
    final recs = _result?.recommendations ?? const <CropRecommendation>[];
    return PredictionContext(
      crop: recs.isNotEmpty ? recs.first.crop : null,
      district: _selectedDistrict,
      season: _selectedSeason,
      irrigation: _selectedIrrigation,
      soilPh: _soilPh,
      soilMoisturePct: _soilMoisture,
      weather: _weather == null
          ? null
          : PredictionWeather(
              rainfallMm: _weather!.rainfallMm,
              tempMinC: _weather!.tempMinC,
              tempMaxC: _weather!.tempMaxC,
              humidityPct: _weather!.humidityPct,
            ),
      recommendations: recs.isEmpty
          ? null
          : recs.map(PredictionCropRecommendation.fromRecommendation).toList(),
    );
  }

  /// Publish to the chat screen and switch to the AI Chat tab — the same
  /// single-slot, consume-once ValueNotifier price and yield use, so the
  /// context persists for follow-up questions in that conversation.
  void _askAi({String? question}) {
    if (_result == null) return;
    predictionHandoff.value = PredictionHandoff(
      _predictionContext(),
      question: question,
    );
    widget.onNavigate?.call(6); // AI Chat tab
  }

  /// Shared styling for every action in the "Ask AI about this" block.
  ///
  /// primaryDark, not the cropRec accent: these are primary actions, and the
  /// accent rules keep those consistent app-wide.
  ButtonStyle get _askAiButtonStyle => ElevatedButton.styleFrom(
    backgroundColor: AppTheme.login.primaryDark,
    foregroundColor: Colors.white,
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    elevation: 2,
  );

  /// The recommendation questions live HERE, on the result, not on an
  /// otherwise blank chat screen — the farmer picks what they want to know
  /// while still looking at the ranking.
  ///
  /// This replaces the per-crop "Ask AI" button that used to sit on all six
  /// cards. Those sent a hand-built English sentence naming one crop; these
  /// send the short visible text and carry the full ranking in
  /// prediction_context, so chat analytics keeps logging the farmer's own
  /// question and the assistant can still compare across crops.
  Widget _askAiBlock() {
    final top = _result?.recommendations.isNotEmpty == true
        ? _result!.recommendations.first.crop
        : null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle(
          _t({
            'en': 'Ask AI about this',
            'si': 'මේ ගැන AI වෙතින් අසන්න',
            'ta': 'இதைப் பற்றி AI-இடம் கேளுங்கள்',
          }),
          Icons.auto_awesome,
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final q in recommendStarters(top))
              ElevatedButton(
                onPressed: () => _askAi(question: q),
                style: _askAiButtonStyle,
                child: Text(
                  q,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 12),
        ElevatedButton.icon(
          onPressed: _askAi,
          icon: SvgPicture.string(
            _navSvg(6, Colors.white),
            width: 18,
            height: 18,
          ),
          label: Text(
            _t({
              'en': 'Ask something else about this',
              'si': 'මේ ගැන වෙනත් දෙයක් අසන්න',
              'ta': 'இதைப் பற்றி வேறு ஏதாவது கேளுங்கள்',
            }),
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
          ),
          style: _askAiButtonStyle,
        ),
      ],
    );
  }

  // ── Suitability verdict ───────────────────────────────────────────────────
  // The four agronomic conditions (temperature, rainfall, humidity, soil pH)
  // are checked per crop against that crop's own tolerance bands, so they
  // genuinely differentiate: for Monaragala/Yala, Cowpea/Maize/Finger millet
  // score 4/4 while Carrot/Green gram/Groundnut score 3/4 on temperature.
  //
  // The old banner could not show that. It ran a single >= 0.7 ratio against
  // flags that used to be model telemetry rather than agronomy, and 3/4
  // (0.75) and 4/4 both clear 0.7 — so every crop rendered the same verdict,
  // as every crop had before for a different reason. Four explicit tiers
  // instead of one ratio, and the count is always spelled out.
  //
  // 3 of 4 is deliberately NOT amber. It is a good result — the previous
  // wording ("Fair match ... consider extra care", in warning colour) read
  // as a caution the farmer had no reason to feel. Amber starts at 2 of 4.
  _MatchTier _tierFor(int met, int total) {
    if (total == 0) return _MatchTier.good; // no flags to judge on
    if (met == total) return _MatchTier.ideal;
    if (met == total - 1) return _MatchTier.good;
    if (met >= total - 2) return _MatchTier.workable;
    return _MatchTier.poor;
  }

  Color _tierColor(_MatchTier t) => switch (t) {
    _MatchTier.ideal => AppTheme.success,
    // cropRec's ink, not amber: a calm, on-brand tone for a good result.
    _MatchTier.good => AppTheme.accents.cropRec.ink,
    _MatchTier.workable => AppTheme.warning,
    _MatchTier.poor => AppTheme.error,
  };

  IconData _tierIcon(_MatchTier t) => switch (t) {
    _MatchTier.ideal => Icons.verified_rounded,
    _MatchTier.good => Icons.check_circle_rounded,
    _MatchTier.workable => Icons.info_rounded,
    _MatchTier.poor => Icons.warning_amber_rounded,
  };

  /// Localised names of the conditions this crop FAILED, in display order.
  /// Naming them is the actionable half: "Watch temperature" tells the farmer
  /// it is the heat, not a vague objection they cannot act on.
  List<String> _failedConditions(CropRecommendation rec) {
    const order = [
      'temp_suitable',
      'rain_suitable',
      'humidity_suitable',
      'ph_suitable',
    ];
    const labels = <String, _L>{
      'temp_suitable': {
        'en': 'temperature',
        'si': 'උෂ්ණත්වය',
        'ta': 'வெப்பநிலை',
      },
      'rain_suitable': {
        'en': 'rainfall',
        'si': 'වර්ෂාපතනය',
        'ta': 'மழைவீழ்ச்சி',
      },
      'humidity_suitable': {
        'en': 'humidity',
        'si': 'ආර්ද්‍රතාවය',
        'ta': 'ஈரப்பதம்',
      },
      'ph_suitable': {'en': 'soil pH', 'si': 'පසේ pH', 'ta': 'மண் pH'},
    };
    return [
      for (final k in order)
        if (rec.suitabilityFlags[k] == false) _t(labels[k]!),
    ];
  }

  /// "temperature" / "temperature and rainfall" / "temperature, rainfall and
  /// humidity" — joined in the active language.
  String _joinConditions(List<String> parts) {
    if (parts.isEmpty) return '';
    if (parts.length == 1) return parts.first;
    final and = _t({'en': 'and', 'si': 'සහ', 'ta': 'மற்றும்'});
    return '${parts.sublist(0, parts.length - 1).join(', ')} $and ${parts.last}';
  }

  Widget _suitabilityBanner(CropRecommendation rec, int met, int total) {
    final tier = _tierFor(met, total);
    final color = _tierColor(tier);
    final failed = _joinConditions(_failedConditions(rec));

    final headline = switch (tier) {
      _MatchTier.ideal => _t({
        'en': 'Ideal match — all $total conditions suit this crop.',
        'si': 'කදිම ගැලපීමකි — කොන්දේසි $total ම මෙම භෝගයට ගැලපේ.',
        'ta':
            'சிறந்த பொருத்தம் — $total நிபந்தனைகளும் இந்தப் பயிருக்கு ஏற்றவை.',
      }),
      _MatchTier.good => _t({
        'en': 'Good match — $met of $total conditions ideal.',
        'si': 'හොඳ ගැලපීමකි — කොන්දේසි $total න් $met ක් සුදුසුයි.',
        'ta': 'நல்ல பொருத்தம் — $total நிபந்தனைகளில் $met ஏற்றவை.',
      }),
      _MatchTier.workable => _t({
        'en': 'Workable — $met of $total conditions ideal. Needs extra care.',
        'si':
            'වගා කළ හැකියි — කොන්දේසි $total න් $met ක් සුදුසුයි. අමතර සැලකිල්ල අවශ්‍යයි.',
        'ta':
            'பயிரிட முடியும் — $total நிபந்தனைகளில் $met ஏற்றவை. கூடுதல் கவனம் தேவை.',
      }),
      _MatchTier.poor => _t({
        'en': 'Poor match — only $met of $total conditions ideal.',
        'si': 'දුර්වල ගැලපීමකි — කොන්දේසි $total න් $met ක් පමණි සුදුසු.',
        'ta': 'மோசமான பொருத்தம் — $total நிபந்தனைகளில் $met மட்டுமே ஏற்றவை.',
      }),
    };

    // Only worth saying when SOME conditions passed — on a poor match the
    // headline already carries it, and listing three failures reads as piling
    // on rather than as advice.
    final watch = (failed.isNotEmpty && tier != _MatchTier.poor)
        ? ' ${_t({'en': 'Watch $failed.', 'si': '$failed නිරීක්ෂණය කරන්න.', 'ta': '$failed கவனிக்கவும்.'})}'
        : '';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(_tierIcon(tier), size: 17, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '$headline$watch',
              style: TextStyle(
                fontSize: 12,
                height: 1.4,
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
          ),
        ],
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
