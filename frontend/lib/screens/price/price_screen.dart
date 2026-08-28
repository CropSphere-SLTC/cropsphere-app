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
import '../../services/prediction_handoff.dart';
import '../../services/price_prefill.dart';
import '../../services/service_factory.dart';
import '../../widgets/animated_lang_text.dart';
import '../../widgets/app_theme.dart';
import '../../widgets/app_top_bar.dart';
import '../../widgets/followup_chip.dart';
import '../../widgets/localized_names.dart';
import '../../widgets/searchable_dropdown.dart';
import '../../widgets/skeleton_loading.dart';

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

class _PriceScreenState extends State<PriceScreen> {
  // ── Selections ─────────────────────────────────────────────────────────────
  String? _selectedCrop;
  String? _selectedDistrict;
  String? _selectedSeason;
  String _supplyKey = 'normal';
  String _demandKey = 'normal';
  int _holidayFlag = 0;
  int _festivalFlag = 0;

  final _qtyCtrl = TextEditingController(text: '100');

  // ── Searchable dropdown text state ─────────────────────────────────────────
  // Crop and District are type-to-filter (RawAutocomplete). Controllers are
  // owned HERE, not left to RawAutocomplete, for the same reason as the yield
  // screen: the "district resets when crop changes" rule has to reach into the
  // text field, which the widget's internal controller wouldn't allow.
  final _cropSearchCtrl = TextEditingController();
  final _districtSearchCtrl = TextEditingController();
  final _cropFocus = FocusNode();
  final _districtFocus = FocusNode();

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

  /// Placeholder for every SearchableDropdown on this screen.
  String get _searchHint => _t({
    'en': 'Type to search',
    'si': 'සෙවීමට ටයිප් කරන්න',
    'ta': 'தேட தட்டச்சு செய்க',
  });

