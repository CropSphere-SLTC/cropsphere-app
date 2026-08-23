import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cropsphere_app/widgets/top_nav_items.dart';
import 'package:cropsphere_app/widgets/top_nav_metrics.dart';

// The desktop top nav is the ONLY navigation from 1024px up (the floating
// bottom nav is hidden there), so a tab scrolled out of the row's
// horizontal ScrollView is unreachable, not just awkward. The row is
// scrollable, so this never throws — it has to be measured.
//
// Guards the configuration actually shipped: short labels (matching the
// bottom nav's wording) at 13px, with BrandWordmark hidden in the
// 600–1200px band.

/// Delegates to the widget's own geometry so the test can't drift from
/// what actually renders.
double navRowWidth(List<String> labels, TopNavMetrics m) =>
    TopNavItems.rowWidth(labels, m);

void main() {
  // Everything sharing the bar besides the nav row, with the wordmark
  // hidden: logo + language control + theme toggle + avatar + gaps + pad.
  // Measured, not assumed — the cluster's controls scale with the metrics,
  // so a hardcoded estimate silently goes stale when they change.
  double langPillsWidth(TopNavMetrics m) {
    var total = 6.0; // container padding
    for (final label in ['EN', 'සිං', 'தமிழ்']) {
      final tp = TextPainter(
        text: TextSpan(
          text: label,
          style: TextStyle(
            fontSize: m.langLabelSize,
            fontWeight: FontWeight.w800,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      total += tp.width + 18; // per-pill horizontal padding
    }
    return total;
  }

  // Below comfortableFrom the language control renders as its compact
  // dropdown (~60px) rather than three pills (~185px) — see
  // LanguageControl. Modelling that is what makes the compact band fit.
  double langWidth(TopNavMetrics m, double screenWidth) =>
      screenWidth >= TopNavMetrics.comfortableFrom ? langPillsWidth(m) : 60;

  double chromeNoWordmark(TopNavMetrics m, double screenWidth) =>
      m.logoSize +
      langWidth(m, screenWidth) +
      m.controlHeight /*toggle button box is square on controlHeight*/ +
      m.avatarSize +
      m.clusterGap * 2 /*gaps inside the right cluster*/ +
      8 /*gap before the cluster*/ +
      28 /*bar padding*/;

  const labels = {
    'en': ['Home', 'Yield', 'Price', 'Weather', 'Crop', 'Demand', 'Chat'],
    'si': ['මුල', 'අස්වැන්න', 'මිල', 'කාලගුණ', 'භෝග', 'ඉල්ලුම', 'AI'],
    'ta': ['முகப்பு', 'விளைச்சல்', 'விலை', 'வானிலை', 'பயிர்', 'தேவை', 'AI'],
  };

  // Each responsive step is checked at the narrowest width it can appear
  // at: compact from 1024, comfortable from TopNavMetrics.comfortableFrom.
  final steps = {
    'compact @1024': (TopNavMetrics.compact, 1024.0),
    'comfortable @${TopNavMetrics.comfortableFrom.toInt()}':
        (TopNavMetrics.comfortable, TopNavMetrics.comfortableFrom),
  };

  for (final step in steps.entries) {
    final (m, width) = step.value;
    for (final e in labels.entries) {
      test('all 7 tabs fit — ${step.key} — ${e.key}', () {
        final available = width - chromeNoWordmark(m, width);
        expect(
          navRowWidth(e.value, m),
          lessThan(available),
          reason: 'nav items would scroll out of reach where the top bar '
              'is the only navigation',
        );
      });
    }
  }

  test('the comfortable step would NOT fit at 1024px', () {
    // Documents why the metrics step up at 1200 rather than applying the
    // larger sizes everywhere.
    final available = 1024 - chromeNoWordmark(TopNavMetrics.comfortable, 1024);
    expect(navRowWidth(labels['ta']!, TopNavMetrics.comfortable),
        greaterThan(available));
  });

  test('wordmark would not fit alongside the labels at 1024px', () {
    // Documents why BrandWordmark hides in this band — if this ever starts
    // passing, the wordmark could be shown again.
    const wordmarkWidth = 185.0 + 10; // measured at 18.5px w800, plus gap
    final available =
        1024 - chromeNoWordmark(TopNavMetrics.compact, 1024) - wordmarkWidth;
    expect(navRowWidth(labels['en']!, TopNavMetrics.compact),
        greaterThan(available));
  });
}
