// lib/screens/demand/demand_screen.dart
// ─────────────────────────────────────────────────────────────────────────────
//  CropSphere — Demand Forecast (v2, farmer-first)
//
//  UPGRADES FROM v1
//  ✅ Full trilingual support (English / Sinhala / Tamil) — including crop
//     names themselves, not just surrounding labels
//  ✅ Shared top nav bar (matches other screens) — "Demand" bolded (index 5)
//  ✅ Removed raw ML-feature sliders (demand lag 1/2/4, consumer preference
//     index, search trend index) as *required* inputs — no farmer can know
//     these numbers. They now sit behind an "I have real market data"
//     advanced toggle with sensible per-crop defaults, same pattern as the
//     Soil card on the Recommend screen.
//  ✅ Fixed weekOfYear bug (was hardcoded to 10 — now computed from today)
//  ✅ Quick crop + season chips (emoji-based, matches Dashboard/Recommend)
//  ✅ Result now includes a plain-language verdict ("good time to sell soon"
//     / "prices may soften" / "steady") instead of a bare index number
//  ✅ Cross-navigation: "Check Price Forecast" + "Ask AI" buttons on the result
//  ✅ Removed the screen's own Scaffold — hosted inside the app shell like
//     the other screens
//  ✅ Colour scheme switched from violet to indigo to match how "Demand" is
//     already colour-coded on the Dashboard's action tile
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../../app_lang.dart';
import '../../models/api_models.dart';
import '../../services/service_factory.dart';
import '../../widgets/app_theme.dart';

typedef _L = Map<String, String>;

int _weekOfYear() {
  final now = DateTime.now();
  final soy = DateTime(now.year, 1, 1);
  return (((now.difference(soy).inDays + soy.weekday - 1) / 7).ceil()).clamp(
    1,
    52,
  );
}

// ─────────────────────────────────────────────────────────────────────────────
//  Crop data — trilingual names + emoji + sensible per-crop defaults for the
//  values a farmer would otherwise have to guess (retail price, demand
//  baseline). These are typical placeholders the farmer can override.
// ─────────────────────────────────────────────────────────────────────────────
class _CropInfo {
  final _L name;
  final String emoji;
  final double typicalPriceLkr;
  final double demandBaseline;
  const _CropInfo({
    required this.name,
    required this.emoji,
    required this.typicalPriceLkr,
    required this.demandBaseline,
  });
}

const Map<String, _CropInfo> _crops = {
  'Carrot': _CropInfo(
    name: {'en': 'Carrot', 'si': 'කැරට්', 'ta': 'கேரட்'},
    emoji: '🥕',
    typicalPriceLkr: 180,
    demandBaseline: 78,
  ),
  'Maize': _CropInfo(
    name: {'en': 'Maize', 'si': 'ඉරිඟු', 'ta': 'மக்காச்சோளம்'},
    emoji: '🌽',
    typicalPriceLkr: 90,
    demandBaseline: 70,
  ),
  'Green gram': _CropInfo(
    name: {'en': 'Green gram', 'si': 'මුං ඇට', 'ta': 'பச்சைப்பயறு'},
    emoji: '🫘',
    typicalPriceLkr: 380,
    demandBaseline: 65,
  ),
  'Cowpea': _CropInfo(
    name: {'en': 'Cowpea', 'si': 'කව්පි', 'ta': 'அவரை'},
    emoji: '🟤',
    typicalPriceLkr: 320,
    demandBaseline: 60,
  ),
  'Finger millet': _CropInfo(
    name: {'en': 'Finger millet', 'si': 'කුරක්කන්', 'ta': 'கேழ்வரகு'},
    emoji: '🌾',
    typicalPriceLkr: 250,
    demandBaseline: 68,
  ),
  'Groundnut': _CropInfo(
    name: {'en': 'Groundnut', 'si': 'රටකජු', 'ta': 'வேர்க்கடலை'},
    emoji: '🥜',
    typicalPriceLkr: 550,
    demandBaseline: 72,
  ),
};

