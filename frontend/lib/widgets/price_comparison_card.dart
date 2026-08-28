// lib/widgets/price_comparison_card.dart
// ─────────────────────────────────────────────────────────────────────────────
//  Predicted vs average farmgate price for the farmer's preferred crop —
//  a stat tile (the price) + a meter showing where it sits against the
//  crop's average, plus a plain-language read of the gap.
//
//  DATA HONESTY (the rule this widget exists to enforce):
//    average_price_source == "real"      → subtle "based on real market data"
//    average_price_source == "synthetic" → "estimated from modelled data"
//    average_price_source == null        → NO badge at all, and no comparison
//
//  A null source means the backend computed no baseline (mock response, or
//  the price datasets were unreadable). In that case the whole card is
//  withheld rather than shown with an unlabelled or guessed baseline — an
//  unattributed number here would read as a market fact the app cannot
//  actually stand behind.
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';

import '../models/api_models.dart';
import '../services/service_factory.dart';
import '../utils/farm_context.dart';
import 'app_theme.dart';
import 'skeleton_loading.dart';

/// Recent farmgate price per crop, used to seed the LSTM's lag inputs.
/// Same table the Price screen uses for its own lag seeding.
const Map<String, double> kRecentFarmgatePrice = {
  'Carrot': 58.0,
  'Maize': 48.0,
  'Green gram': 145.0,
  'Cowpea': 142.0,
  'Finger millet': 98.0,
  'Groundnut': 195.0,
};

/// Width of the average-marker label box under the meter. Fixed so the
/// label can be centred on the marker and clamped inside the track
/// regardless of how wide the translated word is.
const double _kAvgLabelW = 92.0;

class PriceComparisonCard extends StatefulWidget {
  final String? preferredDistrict;
  final String? preferredCrop;
  final String langKey;

  /// Opens the full Price Prediction screen.
  final VoidCallback onSeeFull;

  const PriceComparisonCard({
    super.key,
    required this.preferredDistrict,
    required this.preferredCrop,
    required this.langKey,
    required this.onSeeFull,
  });

  @override
  State<PriceComparisonCard> createState() => _PriceComparisonCardState();
}

class _PriceComparisonCardState extends State<PriceComparisonCard> {
  PriceResponse? _result;
  bool _loading = false;
  bool _failed = false;

  bool get _hasPrefs =>
      widget.preferredDistrict != null && widget.preferredCrop != null;

  @override
  void initState() {
    super.initState();
    if (_hasPrefs) _load();
  }

  @override
  void didUpdateWidget(PriceComparisonCard old) {
    super.didUpdateWidget(old);
    if (old.preferredDistrict != widget.preferredDistrict ||
        old.preferredCrop != widget.preferredCrop) {
      if (_hasPrefs) {
        _load();
      } else {
        setState(() {
          _result = null;
          _loading = false;
          _failed = false;
        });
      }
    }
  }