  @override
  void initState() {
    super.initState();
    pricePrefill.addListener(_onPricePrefill);
    // A pre-fill can already be waiting when this screen first mounts (the
    // demand screen published one before the price tab had ever been built).
    //
    // Deferred to after the first frame, NOT applied inline: setState() is
    // illegal in initState, and _applyPrefill reads _langKey, which resolves
    // AppLangProvider through dependOnInheritedWidgetOfExactType — also
    // illegal here, and an assertion failure rather than a silent one. Same
    // deferral chat_screen uses for its own handoff question.
    final pending = pricePrefill.value;
    if (pending != null) {
      pricePrefill.value = null;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _applyPrefill(pending));
      });
    }
    _cropFocus.addListener(
      () => syncSearchField(
        _cropFocus,
        _cropSearchCtrl,
        cropLabel(_langKey, _selectedCrop),
      ),
    );
    _districtFocus.addListener(
      () => syncSearchField(
        _districtFocus,
        _districtSearchCtrl,
        districtLabel(_langKey, _selectedDistrict),
      ),
    );
  }

  /// Picks up a crop/season carried over from a demand forecast's "Check
  /// Price Forecast" button.
  ///
  /// Consume-once — the channel is reset to null immediately, so returning to
  /// the price tab later doesn't silently re-apply a stale crop over something
  /// the farmer has since changed.
  ///
  /// Deliberately does NOT predict. The farmer arrives with both fields
  /// filled and taps Predict themselves, which is the whole point of the
  /// hand-off: it removes the re-typing, not the decision.
  void _onPricePrefill() {
    final pending = pricePrefill.value;
    if (pending == null) return;
    // Cleared BEFORE any work, for the same reason chat_screen clears
    // predictionHandoff first: assigning re-enters this listener
    // synchronously, and the re-entrant call must find null and return.
    pricePrefill.value = null;
    if (!mounted) return;
    setState(() => _applyPrefill(pending));
  }

  /// Writes the pre-filled values into this screen's own state.
  ///
  /// Not wrapped in setState itself — both callers supply their own, and both
  /// call it from somewhere `context` is safe to read (see initState).
  ///
  /// District is deliberately left alone. Demand collects none, and this
  /// screen's crop -> district dependency means a crop change normally CLEARS
  /// the district; so a pre-filled crop that differs from what is already
  /// selected has to clear it here too, or the form would carry a district
  /// that no longer belongs to the crop shown above it.
  void _applyPrefill(PricePrefill p) {
    if (p.crop != null && _cropDistricts.containsKey(p.crop)) {
      if (_selectedCrop != p.crop) {
        _selectedDistrict = null;
        _districtSearchCtrl.clear();
      }
      _selectedCrop = p.crop;
      // The searchable field shows committed text, so it has to be told —
      // _syncSearchField only runs on focus changes, and this is neither.
      _cropSearchCtrl.text = cropLabel(_langKey, p.crop);
    }
    if (p.season != null && _seasons.any((s) => s['name']!['en'] == p.season)) {
      _selectedSeason = p.season;
    }
    _result = null;
  }

  @override
  void dispose() {
    pricePrefill.removeListener(_onPricePrefill);
    _cropSearchCtrl.dispose();
    _districtSearchCtrl.dispose();
    _cropFocus.dispose();
    _districtFocus.dispose();
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
  double get _estimatedRevenue =>
      (_result?.predictedFarmgatePriceLkrKg ?? 0) * _quantity;

  // NOT AppTheme.warning for 'medium' — that shared token measured 2.56:1
  // against this card's background, under even the lenient 3:1 non-text
  // floor for the small confidence dot. Darkened locally, here only, so
  // other screens that use the shared token are unaffected.
  static const Color _confWarningDeep = Color(0xFFE6710A); // 3.0:1 on FCFBF6

  Color _confColor(String c) => switch (c.toLowerCase()) {
    'high' => AppTheme.success,
    'medium' => _confWarningDeep,
    _ => AppTheme.error,
  };

  // ── AI chat handoff ────────────────────────────────────────────────────────
  /// The numbers this conversation is about, sent invisibly on every request
  /// in the resulting conversation.
  ///
  /// The average is attached ONLY when the backend attributed one. A null
  /// source means no baseline was reported, and the same contract that keeps
  /// the badge off the card keeps the figure out of the prompt — otherwise
  /// the assistant would happily reason about a baseline the screen itself
  /// declined to state.
  PredictionContext _predictionContext() {
    final r = _result;
    final farmgate = r?.predictedFarmgatePriceLkrKg;
    final qty = _quantity;
    final hasAvg = r?.hasAverage == true;
    return PredictionContext(
      crop: _selectedCrop,
      district: _selectedDistrict,
      season: _selectedSeason,
      predictedPriceLkrKg: farmgate,
      averagePriceLkrKg: hasAvg ? r!.averageFarmgatePriceLkrKg : null,
      averagePriceSource: hasAvg
          ? _sourceWireValue(r!.averagePriceSource)
          : null,
      quantityKg: qty > 0 ? qty : null,
      estimatedEarningsLkr: (farmgate != null && qty > 0)
          ? farmgate * qty
          : null,
      supplyLevel: _supplyKey,
      demandLevel: _demandKey,
      holidayWeek: _holidayFlag == 1,
      festivalWeek: _festivalFlag == 1,
      confidence: r?.confidence,
    );
  }

  /// The backend accepts 'real' | 'synthetic' | absent. [AveragePriceSource
  /// .unknown] maps to null so the field is omitted from the request body.
  static String? _sourceWireValue(AveragePriceSource s) => switch (s) {
    AveragePriceSource.real => 'real',
    AveragePriceSource.synthetic => 'synthetic',
    AveragePriceSource.unknown => null,
  };

  /// Publish the prediction to the chat screen and switch to the AI Chat tab.
  ///
  /// Identical mechanism to the yield screen: a single-slot, consume-once
  /// ValueNotifier, so neither screen's constructor changes and the tab switch
  /// stays a pure crossfade. [question] is the chip the farmer tapped, which
  /// the chat screen sends as the conversation's first message; omitted for
  /// the free-form button.
  void _askAi({String? question}) {
    if (_result == null) return;
    predictionHandoff.value = PredictionHandoff(
      _predictionContext(),
      question: question,
    );
    widget.onNavigate?.call(6); // AI Chat tab
  }

  /// Shared styling for every action in the "Ask AI about this" block — the
  /// four quick questions and the free-form button all open the same grounded
  /// conversation, so they read as one class of action.
  ///
  /// primaryDark, not the price accent: these are primary actions, and the
  /// accent rules keep those consistent app-wide.
  ButtonStyle get _askAiButtonStyle => ElevatedButton.styleFrom(
    backgroundColor: AppTheme.login.primaryDark,
    foregroundColor: Colors.white,
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    elevation: 2,
  );

  /// The four price questions live HERE, on the result, not on an otherwise
  /// blank chat screen — the farmer picks what they want to know while still
  /// looking at the numbers, and the answer is already being written by the
  /// time the chat tab finishes opening.
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
          for (final q in kPriceStarters)
            ElevatedButton(
              // Only the short visible text is sent as the message; the
              // numbers ride along in prediction_context, so chat analytics
              // keeps logging the farmer's own question and nothing else.
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
      // Content-width, not double.infinity: this is the free-form fallback
      // under four already-sized starter chips, not a primary action — it
      // was spanning the full card like the Predict button above it.
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

  // ── WhatsApp share ─────────────────────────────────────────────────────────
  Future<void> _shareOnWhatsApp() async {
    if (_result == null) return;
    final farmgate = _result!.predictedFarmgatePriceLkrKg.toStringAsFixed(0);
    final retail = _result!.predictedRetailPriceLkrKg.toStringAsFixed(0);
    final cropEn = cropLabel('en', _selectedCrop);
    final cropSi = cropLabel('si', _selectedCrop);
    final cropTa = cropLabel('ta', _selectedCrop);
    final distEn = districtLabel('en', _selectedDistrict);
    final distSi = districtLabel('si', _selectedDistrict);
    final distTa = districtLabel('ta', _selectedDistrict);
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
            _buildTopBar(context),
            Expanded(child: _buildDetailsTab(w)),
          ],
        );
      },
    );
  }

  // ── Details tab — resizes for mobile / tablet / web ────────────────────────
  Widget _buildDetailsTab(double width) {
    // 1024 is the two-column threshold, same as the yield page: below it the
    // page stacks into ONE column (header -> inputs -> Predict -> result)
    // rather than squeezing a result panel alongside the form.
    if (width >= 1024) return _buildWebDetails(width);
    if (width >= 600) return _buildTabletDetails(width);
    return _buildMobileDetails(width);
  }

  // Bottom padding 180, not the usual 100: below 1024px MainShell overlays
  // FloatingBottomNav (64px capsule + 10px margin + safe area — 100px is
  // that clearance alone, see yield_screen's _buildMobileLayout). Price ALSO
  // pins its OWN _stickyPredict bar to the same bottom:0 on top of that
  // (10+52+14 = 76px), so the two floating bars stack and 100px alone still
  // left the tail of "Ask AI about this" behind them. +80 clears both.
  Widget _buildMobileDetails(double width) {
    final bool isSmall = width < 340;
    final double hPad = isSmall ? 12 : 14;
    return Stack(
      children: [
        SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(hPad, 14, hPad, 180),
          child: _formColumn(),
        ),
        _stickyPredict(),
      ],
    );
  }

  // 600–960dp portrait/landscape tablets: content width and side padding
  // scale with the real viewport instead of one fixed max-width.
  //
  // Bottom padding 180 for the same reason as _buildMobileDetails: this
  // Stack's own _stickyPredict bar and MainShell's FloatingBottomNav both
  // pin to bottom:0 here, so the clearance has to cover both, not just one.
  Widget _buildTabletDetails(double width) {
    final targetContentW = width < 760 ? width - 32 : 680.0;
    final hPad = ((width - targetContentW) / 2).clamp(16.0, 220.0);
    return Stack(
      children: [
        SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(hPad, 14, hPad, 180),
          child: _formColumn(),
        ),
        _stickyPredict(),
      ],
    );
  }

  // Web (≥1024dp): inputs on the left, prediction result on the right.
  Widget _buildWebDetails(double width) {
    // Matches yield_screen.dart's _buildWebLayout exactly (same fraction,
    // same clamp) — the two pages had drifted to different formulas
    // (0.4/340–480 here vs 0.44/360–560 there), so their left columns sat at
    // visibly different widths at the same viewport size.
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
              _stickyPredict(),
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

  // ── Top bar ────────────────────────────────────────────────────────────────
  // This screen used to be the ONE screen with its own separate, hand-tuned
  // mobile bar (different height, logo size, a hand-rolled "CropSphere" text,
  // default-sized language/theme/avatar controls, none of it wired to
  // TopNavMetrics) — the exact drift app_top_bar.dart exists to end. `width`
  // is no longer needed: AppTopBar handles every breakpoint itself.
  Widget _buildTopBar(BuildContext context) => AppTopBar(
    activeIndex: 2,
    activeBg: AppTheme.accents.price.fill.withValues(alpha: 0.16),
    activeColor: AppTheme.accents.price.ink,
    onNavigate: widget.onNavigate,
  );

  // ── Form column — Crop/Location, Market Conditions, Quantity only; ────────
  //    Selling Tips now lives in its own tab, which is what keeps this
  //    column short enough to fit without a forced scroll on web/tablet.
  Widget _formColumn({bool webLeft = false}) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _pageHeader(),
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
          'en': 'Quantity to Sell',
          'si': 'විකිණීමට ප්‍රමාණය',
          'ta': 'விற்பனை அளவு',
        }),
        Icons.scale,
      ),
      const SizedBox(height: 10),
      _quantityCard(),
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
      // Single-column (<1024dp): the result follows the inputs. The Predict
      // button itself stays pinned in the sticky bar over this scroll view.
      if (!webLeft) ...[
        const SizedBox(height: 16),
        if (_isLoading) _resultSkeleton(),
        if (_errorMessage != null) _errorCard(),
        if (_result != null) _resultCard(),
      ],
    ],
  );

  Widget _rightPanel() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      if (_isLoading) ...[_resultSkeleton(), const SizedBox(height: 14)],
      if (_errorMessage != null) ...[_errorCard(), const SizedBox(height: 14)],
      if (_result != null) ...[_resultCard(), const SizedBox(height: 14)],
      if (_result == null && _errorMessage == null && !_isLoading)
        _emptyResultPlaceholder(),
    ],
  );

  // Header gradient's lighter stop. Not part of AppFeatureAccents.price
  // (which stays the single flat identity colour used everywhere else on
  // this page — nav pill, badges) — this is a header-local extension of it,
  // same precedent as yield_screen's own gradient (primaryDark -> primary),
  // which also isn't part of the shared accent system.
  //
  // +0.15 lightness in HLS from the dark anchor, hue/saturation preserved —
  // widened from an earlier +0.035 step (#E29467), which sat close enough
  // to the dark anchor that the gradient read as visually flat. +0.20 was
  // also tried and rejected: it starts blending into the page's own
  // background (#FCFBF6) at the lightest corner. Still does NOT clear AA
  // for white text — see AppFeatureAccents.price's doc comment for why the
  // dark anchor itself is a known, accepted failure too.
  static const Color _headerGradientLight = Color(0xFFEBB798);

  // ── Page header ────────────────────────────────────────────────────────────
  // Gradient, matching yield_screen's header treatment: darker (top-left) to
  // lighter (bottom-right). #DF8A58 is the dark anchor — the SAME value as
  // AppTheme.accents.price.fill.
  //
  // KNOWN, ACCEPTED CONTRAST FAILURE: white text/icons on this header do
  // NOT clear AA — see AppFeatureAccents.price's doc comment for the full
  // history and the numbers. Left as white anyway, by explicit request,
  // after being shown the failing contrast each time (fill, gradient light
  // stop, icon badge, and the Predict Price button below all inherit it).
  Widget _pageHeader() => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      gradient: LinearGradient(
        colors: [AppTheme.accents.price.fill, _headerGradientLight],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
      borderRadius: BorderRadius.circular(14),
      boxShadow: [
        BoxShadow(
          color: AppTheme.accents.price.fill.withValues(alpha: 0.3),
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
            // 2.79-4.03:1 on this glass panel — still under AA, though
            // better than 1.79-2.65:1 sitting directly on the gradient.
            // Known, accepted — see _glassBadge's own comment.
            _navSvg(2, AppTheme.accents.price.onFill),
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
                style: TextStyle(
                  // 2.65:1 (dark end) to 1.79:1 (light end) — fails even the
                  // 3:1 large-text floor across the whole gradient. Known,
                  // accepted — see _pageHeader's own comment above. Sits
                  // directly on the gradient, not on the glass panel — only
                  // the icon badge and Week pill get that treatment.
                  color: AppTheme.accents.price.onFill,
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
                  // Same failure as the title, worse: this needs the 4.5:1
                  // normal-text floor, not 3:1, and gets nowhere near it.
                  color: AppTheme.accents.price.onFill,
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
              color:
                  AppTheme.accents.price.onFill, // 2.79-4.03:1, known/accepted
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    ),
  );

  /// Glass panel — the icon badge and "Week N" pill. A translucent black
  /// tint with a faint white edge as the glass highlight.
  ///
  /// NOT a BackdropFilter blur, deliberately — a first version used one,
  /// but blurring a smooth two-colour gradient is visually imperceptible;
  /// there is no texture behind this panel for a blur to act on, so it
  /// only ever rendered as whatever the tint's own opacity looked like.
  /// Removed rather than kept as decoration that does nothing.
  ///
  /// KNOWN, ACCEPTED CONTRAST FAILURE. 0.20 alpha, by explicit request, for
  /// a genuinely see-through panel — the gradient visibly shows through it,
  /// which is the actual "glass" cue here, not blur. That transparency
  /// comes at a real cost: white icon/text on this panel measures
  /// 2.79-4.03:1 across the gradient, under the 4.5:1 text floor (though
  /// the badge/pill SHAPE itself stays clearly visible — the white border
  /// keeps a crisp edge regardless of the fill's own contrast). A darker,
  /// AA-passing version of this same panel existed at 0.40 alpha
  /// (4.65-6.36:1) — see git history for this file around "frosted glass"
  /// if this needs to be legible again.
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

  // ── Crop & location card ───────────────────────────────────────────────────
  Widget _cropLocationCard() => _card(
    child: Column(
      children: [
        SearchableDropdown(
          label: _t({
            'en': 'Select Crop',
            'si': 'භෝගය තෝරන්න',
            'ta': 'பயிர் தேர்ந்தெடுக்கவும்',
          }),
          value: _selectedCrop,
          items: _cropDistricts.keys.toList(),
          icon: Icons.eco,
          accent: AppTheme.accents.price,
          searchHint: _searchHint,
          itemLabel: (c) => cropLabel(_langKey, c),
          controller: _cropSearchCtrl,
          focusNode: _cropFocus,
          onChanged: (val) {
            // Same reset as before, but the district's TEXT has to be cleared
            // too now — the searchable field would otherwise keep displaying a
            // district that no longer applies to the newly-chosen crop.
            _districtSearchCtrl.clear();
            setState(() {
              _selectedCrop = val;
              _selectedDistrict = null;
              _result = null;
            });
          },
        ),
        const SizedBox(height: 12),
        SearchableDropdown(
          label: _t({
            'en': 'Select District',
            'si': 'දිස්ත්‍රික්කය',
            'ta': 'மாவட்டம்',
          }),
          value: _selectedDistrict,
          items: _availableDistricts,
          icon: Icons.location_on,
          accent: AppTheme.accents.price,
          searchHint: _searchHint,
          itemLabel: (d) => districtLabel(_langKey, d),
          controller: _districtSearchCtrl,
          focusNode: _districtFocus,
          hint: _selectedCrop != null
              ? _t({
                  'en': 'Valid districts for ${cropLabel('en', _selectedCrop)}',
                  'si': '${cropLabel('si', _selectedCrop)} සඳහා දිස්ත්‍රික්ක',
                  'ta': '${cropLabel('ta', _selectedCrop)}-க்கான மாவட்டங்கள்',
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
                  'Recent price for ${cropLabel('en', _selectedCrop)}: Rs. ${_recentPrice.toStringAsFixed(0)}/kg',
              'si':
                  '${cropLabel('si', _selectedCrop)} සඳහා මෑත මිල: රු. ${_recentPrice.toStringAsFixed(0)}/kg',
              'ta':
                  '${cropLabel('ta', _selectedCrop)}-க்கான சமீபத்திய விலை: Rs. ${_recentPrice.toStringAsFixed(0)}/kg',
            }),
            color: AppTheme.accents.price.ink,
            icon: Icons.history,
          ),
        ],
      ],
    ),
  );

  Widget _seasonDropdown() {
    return DropdownButtonFormField<String>(
      initialValue: _selectedSeason,
      // Required once this field gained a suffix tick: the items read
      // "Maha  ·  October – March", and without isExpanded the menu item sizes
      // to its intrinsic width and overflows the narrowed field instead of
      // ellipsising inside it.
      isExpanded: true,
      hint: Text(
        _t({'en': 'Select Season', 'si': 'කන්නය', 'ta': 'பருவம்'}),
        style: TextStyle(color: AppTheme.login.textSecondary),
      ),
      decoration: InputDecoration(
        labelText: _t({'en': 'Season', 'si': 'කන්නය', 'ta': 'பருவம்'}),
        labelStyle: TextStyle(color: AppTheme.login.textSecondary),
        prefixIcon: Icon(
          Icons.calendar_month,
          color: AppTheme.accents.price.ink,
          size: 20,
        ),
        // Season stays a plain dropdown, but carries the same inline tick as
        // the two searchable fields so all three required inputs report their
        // state identically.
        suffixIconConstraints: const BoxConstraints(minWidth: 0, minHeight: 0),
        suffixIcon: Padding(
          padding: const EdgeInsets.only(right: 6),
          child: fieldCheckIcon(_selectedSeason != null),
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
          borderSide: BorderSide(color: AppTheme.login.focusRing, width: 2),
        ),
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
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: AppTheme.login.textPrimary,
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
          color: AppTheme.accents.price.ink,
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
            color: AppTheme.accents.price.fill.withValues(alpha: 0.18),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(Icons.scale, color: AppTheme.accents.price.ink, size: 22),
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
                style: TextStyle(
                  fontSize: 11.5,
                  color: AppTheme.login.textSecondary,
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
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.accents.price.ink,
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

  // ── Sticky predict button ──────────────────────────────────────────────────
  Widget _stickyPredict() => Positioned(
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
            // By request, an explicit exception to the app-wide rule that
            // primary actions stay on login.primaryDark (still true for
            // every other screen, and for Price's own "Ask AI about this"
            // actions — see _askAiButtonStyle). This button uses the price
            // accent instead, tying it to the header's dark gradient anchor
            // (the same fill colour). KNOWN, ACCEPTED CONTRAST FAILURE:
            // white on #DF8A58 is 2.65:1, same failure as the header — see
            // AppFeatureAccents.price's doc comment in app_theme.dart.
            style: ElevatedButton.styleFrom(
              backgroundColor: _canPredict
                  ? AppTheme.accents.price.fill
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
  /// Thousands separator. `intl` is not a dependency here, and pulling it in
  /// for one grouping rule would be a heavy way to place three commas.
  static String _grouped(double v) {
    final digits = v.round().abs().toString();
    final buf = StringBuffer(v < 0 ? '-' : '');
    for (var k = 0; k < digits.length; k++) {
      if (k > 0 && (digits.length - k) % 3 == 0) buf.write(',');
      buf.write(digits[k]);
    }
    return buf.toString();
  }

  /// Below this, a gap is noise at the model's precision. Calling a 1%
  /// difference "above average — sell now" would dress rounding up as advice.
  static const double _kFlatBandPct = 3.0;

  // ──────────────────────────────────────────────────────────────────────────
  //  Result card — price, comparison against the crop average, earnings,
  //  and the handoff into a grounded chat.
  //
  //  The old rising/falling banner is gone deliberately. It measured against
  //  `_recentPrice` (the lag seed), while the comparison below measures
  //  against the backend's crop average — two different baselines that can
  //  disagree, so the card could show "✅ Prices Rising" directly above bars
  //  reading "below average". One baseline, stated once.
  // ──────────────────────────────────────────────────────────────────────────
  Widget _resultCard() {
    final r = _result!;
    final farmgate = r.predictedFarmgatePriceLkrKg;
    final average = r.averageFarmgatePriceLkrKg;
    // hasAverage already folds in the null-source contract: no baseline, or a
    // source the backend would not attribute, means no comparison is drawn.
    final showComparison = r.hasAverage;

    final diffPct = showComparison && average > 0
        ? (farmgate - average) / average * 100
        : 0.0;
    final above = diffPct >= 0;
    final magnitude = diffPct.abs();
    final isFlat = magnitude < _kFlatBandPct;

    final verdict = !showComparison || isFlat
        ? AppTheme.login.textSecondary
        : (above ? AppTheme.success : AppTheme.login.errorMuted);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: AppTheme.login.background,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppTheme.login.borderSubtle, width: 1.4),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── (1) Predicted farmgate price ───────────────────────────────
              Row(
                children: [
                  Expanded(
                    child: Text(
                      _t({
                        'en': 'Predicted farmgate price',
                        'si': 'පුරෝකථිත ගොවිපොළ මිල',
                        'ta': 'கணிக்கப்பட்ட பண்ணை விலை',
                      }),
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.login.textSecondary,
                      ),
                    ),
                  ),
                  if (r.isMock)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: AppTheme.login.borderSubtle,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        'MOCK DATA',
                        style: TextStyle(
                          // textSecondary measured 3.66:1 on borderSubtle —
                          // under AA. dividerText clears 6.65:1 there.
                          color: AppTheme.login.dividerText,
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 6),
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text(
                    'Rs. ${_grouped(farmgate)}',
                    style: TextStyle(
                      fontSize: 34,
                      fontWeight: FontWeight.w800,
                      height: 1.0,
                      color: AppTheme.login.textPrimary,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    '/kg',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.login.textSecondary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                _t({
                  'en':
                      'Retail estimate Rs. ${_grouped(r.predictedRetailPriceLkrKg)}/kg',
                  'si':
                      'සිල්ලර ඇස්තමේන්තුව රු. ${_grouped(r.predictedRetailPriceLkrKg)}/kg',
                  'ta':
                      'சில்லறை மதிப்பீடு Rs. ${_grouped(r.predictedRetailPriceLkrKg)}/kg',
                }),
                style: TextStyle(
                  fontSize: 11.5,
                  color: AppTheme.login.textSecondary,
                ),
              ),

              // ── (2) Two-bar comparison + interpretation ────────────────────
              if (showComparison) ...[
                const SizedBox(height: 16),
                // Capped and centred: on a wide desktop right column the card
                // can be 800px+, and two skinny bars edge-to-edge across that
                // just reads as empty space with numbers floating in it.
                Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 640),
                    child: _comparisonBars(farmgate, average, verdict),
                  ),
                ),
                const SizedBox(height: 12),
                // Icon as well as colour — a verdict must never be carried by
                // colour alone.
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      isFlat
                          ? Icons.remove_rounded
                          : (above
                                ? Icons.arrow_upward_rounded
                                : Icons.arrow_downward_rounded),
                      size: 16,
                      color: verdict,
                    ),
                    const SizedBox(width: 5),
                    Expanded(
                      child: Text(
                        _interpretation(magnitude, above, isFlat),
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          height: 1.35,
                          color: verdict,
                        ),
                      ),
                    ),
                  ],
                ),
                // ── (3) Source badge — omitted entirely for an unknown
                //     source. No fallback text, no implied label.
                ..._sourceBadge(r.averagePriceSource),
              ],

              const SizedBox(height: 16),
              Divider(color: AppTheme.login.borderSubtle, height: 1),
              const SizedBox(height: 14),

              // ── (4) Total earnings — live off the quantity field ───────────
              _earningsRow(farmgate),

              const SizedBox(height: 14),
              Row(
                children: [
                  Icon(Icons.circle, size: 9, color: _confColor(r.confidence)),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      _confidenceLine(r.confidence),
                      style: TextStyle(
                        // textSecondary measured 4.39:1 here — a hair under
                        // AA. dividerText is the verified alternative.
                        color: AppTheme.login.dividerText,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  color: AppTheme.accents.price.fill.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _rStat(
                      _t({'en': 'Crop', 'si': 'භෝගය', 'ta': 'பயிர்'}),
                      cropLabel(_langKey, r.crop),
                    ),
                    _vDiv(),
                    _rStat(
                      _t({
                        'en': 'District',
                        'si': 'දිස්ත්‍රික්කය',
                        'ta': 'மாவட்டம்',
                      }),
                      districtLabel(_langKey, _selectedDistrict),
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
        // Pre-existing WhatsApp share feature, kept and restyled rather than
        // removed. Content-width now, not double.infinity: a full-bleed
        // button read as a primary action (same width as Predict), when
        // this is a secondary one — the four starter chips below already
        // show what content-width secondary actions look like on this card.
        OutlinedButton.icon(
          onPressed: _shareOnWhatsApp,
          icon: Icon(Icons.share, size: 17, color: AppTheme.login.primaryDark),
          label: Text(
            _t({'en': 'Share', 'si': 'බෙදාගන්න', 'ta': 'பகிரவும்'}),
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: AppTheme.login.primaryDark,
            ),
          ),
          style: OutlinedButton.styleFrom(
            backgroundColor: AppTheme.login.primaryDark.withValues(alpha: 0.07),
            side: BorderSide(color: AppTheme.login.primaryDark, width: 1.5),
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),

        // ── (5) Ask AI about this ──────────────────────────────────────────
        const SizedBox(height: 16),
        _askAiBlock(),
      ],
    );
  }

  /// Two bars: this week's predicted price against the crop's average.
  ///
  /// Bars are labelled with their values and their categories in text, so the
  /// comparison survives without colour. Scaled to the larger of the two with
  /// headroom, and floored at a visible height so a very low prediction still
  /// reads as a bar rather than a missing one.
  Widget _comparisonBars(double predicted, double average, Color verdict) {
    const plotH = 104.0;
    final peak = (predicted > average ? predicted : average);
    final scale = peak > 0 ? peak * 1.12 : 1.0;
    double h(double v) => ((v / scale) * plotH).clamp(6.0, plotH);

    Widget bar(String caption, double value, Color color, bool emphasised) =>
        Expanded(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Rs. ${_grouped(value)}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: emphasised ? FontWeight.w800 : FontWeight.w600,
                  color: emphasised
                      ? AppTheme.login.textPrimary
                      : AppTheme.login.textSecondary,
                ),
              ),
              const SizedBox(height: 5),
              Container(
                height: h(value),
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(6),
                  ),
                  border: emphasised
                      ? null
                      : Border.all(color: AppTheme.login.borderSubtle),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                caption,
                maxLines: 2,
                textAlign: TextAlign.center,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 10.5,
                  height: 1.25,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.login.textSecondary,
                ),
              ),
            ],
          ),
        );

    return SizedBox(
      height: plotH + 46,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          const SizedBox(width: 8),
          bar(
            _t({
              'en': 'Your prediction',
              'si': 'ඔබේ පුරෝකථනය',
              'ta': 'உங்கள் கணிப்பு',
            }),
            predicted,
            verdict,
            true,
          ),
          const SizedBox(width: 22),
          bar(
            _t({
              'en': 'Crop average',
              'si': 'භෝග සාමාන්‍යය',
              'ta': 'பயிர் சராசரி',
            }),
            average,
            // NOT borderSubtle — that's a 1.20:1 divider token, invisible
            // against this same card background. textSecondary reads as
            // "neutral reference" against the verdict-coloured prediction
            // bar, at a real 4.39:1.
            AppTheme.login.textSecondary,
            false,
          ),
          const SizedBox(width: 8),
        ],
      ),
    );
  }

  String _interpretation(double magnitude, bool above, bool isFlat) {
    final pct = magnitude.round();
    if (isFlat) {
      return _t({
        'en': 'About average for this crop — no strong signal either way.',
        'si': 'මෙම භෝගය සඳහා සාමාන්‍ය මට්ටමේ — පැහැදිලි සංඥාවක් නැත.',
        'ta': 'இந்தப் பயிருக்கு சராசரி அளவில் — தெளிவான சமிக்ஞை இல்லை.',
      });
    }
    if (above) {
      return _t({
        'en': '$pct% above average — a good time to sell.',
        'si': 'සාමාන්‍යයට වඩා $pct% ඉහළයි — විකිණීමට හොඳ කාලයකි.',
        'ta': 'சராசரியை விட $pct% அதிகம் — விற்க நல்ல நேரம்.',
      });
    }
    return _t({
      'en': '$pct% below average — you may want to wait.',
      'si': 'සාමාන්‍යයට වඩා $pct% පහළයි — රැඳී සිටීම සලකා බලන්න.',
      'ta': 'சராசரியை விட $pct% குறைவு — காத்திருக்கலாம்.',
    });
  }

  /// Provenance for the average. Returns an EMPTY list for
  /// [AveragePriceSource.unknown] — the one case where the app must say
  /// nothing at all about where the baseline came from. No fallback text, no
  /// implied label: an unattributed figure here would read as a market fact
  /// the app cannot stand behind.
  List<Widget> _sourceBadge(AveragePriceSource source) {
    final String text;
    switch (source) {
      case AveragePriceSource.real:
        text = _t({
          'en': 'Average based on real market data',
          'si': 'සැබෑ වෙළඳපොළ දත්ත මත පදනම් වූ සාමාන්‍යය',
          'ta': 'உண்மையான சந்தைத் தரவின் அடிப்படையில் சராசரி',
        });
      case AveragePriceSource.synthetic:
        text = _t({
          'en': 'Average estimated from modelled data',
          'si': 'ආකෘතිගත දත්ත මගින් ඇස්තමේන්තු කළ සාමාන්‍යය',
          'ta': 'மாதிரித் தரவிலிருந்து மதிப்பிடப்பட்ட சராசரி',
        });
      case AveragePriceSource.unknown:
        return const [];
    }
    return [
      const SizedBox(height: 10),
      // A pill, not a bare line: at 10.5px in textSecondary (4.39:1 — under
      // the 4.5 AA floor this redesign held everywhere else) sitting right
      // below a bold coloured interpretation line, the plain-text version
      // was structurally present but easy to lose. `ink` clears 4.50:1 —
      // but only against the exact card background it was measured on. A
      // first pass tinted the pill with the fill colour, which blends
      // #FCFBF6 toward warm orange and drops that ratio to 3.99:1 (caught
      // by accent_contrast_test.dart before shipping). Border only, no
      // fill: the text stays on the literal, already-verified background.
      Align(
        alignment: Alignment.centerLeft,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
          decoration: BoxDecoration(
            border: Border.all(
              color: AppTheme.accents.price.ink.withValues(alpha: 0.35),
            ),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                source == AveragePriceSource.real
                    ? Icons.verified_outlined
                    : Icons.functions_rounded,
                size: 13,
                color: AppTheme.accents.price.ink,
              ),
              const SizedBox(width: 5),
              Flexible(
                child: Text(
                  text,
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.accents.price.ink,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ];
  }

  /// "For 100 kg: 7,800 LKR". Always shown — quantity defaults to 100 — and
  /// rebuilt live, since the quantity field calls setState on every change.
  Widget _earningsRow(double farmgate) {
    final qty = _quantity;
    final total = farmgate * qty;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppTheme.login.primaryDark.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(
            Icons.account_balance_wallet_outlined,
            size: 18,
            color: AppTheme.login.primaryDark,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _t({
                    'en': 'For ${_grouped(qty)} kg',
                    'si': 'කිලෝ ${_grouped(qty)} ක් සඳහා',
                    'ta': '${_grouped(qty)} கிலோவுக்கு',
                  }),
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    // textSecondary measured 3.95:1 on this tint — under AA.
                    // dividerText is the theme's own answer to exactly this:
                    // "textSecondary fell short of AA ... for small divider
                    // labels" (see its doc comment in app_theme.dart).
                    color: AppTheme.login.dividerText,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${_grouped(total)} LKR',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.login.primaryDark,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _confidenceLine(String confidence) =>
      switch (confidence.toUpperCase()) {
        'HIGH' => _t({
          'en': 'We\'re quite sure about this estimate',
          'si': 'මෙම ඇස්තමේන්තුව ගැන හොඳ විශ්වාසයකි',
          'ta': 'இந்த மதிப்பீட்டில் நம்பிக்கை உள்ளது',
        }),
        'MEDIUM' => _t({
          'en': 'Fairly confident — prices may vary',
          'si': 'සාධාරණ විශ්වාසයකි — මිල වෙනස් විය හැක',
          'ta': 'மிதமான நம்பிக்கை — விலை மாறலாம்',
        }),
        _ => _t({
          'en': 'Approximate estimate — confirm with your local market',
          'si': 'ආසන්න ඇස්තමේන්තුවකි — දේශීය වෙළඳපොළෙන් තහවුරු කරන්න',
          'ta': 'தோராயமான மதிப்பீடு — உள்ளூர் சந்தையில் உறுதிப்படுத்தவும்',
        }),
      };

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
      color: AppTheme.login.background,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: AppTheme.login.borderSubtle),
    ),
    child: child,
  );

  // Section labels and their icons are one of the three sanctioned accent
  // uses. They sit on the page background, so they take `ink` (4.50:1 there)
  // rather than `fill` (2.56:1, unreadable as text).
  Widget _sectionTitle(String title, IconData icon) => Row(
    children: [
      Icon(icon, size: 16, color: AppTheme.accents.price.ink),
      const SizedBox(width: 6),
      // Flexible + ellipsis: the longest translated labels overran this row
      // by a fraction of a pixel at 320dp.
      Flexible(
        child: AnimatedLangText(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: AppTheme.accents.price.ink,
          ),
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

  /// Crop/district/season recap at the foot of the result card. white54 /
  /// white / white24 here were leftover from the old dark-gradient card
  /// design and never re-tokened when the card moved to a light background —
  /// measured 1.08:1 / 1.15:1, i.e. genuinely invisible on the peach tint
  /// behind it. Kept (not removed): it mirrors exactly what
  /// [_shareOnWhatsApp] sends, and on mobile the form has scrolled out of
  /// view by the time this result appears, so it's the only place these
  /// three values are still visible.
  Widget _rStat(String l, String v) => Column(
    children: [
      Text(
        l,
        style: TextStyle(color: AppTheme.login.dividerText, fontSize: 10),
      ),
      const SizedBox(height: 3),
      Text(
        v,
        style: TextStyle(
          color: AppTheme.login.textPrimary,
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
        overflow: TextOverflow.ellipsis,
      ),
    ],
  );

  // Full opacity, not alpha-thinned: at up to 0.6 alpha this still landed
  // under 3:1 against the peach tint behind it — a 1px line doesn't need
  // subtlety, it needs to be seen.
  Widget _vDiv() =>
      Container(width: 1, height: 28, color: AppTheme.login.dividerText);
}