// ─────────────────────────────────────────────────────────────────────────────
//  Season data — trilingual (kept consistent with Recommend screen)
// ─────────────────────────────────────────────────────────────────────────────
final List<Map<String, _L>> _seasons = [
  {
    'name': {'en': 'Maha', 'si': 'මහ', 'ta': 'மகா'},
    'emoji': {'en': '🌧️', 'si': '🌧️', 'ta': '🌧️'},
  },
  {
    'name': {'en': 'Yala', 'si': 'යල', 'ta': 'யாலா'},
    'emoji': {'en': '☀️', 'si': '☀️', 'ta': '☀️'},
  },
  {
    'name': {'en': 'Inter', 'si': 'අන්තර්', 'ta': 'இடை'},
    'emoji': {'en': '🌤️', 'si': '🌤️', 'ta': '🌤️'},
  },
];

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
//  DemandScreen
// ─────────────────────────────────────────────────────────────────────────────
class DemandScreen extends StatefulWidget {
  final ValueChanged<int>? onNavigate;
  final ValueChanged<String>? onAiChatContext;

  const DemandScreen({super.key, this.onNavigate, this.onAiChatContext});

  @override
  State<DemandScreen> createState() => _DemandScreenState();
}

class _DemandScreenState extends State<DemandScreen> {
  // ── Selections ────────────────────────────────────────────────────────────
  String _selectedCrop = 'Carrot';
  String _selectedSeason = 'Maha';
  late double _retailPrice = _crops[_selectedCrop]!.typicalPriceLkr;

  // ── Advanced market data (hidden by default, sensible defaults) ──────────
  bool _marketDataOpen = false;
  late double _demandLag1 = _crops[_selectedCrop]!.demandBaseline;
  late double _demandLag2 = _crops[_selectedCrop]!.demandBaseline - 3;
  late double _demandLag4 = _crops[_selectedCrop]!.demandBaseline - 6;
  double _inflationIndex = 1.15;
  double _consumerPrefIndex = 60.0;
  double _searchTrendIndex = 50.0;

  int _holidayFlag = 0;
  int _festivalFlag = 0;

  bool _isLoading = false;
  DemandResponse? _result;
  String? _errorMessage;

  String get _langKey {
    final l = AppLangProvider.lang(context);
    if (l == AppLang.si) return 'si';
    if (l == AppLang.ta) return 'ta';
    return 'en';
  }

  String _t(_L m) => m[_langKey] ?? m['en']!;
  String _cropLabel(String key) => _t(_crops[key]?.name ?? {'en': key});
  String _seasonLabel(String key) {
    final s = _seasons.firstWhere(
      (s) => s['name']!['en'] == key,
      orElse: () => {
        'name': {'en': key},
      },
    );
    return _t(s['name']!);
  }

  void _applyCropDefaults(String crop) {
    final info = _crops[crop]!;
    _retailPrice = info.typicalPriceLkr;
    _demandLag1 = info.demandBaseline;
    _demandLag2 = info.demandBaseline - 3;
    _demandLag4 = info.demandBaseline - 6;
  }

