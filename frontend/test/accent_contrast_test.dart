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

  test('price fill is deepened terracotta, chosen so white text works', () {
    // Originally #DF8A58 with dark onFill (white measured 2.65:1 there —
    // fails even the 3:1 non-text floor). Deepened to #AB5524 by request so
    // the header could carry white text instead — same hue family (0.060 vs
    // 0.062), lower lightness. This pin is a design decision, not an
    // incidental value; if it changes again, re-verify onFill below it.
    expect(AppTheme.accents.price.fill, const Color(0xFFAB5524));
  });

  test(
    'price header takes WHITE text — 5.18:1, real margin not a bare pass',
    () {
      expect(AppTheme.accents.price.onFill, Colors.white);
      expect(
        contrast(Colors.white, AppTheme.accents.price.fill),
        greaterThanOrEqualTo(kAA),
      );
      // The original fill is documented here specifically so nobody re-lightens
      // price.fill back toward #DF8A58 without noticing white stops working.
      const originalFill = Color(0xFFDF8A58);
      expect(
        contrast(Colors.white, originalFill),
        lessThan(kAANonText),
        reason: 'The original fill genuinely cannot carry white text.',
      );
    },
  );

  group('price header gradient', () {
    // The header moved from a flat AppTheme.accents.price.fill to a
    // two-stop gradient (dark top-left -> light bottom-right, matching
    // yield_screen's header). fill (#AB5524) is the dark anchor, unchanged;
    // the light anchor is price_screen's own private
    // _headerGradientLight — hardcoded here since it isn't exposed, the
    // same way the MEDIUM confidence dot's deepened warning colour is
    // pinned elsewhere in this file.
    //
    // #BA5C27 is the actual AA ceiling for white text on this hue family —
    // 4.52:1, chosen deliberately at the edge (by request, for the most
    // visible gradient the accessibility floor allows) over two rejected,
    // safer alternatives: #B35926 (4.80:1, more margin) and, before that,
    // #CC672C (3.79:1, failed outright — passed the TITLE's 3:1 large-text
    // floor but not the SUBTITLE's 4.5:1 one, with no alpha fix available).
    const lightStop = Color(0xFFBA5C27);

    test('the light stop IS the ceiling — one step lighter fails', () {
      expect(contrast(Colors.white, lightStop), greaterThanOrEqualTo(kAA));
      // #BC5D28 is ~0.005 lighter in HLS lightness than the ceiling.
      const oneStepLighter = Color(0xFFBC5D28);
      expect(contrast(Colors.white, oneStepLighter), lessThan(kAA));
    });

    test('both rejected, lighter alternatives are documented', () {
      const saferAlternative = Color(0xFFB35926); // 4.80:1, more margin
      const firstRejected = Color(0xFFCC672C); // 3.79:1, failed outright
      expect(
        contrast(Colors.white, saferAlternative),
        greaterThan(contrast(Colors.white, lightStop)),
      );
      expect(contrast(Colors.white, firstRejected), lessThan(kAA));
    });

    test(
      'white text clears AA across the whole gradient, dark end included',
      () {
        expect(
          contrast(Colors.white, AppTheme.accents.price.fill),
          greaterThanOrEqualTo(kAA),
        );
        expect(contrast(Colors.white, lightStop), greaterThanOrEqualTo(kAA));
      },
    );

    test('the subtitle has zero alpha headroom at the ceiling', () {
      // Unlike the earlier, safer light stop (which still had ~5% alpha
      // headroom), the ceiling itself leaves none: even 99% white drops
      // under 4.5:1 here.
      final at99 = Color.alphaBlend(
        Colors.white.withValues(alpha: 0.99),
        lightStop,
      );
      expect(contrast(at99, lightStop), lessThan(kAA));
      expect(contrast(Colors.white, lightStop), greaterThanOrEqualTo(kAA));
    });

    group('icon badge / Week pill scrim', () {
      // First an ink scrim (0.10, then 0.15): barely visible as a distinct
      // badge, since ink sits close to the fill's own hue/lightness — that
      // WAS the "can't see the icon" bug. White would fix visibility but
      // cost contrast severely: even 0.15 white here drops the icon to
      // 3.92:1, under AA, and it only gets worse from there. Black is the
      // one direction that's a pure win — darkening only ever IMPROVES
      // white-on-it contrast — so it is both clearly visible as a distinct
      // badge and higher-contrast than the flat fill was on its own.

      test('a white scrim would fail — the reason it was NOT used', () {
        final whiteScrim = Color.alphaBlend(
          Colors.white.withValues(alpha: 0.15),
          lightStop,
        );
        expect(contrast(Colors.white, whiteScrim), lessThan(kAA));
      });

      test('the black@0.20 scrim clears AA across the whole gradient', () {
        final darkEnd = Color.alphaBlend(
          Colors.black.withValues(alpha: 0.20),
          AppTheme.accents.price.fill,
        );
        final lightEnd = Color.alphaBlend(
          Colors.black.withValues(alpha: 0.20),
          lightStop,
        );
        expect(contrast(Colors.white, darkEnd), greaterThanOrEqualTo(kAA));
        expect(contrast(Colors.white, lightEnd), greaterThanOrEqualTo(kAA));
        // Genuinely better than the un-scrimmed flat fill it replaced.
        expect(
          contrast(Colors.white, lightEnd),
          greaterThan(contrast(Colors.white, AppTheme.accents.price.fill)),
        );
      });
    });
  });

  test('primary actions stay on primaryDark, not on any accent', () {
    // Step 3's rule. primaryDark is the one action colour app-wide, and it
    // clears AA against white comfortably. price_screen's "Predict Price"
    // button is now ONE explicit, requested exception to this — see the
    // 'Predict Price button uses the price accent' test below — every
    // other primary action, including Price's own "Ask AI about this",
    // still follows this rule.
    expect(
      contrast(Colors.white, AppTheme.login.primaryDark),
      greaterThanOrEqualTo(kAA),
    );
  });

  test('Predict Price button uses the price accent, deliberately', () {
    // The one exception to the rule above. price_screen's button uses
    // accents.price.fill instead of login.primaryDark, tying it to the
    // header's dark gradient anchor — same colour, separately verified.
    expect(
      contrast(Colors.white, AppTheme.accents.price.fill),
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
