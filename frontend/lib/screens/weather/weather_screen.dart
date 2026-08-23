// lib/screens/weather/weather_screen.dart
// ─────────────────────────────────────────────────────────────────────────────
//  CropSphere — Weather Forecast (v2)
//
//  CHANGES FROM v1
//  ✅ Same shell as Dashboard/Yield/Price: top nav bar (active tab bold +
//     highlighted), language pill, responsive mobile/tablet/web layout,
//     sticky "Get Forecast" bar on mobile/tablet.
//  ✅ Fully trilingual (en/si/ta) throughout — district names, week labels,
//     stat labels, advice text.
//  ✅ Quick-select district chips (tap-and-go, like Yield/Price crop chips).
//  ✅ "Weeks ahead" chips use farmer-friendly labels ("1 week", "2 weeks"...)
//     instead of bare numbers.
//  ✅ Each week's forecast gets a plain-language advice banner (heavy rain /
//     dry spell / good conditions) derived from the rainfall figure —
//     not just raw numbers.
//  ✅ Collapsible "Weather & Farming Tips" card, general seasonal advice.
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../../app_lang.dart';
import '../../models/api_models.dart';
import '../../services/service_factory.dart';
import '../../widgets/animated_lang_text.dart';
import '../../widgets/app_theme.dart';
import '../../widgets/brand_wordmark.dart';
import '../../widgets/top_nav_items.dart';
import '../../widgets/top_nav_metrics.dart';
import '../../widgets/language_control.dart';
import '../../widgets/profile_avatar_button.dart';
import '../../widgets/skeleton_loading.dart';
import '../../widgets/theme_toggle_button.dart';

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
//  General weather & farming tips — trilingual
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