  Future<void> _load() async {
    final crop = widget.preferredCrop;
    final district = widget.preferredDistrict;
    if (crop == null || district == null) return;
    setState(() {
      _loading = true;
      _failed = false;
    });
    try {
      final base = kRecentFarmgatePrice[crop] ?? 80.0;
      final res = await ServiceFactory.getService().predictPrice(
        PriceRequest(
          crop: crop,
          district: district,
          season: farmCurrentSeason(),
          weekOfYear: farmWeekOfYear(),
          inflationIndex: 1.15,
          fuelPriceIndex: 1.10,
          transportCostIndex: 1.10,
          supplyIndex: 100,
          demandIndex: 100,
          holidayFlag: 0,
          festivalFlag: 0,
          farmgatePriceLag1: base,
          farmgatePriceLag2: base * 0.98,
          farmgatePriceLag4: base * 0.95,
        ),
      );
      if (!mounted) return;
      setState(() {
        _result = res;
        _loading = false;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _loading = false;
          _failed = true;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Depends on the same preferences as the hero — stay out of the layout
    // entirely when they aren't set.
    if (!_hasPrefs) return const SizedBox.shrink();
    if (_loading) return PriceComparisonSkeleton();

    final r = _result;
    // No baseline to compare against (including a null source) means there
    // is no honest comparison to draw — withhold the card rather than show
    // an unattributed number.
    if (_failed || r == null || !r.hasAverage) return const SizedBox.shrink();

    return PriceComparisonCardView(
      result: r,
      langKey: widget.langKey,
      onSeeFull: widget.onSeeFull,
    );
  }
}

/// The card's presentation, separated from the fetch so its layout can be
/// rendered in tests at every width and language it ships to (the meter's
/// geometry is the part that historically overflowed).
class PriceComparisonCardView extends StatelessWidget {
  final PriceResponse result;
  final String langKey;
  final VoidCallback onSeeFull;

  const PriceComparisonCardView({
    super.key,
    required this.result,
    required this.langKey,
    required this.onSeeFull,
  });

  String _t(Map<String, String> m) => m[langKey] ?? m['en']!;

  @override
  Widget build(BuildContext context) => _buildCard(result);

  Widget _buildCard(PriceResponse r) {
    final predicted = r.predictedFarmgatePriceLkrKg;
    final average = r.averageFarmgatePriceLkrKg;
    final diffPct = (predicted - average) / average * 100;
    final above = diffPct >= 0;
    final magnitude = diffPct.abs();
    // Under ~3% either way is noise at this precision — calling that
    // "above average, good time to sell" would overstate what the model
    // can actually distinguish.
    final isFlat = magnitude < 3;

    final accent = isFlat
        ? AppTheme.login.textSecondary
        : (above ? const Color(0xFF2E7D32) : const Color(0xFFC0473F));

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.login.background,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.login.borderSubtle, width: 1.4),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  _t({
                    'en': '${r.crop} price outlook',
                    'si': '${r.crop} මිල අනාවැකිය',
                    'ta': '${r.crop} விலை முன்னோட்டம்',
                  }),
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.login.textPrimary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              TextButton(
                onPressed: onSeeFull,
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: Text(
                  _t({'en': 'Details', 'si': 'විස්තර', 'ta': 'விவரம்'}),
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.login.primaryGreen,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // The value IS the headline — a stat tile, not a plot. See the
          // _buildMeter comment for why this replaced a two-bar chart.
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                'Rs. ${predicted.round()}',
                style: TextStyle(
                  fontSize: 30,
                  fontWeight: FontWeight.w800,
                  height: 1.0,
                  color: AppTheme.login.textPrimary,
                ),
              ),
              const SizedBox(width: 3),
              Text(
                '/kg',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.login.textSecondary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          // Delta carries an icon as well as color — status must never be
          // signalled by color alone.
          Row(
            children: [
              Icon(
                isFlat
                    ? Icons.remove_rounded
                    : (above
                          ? Icons.arrow_upward_rounded
                          : Icons.arrow_downward_rounded),
                size: 15,
                color: accent,
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  _interpretation(magnitude, above, isFlat),
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    height: 1.35,
                    color: accent,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          _buildMeter(predicted, average, accent),
          // Source attribution — only ever rendered for a source the
          // backend actually reported. See the file header.
          ..._buildSourceLabel(r.averagePriceSource),
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

  /// Returns an empty list for [AveragePriceSource.unknown] — the one case
  /// where the app must say nothing at all about provenance.
  List<Widget> _buildSourceLabel(AveragePriceSource source) {
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
      const SizedBox(height: 8),
      Row(
        children: [
          Icon(
            source == AveragePriceSource.real
                ? Icons.verified_outlined
                : Icons.functions_rounded,
            size: 13,
            color: AppTheme.login.textSecondary,
          ),
          const SizedBox(width: 5),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 10.5,
                color: AppTheme.login.textSecondary,
              ),
            ),
          ),
        ],
      ),
    ];
  }

  /// Where today's price sits relative to the crop's average.
  ///
  /// Replaces a two-bar chart. Two bars imply two comparable categories,
  /// but this is ONE value measured against a reference — the average is a
  /// baseline, not a peer series. A track with the average marked on it
  /// answers "where am I vs normal" directly, in a third of the height,
  /// and stops the reference being read as a rival quantity.
  Widget _buildMeter(double predicted, double average, Color accent) {
    // Scale so the average always sits at 70% of the track: the marker
    // stays put between crops, and there is headroom to show a price above
    // average without the fill running off the end.
    final scaleMax = average / 0.7;
    final fill = (predicted / scaleMax).clamp(0.0, 1.0);
    const avgAt = 0.7;

    return LayoutBuilder(
      builder: (context, c) {
        final w = c.maxWidth;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              height: 14,
              child: Stack(
                children: [
                  // Track
                  Container(
                    height: 14,
                    decoration: BoxDecoration(
                      color: AppTheme.login.borderSubtle,
                      borderRadius: BorderRadius.circular(7),
                    ),
                  ),
                  // Fill — today's price
                  FractionallySizedBox(
                    widthFactor: fill,
                    child: Container(
                      height: 14,
                      decoration: BoxDecoration(
                        color: accent,
                        borderRadius: BorderRadius.circular(7),
                      ),
                    ),
                  ),
                  // Average marker — a 2px surface gap either side keeps it
                  // legible where it sits on top of the fill.
                  Positioned(
                    left: (w * avgAt) - 2,
                    child: Container(
                      width: 4,
                      height: 14,
                      decoration: BoxDecoration(
                        color: AppTheme.login.textPrimary,
                        borderRadius: BorderRadius.circular(2),
                        border: Border.all(
                          color: AppTheme.login.background,
                          width: 1,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 5),
            // Label the marker directly rather than with a legend — one
            // reference line doesn't warrant a legend box.
            // Fixed-width label box, positioned to centre under the marker
            // and clamped inside the track. Sized rather than intrinsic so
            // a longer Sinhala/Tamil word can't push past the card edge —
            // it ellipsises instead of overflowing.
            SizedBox(
              width: w,
              child: Stack(
                children: [
                  Padding(
                    padding: EdgeInsets.only(
                      left: (w * avgAt - _kAvgLabelW / 2).clamp(
                        0.0,
                        (w - _kAvgLabelW).clamp(0.0, double.infinity),
                      ),
                    ),
                    child: SizedBox(
                      width: _kAvgLabelW,
                      child: Text(
                        '${_t({'en': 'avg', 'si': 'සාමාන්‍ය', 'ta': 'சராசரி'})} '
                        'Rs. ${average.round()}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.login.textSecondary,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Loading placeholder mirroring the card's real shape.
class PriceComparisonSkeleton extends StatelessWidget {
  const PriceComparisonSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return PulseFade(
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppTheme.login.background,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppTheme.login.borderSubtle, width: 1.4),
        ),
        child: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SkeletonBox(width: 140, height: 14),
            SizedBox(height: 14),
            SkeletonBox(width: 120, height: 30),
            SizedBox(height: 8),
            SkeletonBox(width: 190, height: 12),
            SizedBox(height: 16),
            SkeletonBox(height: 14, radius: 7),
            SizedBox(height: 7),
            SkeletonBox(width: 70, height: 10),
          ],
        ),
      ),
    );
  }
}