  Future<void> _predict() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _result = null;
    });
    try {
      final service = ServiceFactory.getService();
      final response = await service.predictDemand(
        DemandRequest(
          crop: _selectedCrop,
          season: _selectedSeason,
          weekOfYear: _weekOfYear(),
          demandLag1: _demandLag1,
          demandLag2: _demandLag2,
          demandLag4: _demandLag4,
          retailPriceLkrKg: _retailPrice,
          inflationIndex: _inflationIndex,
          holidayFlag: _holidayFlag,
          festivalFlag: _festivalFlag,
          consumerPrefIndex: _consumerPrefIndex,
          searchTrendIndex: _searchTrendIndex,
        ),
      );
      if (mounted) setState(() => _result = response);
    } catch (e) {
      if (mounted) {
        setState(
          () => _errorMessage = _t({
            'en': 'Could not forecast demand. Please try again.',
            'si': 'ඉල්ලුම පුරෝකථනය කළ නොහැක. නැවත උත්සාහ කරන්න.',
            'ta': 'தேவையை கணிக்க முடியவில்லை. மீண்டும் முயற்சிக்கவும்.',
          }),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Color _trendColor(String trend) => switch (trend) {
    'rising' => AppTheme.success,
    'falling' => AppTheme.error,
    _ => AppTheme.warning,
  };

  IconData _trendIcon(String trend) => switch (trend) {
    'rising' => Icons.trending_up,
    'falling' => Icons.trending_down,
    _ => Icons.trending_flat,
  };

  String _trendLabel(String trend) => switch (trend) {
    'rising' => _t({'en': 'RISING', 'si': 'ඉහළ යමින්', 'ta': 'உயர்கிறது'}),
    'falling' => _t({'en': 'FALLING', 'si': 'පහළ යමින්', 'ta': 'குறைகிறது'}),
    _ => _t({'en': 'STEADY', 'si': 'ස්ථාවර', 'ta': 'நிலையானது'}),
  };

  String _verdict(String trend) => switch (trend) {
    'rising' => _t({
      'en':
          'Demand looks set to rise. This could be a good time to plan your harvest for sale in the coming weeks.',
      'si':
          'ඉල්ලුම ඉහළ යනු ඇතැයි පෙනේ. ඉදිරි සති කිහිපය තුළ විකිණීම සඳහා ඔබේ අස්වැන්න සැලසුම් කිරීමට මෙය හොඳ කාලයක් විය හැක.',
      'ta':
          'தேவை உயரும் என்று தெரிகிறது. அடுத்த சில வாரங்களில் விற்பனைக்கு உங்கள் அறுவடையைத் திட்டமிட இது நல்ல நேரமாக இருக்கலாம்.',
    }),
    'falling' => _t({
      'en':
          'Demand looks set to soften. You may want to hold your stock a little longer or explore other markets.',
      'si':
          'ඉල්ලුම මඳක් අඩු විය හැකි බව පෙනේ. ඔබේ අස්වැන්න තව ටිකක් තබා ගැනීම හෝ වෙනත් වෙළඳපොළවල් සොයා බැලීම සලකා බලන්න.',
      'ta':
          'தேவை சற்று குறையக்கூடும் என்று தெரிகிறது. உங்கள் பொருட்களை இன்னும் சிறிது காலம் வைத்திருப்பதை அல்லது வேறு சந்தைகளைப் பார்ப்பதை பரிசீலிக்கவும்.',
    }),
    _ => _t({
      'en':
          'Demand looks steady for now — no major change expected in the coming weeks.',
      'si':
          'දැනට ඉල්ලුම ස්ථාවරව පවතී — ඉදිරි සති කිහිපය තුළ විශාල වෙනසක් අපේක්ෂා නොකෙරේ.',
      'ta':
          'தற்போது தேவை நிலையானதாக உள்ளது — அடுத்த சில வாரங்களில் பெரிய மாற்றம் எதிர்பார்க்கப்படவில்லை.',
    }),
  };

  // ══════════════════════════════════════════════════════════════════════════
  //  BUILD
  // ══════════════════════════════════════════════════════════════════════════
  @override
  Widget build(BuildContext context) {
    AppLangProvider.of(context);
    return Container(
      color: AppTheme.background,
      child: LayoutBuilder(
        builder: (ctx, bc) {
          final w = bc.maxWidth;
          return Column(
            children: [
              _buildTopBar(context),
              Expanded(
                child: w >= 960
                    ? _buildWebLayout()
                    : w >= 600
                    ? _buildCenteredScroll(700)
                    : _buildCenteredScroll(null),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildCenteredScroll(double? maxW) => Stack(
    children: [
      LayoutBuilder(
        builder: (ctx, bc) {
          final hPad = maxW == null
              ? 14.0
              : ((bc.maxWidth - maxW) / 2).clamp(14.0, 200.0);
          return SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(hPad, 14, hPad, 100),
            child: _formColumn(),
          );
        },
      ),
      _stickyPredictButton(),
    ],
  );

  Widget _stickyPredictButton() => Positioned(
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
      child: SafeArea(top: false, child: _predictButton()),
    ),
  );

  Widget _buildWebLayout() => LayoutBuilder(
    builder: (ctx, bc) {
      final leftW = (bc.maxWidth * 0.45).clamp(340.0, 520.0);
      return Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: leftW,
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 14, 12, 28),
              child: _formColumn(webLeft: true),
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

  Widget _formColumn({bool webLeft = false}) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _pageHeader(),
      const SizedBox(height: 16),
      _sectionTitle(_t({'en': 'Crop', 'si': 'භෝගය', 'ta': 'பயிர்'}), Icons.eco),
      const SizedBox(height: 10),
      _cropChips(),
      const SizedBox(height: 20),
      _sectionTitle(
        _t({'en': 'Season', 'si': 'කන්නය', 'ta': 'பருவம்'}),
        Icons.calendar_month,
      ),
      const SizedBox(height: 10),
      _seasonChips(),
      const SizedBox(height: 20),
      _sectionTitle(
        _t({
          'en': 'Today\'s Market Price',
          'si': 'අද වෙළඳපොළ මිල',
          'ta': 'இன்றைய சந்தை விலை',
        }),
        Icons.payments,
      ),
      const SizedBox(height: 10),
      _priceCard(),
      const SizedBox(height: 20),
      _sectionTitle(
        _t({
          'en': 'Holidays & Festivals',
          'si': 'නිවාඩු හා උත්සව',
          'ta': 'விடுமுறைகள் & திருவிழாக்கள்',
        }),
        Icons.celebration,
      ),
      const SizedBox(height: 10),
      _flagsCard(),
      const SizedBox(height: 20),
      _sectionTitle(
        _t({'en': 'Market Data', 'si': 'වෙළඳපොළ දත්ත', 'ta': 'சந்தைத் தரவு'}),
        Icons.insights,
      ),
      const SizedBox(height: 10),
      _marketDataCard(),
      const SizedBox(height: 20),
      if (webLeft) _predictButton(),
      if (!webLeft) ...[
        const SizedBox(height: 20),
        if (_errorMessage != null) _errorCard(),
        if (_result != null) _resultCard(),
        if (_result == null && _errorMessage == null && !_isLoading)
          _emptyPlaceholder(),
      ],
    ],
  );

  Widget _rightPanel() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      if (_errorMessage != null) ...[_errorCard(), const SizedBox(height: 14)],
      if (_result != null) _resultCard(),
      if (_result == null && _errorMessage == null && !_isLoading)
        _emptyPlaceholder(),
    ],
  );

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

    const activeBg = Color(0xFFE8EAF6);
    const activeColor = Color(0xFF283593);
    const activeIndex = 5; // Demand

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
                    final active = i == activeIndex;
                    return Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 2),
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
          const _LangPill(),
        ],
      ),
    );
  }

  // ── Page header ────────────────────────────────────────────────────────────
  Widget _pageHeader() => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      gradient: const LinearGradient(
        colors: [Color(0xFF283593), Color(0xFF3F51B5)],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
      borderRadius: BorderRadius.circular(14),
      boxShadow: [
        BoxShadow(
          color: const Color(0xFF283593).withValues(alpha: 0.3),
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
            _navSvg(5, Colors.white),
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
                _t({
                  'en': 'Demand Forecast',
                  'si': 'ඉල්ලුම් පුරෝකථනය',
                  'ta': 'தேவை முன்னறிவிப்பு',
                }),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                _t({
                  'en': 'Know if demand is rising before you sell',
                  'si': 'විකිණීමට පෙර ඉල්ලුම ඉහළ යනවාදැයි දැනගන්න',
                  'ta': 'விற்பதற்கு முன் தேவை அதிகரிக்கிறதா என்று அறியுங்கள்',
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
              'en': 'Week ${_weekOfYear()}',
              'si': 'සති ${_weekOfYear()}',
              'ta': 'வாரம் ${_weekOfYear()}',
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

  // ── Crop quick chips ───────────────────────────────────────────────────────
  Widget _cropChips() => Wrap(
    spacing: 8,
    runSpacing: 8,
    children: _crops.keys.map((key) {
      final info = _crops[key]!;
      final active = _selectedCrop == key;
      return GestureDetector(
        onTap: () => setState(() {
          _selectedCrop = key;
          _applyCropDefaults(key);
          _result = null;
        }),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
          decoration: BoxDecoration(
            color: active ? AppTheme.primary : Colors.white,
            borderRadius: BorderRadius.circular(20),
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
          child: Text(
            '${info.emoji}  ${_t(info.name)}',
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              color: active ? Colors.white : AppTheme.textPrimary,
            ),
          ),
        ),
      );
    }).toList(),
  );

  // ── Season quick chips ─────────────────────────────────────────────────────
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
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
          decoration: BoxDecoration(
            color: active ? AppTheme.primary : Colors.white,
            borderRadius: BorderRadius.circular(20),
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
          child: Text(
            '${_t(s['emoji']!)}  ${_t(s['name']!)}',
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              color: active ? Colors.white : AppTheme.textPrimary,
            ),
          ),
        ),
      );
    }).toList(),
  );

  // ── Price card — the one number a farmer can plausibly know ────────────────
  Widget _priceCard() => _card(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _infoBox(
          _t({
            'en':
                'Auto-filled with a typical price for ${_cropLabel(_selectedCrop)}. Adjust it if you know today\'s price at your local market.',
            'si':
                '${_cropLabel(_selectedCrop)} සඳහා සාමාන්‍ය මිලක් මෙහි ඇතුළත් කර ඇත. ඔබේ ප්‍රදේශයේ අද මිල දන්නේ නම් එය වෙනස් කරන්න.',
            'ta':
                '${_cropLabel(_selectedCrop)}-க்கான வழக்கமான விலை இங்கு பூர்த்தி செய்யப்பட்டுள்ளது. உங்கள் பகுதியில் இன்றைய விலை தெரிந்தால் அதை மாற்றவும்.',
          }),
          color: AppTheme.info,
          icon: Icons.info_outline,
        ),
        const SizedBox(height: 10),
        _slider(
          _t({
            'en': 'Retail Price (LKR/kg)',
            'si': 'සිල්ලර මිල (රු./kg)',
            'ta': 'சில்லறை விலை (ரூ./kg)',
          }),
          _retailPrice,
          20,
          800,
          '',
          AppTheme.success,
          (v) => setState(() => _retailPrice = v),
        ),
      ],
    ),
  );

  // ── Holiday / festival card ─────────────────────────────────────────────────
  Widget _flagsCard() => _card(
    child: Column(
      children: [
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(
            _t({
              'en': 'Holiday this week',
              'si': 'මේ සතියේ නිවාඩුවක් තිබේ',
              'ta': 'இந்த வாரம் விடுமுறை உள்ளது',
            }),
            style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600),
          ),
          value: _holidayFlag == 1,
          onChanged: (v) => setState(() => _holidayFlag = v ? 1 : 0),
          activeThumbColor: AppTheme.primary,
        ),
        const Divider(height: 1),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(
            _t({
              'en': 'Festival this week',
              'si': 'මේ සතියේ උත්සවයක් තිබේ',
              'ta': 'இந்த வாரம் திருவிழா உள்ளது',
            }),
            style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600),
          ),
          subtitle: Text(
            _t({
              'en': 'e.g. Avurudu, Vesak, Deepavali, Christmas',
              'si': 'උදා: අවුරුද්ද, වෙසක්, දීපාවලිය, නත්තල',
              'ta': 'எ.கா: புத்தாண்டு, வெசாக், தீபாவளி, கிறிஸ்துமஸ்',
            }),
            style: const TextStyle(fontSize: 11),
          ),
          value: _festivalFlag == 1,
          onChanged: (v) => setState(() => _festivalFlag = v ? 1 : 0),
          activeThumbColor: Colors.orange,
        ),
      ],
    ),
  );

  // ── Advanced market data (hidden by default) ────────────────────────────────
  Widget _marketDataCard() => _card(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _infoBox(
          _t({
            'en':
                'Using typical market trend values for ${_cropLabel(_selectedCrop)}. Tap below only if you have real recent price/demand data.',
            'si':
                '${_cropLabel(_selectedCrop)} සඳහා සාමාන්‍ය වෙළඳපොළ ප්‍රවණතා අගයන් භාවිත වේ. ඔබ සතුව මෑත මිල/ඉල්ලුම් දත්ත තිබේ නම් පමණක් පහත ඔබන්න.',
            'ta':
                '${_cropLabel(_selectedCrop)}-க்கான வழக்கமான சந்தைப் போக்கு மதிப்புகள் பயன்படுத்தப்படுகின்றன. உங்களிடம் சமீபத்திய விலை/தேவை தரவு இருந்தால் மட்டும் கீழே தட்டவும்.',
          }),
          color: AppTheme.info,
          icon: Icons.info_outline,
        ),
        const SizedBox(height: 10),
        GestureDetector(
          onTap: () => setState(() => _marketDataOpen = !_marketDataOpen),
          child: Row(
            children: [
              Icon(
                _marketDataOpen ? Icons.expand_less : Icons.tune,
                size: 15,
                color: AppTheme.textSecondary,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  _marketDataOpen
                      ? _t({
                          'en': 'Hide market data details',
                          'si': 'වෙළඳපොළ දත්ත විස්තර සඟවන්න',
                          'ta': 'சந்தைத் தரவு விவரங்களை மறைக்கவும்',
                        })
                      : _t({
                          'en': 'I have real market data',
                          'si': 'මා සතුව සැබෑ වෙළඳපොළ දත්ත තිබේ',
                          'ta': 'என்னிடம் உண்மையான சந்தைத் தரவு உள்ளது',
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
        if (_marketDataOpen) ...[
          const SizedBox(height: 10),
          Text(
            _t({
              'en':
                  'How much demand there was for this crop in recent weeks (0 = none, 100+ = very high)',
              'si':
                  'මෑත සති කිහිපයේදී මෙම භෝගයට තිබූ ඉල්ලුම (0 = නැත, 100+ = ඉතා ඉහළ)',
              'ta':
                  'சமீபத்திய வாரங்களில் இந்த பயிருக்கு இருந்த தேவை (0 = இல்லை, 100+ = மிக அதிகம்)',
            }),
            style: const TextStyle(
              fontSize: 11,
              color: AppTheme.textMuted,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 6),
          _slider(
            _t({'en': 'Last week', 'si': 'පසුගිය සතිය', 'ta': 'கடந்த வாரம்'}),
            _demandLag1,
            0,
            150,
            '',
            Colors.purple,
            (v) => setState(() => _demandLag1 = v),
          ),
          _slider(
            _t({
              'en': '2 weeks ago',
              'si': 'සති 2කට පෙර',
              'ta': '2 வாரங்களுக்கு முன்',
            }),
            _demandLag2,
            0,
            150,
            '',
            Colors.deepPurple,
            (v) => setState(() => _demandLag2 = v),
          ),
          _slider(
            _t({
              'en': '4 weeks ago',
              'si': 'සති 4කට පෙර',
              'ta': '4 வாரங்களுக்கு முன்',
            }),
            _demandLag4,
            0,
            150,
            '',
            Colors.indigo,
            (v) => setState(() => _demandLag4 = v),
          ),
          const SizedBox(height: 4),
          _slider(
            _t({
              'en': 'Inflation Index',
              'si': 'උද්ධමන දර්ශකය',
              'ta': 'பணவீக்க குறியீடு',
            }),
            _inflationIndex,
            0.5,
            3.0,
            '',
            Colors.red,
            (v) => setState(() => _inflationIndex = v),
          ),
          _slider(
            _t({
              'en': 'Buyer Interest',
              'si': 'ගැනුම්කරුවන්ගේ උනන්දුව',
              'ta': 'வாங்குபவர் ஆர்வம்',
            }),
            _consumerPrefIndex,
            0,
            100,
            '',
            Colors.teal,
            (v) => setState(() => _consumerPrefIndex = v),
          ),
          _slider(
            _t({
              'en': 'Online Search Interest',
              'si': 'අන්තර්ජාල සෙවීම් උනන්දුව',
              'ta': 'ஆன்லைன் தேடல் ஆர்வம்',
            }),
            _searchTrendIndex,
            0,
            100,
            '',
            Colors.blueGrey,
            (v) => setState(() => _searchTrendIndex = v),
          ),
        ],
      ],
    ),
  );

  // ── Predict button ──────────────────────────────────────────────────────
  Widget _predictButton() => SizedBox(
    width: double.infinity,
    height: 52,
    child: ElevatedButton.icon(
      onPressed: _isLoading ? null : _predict,
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
            ? _t({
                'en': 'Forecasting...',
                'si': 'පුරෝකථනය කරමින්...',
                'ta': 'முன்னறிவிக்கிறோம்...',
              })
            : _t({
                'en': 'Forecast Demand',
                'si': 'ඉල්ලුම පුරෝකථනය කරන්න',
                'ta': 'தேவையை முன்னறிவிக்கவும்',
              }),
        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
      ),
      style: ElevatedButton.styleFrom(
        backgroundColor: const Color(0xFF283593),
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
          _navSvg(5, const Color(0xFFB0C4B0)),
          width: 48,
          height: 48,
        ),
        const SizedBox(height: 12),
        Text(
          _t({
            'en': 'Your demand forecast will appear here',
            'si': 'ඔබේ ඉල්ලුම් පුරෝකථනය මෙතැන දිස්වේ',
            'ta': 'உங்கள் தேவை முன்னறிவிப்பு இங்கே தோன்றும்',
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

  // ── Result card ────────────────────────────────────────────────────────
  Widget _resultCard() {
    final trend = _result!.trend;
    final color = _trendColor(trend);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [color.withValues(alpha: 0.85), color],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(14),
            boxShadow: [
              BoxShadow(
                color: color.withValues(alpha: 0.35),
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
                    '${_crops[_selectedCrop]?.emoji ?? ''}  ${_cropLabel(_selectedCrop)}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  if (_result!.isMock) const CsMockBadge(),
                ],
              ),
              const SizedBox(height: 14),
              Text(
                _result!.predictedDemandIndex.toStringAsFixed(0),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 46,
                  fontWeight: FontWeight.bold,
                  letterSpacing: -0.5,
                ),
              ),
              Text(
                _t({
                  'en': 'Demand Index',
                  'si': 'ඉල්ලුම් දර්ශකය',
                  'ta': 'தேவை குறியீடு',
                }),
                style: const TextStyle(color: Colors.white70, fontSize: 12.5),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.4),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(_trendIcon(trend), color: Colors.white, size: 17),
                    const SizedBox(width: 6),
                    Text(
                      _trendLabel(trend),
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 12.5,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        // ── Plain-language verdict ─────────────────────────────────────────
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
                  Icon(Icons.lightbulb_outline, size: 15, color: color),
                  const SizedBox(width: 6),
                  Text(
                    _t({
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
                _verdict(trend),
                style: const TextStyle(
                  fontSize: 13,
                  color: AppTheme.textPrimary,
                  height: 1.5,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        // ── Cross-navigation buttons ───────────────────────────────────────
        LayoutBuilder(
          builder: (ctx, bc) {
            final narrow = bc.maxWidth < 300;
            final priceBtn = OutlinedButton.icon(
              onPressed: () => widget.onNavigate?.call(2), // Price tab
              icon: const Icon(Icons.payments, size: 16),
              label: Text(
                _t({
                  'en': 'Check Price Forecast',
                  'si': 'මිල පුරෝකථනය බලන්න',
                  'ta': 'விலை முன்னறிவிப்பைப் பார்க்கவும்',
                }),
                style: const TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                ),
                overflow: TextOverflow.ellipsis,
              ),
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFF283593),
                side: const BorderSide(color: Color(0xFF3F51B5)),
                padding: const EdgeInsets.symmetric(vertical: 10),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            );
            final askBtn = ElevatedButton.icon(
              onPressed: () {
                final trendWord = _trendLabel(trend).toLowerCase();
                final sLabel = _seasonLabel(_selectedSeason);
                final ctx = _t({
                  'en':
                      'You forecast $trendWord demand for ${_cropLabel(_selectedCrop)} '
                      '(index: ${_result!.predictedDemandIndex.toStringAsFixed(0)}) in $_selectedSeason season. '
                      'What should I do to get the best price for my harvest?',
                  'si':
                      '$sLabel කන්නයේ ${_cropLabel(_selectedCrop)} සඳහා ඉල්ලුම $trendWord බව ඔබ පුරෝකථනය කළා '
                      '(දර්ශකය: ${_result!.predictedDemandIndex.toStringAsFixed(0)}). '
                      'මගේ අස්වැන්නට හොඳම මිල ලබාගැනීමට මා කුමක් කළ යුතුද?',
                  'ta':
                      '$sLabel பருவத்தில் ${_cropLabel(_selectedCrop)}-க்கான தேவை $trendWord என நீங்கள் கணித்தீர்கள் '
                      '(குறியீடு: ${_result!.predictedDemandIndex.toStringAsFixed(0)}). '
                      'எனது அறுவடைக்கு சிறந்த விலை பெற நான் என்ன செய்ய வேண்டும்?',
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
                _t({'en': 'Ask AI', 'si': 'AI අසන්න', 'ta': 'AI கேளுங்கள்'}),
                style: const TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                ),
                overflow: TextOverflow.ellipsis,
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF283593),
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
                  SizedBox(width: double.infinity, child: priceBtn),
                  const SizedBox(height: 8),
                  SizedBox(width: double.infinity, child: askBtn),
                ],
              );
            }
            return Row(
              children: [
                Expanded(child: priceBtn),
                const SizedBox(width: 8),
                Expanded(child: askBtn),
              ],
            );
          },
        ),
      ],
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
    ValueChanged<double> onChanged,
  ) => Padding(
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
                '${value.toStringAsFixed(max <= 3 ? 2 : 0)} $unit'.trim(),
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
          child: Slider(value: value, min: min, max: max, onChanged: onChanged),
        ),
      ],
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
//  Language pill (matches other screens)
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
