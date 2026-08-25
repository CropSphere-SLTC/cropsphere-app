// lib/screens/weather/weather_screen.dart
// ─────────────────────────────────────────────────────────────────────────────
//  CropSphere — Weather Forecast (v3)
//
//  CHANGES FROM v2 — redesign matching Yield/Price's post-redesign pattern:
//  ✅ AppTheme.accents.weather header (gradient, glass icon badge, Week
//     pill) instead of a hardcoded blue — same structure as price_screen's
//     header, see _pageHeader.
//  ✅ Quick-select district chips removed — the searchable dropdown is now
//     the sole district selector (matches Yield/Price).
//  ✅ District field is a type-to-filter RawAutocomplete dropdown with an
//     inline checkmark, ported from price_screen's `_searchableDropdown`.
//  ✅ Two-column layout at >=1024px — inputs left (header, location, range,
//     tips, Get Forecast), results right (forecast cards + Ask AI) — same
//     1024px threshold and left-column width formula as price_screen.
//  ✅ "Get Forecast" button uses AppTheme.accents.weather.fill, by explicit
//     request — the second such exception to "primary actions stay green",
//     after price_screen's "Predict Price" button.
//  ✅ "Ask AI about this" — same predictionHandoff mechanism as Yield/Price,
//     4 weather-specific starter chips (kWeatherStarters).
//  ✅ The advice banner's emoji prefixes are gone — the icon already drawn
//     alongside each banner (adviceIcon) is the only glyph now.
//  ✅ Fully trilingual (en/si/ta) throughout — unchanged from v2.
//  ✅ Weather forecast logic, the ML call, and the "Good Growing
//     Conditions" interpretation wording are unchanged — only presentation.
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../../app_lang.dart';
import '../../models/api_models.dart';
import '../../services/prediction_handoff.dart';
import '../../services/service_factory.dart';
import '../../widgets/animated_lang_text.dart';
import '../../widgets/app_theme.dart';
import '../../widgets/app_top_bar.dart';
import '../../widgets/followup_chip.dart';
import '../../widgets/skeleton_loading.dart';

typedef _L = Map<String, String>;

// ─────────────────────────────────────────────────────────────────────────────
//  Trilingual district names (self-contained per screen, same values as
//  Dashboard/Yield/Price so districts read identically everywhere)
// ─────────────────────────────────────────────────────────────────────────────
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

const List<String> _districtKeys = [
  'Nuwara Eliya',
  'Badulla',
  'Anuradhapura',
  'Monaragala',
  'Ampara',
  'Hambantota',
  'Batticaloa',
  'Jaffna',
];

String _districtLabel(String langKey, String? district) {
  if (district == null) return '';
  final m = _districtNames[district];
  if (m == null) return district;
  return m[langKey] ?? m['en'] ?? district;
}

// ─────────────────────────────────────────────────────────────────────────────
//  Weeks-ahead options — farmer-friendly labels, trilingual
// ─────────────────────────────────────────────────────────────────────────────
const List<_L> _weekOptions = [
  {'en': '1 week', 'si': 'සති 1', 'ta': '1 வாரம்'},
  {'en': '2 weeks', 'si': 'සති 2', 'ta': '2 வாரங்கள்'},
  {'en': '3 weeks', 'si': 'සති 3', 'ta': '3 வாரங்கள்'},
  {'en': '4 weeks', 'si': 'සති 4', 'ta': '4 வாரங்கள்'},
];

// ─────────────────────────────────────────────────────────────────────────────
//  General weather & farming tips — trilingual. Unchanged from v2, just
//  relocated into the left column (see _formColumn).
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