// ─────────────────────────────────────────────────────────────────────────────
//  SVG icons (matching Dashboard / Yield / Price)
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

  String get _langKey {
    final l = AppLangProvider.lang(context);
    if (l == AppLang.si) return 'si';
    if (l == AppLang.ta) return 'ta';
    return 'en';
  }

  String _t(_L m) => m[_langKey] ?? m['en']!;

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
  /// (label, detail, color, icon). No raw jargon, just what to do.
  (String, String, Color, IconData) _adviceFor(WeatherForecastWeek w) {
    if (w.rainfallMm >= 60) {
      return (
        _t({
          'en': '⚠️ Heavy Rain Expected',
          'si': '⚠️ තද වර්ෂාව අපේක්ෂිතයි',
          'ta': '⚠️ கனமழை எதிர்பார்க்கப்படுகிறது',
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
          'en': '☀️ Dry & Hot Week',
          'si': '☀️ වියළි හා උණුසුම් සතියක්',
          'ta': '☀️ உலர்ந்த வெப்பமான வாரம்',
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
        'en': '✅ Good Growing Conditions',
        'si': '✅ හොඳ වගා තත්ත්ව',
        'ta': '✅ நல்ல வளர்ச்சி நிலைமைகள்',
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

  Widget _buildTopBar(BuildContext context) {
    final m = TopNavMetrics.of(context);
    final lang = AppLangProvider.lang(context);
    final List<String> navLabels = lang == AppLang.si
        ? ['මුල', 'අස්වැන්න', 'මිල', 'කාලගුණ', 'භෝග', 'ඉල්ලුම', 'AI']
        : lang == AppLang.ta
        ? ['முகப்பு', 'விளைச்சல்', 'விலை', 'வானிலை', 'பயிர்', 'தேவை', 'AI']
        : ['Home', 'Yield', 'Price', 'Weather', 'Crop', 'Demand', 'Chat'];

    const activeBg = Color(0xFFE3F2FD);
    const activeColor = Color(0xFF1565C0);

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
      child: LayoutBuilder(
        builder: (ctx, bc) {
          // Below 600px (mobile) the text nav labels are dropped entirely —
          // just logo + language pill remain. Tablet/web (>=600px) keep the
          // full nav bar. Same pattern as other screens.
          final isMobile = bc.maxWidth < 600;
          return Row(
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
                    _cropSphereSvg,
                    width: m.logoGlyphSize,
                    height: m.logoGlyphSize,
                  ),
                ),
              ),
              const BrandWordmark(),
              if (!isMobile)
                Expanded(
                  child: Center(
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: TopNavItems(
                        labels: navLabels,
                        activeIndex: 3,
                        activeBg: activeBg,
                        activeColor: activeColor,
                        onNavigate: widget.onNavigate,
                        metrics: m,
                      ),
                    ),
                  ),
                ),
              if (isMobile) const Spacer(),
              const SizedBox(width: 8),
              LanguageControl(
                labelSize: m.langLabelSize,
                height: m.controlHeight,
              ),
              SizedBox(width: m.clusterGap),
              ThemeToggleButton(
                size: m.toggleIconSize,
                height: m.controlHeight,
              ),
              SizedBox(width: m.clusterGap),
              ProfileAvatarButton(diameter: m.avatarSize),
            ],
          );
        },
      ),
    );
  }

  // ── Mobile / tablet: unchanged single-column stack with a sticky
  //    "Get Forecast" bar. Web: compact 2-column grid so every input is
  //    visible without scrolling — see _formColumn. ─────────────────────────
  Widget _buildMobileLayout() => Stack(
    children: [
      SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 100),
        child: _formColumn(isWeb: false),
      ),
      _stickyForecastButton(),
    ],
  );

  Widget _buildTabletLayout() => Stack(
    children: [
      LayoutBuilder(
        builder: (ctx, bc) {
          final hPad = ((bc.maxWidth - 700) / 2).clamp(0.0, 200.0);
          return SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(hPad + 16, 14, hPad + 16, 100),
            child: _formColumn(isWeb: false),
          );
        },
      ),
      _stickyForecastButton(),
    ],
  );

  // Web: no more splitting the screen into a form panel + a separate
  // results panel (that produced a mostly-empty right side before the
  // farmer had a result). Instead, a compact 2-column grid holds every
  // input, with the button/result shown full-width beneath it. No
  // IntrinsicHeight anywhere, so it stays compatible with any scrollable
  // content inside either column.
  Widget _buildWebLayout() => LayoutBuilder(
    builder: (ctx, bc) {
      final maxW = 1000.0;
      final hPad = ((bc.maxWidth - maxW) / 2).clamp(14.0, 120.0);
      return SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(hPad, 14, hPad, 24),
        child: _formColumn(isWeb: true),
      );
    },
  );

  Widget _formColumn({required bool isWeb}) {
    final locationBlock = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _districtQuickChips(),
        const SizedBox(height: 16),
        _sectionTitle(
          _t({'en': 'Location', 'si': 'ස්ථානය', 'ta': 'இடம்'}),
          Icons.location_on,
        ),
        const SizedBox(height: 10),
        _districtDropdownCard(),
      ],
    );

    final rangeBlock = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
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
      ],
    );

    final tipsBlock = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
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
      ],
    );

    // ── Mobile / tablet: unchanged single-column stack ─────────────────────
    if (!isWeb) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _pageHeader(),
          const SizedBox(height: 16),
          locationBlock,
          const SizedBox(height: 20),
          rangeBlock,
          const SizedBox(height: 20),
          tipsBlock,
          const SizedBox(height: 16),
          if (_isLoading) _resultSkeleton(),
          if (_errorMessage != null) _errorCard(),
          if (_result != null) _resultSection(),
          if (_result == null && _errorMessage == null && !_isLoading)
            _emptyResultPlaceholder(),
        ],
      );
    }

    // ── Web: compact 2-column grid — Location on the left, Forecast Range
    //    + Tips on the right, result/button full-width beneath. ────────────
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _pageHeader(),
        const SizedBox(height: 14),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(flex: 5, child: locationBlock),
            const SizedBox(width: 16),
            Expanded(
              flex: 4,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [rangeBlock, const SizedBox(height: 14), tipsBlock],
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
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
              backgroundColor: const Color(0xFF1565C0),
              foregroundColor: Colors.white,
              minimumSize: const Size.fromHeight(52),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ),
        const SizedBox(height: 16),
        if (_isLoading) _resultSkeleton(),
        if (_errorMessage != null) _errorCard(),
        if (_result != null) _resultSection(),
        if (_result == null && _errorMessage == null && !_isLoading)
          _emptyResultPlaceholder(),
      ],
    );
  }

  Widget _pageHeader() => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      gradient: const LinearGradient(
        colors: [Color(0xFF1565C0), Color(0xFF1E88E5)],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
      borderRadius: BorderRadius.circular(14),
      boxShadow: [
        BoxShadow(
          color: const Color(0xFF1565C0).withValues(alpha: 0.3),
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
            _navSvg(3, Colors.white),
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
                style: const TextStyle(
                  color: Colors.white,
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
                  color: Colors.white.withValues(alpha: 0.75),
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );

  Widget _districtQuickChips() => Column(
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
        children: _districtKeys.map((d) {
          final active = _selectedDistrict == d;
          return GestureDetector(
            onTap: () => setState(() {
              _selectedDistrict = d;
              _result = null;
            }),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              decoration: BoxDecoration(
                color: active ? const Color(0xFF1565C0) : Colors.white,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: active
                      ? const Color(0xFF1565C0)
                      : const Color(0xFFBBDEFB),
                  width: active ? 2 : 1.5,
                ),
                boxShadow: active
                    ? [
                        BoxShadow(
                          color: const Color(0xFF1565C0).withValues(alpha: 0.2),
                          blurRadius: 6,
                          offset: const Offset(0, 2),
                        ),
                      ]
                    : [],
              ),
              child: Text(
                '📍 ${_districtLabel(_langKey, d)}',
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

  Widget _districtDropdownCard() => _card(
    child: DropdownButtonFormField<String>(
      initialValue: _selectedDistrict,
      hint: Text(
        _t({
          'en': 'Select District',
          'si': 'දිස්ත්‍රික්කය තෝරන්න',
          'ta': 'மாவட்டத்தை தேர்ந்தெடுக்கவும்',
        }),
      ),
      decoration: InputDecoration(
        labelText: _t({
          'en': 'Select District',
          'si': 'දිස්ත්‍රික්කය තෝරන්න',
          'ta': 'மாவட்டத்தை தேர்ந்தெடுக்கவும்',
        }),
        prefixIcon: const Icon(
          Icons.location_on,
          color: Color(0xFF1565C0),
          size: 20,
        ),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 10,
        ),
      ),
      items: _districtKeys
          .map(
            (d) => DropdownMenuItem(
              value: d,
              child: Text(_districtLabel(_langKey, d)),
            ),
          )
          .toList(),
      onChanged: (v) => setState(() {
        _selectedDistrict = v;
        _result = null;
      }),
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
                    ? const Color(0xFF1565C0)
                    : const Color(0xFF1565C0).withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: active
                      ? const Color(0xFF1565C0)
                      : const Color(0xFF1565C0).withValues(alpha: 0.25),
                  width: active ? 2 : 1.2,
                ),
              ),
              child: Text(
                _t(_weekOptions[i]),
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: active ? Colors.white : const Color(0xFF1565C0),
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
      border: Border.all(color: const Color(0xFFBBDEFB)),
      borderRadius: BorderRadius.circular(12),
      color: const Color(0xFFE3F2FD).withValues(alpha: 0.4),
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
                const Icon(
                  Icons.tips_and_updates,
                  size: 18,
                  color: Color(0xFF1565C0),
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
                    style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF1565C0),
                    ),
                  ),
                ),
                Icon(
                  _tipsExpanded ? Icons.expand_less : Icons.expand_more,
                  size: 18,
                  color: const Color(0xFF1565C0),
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
              backgroundColor: const Color(0xFF1565C0),
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
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF0D47A1),
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
        ...result.forecasts.map((f) => _weekCard(f)),
      ],
    );
  }

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
                    color: const Color(0xFF1565C0),
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
                      const Color(0xFF1565C0),
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
      color: const Color(0xFFE3F2FD).withValues(alpha: 0.5),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: const Color(0xFFBBDEFB)),
    ),
    child: Column(
      children: [
        SvgPicture.string(
          _navSvg(3, const Color(0xFF90A4C4)),
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
  /// flight — the result card is text-heavy (headline conditions +
  /// narrative breakdown), so Typewriter fits: bars reveal left-to-right
  /// like the eventual text being "written in".
  Widget _resultSkeleton() => _card(
    child: const TypewriterSkeleton(
      lineWidthFractions: [0.5, 1.0, 0.9, 0.7, 0.85, 0.4],
      lineHeight: 11,
    ),
  );

  Widget _sectionTitle(String title, IconData icon) => Row(
    children: [
      Icon(icon, size: 16, color: const Color(0xFF1565C0)),
      const SizedBox(width: 6),
      AnimatedLangText(
        title,
        style: const TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w700,
          color: Color(0xFF0D47A1),
        ),
      ),
    ],
  );
}
