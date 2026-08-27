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
import '../../services/prediction_handoff.dart';
import '../../services/price_prefill.dart';
import '../../services/service_factory.dart';
import '../../widgets/animated_lang_text.dart';
import '../../widgets/app_theme.dart';
import '../../widgets/localized_names.dart';
import '../../widgets/searchable_dropdown.dart';
import '../../widgets/app_top_bar.dart';
import '../../widgets/followup_chip.dart';
import '../../widgets/skeleton_loading.dart';

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
//  Crop data — emoji + sensible per-crop defaults for the values a farmer
//  would otherwise have to guess (retail price, demand baseline). These are
//  typical placeholders the farmer can override.
//
//  Display NAMES are not here: they live in kCropNames (localized_names.dart)
//  with every other screen's. This map used to carry its own trilingual copy,
//  which had drifted from price_screen's in two cells — see kCropNames.
// ─────────────────────────────────────────────────────────────────────────────
class _CropInfo {
  final String emoji;
  final double typicalPriceLkr;
  final double demandBaseline;
  const _CropInfo({
    required this.emoji,
    required this.typicalPriceLkr,
    required this.demandBaseline,
  });
}

const Map<String, _CropInfo> _crops = {
  'Carrot': _CropInfo(emoji: '🥕', typicalPriceLkr: 180, demandBaseline: 78),
  'Maize': _CropInfo(emoji: '🌽', typicalPriceLkr: 90, demandBaseline: 70),
  'Green gram': _CropInfo(
    emoji: '🫘',
    typicalPriceLkr: 380,
    demandBaseline: 65,
  ),
  'Cowpea': _CropInfo(emoji: '🟤', typicalPriceLkr: 320, demandBaseline: 60),
  'Finger millet': _CropInfo(
    emoji: '🌾',
    typicalPriceLkr: 250,
    demandBaseline: 68,
  ),
  'Groundnut': _CropInfo(emoji: '🥜', typicalPriceLkr: 550, demandBaseline: 72),
};