const _kWeatherTips = <_Tip>[
  _Tip(
    title: {
      'en': 'Check before spraying',
      'si': 'ස්ප්‍රේ කිරීමට පෙර පරීක්ෂා කරන්න',
      'ta': 'தெளிக்கும் முன் சரிபாருங்கள்',
    },
    text: {
      'en':
          'Avoid spraying fertiliser or pesticide if heavy rain is expected within 24 hours — it washes off before it can work.',
      'si':
          'පැය 24ක් තුළ තද වැස්සක් අපේක්ෂිත නම් පොහොර හෝ පළිබෝධනාශක ස්ප්‍රේ නොකරන්න — ක්‍රියා කිරීමට පෙර සෝදා යයි.',
      'ta':
          '24 மணி நேரத்திற்குள் கனமழை எதிர்பார்க்கப்பட்டால் உரம் அல்லது பூச்சிக்கொல்லி தெளிக்காதீர்கள் — வேலை செய்வதற்கு முன் கழுவப்படும்.',
    },
    icon: Icons.water_drop_outlined,
    color: Color(0xFF1565C0),
  ),
  _Tip(
    title: {
      'en': 'Prepare drainage early',
      'si': 'කලින් ජල බැස්සීම සූදානම් කරන්න',
      'ta': 'முன்கூட்டியே வடிகால் தயார் செய்யுங்கள்',
    },
    text: {
      'en':
          'Clear drainage channels a day or two before a predicted heavy-rain week to prevent root rot and waterlogging.',
      'si':
          'තද වැසි සතියකට දින 1-2 කට පෙර ජල බැස්සීම් නාලිකා පිරිසිදු කර මූල කුණු වීම වළක්වන්න.',
      'ta':
          'கனமழை வாரத்திற்கு 1-2 நாட்களுக்கு முன் வடிகால்களை சுத்தம் செய்து வேர் அழுகலைத் தடுக்கவும்.',
    },
    icon: Icons.grid_view_rounded,
    color: Color(0xFF00695C),
  ),
  _Tip(
    title: {
      'en': 'Irrigate during dry spells',
      'si': 'නියං කාලවලදී ජලනය කරන්න',
      'ta': 'வறட்சி காலத்தில் நீர்ப்பாசனம் செய்யுங்கள்',
    },
    text: {
      'en':
          'If a week shows low rainfall and high temperatures, increase irrigation — especially for young or flowering plants.',
      'si':
          'සතියක අඩු වර්ෂාපතනයක් හා ඉහළ උෂ්ණත්වයක් පෙන්වයි නම්, ජලනය වැඩි කරන්න — විශේෂයෙන් තරුණ හෝ මල් පිපෙන ශාකවලට.',
      'ta':
          'ஒரு வாரத்தில் குறைந்த மழையும் அதிக வெப்பநிலையும் இருந்தால், நீர்ப்பாசனத்தை அதிகரிக்கவும் — குறிப்பாக இளம் அல்லது பூக்கும் செடிகளுக்கு.',
    },
    icon: Icons.opacity,
    color: Color(0xFFE65100),
  ),
  _Tip(
    title: {
      'en': 'Time your harvest',
      'si': 'අස්වනු නෙලීම කාලෝචිතව කරන්න',
      'ta': 'அறுவடையை சரியான நேரத்தில் செய்யுங்கள்',
    },
    text: {
      'en':
          'Try to harvest during a dry, low-humidity window — wet harvests spoil faster and fetch lower prices.',
      'si':
          'වියළි, අඩු ආර්ද්‍රතා කාලයක අස්වනු නෙලීමට උත්සාහ කරන්න — තෙත් අස්වනු ඉක්මනින් හානි වී අඩු මිලක් ලබාදෙයි.',
      'ta':
          'உலர்ந்த, குறைந்த ஈரப்பத காலத்தில் அறுவடை செய்ய முயற்சிக்கவும் — ஈரமான அறுவடை விரைவில் கெட்டு குறைந்த விலை பெறும்.',
    },
    icon: Icons.agriculture,
    color: Color(0xFF2E7D32),
  ),
];

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
//  WeatherScreen
// ─────────────────────────────────────────────────────────────────────────────
class WeatherScreen extends StatefulWidget {
  final ValueChanged<int>? onNavigate;

  const WeatherScreen({super.key, this.onNavigate});

  @override
  State<WeatherScreen> createState() => _WeatherScreenState();
}

class _WeatherScreenState extends State<WeatherScreen> {
  // Nothing is pre-selected — the farmer must actively choose a District
  // and a Forecast Range themselves.
  String? _selectedDistrict;
  int? _weeksAhead;
  bool _isLoading = false;
  WeatherResponse? _result;
  String? _errorMessage;
  bool _tipsExpanded = false;

  // ── Searchable district dropdown text state ────────────────────────────
  // Same pattern as price_screen/yield_screen: the controller is owned HERE
  // (not left to RawAutocomplete) so _syncSearchField can reach into it on
  // focus change.
  final _districtSearchCtrl = TextEditingController();
  final _districtFocus = FocusNode();

  String get _langKey {
    final l = AppLangProvider.lang(context);
    if (l == AppLang.si) return 'si';
    if (l == AppLang.ta) return 'ta';
    return 'en';
  }

  String _t(_L m) => m[_langKey] ?? m['en']!;

  @override
  void initState() {
    super.initState();
    _districtFocus.addListener(
      () => _syncSearchField(
        _districtFocus,
        _districtSearchCtrl,
        _districtLabel(_langKey, _selectedDistrict),
      ),
    );
  }

  /// Keeps the searchable dropdown honest across focus changes. Ported
  /// verbatim from price_screen/yield_screen — see either for the full
  /// rationale.
  void _syncSearchField(
    FocusNode node,
    TextEditingController ctrl,
    String selected,
  ) {
    if (node.hasFocus) {
      if (ctrl.text.isNotEmpty) {
        ctrl.clear();
      } else {
        ctrl.value = const TextEditingValue(text: ' ');
        ctrl.clear();
      }
      return;
    }
    if (ctrl.text != selected) ctrl.text = selected;
  }

