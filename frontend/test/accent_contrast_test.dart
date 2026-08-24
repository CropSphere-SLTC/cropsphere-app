import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cropsphere_app/widgets/app_theme.dart';

// Pins the WCAG guarantees the per-feature accent palette was built around.
//
// The accents are chosen to sit behind text and to BE text, and four of the
// six identity hues cannot do both. These tests encode which pairing was
// verified for each, so darkening a hue "just a little" for visual reasons
// fails here instead of silently shipping 2.6:1 body text.

double _lin(int c) {
  final s = c / 255.0;
  return s <= 0.03928
      ? s / 12.92
      : math.pow((s + 0.055) / 1.055, 2.4) as double;
}

double _lum(Color c) {
  final r = (c.r * 255).round();
  final g = (c.g * 255).round();
  final b = (c.b * 255).round();
  return 0.2126 * _lin(r) + 0.7152 * _lin(g) + 0.0722 * _lin(b);
}

double contrast(Color a, Color b) {
  final la = _lum(a), lb = _lum(b);
  final hi = math.max(la, lb), lo = math.min(la, lb);
  return (hi + 0.05) / (lo + 0.05);
}

/// The page background every `ink` was measured against.
final Color _bg = AppTheme.login.background;

const double kAA = 4.5; // normal-size text
const double kAANonText = 3.0; // icons, UI boundaries