// ─────────────────────────────────────────────────────────────────────────────
//  Season data — trilingual (kept consistent with Recommend screen)
// ─────────────────────────────────────────────────────────────────────────────
// `months` is new here: the season cards (see _seasonCards) show the date
// range under the name, so a farmer picking a season is not relying on
// remembering which months Maha covers. Values are recommend_screen's
// verbatim, so the same season reads identically on both pages.
final List<Map<String, _L>> _seasons = [
  {
    'name': {'en': 'Maha', 'si': 'මහ', 'ta': 'மகா'},
    'emoji': {'en': '🌧️', 'si': '🌧️', 'ta': '🌧️'},
    'months': {
      'en': 'October – March',
      'si': 'ඔක්තෝබර් – මාර්තු',
      'ta': 'அக்டோபர் – மார்ச்',
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
  },
  {
    'name': {'en': 'Inter', 'si': 'අන්තර්', 'ta': 'இடை'},
    'emoji': {'en': '🌤️', 'si': '🌤️', 'ta': '🌤️'},
    'months': {
      'en': 'Mar–Apr & Sep–Oct',
      'si': 'මාර්-අප්‍රේල් & සැප්-ඔක්',
      'ta': 'மார்-ஏப் & செப்-அக்',
    },
  },
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
          '</svg>',
    4 =>
      '<svg viewBox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg">'
          '<path d="M12 22C12 16 12 11 12 6" stroke="$c" stroke-width="2" stroke-linecap="round"/>'
          '<path d="M12 15C8 13 4 9 6 4C10 8 11 12 12 15Z" fill="$c" opacity="0.65"/>'
          '<path d="M12 11C16 9 20 5 18 0C14 5 12 9 12 11Z" fill="$c"/>'
          '<circle cx="18" cy="5" r="4.5" fill="$c"/>'
          '<path d="M16 5L17.5 7L20 3.5" stroke="white" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round"/>'
          '</svg>',
    // Demand — market basket + arrow. The two stroke paths at the end are the
    // ARROW, and this local copy was missing them: it drew the basket alone,
    // so the header icon and the empty-state icon did not match the glyph the
    // bottom nav shows for this same tab. Kept byte-identical to
    // floating_bottom_nav's case 5 — that one is the canonical version.
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
  // Nothing is pre-selected — the farmer must actively choose a Crop and
  // Season themselves.
  String? _selectedCrop;
  String? _selectedSeason;
  // Generic starting price until a crop is picked — then this updates to
  // that crop's typical price automatically (still fully editable).
  double _retailPrice = 150.0;

  // ── Advanced market data (hidden by default, sensible defaults) ──────────
  bool _marketDataOpen = false;
  double _demandLag1 = 65.0;
  double _demandLag2 = 62.0;
  double _demandLag4 = 59.0;
  double _inflationIndex = 1.15;
  double _consumerPrefIndex = 60.0;
  double _searchTrendIndex = 50.0;

  int _holidayFlag = 0;
  int _festivalFlag = 0;

  bool _isLoading = false;
  DemandResponse? _result;
  String? _errorMessage;

  // Retail price is entered as exact text (no artificial ceiling) rather
  // than a capped slider — real market prices can go well past what any
  // fixed slider maximum would allow.
  final TextEditingController _priceController = TextEditingController(
    text: '150',
  );

  // ── Searchable dropdown text state ────────────────────────────────────────
  // Crop is type-to-filter (RawAutocomplete), same as recommend_screen's
  // District field. The controller holds what the farmer has TYPED, which is
  // not the same thing as what they have COMMITTED — _selectedCrop is the
  // selection, this is just the text in the box.
  final TextEditingController _cropCtrl = TextEditingController();
  final FocusNode _cropFocus = FocusNode();

  @override
  void dispose() {
    _priceController.dispose();
    _cropCtrl.dispose();
    _cropFocus.dispose();
    super.dispose();
  }

  String get _langKey {
    final l = AppLangProvider.lang(context);
    if (l == AppLang.si) return 'si';
    if (l == AppLang.ta) return 'ta';
    return 'en';
  }

  String _t(_L m) => m[_langKey] ?? m['en']!;

  /// Placeholder for this screen's SearchableDropdown.
  String get _searchHint => _t({
    'en': 'Type to search',
    'si': 'සෙවීමට ටයිප් කරන්න',
    'ta': 'தேட தட்டச்சு செய்க',
  });

  String get _notSelectedLabel => _t({
    'en': 'not selected yet',
    'si': 'තවම තෝරා නැත',
    'ta': 'இன்னும் தேர்ந்தெடுக்கப்படவில்லை',
  });

  String _cropLabel(String? key) =>
      key == null ? _notSelectedLabel : cropLabel(_langKey, key);

  /// The same translated name, but for a key that is always present — what
  /// the searchable dropdown renders and filters its options on. Separate
  /// from [_cropLabel] because that one substitutes "not selected yet" for
  /// null, which is a prose stand-in, not an option label.
  String _cropName(String key) => cropLabel(_langKey, key);

  // ── Meaningful labels for the "I have real market data" sliders ─────────
  // These replace raw, meaningless numbers (e.g. "87", "1.15") with bands a
  // farmer can actually interpret at a glance — same pattern as the Soil
  // N/P/K fertility ratings on the Recommend screen.
  String _demandLevelLabel(double v) {
    if (v < 35) {
      return _t({'en': 'Very Low', 'si': 'ඉතා අඩු', 'ta': 'மிகக் குறைவு'});
    } else if (v < 60) {
      return _t({'en': 'Low', 'si': 'අඩු', 'ta': 'குறைவு'});
    } else if (v < 90) {
      return _t({'en': 'Moderate', 'si': 'මධ්‍යම', 'ta': 'மிதமான'});
    } else if (v < 120) {
      return _t({'en': 'High', 'si': 'ඉහළ', 'ta': 'அதிகம்'});
    }
    return _t({'en': 'Very High', 'si': 'ඉතා ඉහළ', 'ta': 'மிக அதிகம்'});
  }

  /// Inflation Index shown as a plain percentage change from normal
  /// (index 1.0 = 0%) plus a direction word, instead of a raw "1.15".
  String _inflationLevelLabel(double v) {
    final pct = ((v - 1) * 100).round();
    final sign = pct >= 0 ? '+' : '';
    final String word;
    if (pct <= -15) {
      word = _t({
        'en': 'Falling Fast',
        'si': 'ඉක්මනින් අඩුවෙයි',
        'ta': 'வேகமாக குறைகிறது',
      });
    } else if (pct < 0) {
      word = _t({'en': 'Falling', 'si': 'අඩුවෙයි', 'ta': 'குறைகிறது'});
    } else if (pct < 10) {
      word = _t({'en': 'Stable', 'si': 'ස්ථාවර', 'ta': 'நிலையானது'});
    } else if (pct < 30) {
      word = _t({'en': 'Rising', 'si': 'ඉහළ යයි', 'ta': 'உயர்கிறது'});
    } else {
      word = _t({
        'en': 'Rising Fast',
        'si': 'ඉක්මනින් ඉහළ යයි',
        'ta': 'வேகமாக உயர்கிறது',
      });
    }
    return '$sign$pct% · $word';
  }

  String _interestLevelLabel(double v) {
    if (v < 25) {
      return _t({'en': 'Low', 'si': 'අඩු', 'ta': 'குறைவு'});
    } else if (v < 50) {
      return _t({'en': 'Moderate', 'si': 'මධ්‍යම', 'ta': 'மிதமான'});
    } else if (v < 75) {
      return _t({'en': 'High', 'si': 'ඉහළ', 'ta': 'அதிகம்'});
    }
    return _t({'en': 'Very High', 'si': 'ඉතා ඉහළ', 'ta': 'மிக அதிகம்'});
  }

  void _applyCropDefaults(String crop) {
    final info = _crops[crop]!;
    _retailPrice = info.typicalPriceLkr;
    _priceController.text = info.typicalPriceLkr.toStringAsFixed(0);
    _demandLag1 = info.demandBaseline;
    _demandLag2 = info.demandBaseline - 3;
    _demandLag4 = info.demandBaseline - 6;
  }

  Future<void> _predict() async {
    // Crop and Season are required — nothing is pre-selected, so make sure
    // the farmer actually picked both before calling the API.
    if (_selectedCrop == null || _selectedSeason == null) {
      setState(() {
        _result = null;
        _errorMessage = _t({
          'en': 'Please select a Crop and Season first.',
          'si': 'කරුණාකර පළමුව භෝගයක් සහ කන්නයක් තෝරන්න.',
          'ta': 'முதலில் ஒரு பயிரையும் பருவத்தையும் தேர்ந்தெடுக்கவும்.',
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
      final response = await service.predictDemand(
        DemandRequest(
          crop: _selectedCrop!,
          season: _selectedSeason!,
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

  /// STEADY's badge colour, deepened from the shared AppTheme.warning.
  ///
  /// #F57F17 carries white at 2.65:1 — under even the 3:1 non-text floor. On
  /// the OLD result card that was not a badge-sized problem, it was the whole
  /// card: the card's gradient was this colour and the 46px index, its label,
  /// the crop name and the trend pill were all white on it, so every steady
  /// forecast — the most common outcome — rendered its entire result under
  /// the floor. #BA5B08 is the minimal HLS darkening that gets white to
  /// 4.58:1.
  ///
  /// Deepened LOCALLY, not in the shared token, so screens using
  /// AppTheme.warning elsewhere are unaffected — the same thing price_screen
  /// does with its own _confWarningDeep (#E6710A, which is a 3:1 dot value
  /// and would not clear the text floor a badge needs).
  static const Color _trendSteadyDeep = Color(0xFFBA5B08);

  /// rising/falling keep the shared tokens: white measures 5.13:1 on
  /// AppTheme.success and 5.62:1 on AppTheme.error, so neither needs help.
  Color _trendColor(String trend) => switch (trend) {
    'rising' => AppTheme.success,
    'falling' => AppTheme.error,
    _ => _trendSteadyDeep,
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

  // ── Layout — resizes for mobile / tablet / web ────────────────────────────
  // Thresholds and column formula are recommend_screen's verbatim rather than
  // re-derived. This page used its own single >= 960 break and a 5:4 grid of
  // INPUTS ONLY (Crop+Season+Price left, Holidays+MarketData right) with the
  // button and result spanning full width underneath — so at the same
  // viewport its columns sat at visibly different widths from every other
  // feature page, and the farmer submitted the form from below both columns.
  Widget _buildDetailsTab(double width) {
    if (width >= 1024) return _buildWebDetails(width);
    if (width >= 600) return _buildTabletDetails(width);
    return _buildMobileDetails(width);
  }

  // Bottom padding 180 for the same reason as recommend_screen's and
  // price_screen's: below 1024px MainShell overlays FloatingBottomNav AND
  // this Stack pins its own sticky button to the same bottom:0, so the
  // clearance has to cover both bars. The old value here was 100, which only
  // ever accounted for this screen's own bar.
  Widget _buildMobileDetails(double width) {
    final hPad = width < 340 ? 12.0 : 14.0;
    return Stack(
      children: [
        SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(hPad, 14, hPad, 180),
          child: _formColumn(),
        ),
        _stickyPredictButton(),
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
        _stickyPredictButton(),
      ],
    );
  }

  // Web (>= 1024dp): ALL inputs left, result + chat right.
  //
  // Holidays/Festivals and Market Data move INTO the left column here — they
  // are inputs, and the old split put two of them beside the other three for
  // no reason other than filling the right half. The button is pinned to the
  // bottom of the left column, exactly as recommend/price/yield pin theirs,
  // so the farmer fills the column in and submits it without crossing the
  // page.
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
              _stickyPredictButton(),
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

  // ── Sticky bottom action button ──────────────────────────────────────────
  Widget _stickyPredictButton() => Positioned(
    bottom: 0,
    left: 0,
    right: 0,
    child: Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
      decoration: BoxDecoration(
        // login.background, not Colors.white — the bar sits over the page
        // ground and a pure-white slab under a #FCFBF6 page reads as a seam.
        color: AppTheme.login.background,
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

  // ── Form column (LEFT on web, the whole page below 1024dp) ───────────────
  // Order is fixed: header -> Crop -> Season -> Today's Market Price ->
  // Holidays & Festivals -> Market Data, then the sticky button pinned over
  // the bottom of this same column.
  //
  // Every one of these blocks keeps its existing content and behaviour. Only
  // the crop selector (chips -> searchable dropdown) and the season selector
  // (chips -> cards) changed shape; Price, Holidays and Market Data are the
  // same widgets, relocated.
  Widget _formColumn({bool webLeft = false}) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _pageHeader(),
      const SizedBox(height: 16),
      _sectionTitle(_t({'en': 'Crop', 'si': 'භෝගය', 'ta': 'பயிர்'}), Icons.eco),
      const SizedBox(height: 10),
      _cropCard(),
      const SizedBox(height: 20),
      _sectionTitle(
        _t({'en': 'Season', 'si': 'කන්නය', 'ta': 'பருவம்'}),
        Icons.calendar_month,
      ),
      const SizedBox(height: 10),
      _seasonCards(),
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
      // Single column (<1024dp): the result and the chat block follow the
      // inputs. The button itself stays pinned in the sticky bar above this
      // scroll view, so it is never scrolled away from.
      if (!webLeft) ...[const SizedBox(height: 20), _rightPanel()],
    ],
  );

  // ── Right panel (RIGHT on web, appended below the inputs on mobile) ───────
  Widget _rightPanel() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      if (_isLoading) _resultSkeleton(),
      if (_errorMessage != null) _errorCard(),
      if (_result != null) ...[
        _resultCard(),
        const SizedBox(height: 16),
        _askAiBlock(),
      ],
      if (_result == null && _errorMessage == null && !_isLoading)
        _emptyPlaceholder(),
    ],
  );

  // Demand is nav index 5. See app_top_bar.dart for why this is one shared
  // widget now instead of six independent copies of this same bar.
  Widget _buildTopBar(BuildContext context) => AppTopBar(
    activeIndex: 5,
    activeBg: AppTheme.accents.demand.fill.withValues(alpha: 0.16),
    activeColor: AppTheme.accents.demand.ink,
    onNavigate: widget.onNavigate,
  );

  // ── Page header ────────────────────────────────────────────────────────────
  // Structurally identical to recommend_screen's header — same gradient
  // direction (dark top-left -> light bottom-right), same computed light
  // stop, same icon container, glass badge and title/subtitle sizing.
  //
  // What it REPLACES is not a themed header at all: this page predated the
  // accent system and hardcoded #283593 -> #3F51B5 indigo, which is why it
  // rendered blue while accents.demand held an ochre nothing referenced.
  //
  //   #613298 (dark anchor, == accents.demand.fill)  onFill 8.38:1
  //   #8751C6 (light stop, +0.15 HLS lightness)      onFill 5.04:1
  //
  // Both clear AA for normal-size text with real margin. Unlike price and
  // weather, nothing here is a known-accepted failure.

  /// #8751C6 — the header's light gradient stop.
  ///
  /// Computed rather than hardcoded so the relationship to fill survives a
  /// re-theme. This is price/weather's PLAIN +0.15 lightness widening, not
  /// recommend_screen's +0.102/-0.039: that page's saturation term exists to
  /// stop a mid-green going minty at the light end, and purple has no such
  /// failure mode. Draining saturation here only narrows the step (#7A44BA),
  /// which reads closer to flat.
  static final Color _headerGradientLight = _lighten(
    AppTheme.accents.demand.fill,
    0.15,
  );

  /// Shift a colour's lightness in HLS, hue and saturation preserved. Kept as
  /// code, not a second hardcoded hex, so re-theming fill moves the gradient
  /// with it.
  static Color _lighten(Color c, double lightness) {
    final hsl = HSLColor.fromColor(c);
    return hsl
        .withLightness((hsl.lightness + lightness).clamp(0.0, 1.0))
        .toColor();
  }

  Widget _pageHeader() => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      gradient: LinearGradient(
        colors: [AppTheme.accents.demand.fill, _headerGradientLight],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
      borderRadius: BorderRadius.circular(14),
      boxShadow: [
        BoxShadow(
          color: AppTheme.accents.demand.fill.withValues(alpha: 0.3),
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
            _navSvg(5, AppTheme.accents.demand.onFill),
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
                  'en': 'Demand Forecast',
                  'si': 'ඉල්ලුම් පුරෝකථනය',
                  'ta': 'தேவை முன்னறிவிப்பு',
                }),
                style: TextStyle(
                  color: AppTheme.accents.demand.onFill, // 8.38:1 / 5.04:1
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              AnimatedLangText(
                _t({
                  'en': 'Know if demand is rising before you sell',
                  'si': 'විකිණීමට පෙර ඉල්ලුම ඉහළ යනවාදැයි දැනගන්න',
                  'ta': 'விற்பதற்கு முன் தேவை அதிகரிக்கிறதா என்று அறியுங்கள்',
                }),
                // FULL OPACITY, no alpha. The old header ran this subtitle at
                // 0.8 on its indigo; carried onto the purple light stop that
                // measures 3.85:1, under the 4.5:1 normal-text floor. 0.90 is
                // 4.41 (still under), 0.95 is 4.70 with almost no headroom,
                // full opacity is 5.04. Same conclusion recommend_screen and
                // price_screen each reached on their own headers.
                style: TextStyle(
                  color: AppTheme.accents.demand.onFill,
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
              'en': 'Week ${_weekOfYear()}',
              'si': 'සති ${_weekOfYear()}',
              'ta': 'வாரம் ${_weekOfYear()}',
            }),
            style: TextStyle(
              color: AppTheme.accents.demand.onFill, // 11.96:1 / 8.33:1
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    ),
  );

  /// Glass panel — the icon container and the "Week N" pill.
  ///
  /// The tint direction and BOTH alphas were re-measured against this purple
  /// rather than inherited from recommend_screen, because a more saturated
  /// anchor does not behave like that page's olive.
  ///
  /// DIRECTION — black, and the current white is the bug being fixed. On this
  /// fill the content is off-white, so a lightening scrim erodes exactly the
  /// contrast it needs to protect. At the light stop:
  ///
  ///   white@0.15  3.78:1   <- what this header ships today, under the floor
  ///   white@0.20  3.44:1
  ///   white@0.25  3.15:1
  ///
  /// All three fail, which is why the icon container currently disappears
  /// into the fill. Black holds text easily at every alpha (black@0.30 is
  /// 11.96:1 at the anchor, 8.33:1 at the light stop).
  ///
  /// ALPHA — 0.30, not recommend_screen's 0.20. Since black clears the text
  /// floor everywhere, the alpha was chosen on SEPARATION instead — how far
  /// the tinted panel sits from the fill behind it:
  ///
  ///   black@0.20  1.27 (anchor) / 1.39 (light stop)
  ///   black@0.30  1.43        / 1.65                 <- chosen
  ///   black@0.50  1.77        / 2.33
  ///
  /// NOTE what those numbers mean: no scrim of any alpha reaches the 3:1
  /// non-text floor, because a translucent tint of the colour underneath it
  /// cannot diverge far from that colour. recommend_screen has the identical
  /// property — its black@0.20 measures 1.30 against its own fill. So the
  /// scrim is not what makes these panels visible, and 0.30 is simply the
  /// most separation available before the panel stops reading as glass.
  ///
  /// EDGE — white@0.45, not recommend_screen's 0.25. Since the scrim cannot
  /// delineate the panel, the border is what actually does, and 0.25 measures
  /// 1.61:1 (anchor) / 1.29:1 (light) against this fill — no edge at all.
  /// 0.45 clears the 3:1 non-text floor against the panel it encloses at the
  /// anchor (3.51:1) while still reading as a highlight. 0.70 clears 3:1
  /// against the fill at both ends but stops looking translucent and starts
  /// looking like a hard white outline.
  Widget _glassBadge({
    required double borderRadius,
    required EdgeInsets padding,
    required Widget child,
  }) => Container(
    padding: padding,
    decoration: BoxDecoration(
      color: Colors.black.withValues(alpha: 0.30),
      borderRadius: BorderRadius.circular(borderRadius),
      border: Border.all(color: Colors.white.withValues(alpha: 0.45), width: 1),
    ),
    child: child,
  );

  // ── Crop ──────────────────────────────────────────────────────────────────
  // Was a Wrap of six emoji quick-select chips. Replaced with the same
  // type-to-filter dropdown recommend_screen uses for District, plus the
  // inline green tick, so both pages signal "this required field is done"
  // with one shared vocabulary instead of two.
  //
  // Selection behaviour is UNCHANGED from the chips: picking a crop still
  // applies that crop's typical-price/demand-baseline defaults and clears any
  // stale result.
  Widget _cropCard() => _card(
    child: SearchableDropdown(
      label: _t({'en': 'Crop', 'si': 'භෝගය', 'ta': 'பயிர்'}),
      value: _selectedCrop,
      items: _crops.keys.toList(),
      icon: Icons.eco,
      accent: AppTheme.accents.demand,
      searchHint: _searchHint,
      controller: _cropCtrl,
      focusNode: _cropFocus,
      itemLabel: _cropName,
      onChanged: (v) {
        if (v == null) return;
        setState(() {
          _selectedCrop = v;
          _applyCropDefaults(v);
          _result = null;
        });
      },
    ),
  );

  // ── Season cards ──────────────────────────────────────────────────────────
  // Was a Wrap of three single-line emoji chips. Now recommend_screen's card
  // treatment verbatim: the season name over its date range, so the farmer
  // does not have to remember that Maha means October–March.
  //
  // SELECTED state uses the demand accent, not AppTheme.primary. The chips
  // this replaced went green on selection, which read as a different feature's
  // colour on a purple page — the header, the Forecast button and this card
  // are now one accent. White on #613298 is 8.69:1 for the name and 6.75:1 for
  // the months line at 0.85.
  Widget _seasonCards() => Wrap(
    spacing: 8,
    runSpacing: 8,
    children: _seasons.map((s) {
      final key = s['name']!['en']!;
      final active = _selectedSeason == key;
      final accent = AppTheme.accents.demand.fill;
      return GestureDetector(
        onTap: () => setState(() {
          _selectedSeason = key;
          _result = null;
        }),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: active ? accent : Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: active ? accent : const Color(0xFFD0E8C8),
              width: active ? 2 : 1.5,
            ),
            boxShadow: active
                ? [
                    BoxShadow(
                      color: accent.withValues(alpha: 0.2),
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

  // ── Price card — the one number a farmer can plausibly know ────────────────
  Widget _priceCard() => _card(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _infoBox(
          _selectedCrop == null
              ? _t({
                  'en':
                      'Select a crop above, then enter today\'s market price. There is no upper limit — enter the exact price you\'ve seen at your local market.',
                  'si':
                      'ඉහත භෝගයක් තෝරන්න, පසුව අද වෙළඳපොළ මිල ඇතුළත් කරන්න. උපරිම සීමාවක් නැත — ඔබේ ප්‍රදේශයේ දුටු නිවැරදි මිල ඇතුළත් කරන්න.',
                  'ta':
                      'மேலே ஒரு பயிரைத் தேர்ந்தெடுக்கவும், பின்னர் இன்றைய சந்தை விலையை உள்ளிடவும். அதிகபட்ச வரம்பு இல்லை — உங்கள் பகுதியில் கண்ட சரியான விலையை உள்ளிடவும்.',
                })
              : _t({
                  'en':
                      'Auto-filled with a typical price for ${_cropLabel(_selectedCrop)}. Type in today\'s actual price at your local market — there is no upper limit.',
                  'si':
                      '${_cropLabel(_selectedCrop)} සඳහා සාමාන්‍ය මිලක් මෙහි ඇතුළත් කර ඇත. ඔබේ ප්‍රදේශයේ අද සැබෑ මිල ටයිප් කරන්න — උපරිම සීමාවක් නැත.',
                  'ta':
                      '${_cropLabel(_selectedCrop)}-க்கான வழக்கமான விலை இங்கு பூர்த்தி செய்யப்பட்டுள்ளது. உங்கள் பகுதியில் இன்றைய உண்மையான விலையை தட்டச்சு செய்யவும் — அதிகபட்ச வரம்பு இல்லை.',
                }),
          color: AppTheme.info,
          icon: Icons.info_outline,
        ),
        const SizedBox(height: 12),
        TextFormField(
          controller: _priceController,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          style: const TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w800,
            color: AppTheme.textPrimary,
          ),
          decoration: InputDecoration(
            labelText: _t({
              'en': 'Retail Price (LKR/kg)',
              'si': 'සිල්ලර මිල (රු./kg)',
              'ta': 'சில்லறை விலை (ரூ./kg)',
            }),
            prefixText: 'Rs. ',
            prefixStyle: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: AppTheme.success,
            ),
            prefixIcon: const Icon(
              Icons.payments_outlined,
              color: AppTheme.success,
            ),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 12,
            ),
          ),
          onChanged: (text) {
            final parsed = double.tryParse(text.trim());
            if (parsed != null && parsed >= 0) {
              setState(() {
                _retailPrice = parsed;
                _result = null;
              });
            }
          },
        ),
        if (_selectedCrop != null) ...[
          const SizedBox(height: 8),
          GestureDetector(
            onTap: () => setState(() {
              final typical = _crops[_selectedCrop]!.typicalPriceLkr;
              _retailPrice = typical;
              _priceController.text = typical.toStringAsFixed(0);
              _result = null;
            }),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.restore,
                  size: 13,
                  color: AppTheme.primaryDark,
                ),
                const SizedBox(width: 4),
                Text(
                  _t({
                    'en':
                        'Use typical price for ${_cropLabel(_selectedCrop)} (Rs. ${_crops[_selectedCrop]!.typicalPriceLkr.toStringAsFixed(0)})',
                    'si':
                        '${_cropLabel(_selectedCrop)} සඳහා සාමාන්‍ය මිල භාවිතා කරන්න (රු. ${_crops[_selectedCrop]!.typicalPriceLkr.toStringAsFixed(0)})',
                    'ta':
                        '${_cropLabel(_selectedCrop)}-க்கான வழக்கமான விலையைப் பயன்படுத்தவும் (ரூ. ${_crops[_selectedCrop]!.typicalPriceLkr.toStringAsFixed(0)})',
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
                  'How strong demand was for this crop in recent weeks, on a Very Low → Very High scale.',
              'si':
                  'මෑත සති කිහිපයේදී මෙම භෝගයට තිබූ ඉල්ලුම, ඉතා අඩු → ඉතා ඉහළ පරිමාණයෙන්.',
              'ta':
                  'சமீபத்திய வாரங்களில் இந்த பயிருக்கு இருந்த தேவை, மிகக் குறைவு → மிக அதிகம் அளவில்.',
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
            showRawValue: true,
            levelLabel: _demandLevelLabel,
            divisions: 4,
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
            showRawValue: true,
            levelLabel: _demandLevelLabel,
            divisions: 4,
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
            showRawValue: true,
            levelLabel: _demandLevelLabel,
            divisions: 4,
          ),
          const SizedBox(height: 10),
          // ── What the number beside each band actually means ──────────────
          // Added because the bands alone ("Moderate") gave a farmer nothing
          // to reason about: they hid the index the model is given, and the
          // page never said how the RISING/STEADY/FALLING verdict follows
          // from it.
          //
          // Deliberately RELATIVE ("higher means stronger"), not absolute.
          // The model's own scale runs 0-200 centred on 100 = normal
          // (schemas.demand_lag1 is ge=0 le=200; recommend_service pins
          // _BASELINE_DEMAND_INDEX = 100.0; demand_service defaults
          // supply_index to "100.0 (neutral)"), but these sliders are
          // calibrated 0-150 with bands centred nearer 75 — so 100 renders
          // here as "High". Stating "100 is a normal week" would contradict
          // the label directly above it. Until the bands are re-centred, the
          // only honest framing is a relative one.
          //
          // The trend rule IS exact and is stated as such: demand_service
          // ._infer_trend classifies on predicted - demand_lag1, rising above
          // +5 and falling below -5.
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
            decoration: BoxDecoration(
              color: AppTheme.accents.demand.fill.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: AppTheme.accents.demand.fill.withValues(alpha: 0.18),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _t({
                    'en': 'How to read this scale',
                    'si': 'මෙම පරිමාණය කියවන්නේ කෙසේද',
                    'ta': 'இந்த அளவை எப்படி படிப்பது',
                  }),
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.accents.demand.ink,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  _t({
                    'en':
                        'The number beside each band is the demand index the forecast is given. '
                        'It is a comparison scale, not a quantity — a higher number means stronger '
                        'demand for this crop than a lower one, and only the gap between your weeks '
                        'matters.\n\n'
                        'Your result is shown as RISING when the forecast lands more than 5 points '
                        'above your "Last week" figure, FALLING when it lands more than 5 points '
                        'below it, and STEADY anywhere in between.',
                    'si':
                        'සෑම කාණ්ඩයක් අසල ඇති අංකය පුරෝකථනයට ලබා දෙන ඉල්ලුම් දර්ශකයයි. '
                        'එය ප්‍රමාණයක් නොව සංසන්දන පරිමාණයකි — වැඩි අංකයක් යනු අඩු අංකයකට වඩා '
                        'මෙම භෝගයට ශක්තිමත් ඉල්ලුමක් ඇති බවයි. වැදගත් වන්නේ ඔබේ සති අතර වෙනස පමණි.\n\n'
                        'පුරෝකථනය ඔබේ "පසුගිය සතිය" අගයට වඩා ලකුණු 5කට වැඩියෙන් ඉහළ නම් ප්‍රතිඵලය '
                        'ඉහළ යමින් ලෙසත්, ලකුණු 5කට වැඩියෙන් පහළ නම් පහළ යමින් ලෙසත්, '
                        'ඒ අතර නම් ස්ථාවර ලෙසත් පෙන්වයි.',
                    'ta':
                        'ஒவ்வொரு நிலைக்கும் அருகில் உள்ள எண் முன்னறிவிப்புக்கு வழங்கப்படும் தேவை '
                        'குறியீடு ஆகும். இது ஒரு அளவு அல்ல, ஒப்பீட்டு அளவுகோல் — அதிக எண் என்றால் '
                        'குறைந்த எண்ணை விட இந்த பயிருக்கு அதிக தேவை. உங்கள் வாரங்களுக்கு இடையிலான '
                        'வித்தியாசம் மட்டுமே முக்கியம்.\n\n'
                        'முன்னறிவிப்பு உங்கள் "கடந்த வாரம்" மதிப்பை விட 5 புள்ளிகளுக்கு மேல் இருந்தால் '
                        'உயர்கிறது எனவும், 5 புள்ளிகளுக்கு மேல் குறைவாக இருந்தால் குறைகிறது எனவும், '
                        'இடையில் இருந்தால் நிலையானது எனவும் காட்டப்படும்.',
                  }),
                  style: TextStyle(
                    fontSize: 11,
                    color: AppTheme.login.dividerText, // 8.25:1 on the card
                    height: 1.5,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          _slider(
            _t({
              'en': 'Price Trend (Inflation)',
              'si': 'මිල ප්‍රවණතාව (උද්ධමනය)',
              'ta': 'விலைப் போக்கு (பணவீக்கம்)',
            }),
            _inflationIndex,
            0.5,
            3.0,
            '',
            Colors.red,
            (v) => setState(() => _inflationIndex = v),
            levelLabel: _inflationLevelLabel,
            helperText: _t({
              'en':
                  'Shown as % change from a normal market — e.g. "+15% · Rising" means prices are about 15% above usual.',
              'si':
                  'සාමාන්‍ය වෙළඳපොළට සාපේක්ෂව % වෙනස ලෙස පෙන්වයි — උදා: "+15% · ඉහළ යයි" යනු මිල සාමාන්‍යයට වඩා 15%ක් පමණ ඉහළ බවයි.',
              'ta':
                  'சாதாரண சந்தையிலிருந்து % மாற்றமாக காட்டப்படுகிறது — எ.கா. "+15% · உயர்கிறது" என்றால் விலை வழக்கத்தை விட சுமார் 15% அதிகம்.',
            }),
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
            showRawValue: true,
            levelLabel: _interestLevelLabel,
            divisions: 3,
            helperText: _t({
              'en':
                  'How eager buyers/traders seem to be for this crop right now.',
              'si':
                  'මේ මොහොතේ ගැනුම්කරුවන්/වෙළෙන්දන් මෙම භෝගය සඳහා පෙන්වන උනන්දුව.',
              'ta':
                  'இப்போது வாங்குபவர்கள்/வர்த்தகர்கள் இந்த பயிருக்கு காட்டும் ஆர்வம்.',
            }),
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
            showRawValue: true,
            levelLabel: _interestLevelLabel,
            divisions: 3,
            helperText: _t({
              'en':
                  'How often people have been searching/asking about this crop online lately.',
              'si': 'මෑතකදී අන්තර්ජාලයේ මෙම භෝගය ගැන කොපමණ නිතර සොයා ඇත්දැයි.',
              'ta':
                  'சமீபத்தில் மக்கள் இணையத்தில் இந்த பயிரை எவ்வளவு அடிக்கடி தேடியுள்ளனர்.',
            }),
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
      // ── One documented exception to the app-wide primary-action rule ─────
      // Primary actions stay on AppTheme.login.primaryDark everywhere else,
      // including this page's own "Ask AI about this" block. This button uses
      // the demand accent instead, tying it to the header's dark anchor — the
      // same exception price_screen's Predict button and weather_screen's Get
      // Forecast button carry, granted the same way: by explicit request.
      //
      // Note what it REPLACES: a hardcoded #283593 indigo that predated the
      // accent system and matched no token at all. So this is an untracked
      // deviation becoming a tracked one, not a fresh one.
      //
      // White on #613298 measures 8.69:1 — the most margin of the three
      // accent-coloured action buttons in the app, and unlike price's (2.65:1)
      // and weather's (4.30:1) nothing is being accepted here.
      style: ElevatedButton.styleFrom(
        backgroundColor: AppTheme.accents.demand.fill,
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
  // Was three stacked containers running roughly a third of the page height
  // to show three values: a padding-20 gradient block with the index and
  // trend stacked vertically, a separate padding-14 verdict card, and a
  // separate button row below both.
  //
  // Now ONE card. The height came out of the container, not the type — the
  // 46px index, the 13px verdict and every label are the sizes they were.
  // What changed:
  //   • three containers -> one (two 14px gaps and two sets of padding gone)
  //   • index and trend badge sit SIDE BY SIDE instead of stacked
  //   • padding 20 -> 14, internal gaps 14/12 -> 10/6
  //
  // It also stops being a saturated gradient card. The page's other result
  // surfaces moved to a light card with dark text for exactly this reason
  // (see price_screen's own pass), and here it additionally fixes the
  // white-on-#F57F17 failure documented on _trendSteadyDeep — the trend
  // colour now appears only on the badge, which is the one place it carries
  // meaning.
  Widget _resultCard() {
    final trend = _result!.trend;
    final color = _trendColor(trend);
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '${_crops[_selectedCrop]?.emoji ?? ''}  ${_cropLabel(_selectedCrop)}',
                  style: const TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              if (_result!.isMock) const CsMockBadge(),
            ],
          ),
          const SizedBox(height: 10),
          // Index and trend on one line — this is where most of the removed
          // height came from.
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _result!.predictedDemandIndex.toStringAsFixed(0),
                    style: const TextStyle(
                      color: AppTheme.textPrimary,
                      fontSize: 46,
                      fontWeight: FontWeight.bold,
                      letterSpacing: -0.5,
                      height: 1.05,
                    ),
                  ),
                  Text(
                    _t({
                      'en': 'Demand Index',
                      'si': 'ඉල්ලුම් දර්ශකය',
                      'ta': 'தேவை குறியீடு',
                    }),
                    style: TextStyle(
                      color: AppTheme.login.dividerText,
                      fontSize: 12.5,
                    ),
                  ),
                ],
              ),
              const Spacer(),
              // White on the badge fill: 5.13:1 rising, 5.62:1 falling,
              // 4.58:1 steady (see _trendSteadyDeep).
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 7,
                ),
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(_trendIcon(trend), color: Colors.white, size: 16),
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
          const SizedBox(height: 12),
          Divider(height: 1, color: AppTheme.login.borderSubtle),
          const SizedBox(height: 10),
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
          const SizedBox(height: 6),
          Text(
            _verdict(trend),
            style: const TextStyle(
              fontSize: 13,
              color: AppTheme.textPrimary,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 12),
          // The "Ask AI" half of the old button row is gone from here — the
          // five-chip _askAiBlock below the card replaces it, so this card
          // carries only the cross-navigation action.
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _openPriceForecast,
              icon: const Icon(Icons.payments, size: 16),
              label: Text(
                _t({
                  'en': 'Check Price Forecast',
                  'si': 'මිල පුරෝකථනය බලන්න',
                  'ta': 'விலை முன்னறிவிப்பைப் பார்க்கவும்',
                }),
                style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                ),
                overflow: TextOverflow.ellipsis,
              ),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppTheme.accents.demand.ink,
                side: BorderSide(color: AppTheme.accents.demand.fill),
                padding: const EdgeInsets.symmetric(vertical: 10),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Price-forecast handoff ───────────────────────────────────────────────
  /// Carry this forecast's crop and season over to the Price screen, so the
  /// farmer only has to tap Predict rather than re-entering both.
  ///
  /// Published through [pricePrefill], the twin of the [predictionHandoff]
  /// channel this screen's "Ask AI about this" block uses — same single-slot,
  /// consume-once ValueNotifier shape, for the same reason (main.dart builds
  /// the seven screens once and crossfades, so constructor arguments are not
  /// available and a rebuild would discard live state).
  ///
  /// Was a bare `onNavigate(2)`: it switched tabs and carried nothing, so the
  /// farmer arrived at an empty Price form having just told this page the two
  /// values it needs.
  void _openPriceForecast() {
    pricePrefill.value = PricePrefill(
      crop: _selectedCrop,
      season: _selectedSeason,
    );
    widget.onNavigate?.call(2); // Price tab
  }

  // ── Chat handoff ─────────────────────────────────────────────────────────
  /// The whole forecast, structured, for the chat screen to reason over.
  ///
  /// Note what is NOT here: a district. This screen never collects one, so
  /// the handoff sets crop and leaves district null — the reverse of a
  /// weather handoff. The backend's confirmation gate reads crop off
  /// prediction_context ahead of any saved profile, so the forecast's crop
  /// always wins and only the district is ever confirmed back to the farmer.
  ///
  /// [realMarketData] is sent in both states on purpose. A demand index built
  /// from the per-crop typical defaults is a much weaker claim than one built
  /// from the farmer's own figures, and an assistant told nothing would
  /// present them identically.
  PredictionContext _predictionContext() => PredictionContext(
    crop: _selectedCrop,
    season: _selectedSeason,
    retailPriceLkrKg: _retailPrice,
    holidayWeek: _holidayFlag == 1,
    festivalWeek: _festivalFlag == 1,
    realMarketData: _marketDataOpen,
    predictedDemandIndex: _result?.predictedDemandIndex,
    demandTrend: _result?.trend,
    confidence: _result?.confidence,
  );

  /// Publish to the chat screen and switch to the AI Chat tab — the same
  /// single-slot, consume-once ValueNotifier every other feature page uses,
  /// so the context persists for follow-up questions in that conversation
  /// rather than only decorating the first message.
  ///
  /// This REPLACES the screen's old `onAiChatContext` handoff, which built a
  /// hand-written trilingual sentence naming the crop, index and season and
  /// pushed it in as the farmer's visible message. That is the pattern every
  /// other page has already migrated off: chat analytics logged the generated
  /// paragraph instead of the farmer's own question, and nothing structured
  /// reached the model.
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
  /// primaryDark, not the demand accent: these are primary actions, and the
  /// accent rules keep those consistent app-wide.
  ButtonStyle get _askAiButtonStyle => ElevatedButton.styleFrom(
    backgroundColor: AppTheme.login.primaryDark,
    foregroundColor: Colors.white,
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    elevation: 2,
  );

  /// The demand questions live HERE, on the result, not on an otherwise blank
  /// chat screen — the farmer picks what they want to know while still
  /// looking at the index, and the answer is already being written by the
  /// time the chat tab finishes opening.
  ///
  /// Four starter chips plus the free-form button, the same five-action shape
  /// recommend_screen uses. Only the short visible text is sent as the
  /// message; the crop, season, price entered, holiday/festival flags,
  /// whether real market data was supplied, the index and the trend all ride
  /// invisibly in prediction_context.
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
          for (final q in kDemandStarters)
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

  /// Shown in place of the empty placeholder while a prediction is in
  /// flight — the result card is text-heavy (headline demand figure +
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
    bool showRawValue = false,
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
                    ? '${value.toStringAsFixed(max <= 3 ? 2 : 0)} $unit'.trim()
                    // The band alone ("Moderate") is not something a farmer
                    // can act on or re-enter — it hides the one number the
                    // model is actually given. showRawValue puts it back
                    // beside the band without replacing it, so the plain-
                    // language reading stays primary.
                    : showRawValue
                    ? '${levelLabel(value)}  ·  ${value.toStringAsFixed(0)}'
                    : levelLabel(value),
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