  @override
  void dispose() {
    _districtSearchCtrl.dispose();
    _districtFocus.dispose();
    super.dispose();
  }

  Future<void> _forecast() async {
    // District and Forecast Range are required — nothing is pre-selected,
    // so make sure the farmer actually picked both first.
    if (_selectedDistrict == null || _weeksAhead == null) {
      setState(() {
        _result = null;
        _errorMessage = _t({
          'en': 'Please select a District and Forecast Range first.',
          'si': 'කරුණාකර පළමුව දිස්ත්‍රික්කය සහ අනාවැකි කාලය තෝරන්න.',
          'ta':
              'முதலில் ஒரு மாவட்டத்தையும் முன்னறிவிப்பு காலத்தையும் தேர்ந்தெடுக்கவும்.',
        });
      });
      return;
    }
    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _result = null;
    });
    try {
      final service = ServiceFactory.getService();
      final now = DateTime.now();
      final startDate =
          '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
      final response = await service.forecastWeather(
        WeatherRequest(
          district: _selectedDistrict!,
          startDate: startDate,
          weeksAhead: _weeksAhead!,
        ),
      );
      setState(() => _result = response);
    } catch (e) {
      setState(
        () => _errorMessage = _t({
          'en':
              'Could not load the forecast. Please check your connection and try again.',
          'si':
              'අනාවැකිය පූරණය කළ නොහැක. ඔබේ සම්බන්ධතාව පරීක්ෂා කර නැවත උත්සාහ කරන්න.',
          'ta':
              'முன்னறிவிப்பை ஏற்ற முடியவில்லை. இணைப்பை சரிபார்த்து மீண்டும் முயற்சிக்கவும்.',
        }),
      );
    } finally {
      setState(() => _isLoading = false);
    }
  }

  /// Plain-language advice derived from the week's rainfall figure —
  /// (label, detail, color, icon). Interpretation logic and wording are
  /// UNCHANGED from v2 — only the emoji that used to prefix each label is
  /// gone; `adviceIcon` (already drawn alongside the label in _weekCard) is
  /// now the only glyph carrying that meaning.
  (String, String, Color, IconData) _adviceFor(WeatherForecastWeek w) {
    if (w.rainfallMm >= 60) {
      return (
        _t({
          'en': 'Heavy Rain Expected',
          'si': 'තද වර්ෂාව අපේක්ෂිතයි',
          'ta': 'கனமழை எதிர்பார்க்கப்படுகிறது',
        }),
        _t({
          'en': 'Check drainage and avoid spraying — rain will wash it off.',
          'si':
              'ජල බැස්සීම පරීක්ෂා කරන්න, ස්ප්‍රේ නොකරන්න — වැස්සෙන් සෝදා යයි.',
          'ta': 'வடிகாலை சரிபார்க்கவும், தெளிக்காதீர்கள் — மழை கழுவிவிடும்.',
        }),
        AppTheme.error,
        Icons.warning_rounded,
      );
    }
    if (w.rainfallMm <= 10 && w.tempMaxC >= 30) {
      return (
        _t({
          'en': 'Dry & Hot Week',
          'si': 'වියළි හා උණුසුම් සතියක්',
          'ta': 'உலர்ந்த வெப்பமான வாரம்',
        }),
        _t({
          'en':
              'Increase irrigation, especially for young or flowering plants.',
          'si': 'ජලනය වැඩි කරන්න, විශේෂයෙන් තරුණ හෝ මල් පිපෙන ශාකවලට.',
          'ta':
              'நீர்ப்பாசனத்தை அதிகரிக்கவும், குறிப்பாக இளம் அல்லது பூக்கும் செடிகளுக்கு.',
        }),
        const Color(0xFFE65100),
        Icons.local_fire_department_rounded,
      );
    }
    return (
      _t({
        'en': 'Good Growing Conditions',
        'si': 'හොඳ වගා තත්ත්ව',
        'ta': 'நல்ல வளர்ச்சி நிலைமைகள்',
      }),
      _t({
        'en': 'Balanced rain and temperature — normal field work is safe.',
        'si':
            'සමතුලිත වර්ෂාව හා උෂ්ණත්වය — සාමාන්‍ය ක්ෂේත්‍ර කටයුතු ආරක්ෂිතයි.',
        'ta':
            'சமச்சீரான மழையும் வெப்பநிலையும் — வழக்கமான வயல் வேலை பாதுகாப்பானது.',
      }),
      AppTheme.success,
      Icons.check_circle_rounded,
    );
  }

  /// The short condition key each week resolves to — same three-way split
  /// as [_adviceFor], expressed as a bounded token instead of display text.
  /// Feeds the weather-shaped `prediction_context` sent to chat (Step 8).
  String _conditionKey(WeatherForecastWeek w) {
    if (w.rainfallMm >= 60) return 'heavy_rain';
    if (w.rainfallMm <= 10 && w.tempMaxC >= 30) return 'dry_hot';
    return 'good';
  }

  // ── AI chat handoff ────────────────────────────────────────────────────────
  /// The forecast this conversation is about, sent invisibly on every
  /// request in the resulting conversation. Same single-slot handoff
  /// mechanism as yield/price — see [_askAi].
  ///
  /// forecastWeeks carries enough per-week detail (rainfall, min/max temp,
  /// humidity, and the same growing-conditions interpretation shown on the
  /// card) for the assistant to meaningfully explain or advise on the
  /// forecast, not just restate the district.
  PredictionContext _predictionContext() {
    final r = _result;
    return PredictionContext(
      district: _selectedDistrict,
      weeksAhead: _weeksAhead,
      forecastWeeks: r?.forecasts
          .map(
            (w) => PredictionWeatherWeek(
              weekNumber: w.weekNumber,
              date: w.date,
              rainfallMm: w.rainfallMm,
              tempMinC: w.tempMinC,
              tempMaxC: w.tempMaxC,
              humidityPct: w.humidityPct,
              condition: _conditionKey(w),
            ),
          )
          .toList(),
    );
  }

  /// Publish the forecast to the chat screen and switch to the AI Chat tab.
  /// Identical mechanism to yield/price_screen — see prediction_handoff.dart.
  void _askAi({String? question}) {
    if (_result == null) return;
    predictionHandoff.value = PredictionHandoff(
      _predictionContext(),
      question: question,
    );
    widget.onNavigate?.call(6); // AI Chat tab
  }

  /// Shared styling for every action in the "Ask AI about this" block —
  /// primaryDark, not the weather accent: these are primary actions, and
  /// the accent rules keep those consistent app-wide (same as price_screen's
  /// _askAiButtonStyle).
  ButtonStyle get _askAiButtonStyle => ElevatedButton.styleFrom(
    backgroundColor: AppTheme.login.primaryDark,
    foregroundColor: Colors.white,
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    elevation: 2,
  );

  /// The four weather questions live HERE, on the result, not on an
  /// otherwise blank chat screen — same placement as price_screen's
  /// _askAiBlock.
  Widget _askAiBlock() => Column(
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
          for (final q in kWeatherStarters)
            ElevatedButton(
              // Only the short visible text is sent as the message; the
              // forecast rides along in prediction_context.
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
            Expanded(child: _buildDetailsTab(w)),
          ],
        );
      },
    );
  }

  // Weather is nav index 3. See app_top_bar.dart for why this is one shared
  // widget now instead of six independent copies of this same bar.
  Widget _buildTopBar(BuildContext context) => AppTopBar(
    activeIndex: 3,
    activeBg: AppTheme.accents.weather.fill.withValues(alpha: 0.16),
    activeColor: AppTheme.accents.weather.ink,
    onNavigate: widget.onNavigate,
  );

  // 1024 is the two-column threshold — same as price_screen/yield_screen:
  // below it the page stacks into ONE column (header -> inputs -> Get
  // Forecast -> result) rather than squeezing a results panel alongside
  // the form.
  Widget _buildDetailsTab(double width) {
    if (width >= 1024) return _buildWebDetails(width);
    if (width >= 600) return _buildTabletDetails(width);
    return _buildMobileDetails(width);
  }

  Widget _buildMobileDetails(double width) {
    final bool isSmall = width < 340;
    final double hPad = isSmall ? 12 : 14;
    return Stack(
      children: [
        SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(hPad, 14, hPad, 180),
          child: _formColumn(),
        ),
        _stickyForecastButton(),
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
        _stickyForecastButton(),
      ],
    );
  }

  // Web (>=1024dp): inputs on the left, forecast result on the right — same
  // fraction/clamp as price_screen's _buildWebDetails.
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
              _stickyForecastButton(),
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

  // ── Form column — Header, Location, Forecast Range, Tips. Below 1024dp
  //    the result/empty state is appended here too, after the button. ──────
  Widget _formColumn({bool webLeft = false}) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _pageHeader(),
      const SizedBox(height: 16),
      _sectionTitle(
        _t({'en': 'Location', 'si': 'ස්ථානය', 'ta': 'இடம்'}),
        Icons.location_on,
      ),
      const SizedBox(height: 10),
      _locationCard(),
      const SizedBox(height: 20),
      _sectionTitle(
        _t({
          'en': 'Forecast Range',
          'si': 'අනාවැකි කාලය',
          'ta': 'முன்னறிவிப்பு காலம்',
        }),
        Icons.calendar_month,
      ),
      const SizedBox(height: 10),
      _weeksAheadCard(),
      const SizedBox(height: 20),
      _sectionTitle(
        _t({
          'en': 'Weather & Farming Tips',
          'si': 'කාලගුණ හා ගොවිතැන් ඉඟි',
          'ta': 'வானிலை & விவசாய குறிப்புகள்',
        }),
        Icons.tips_and_updates,
      ),
      const SizedBox(height: 10),
      _tipsCard(),
      // Single-column (<1024dp): the result follows the inputs. The Get
      // Forecast button itself stays pinned in the sticky bar over this
      // scroll view.
      if (!webLeft) ...[
        const SizedBox(height: 16),
        if (_isLoading) _resultSkeleton(),
        if (_errorMessage != null) _errorCard(),
        if (_result != null) ..._resultBody(),
        if (_result == null && _errorMessage == null && !_isLoading)
          _emptyResultPlaceholder(),
      ],
    ],
  );

  Widget _rightPanel() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      if (_isLoading) ...[_resultSkeleton(), const SizedBox(height: 14)],
      if (_errorMessage != null) ...[_errorCard(), const SizedBox(height: 14)],
      if (_result != null) ..._resultBody(),
      if (_result == null && _errorMessage == null && !_isLoading)
        _emptyResultPlaceholder(),
    ],
  );

  // Header gradient's lighter stop — header-local, not part of
  // AppFeatureAccents.weather, same precedent as price_screen's own
  // _headerGradientLight. +0.15 HLS lightness from the dark anchor
  // (accents.weather.fill), hue/saturation preserved — identical formula to
  // price's, so the two headers carry the same gradient "intensity".
  //
  // KNOWN, ACCEPTED CONTRAST FAILURE, same shape as price's: white text on
  // this header does not clear AA at either end — see
  // AppFeatureAccents.weather's doc comment for the numbers.
  static const Color _headerGradientLight = Color(0xFF7DA4C1);

  // ── Page header ────────────────────────────────────────────────────────────
  // Same structure as price_screen's _pageHeader: gradient (dark top-left ->
  // light bottom-right), icon in a glass badge on the left, title/subtitle,
  // "Week N" glass pill on the right.
  Widget _pageHeader() => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      gradient: LinearGradient(
        colors: [AppTheme.accents.weather.fill, _headerGradientLight],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
      borderRadius: BorderRadius.circular(14),
      boxShadow: [
        BoxShadow(
          color: AppTheme.accents.weather.fill.withValues(alpha: 0.3),
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
            _navSvg(3, AppTheme.accents.weather.onFill),
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
                  'en': 'Weather Forecast',
                  'si': 'කාලගුණ අනාවැකිය',
                  'ta': 'வானிலை முன்னறிவிப்பு',
                }),
                style: TextStyle(
                  color: AppTheme.accents.weather.onFill,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              AnimatedLangText(
                _t({
                  'en': 'AI-powered weekly forecast',
                  'si': 'AI-ශක්තිමත් සතිපතා අනාවැකිය',
                  'ta': 'AI-சார்ந்த வாராந்திர முன்னறிவிப்பு',
                }),
                style: TextStyle(
                  color: AppTheme.accents.weather.onFill,
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
            'Week ${_weekOfYear()}',
            style: TextStyle(
              color: AppTheme.accents.weather.onFill,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    ),
  );

  /// Glass panel — icon badge and "Week N" pill. Same treatment as
  /// price_screen's `_glassBadge`: translucent black tint + a faint white
  /// edge, no blur (see price_screen's comment for why). Unlike price's,
  /// the dark end of THIS gradient clears AA once tinted — see
  /// AppFeatureAccents.weather's doc comment / accent_contrast_test.dart.
  Widget _glassBadge({
    required double borderRadius,
    required EdgeInsets padding,
    required Widget child,
  }) => Container(
    padding: padding,
    decoration: BoxDecoration(
      color: Colors.black.withValues(alpha: 0.20),
      borderRadius: BorderRadius.circular(borderRadius),
      border: Border.all(color: Colors.white.withValues(alpha: 0.25), width: 1),
    ),
    child: child,
  );

  /// Inline validation tick for the district field — verbatim copy of
  /// price_screen's `_fieldCheck`, so a farmer moving between forms sees one
  /// signal, not two dialects of one.
  Widget _fieldCheck(bool done) => Padding(
    padding: const EdgeInsets.only(right: 2),
    child: Icon(
      done ? Icons.check_circle : Icons.radio_button_unchecked,
      size: 19,
      color: done ? AppTheme.success : AppTheme.login.borderSubtle,
    ),
  );

  // ── Location card — a single searchable district dropdown ─────────────────
  Widget _locationCard() => _card(
    child: _searchableDropdown(
      label: _t({
        'en': 'Select District',
        'si': 'දිස්ත්‍රික්කය තෝරන්න',
        'ta': 'மாவட்டத்தை தேர்ந்தெடுக்கவும்',
      }),
      value: _selectedDistrict,
      items: _districtKeys,
      icon: Icons.location_on,
      itemLabel: (d) => _districtLabel(_langKey, d),
      controller: _districtSearchCtrl,
      focusNode: _districtFocus,
      onChanged: (val) => setState(() {
        _selectedDistrict = val;
        _result = null;
      }),
    ),
  );

  /// Type-to-filter dropdown — price_screen's `_searchableDropdown`, ported
  /// with only the accent tokens changed (weather instead of price). Filter
  /// matches either the English key or the translated label, same reasoning
  /// as price's version.
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
                    ? AppTheme.accents.weather.ink
                    : AppTheme.login.textSecondary,
                size: 20,
              ),
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
                          ? AppTheme.accents.weather.ink
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
                              ? AppTheme.accents.weather.fill.withValues(
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
                                        ? AppTheme.accents.weather.ink
                                        : AppTheme.login.textPrimary,
                                  ),
                                ),
                              ),
                              if (isSelected)
                                Icon(
                                  Icons.check,
                                  size: 16,
                                  color: AppTheme.accents.weather.ink,
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

  Widget _weeksAheadCard() => _card(
    child: Row(
      children: List.generate(_weekOptions.length, (i) {
        final n = i + 1;
        final active = _weeksAhead == n;
        return Expanded(
          child: GestureDetector(
            onTap: () => setState(() {
              _weeksAhead = n;
              _result = null;
            }),
            child: Container(
              margin: EdgeInsets.only(right: n == _weekOptions.length ? 0 : 8),
              padding: const EdgeInsets.symmetric(vertical: 12),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: active
                    ? AppTheme.accents.weather.fill
                    : AppTheme.accents.weather.fill.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: active
                      ? AppTheme.accents.weather.fill
                      : AppTheme.accents.weather.fill.withValues(alpha: 0.25),
                  width: active ? 2 : 1.2,
                ),
              ),
              child: Text(
                _t(_weekOptions[i]),
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: active ? Colors.white : AppTheme.accents.weather.ink,
                ),
              ),
            ),
          ),
        );
      }),
    ),
  );

  Widget _tipsCard() => Container(
    decoration: BoxDecoration(
      border: Border.all(
        color: AppTheme.accents.weather.fill.withValues(alpha: 0.3),
      ),
      borderRadius: BorderRadius.circular(12),
      color: AppTheme.accents.weather.fill.withValues(alpha: 0.05),
    ),
    child: Column(
      children: [
        InkWell(
          onTap: () => setState(() => _tipsExpanded = !_tipsExpanded),
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                Icon(
                  Icons.tips_and_updates,
                  size: 18,
                  color: AppTheme.accents.weather.ink,
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: Text(
                    _t({
                      'en': 'How to use this forecast on your farm',
                      'si': 'මෙම අනාවැකිය ගොවිපොළේදී භාවිත කරන ආකාරය',
                      'ta':
                          'இந்த முன்னறிவிப்பை உங்கள் பண்ணையில் பயன்படுத்துவது',
                    }),
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.accents.weather.ink,
                    ),
                  ),
                ),
                Icon(
                  _tipsExpanded ? Icons.expand_less : Icons.expand_more,
                  size: 18,
                  color: AppTheme.accents.weather.ink,
                ),
              ],
            ),
          ),
        ),
        if (_tipsExpanded)
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
            child: Column(
              children: _kWeatherTips
                  .map(
                    (tip) => Container(
                      margin: const EdgeInsets.only(top: 8),
                      padding: const EdgeInsets.all(11),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: tip.color.withValues(alpha: 0.2),
                        ),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            width: 30,
                            height: 30,
                            decoration: BoxDecoration(
                              color: tip.color.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Icon(tip.icon, size: 15, color: tip.color),
                          ),
                          const SizedBox(width: 9),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _t(tip.title),
                                  style: TextStyle(
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w800,
                                    color: tip.color,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  _t(tip.text),
                                  style: const TextStyle(
                                    fontSize: 11,
                                    color: AppTheme.textSecondary,
                                    height: 1.4,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                  .toList(),
            ),
          ),
      ],
    ),
  );

  // "Get Forecast" — AppTheme.accents.weather.fill, by explicit request.
  //
  // This is the SECOND explicit, requested exception to "primary actions
  // stay on primaryDark" — the first is price_screen's "Predict Price"
  // button (see AppFeatureAccents' class doc comment). Every other primary
  // action on this screen, and weather's own "Ask AI about this" actions,
  // still use primaryDark.
  //
  // KNOWN, ACCEPTED CONTRAST FAILURE, inherited from accents.weather.fill:
  // white on #4E7FA3 is 4.30:1 — under the 4.5:1 AA text floor, though it
  // clears the 3:1 non-text floor (see AppFeatureAccents.weather's doc
  // comment / accent_contrast_test.dart for the full numbers).
  Widget _stickyForecastButton() => Positioned(
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
            onPressed: _isLoading ? null : _forecast,
            icon: _isLoading
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.wb_sunny),
            label: Text(
              _isLoading
                  ? _t({
                      'en': 'Getting forecast...',
                      'si': 'අනාවැකිය ලබාගනිමින්...',
                      'ta': 'முன்னறிவிப்பு பெறப்படுகிறது...',
                    })
                  : _t({
                      'en': 'Get Forecast',
                      'si': 'අනාවැකිය ලබාගන්න',
                      'ta': 'முன்னறிவிப்பு பெறவும்',
                    }),
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.accents.weather.fill,
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

  // ── Result — "Forecast for X" heading, the stacked weekly cards (all
  //    weeks expanded, unchanged), then "Ask AI about this". ────────────────
  List<Widget> _resultBody() => [
    _resultSection(),
    const SizedBox(height: 16),
    _askAiBlock(),
  ];

  Widget _resultSection() {
    final result = _result!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                _t({
                  'en':
                      'Forecast for ${_districtLabel('en', _selectedDistrict)}',
                  'si':
                      '${_districtLabel('si', _selectedDistrict)} සඳහා අනාවැකිය',
                  'ta':
                      '${_districtLabel('ta', _selectedDistrict)}-க்கான முன்னறிவிப்பு',
                }),
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: AppTheme.accents.weather.ink,
                ),
              ),
            ),
            if (result.isMock)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.orange.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.orange),
                ),
                child: Text(
                  _t({'en': 'MOCK', 'si': 'ආදර්ශ', 'ta': 'மாதிரி'}),
                  style: const TextStyle(color: Colors.orange, fontSize: 10),
                ),
              ),
          ],
        ),
        const SizedBox(height: 12),
        if (result.isLowConfidence) ...[
          _lowConfidenceNotice(),
          const SizedBox(height: 12),
        ],
        ...result.forecasts.map((f) => _weekCard(f)),
      ],
    );
  }

  /// Shown when the backend labels this district's forecast low-confidence.
  ///
  /// Our weather model was trained on data that records the hill country as
  /// lowland-hot — Nuwara Eliya at a 34 C weekly maximum against a real ~19 C
  /// — which collapses its predicted rainfall for those districts. The
  /// forecast is still shown because nothing else looks four weeks ahead, but
  /// it is not presented as trustworthy.
  ///
  /// Same principle as the price page's real/synthetic average badge:
  /// provenance is stated, not hidden, and never dressed up as certainty.
  Widget _lowConfidenceNotice() => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    decoration: BoxDecoration(
      color: AppTheme.warning.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: AppTheme.warning.withValues(alpha: 0.3)),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.info_rounded, size: 17, color: AppTheme.warning),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            _t({
              'en':
                  'Limited accuracy for this district. Our forecast model has '
                  'less reliable data for the hill country, so rainfall here '
                  'may be under-estimated. Treat these figures as a rough '
                  'guide.',
              'si':
                  'මෙම දිස්ත්‍රික්කය සඳහා නිරවද්‍යතාව සීමිතයි. කඳුකර ප්‍රදේශ සඳහා '
                  'අපගේ ආකෘතියේ දත්ත එතරම් විශ්වාස නොවන බැවින්, මෙහි වර්ෂාපතනය '
                  'අඩුවෙන් ඇස්තමේන්තු විය හැක. මෙම අගයන් දළ මාර්ගෝපදේශයක් ලෙස ගන්න.',
              'ta':
                  'இந்த மாவட்டத்திற்கு துல்லியம் குறைவு. மலைநாட்டுப் பகுதிகளுக்கு '
                  'எங்கள் மாதிரியின் தரவு நம்பகத்தன்மை குறைவு, எனவே இங்கு மழைவீழ்ச்சி '
                  'குறைவாக மதிப்பிடப்படலாம். இந்த எண்களை தோராயமான வழிகாட்டியாகக் கொள்ளுங்கள்.',
            }),
            style: TextStyle(
              fontSize: 12,
              height: 1.4,
              fontWeight: FontWeight.w500,
              color: AppTheme.warning,
            ),
          ),
        ),
      ],
    ),
  );

  Widget _weekCard(WeatherForecastWeek week) {
    final (adviceLabel, adviceDetail, adviceColor, adviceIcon) = _adviceFor(
      week,
    );
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: AppTheme.surfaceCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE0EBE0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 0),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: AppTheme.accents.weather.fill,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    _t({
                      'en': 'Week ${week.weekNumber}',
                      'si': 'සතිය ${week.weekNumber}',
                      'ta': 'வாரம் ${week.weekNumber}',
                    }),
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  week.date,
                  style: const TextStyle(
                    color: AppTheme.textMuted,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Interpretation banner — Step 9: the emoji that used to
                // prefix `adviceLabel` is gone; this Icon is the only glyph
                // now. Interpretation logic/wording is otherwise unchanged.
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: adviceColor.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: adviceColor.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(adviceIcon, size: 18, color: adviceColor),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              adviceLabel,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w800,
                                color: adviceColor,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              adviceDetail,
                              style: TextStyle(
                                fontSize: 11.5,
                                color: adviceColor,
                                height: 1.4,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    _weatherStat(
                      '🌧',
                      _t({'en': 'Rain', 'si': 'වර්ෂාව', 'ta': 'மழை'}),
                      '${week.rainfallMm.toStringAsFixed(0)} mm',
                      AppTheme.accents.weather.ink,
                    ),
                    _weatherStat(
                      '🌡',
                      _t({'en': 'Min Temp', 'si': 'අවම', 'ta': 'குறை வெப்பம்'}),
                      '${week.tempMinC.toStringAsFixed(0)}°C',
                      const Color(0xFF4FC3F7),
                    ),
                    _weatherStat(
                      '☀️',
                      _t({
                        'en': 'Max Temp',
                        'si': 'උපරිම',
                        'ta': 'அதிக வெப்பம்',
                      }),
                      '${week.tempMaxC.toStringAsFixed(0)}°C',
                      const Color(0xFFE65100),
                    ),
                    _weatherStat(
                      '💧',
                      _t({
                        'en': 'Humidity',
                        'si': 'ආර්ද්‍රතාව',
                        'ta': 'ஈரப்பதம்',
                      }),
                      '${week.humidityPct.toStringAsFixed(0)}%',
                      const Color(0xFF00695C),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // Per-stat emoji (🌧🌡☀️💧) are UNCHANGED — Step 9 scopes the icon
  // replacement to the "Good Growing Conditions"-style interpretation
  // banner only, which already carries its own Icon widget (adviceIcon).
  Widget _weatherStat(String emoji, String label, String value, Color color) {
    return Expanded(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 3),
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.07),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withValues(alpha: 0.2)),
        ),
        child: Column(
          children: [
            Text(emoji, style: const TextStyle(fontSize: 16)),
            const SizedBox(height: 4),
            Text(
              value,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.bold,
                color: color,
              ),
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 1),
            Text(
              label,
              style: TextStyle(
                fontSize: 8.5,
                color: color.withValues(alpha: 0.8),
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _emptyResultPlaceholder() => Container(
    padding: const EdgeInsets.all(24),
    decoration: BoxDecoration(
      color: AppTheme.accents.weather.fill.withValues(alpha: 0.06),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(
        color: AppTheme.accents.weather.fill.withValues(alpha: 0.3),
      ),
    ),
    child: Column(
      children: [
        SvgPicture.string(
          _navSvg(3, AppTheme.accents.weather.fill.withValues(alpha: 0.55)),
          width: 48,
          height: 48,
        ),
        const SizedBox(height: 12),
        Text(
          _t({
            'en': 'Your weather forecast will appear here',
            'si': 'ඔබේ කාලගුණ අනාවැකිය මෙතැන දිස්වේ',
            'ta': 'உங்கள் வானிலை முன்னறிவிப்பு இங்கே தோன்றும்',
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
            'en': 'Choose a district and weeks ahead, then tap Get Forecast',
            'si': 'දිස්ත්‍රික්කය හා සති ගණන තෝරා Get Forecast ඔබන්න',
            'ta': 'மாவட்டம் மற்றும் வாரங்களைத் தேர்ந்தெடுத்து கணிக்கவும்',
          }),
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 11, color: AppTheme.textMuted),
        ),
      ],
    ),
  );

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

  Widget _card({required Widget child}) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: AppTheme.surfaceCard,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: const Color(0xFFE0EBE0)),
    ),
    child: child,
  );

  /// Shown in place of the empty placeholder while a forecast is in
  /// flight — the result card is text-heavy, so Typewriter fits.
  Widget _resultSkeleton() => _card(
    child: const TypewriterSkeleton(
      lineWidthFractions: [0.5, 1.0, 0.9, 0.7, 0.85, 0.4],
      lineHeight: 11,
    ),
  );

  Widget _sectionTitle(String title, IconData icon) => Row(
    children: [
      Icon(icon, size: 16, color: AppTheme.accents.weather.ink),
      const SizedBox(width: 6),
      AnimatedLangText(
        title,
        style: TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w700,
          color: AppTheme.accents.weather.ink,
        ),
      ),
    ],
  );
}