void main() {
  final accents = <String, FeatureAccent>{
    'yield': AppTheme.accents.yield,
    'price': AppTheme.accents.price,
    'weather': AppTheme.accents.weather,
    'cropRec': AppTheme.accents.cropRec,
    'demand': AppTheme.accents.demand,
    'chat': AppTheme.accents.chat,
  };

  group('accent ink is readable as text on the page background', () {
    accents.forEach((name, a) {
      test('$name ink >= 4.5:1 on ${_bg.toString()}', () {
        expect(
          contrast(a.ink, _bg),
          greaterThanOrEqualTo(kAA),
          reason:
              '$name.ink is used for section labels, which are normal-size '
              'text on the page background.',
        );
      });
    });
  });

  group('accent onFill is readable on its own fill', () {
    accents.forEach((name, a) {
      test('$name onFill >= 4.5:1 on fill', () {
        expect(
          contrast(a.onFill, a.fill),
          greaterThanOrEqualTo(kAA),
          reason:
              'The $name header card carries a 12px subtitle, so its text '
              'colour must clear AA for normal-size text — not just large.',
        );
      });
    });
  });

  group('accent ink doubles as a fill behind white', () {
    accents.forEach((name, a) {
      test('white on $name ink >= 4.5:1', () {
        expect(contrast(Colors.white, a.ink), greaterThanOrEqualTo(kAA));
      });
    });
  });

  test('price keeps its terracotta identity as the header fill', () {
    // The specified hue, unmodified. If this ever has to change, the change
    // is a design decision, not an accessibility workaround.
    expect(AppTheme.accents.price.fill, const Color(0xFFDF8A58));
  });

  test('price header takes DARK text — white would be 2.65:1', () {
    expect(AppTheme.accents.price.onFill, AppTheme.login.textPrimary);
    expect(
      contrast(Colors.white, AppTheme.accents.price.fill),
      lessThan(kAANonText),
      reason:
          'Documents why onFill is dark here: white fails even the non-text '
          'floor on this fill.',
    );
  });

  test('the price header subtitle alpha stays above AA', () {
    // The subtitle renders onFill at 90% over the fill. Below ~0.87 the
    // blended ink drops under 4.5:1.
    const alpha = 0.90;
    final fill = AppTheme.accents.price.fill;
    final ink = AppTheme.accents.price.onFill;
    final blended = Color.from(
      alpha: 1.0,
      red: alpha * ink.r + (1 - alpha) * fill.r,
      green: alpha * ink.g + (1 - alpha) * fill.g,
      blue: alpha * ink.b + (1 - alpha) * fill.b,
    );
    expect(contrast(blended, fill), greaterThanOrEqualTo(kAA));
  });

  test('primary actions stay on primaryDark, not on any accent', () {
    // Step 3's rule. primaryDark is the one action colour app-wide, and it
    // clears AA against white comfortably.
    expect(
      contrast(Colors.white, AppTheme.login.primaryDark),
      greaterThanOrEqualTo(kAA),
    );
  });

  group('price result-card legibility fixes', () {
    // Regression coverage for three near-invisible elements found on the
    // rendered Price result card: a comparison-bar fill, a source badge, and
    // a share button that all used tokens too close to the card background
    // to actually be seen.

    test('the average bar\'s fill is NOT borderSubtle', () {
      // borderSubtle (#E4E8E0) measured 1.20:1 against the card background —
      // a divider token, not a fill. The bar used it as a fill and
      // disappeared. textSecondary is the replacement.
      const borderSubtle = Color(0xFFE4E8E0);
      expect(contrast(borderSubtle, _bg), lessThan(kAANonText));
      expect(
        contrast(AppTheme.login.textSecondary, _bg),
        greaterThanOrEqualTo(4.0),
        reason: 'textSecondary is the average-bar fill this was fixed to.',
      );
    });

    test('the source badge ink reads on the card background', () {
      // The badge moved from bare textSecondary text (4.39:1 — under AA) to
      // accents.price.ink, which only clears AA against the EXACT background
      // it was measured on (#FCFBF6, 4.50:1 — see AppFeatureAccents' class
      // doc). A first pass put it on a price.fill-tinted pill, which blends
      // the background toward warm orange and drops that ratio to 3.99:1.
      // The pill is border-only now — pin that no fill tint comes back.
      expect(
        contrast(AppTheme.accents.price.ink, _bg),
        greaterThanOrEqualTo(kAA),
      );

      final rejectedTint = Color.alphaBlend(
        AppTheme.accents.price.fill.withValues(alpha: 0.14),
        _bg,
      );
      expect(
        contrast(AppTheme.accents.price.ink, rejectedTint),
        lessThan(kAA),
        reason: 'Documents why the pill went border-only instead of tinted.',
      );
    });

    test('the restyled share button keeps its text/icon contrast', () {
      // Adding a 0.07-alpha primaryDark tint behind primaryDark text must
      // not be the thing that drags this under AA.
      final tint = Color.alphaBlend(
        AppTheme.login.primaryDark.withValues(alpha: 0.07),
        _bg,
      );
      expect(
        contrast(AppTheme.login.primaryDark, tint),
        greaterThanOrEqualTo(kAA),
      );
    });
  });

  group('second pass: earnings row, confidence line, crop/district strip', () {
    // A full sweep of the result card surfaced more of the same class of
    // bug: textSecondary reused past the exact background it clears AA on,
    // and one leftover white-on-dark styling from the pre-redesign card.

    test(
      'textSecondary is under AA on the earnings-row tint — why it moved',
      () {
        final tint = Color.alphaBlend(
          AppTheme.login.primaryDark.withValues(alpha: 0.07),
          _bg,
        );
        expect(contrast(AppTheme.login.textSecondary, tint), lessThan(kAA));
        expect(
          contrast(AppTheme.login.dividerText, tint),
          greaterThanOrEqualTo(kAA),
          reason: 'dividerText is the earnings-label and confidence-line fix.',
        );
      },
    );

    test(
      'textSecondary is under AA on the plain card — the confidence line bug',
      () {
        expect(contrast(AppTheme.login.textSecondary, _bg), lessThan(kAA));
        expect(
          contrast(AppTheme.login.dividerText, _bg),
          greaterThanOrEqualTo(kAA),
        );
      },
    );

    test(
      'textSecondary is under AA on borderSubtle — the MOCK DATA badge bug',
      () {
        const borderSubtle = Color(0xFFE4E8E0);
        expect(
          contrast(AppTheme.login.textSecondary, borderSubtle),
          lessThan(kAA),
        );
        expect(
          contrast(AppTheme.login.dividerText, borderSubtle),
          greaterThanOrEqualTo(kAA),
        );
      },
    );

    test('the MEDIUM confidence dot is deepened past AppTheme.warning', () {
      // AppTheme.warning (#F57F17) is a shared, app-wide token measured at
      // 2.56:1 here — under even the 3:1 non-text floor. Deepened locally in
      // price_screen's own _confColor (not the shared token, so other
      // screens using AppTheme.warning are unaffected).
      const warning = Color(0xFFF57F17);
      const deepened = Color(0xFFE6710A);
      expect(contrast(warning, _bg), lessThan(kAANonText));
      expect(contrast(deepened, _bg), greaterThanOrEqualTo(kAANonText));
    });

    test('the crop/district/season strip is no longer white-on-light', () {
      // white54/white/white24 were leftover from the old dark-gradient
      // card and measured 1.08:1 / 1.15:1 / ~1:1 against the peach tint
      // behind them — effectively invisible. Now dividerText (label),
      // textPrimary (value), dividerText solid (divider line).
      final pinkTint = Color.alphaBlend(
        AppTheme.accents.price.fill.withValues(alpha: 0.12),
        _bg,
      );
      const white54 = Color(0x8AFFFFFF);
      final oldLabel = Color.alphaBlend(white54, pinkTint);
      expect(contrast(oldLabel, pinkTint), lessThan(kAA));
      expect(contrast(Colors.white, pinkTint), lessThan(kAA));

      expect(
        contrast(AppTheme.login.dividerText, pinkTint),
        greaterThanOrEqualTo(kAA),
      );
      expect(
        contrast(AppTheme.login.textPrimary, pinkTint),
        greaterThanOrEqualTo(kAA),
      );
      // The divider line only needs the non-text floor, but half-measure
      // alpha values (up to 0.6) still landed under 3:1 on this tint — full
      // opacity is what actually cleared it.
      expect(
        contrast(AppTheme.login.dividerText, pinkTint),
        greaterThanOrEqualTo(kAANonText),
      );
    });
  });

  test('Sea Green is deliberately NOT used as a header fill', () {
    // #3A8943 carries no small text in either direction (4.34:1 white,
    // 3.43:1 textPrimary), which is why yield/chat fall back to primaryDark.
    const seaGreen = Color(0xFF3A8943);
    expect(contrast(Colors.white, seaGreen), lessThan(kAA));
    expect(contrast(AppTheme.login.textPrimary, seaGreen), lessThan(kAA));
    expect(AppTheme.accents.yield.fill, isNot(seaGreen));
    expect(AppTheme.accents.chat.fill, isNot(seaGreen));
  });
}
