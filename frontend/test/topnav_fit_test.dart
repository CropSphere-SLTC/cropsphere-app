import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// The desktop top nav is the ONLY navigation from 1024px up (the floating
// bottom nav is hidden there), so a tab scrolled out of the row's
// horizontal ScrollView is unreachable, not just awkward. The row is
// scrollable, so this never throws — it has to be measured.
//
// Guards the configuration actually shipped: short labels (matching the
// bottom nav's wording) at 13px, with BrandWordmark hidden in the
// 600–1200px band.

double _textWidth(String s, double size) {
  final tp = TextPainter(
    text: TextSpan(
      text: s,
      style: TextStyle(fontSize: size, fontWeight: FontWeight.w700),
    ),
    textDirection: TextDirection.ltr,
  )..layout();
  return tp.width;
}

/// Laid-out width of the 7-item nav row.
double navRowWidth(List<String> labels) => labels.fold(
      0.0,
      (a, l) => a + _textWidth(l, 13) + 15 * 2 /*button pad*/ + 3 * 2 /*gap*/,
    );

void main() {
  // Everything sharing the bar besides the nav row, with the wordmark
  // hidden: logo + language control + theme toggle + avatar + gaps + pad.
  const chromeNoWordmark = 44 + 92 + 44 + 34 + 24 + 28;

  const labels = {
    'en': ['Home', 'Yield', 'Price', 'Weather', 'Crop', 'Demand', 'Chat'],
    'si': ['මුල', 'අස්වැන්න', 'මිල', 'කාලගුණ', 'භෝග', 'ඉල්ලුම', 'AI'],
    'ta': ['முகப்பு', 'விளைச்சல்', 'விலை', 'வானிலை', 'பயிர்', 'தேவை', 'AI'],
  };

  for (final e in labels.entries) {
    test('all 7 tabs fit at the 1024px breakpoint — ${e.key}', () {
      final available = 1024 - chromeNoWordmark;
      expect(
        navRowWidth(e.value),
        lessThan(available.toDouble()),
        reason: 'nav items would scroll out of reach where the top bar is '
            'the only navigation',
      );
    });
  }

  test('wordmark would not fit alongside the labels at 1024px', () {
    // Documents why BrandWordmark hides in this band — if this ever starts
    // passing, the wordmark could be shown again.
    const wordmarkWidth = 185.0 + 10; // measured at 18.5px w800, plus gap
    final available = 1024 - chromeNoWordmark - wordmarkWidth;
    expect(navRowWidth(labels['en']!), greaterThan(available));
  });
}
