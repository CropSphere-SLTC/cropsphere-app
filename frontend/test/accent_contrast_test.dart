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
    // price and weather are excluded here deliberately — both are documented
    // exceptions (see AppFeatureAccents.price/.weather's doc comments and the
    // 'price header' / 'weather header' tests below, which pin each failure
    // explicitly instead of silently excluding it from coverage).
    accents.forEach((name, a) {
      if (name == 'price' || name == 'weather') return;
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

  group(
    'price fill: known, accepted contrast failure — read before "fixing"',
    () {
      // History: shipped as #DF8A58 with dark onFill (correct — 5.62:1).
      // Deepened to #AB5524 specifically so white onFill could pass instead
      // (5.18:1, real margin). Then reverted back to #DF8A58 BY REQUEST, with
      // onFill kept at white — shown the failing number (2.65:1) each time
      // this was asked for. This is not an oversight; do not silently
      // "correct" it back to #AB5524 or to dark text without asking first.
      // See AppFeatureAccents.price's doc comment in app_theme.dart for the
      // full history.

      test('fill is #DF8A58, onFill is white', () {
        expect(AppTheme.accents.price.fill, const Color(0xFFDF8A58));
        expect(AppTheme.accents.price.onFill, Colors.white);
      });

      test('white on fill fails AA — and even the non-text floor', () {
        expect(
          contrast(Colors.white, AppTheme.accents.price.fill),
          lessThan(kAANonText),
          reason:
              '2.65:1 — this is the accepted failure, not a regression to fix.',
        );
      });

      test('the deepened alternative that DID pass is preserved here', () {
        // #AB5524 is what onFill would need fill to be for white to clear AA
        // (5.18:1) — kept as a literal in case this is ever revisited.
        const passingAlternative = Color(0xFFAB5524);
        expect(
          contrast(Colors.white, passingAlternative),
          greaterThanOrEqualTo(kAA),
        );
      });
    },
  );

  group('cropRec header gradient — deep olive, AA-clean at both ends', () {
    // 2026-08 revision. This header shipped as a lighter #7CA759 carrying
    // DARK ink (#1F2A1F, 5.34:1) and read as washed out. It could not simply
    // be darkened: darkening a mid-green erodes dark-on-it contrast fast, and
    // dark ink fell under AA by -0.05 lightness (4.40:1) — long before the
    // fill looked meaningfully darker. Going dark enough to read as fixed
    // meant flipping the text to off-white, so this is a two-part change.
    //
    // Unlike price and weather, nothing here is an accepted failure: both
    // gradient ends clear AA for normal-size text with real margin.
    const anchor = Color(0xFF3D5A3D);
    const lightStop = Color(0xFF567556);
    const offWhite = Color(0xFFFCFBF6);

    test('fill is #3D5A3D and onFill is the warm off-white', () {
      expect(AppTheme.accents.cropRec.fill, anchor);
      expect(AppTheme.accents.cropRec.onFill, offWhite);
    });

    test('onFill clears AA on the dark anchor', () {
      expect(contrast(offWhite, anchor), greaterThanOrEqualTo(kAA));
      expect(contrast(offWhite, anchor), closeTo(7.43, 0.02));
    });

    test('onFill clears AA on the light gradient stop', () {
      // The binding end. The subtitle is 12px, so this is the normal-text
      // floor, not the 3:1 large-text one.
      expect(contrast(offWhite, lightStop), greaterThanOrEqualTo(kAA));
      expect(contrast(offWhite, lightStop), closeTo(4.97, 0.02));
    });

    test('the subtitle runs at FULL opacity, because 0.90 fails', () {
      // Pins the reason rather than the value: at 0.90 (the alpha that was
      // correct for dark ink on the old light fill) off-white measures
      // 4.39:1 on the light stop, under the floor.
      final faded = Color.alphaBlend(offWhite.withValues(alpha: 0.90), lightStop);
      expect(contrast(faded, lightStop), lessThan(kAA));
      expect(contrast(faded, lightStop), closeTo(4.39, 0.03));
    });

    test('the glass badge tint is BLACK, and white would fail', () {
      // The tint flipped with the accent. On the old light fill, dark content
      // needed a LIGHTENING scrim (white@0.15, 6.36-8.43:1). On this dark
      // anchor the content is off-white, so darkening is what preserves it.
      final black20 = Color.alphaBlend(
        Colors.black.withValues(alpha: 0.20),
        lightStop,
      );
      expect(contrast(offWhite, black20), greaterThanOrEqualTo(kAA));
      expect(contrast(offWhite, black20), closeTo(6.89, 0.02));

      // Kept as documentation: the rejected alternative, at the end where it
      // fails, so nobody re-lightens this scrim without the test catching it.
      final white15 = Color.alphaBlend(
        Colors.white.withValues(alpha: 0.15),
        lightStop,
      );
      expect(contrast(offWhite, white15), lessThan(kAA));
    });

    test('ink is unchanged and still readable on the page background', () {
      // ink was verified as text against #FCFBF6, never against fill, so
      // darkening the fill does not affect it.
      expect(AppTheme.accents.cropRec.ink, const Color(0xFF5D7D42));
      expect(contrast(AppTheme.accents.cropRec.ink, _bg), greaterThanOrEqualTo(kAA));
    });

    test('the light stop is derivable from fill, not a free-floating hex', () {
      // recommend_screen computes it as +0.102 lightness / -0.039 saturation
      // in HSL. A plain lightness shift (price_screen's widening) cannot
      // reach it — that gives #527852 — which is why the helper there takes
      // a saturation term as well.
      final hsl = HSLColor.fromColor(anchor);
      final derived = hsl
          .withLightness((hsl.lightness + 0.102).clamp(0.0, 1.0))
          .withSaturation((hsl.saturation - 0.039).clamp(0.0, 1.0))
          .toColor();
      expect(derived.toARGB32(), lightStop.toARGB32());
    });
  });

  group('price header gradient — known, accepted failure across both ends', () {
    // The header is a two-stop gradient (dark top-left -> light
    // bottom-right, matching yield_screen's header). fill (#DF8A58) is the
    // dark anchor; the light anchor is price_screen's own private
    // _headerGradientLight — hardcoded here since it isn't exposed, the
    // same way the MEDIUM confidence dot's deepened warning colour is
    // pinned elsewhere in this file.
    //
    // #EBB798 is +0.15 HLS lightness from the dark anchor, widened from an
    // earlier +0.035 step (#E29467) that sat close enough to the dark
    // anchor to read as visually flat rather than a gradient. +0.20 was
    // also tried and rejected — it starts blending into the page's own
    // background (#FCFBF6) at the lightest corner. None of these clear AA;
    // nothing lighter than the (already-failing) dark anchor could. Two
    // even earlier, AA-passing light stops existed here before fill
    // reverted to #DF8A58 out from under them: #BA5C27 (4.52:1, the actual
    // ceiling for the OLD dark anchor) and #B35926 (4.80:1, more margin).
    const lightStop = Color(0xFFEBB798);

    test('both gradient ends fail AA for white text', () {
      expect(
        contrast(Colors.white, AppTheme.accents.price.fill),
        lessThan(kAA),
      );
      expect(contrast(Colors.white, lightStop), lessThan(kAA));
      // The light end is worse, not better — lightening a colour that
      // already fails only ever erodes white contrast further.
      expect(
        contrast(Colors.white, lightStop),
        lessThan(contrast(Colors.white, AppTheme.accents.price.fill)),
      );
    });

    test('the rejected wider step and the two former AA-passing stops', () {
      // Kept as literals in case this is ever revisited.
      const rejectedTooLight = Color(0xFFEFC6AE); // +0.20, blends into #FCFBF6
      const formerNarrowStep = Color(0xFFE29467); // +0.035, read as flat
      const formerCeiling = Color(0xFFBA5C27); // 4.52:1 against #AB5524
      const formerSaferChoice = Color(0xFFB35926); // 4.80:1 against #AB5524
      expect(
        contrast(rejectedTooLight, AppTheme.login.background),
        lessThan(3.0),
        reason: 'Why +0.20 was rejected — barely distinguishable from #FCFBF6.',
      );
      expect(contrast(Colors.white, formerNarrowStep), lessThan(kAA));
      expect(contrast(Colors.white, formerCeiling), greaterThanOrEqualTo(kAA));
      expect(
        contrast(Colors.white, formerSaferChoice),
        greaterThanOrEqualTo(kAA),
      );
    });

    group('icon badge / Week pill: glass panel, known failure at 0.20', () {
      // price_screen's _glassBadge: a translucent black tint + a faint
      // white edge, NOT a BackdropFilter blur — an earlier version used
      // one, but blurring a smooth two-colour gradient is imperceptible
      // (nothing behind this panel has texture for a blur to act on), so
      // it was removed rather than kept as decoration that did nothing.
      //
      // Alpha history: 0.20 (first pass, ink-scrim era) -> 0.30 (fill
      // reverted #AB5524 -> #DF8A58) -> 0.40 (light stop widened to
      // #EBB798, the AA-passing value) -> back to 0.20, by explicit
      // request, for a genuinely see-through panel — the gradient visibly
      // shows through it, which is the actual "glass" cue, not blur. KNOWN,
      // ACCEPTED CONTRAST FAILURE: white icon/text on it is 2.79-4.03:1,
      // under the 4.5:1 text floor.

      test('black@0.20 is genuinely transparent — and fails AA', () {
        final darkEnd = Color.alphaBlend(
          Colors.black.withValues(alpha: 0.20),
          AppTheme.accents.price.fill,
        );
        final lightEnd = Color.alphaBlend(
          Colors.black.withValues(alpha: 0.20),
          lightStop,
        );
        expect(contrast(Colors.white, darkEnd), lessThan(kAA));
        expect(contrast(Colors.white, lightEnd), lessThan(kAA));
      });

      test('the AA-passing alternative (0.40) is preserved here', () {
        final darkEnd = Color.alphaBlend(
          Colors.black.withValues(alpha: 0.40),
          AppTheme.accents.price.fill,
        );
        final lightEnd = Color.alphaBlend(
          Colors.black.withValues(alpha: 0.40),
          lightStop,
        );
        expect(contrast(Colors.white, darkEnd), greaterThanOrEqualTo(kAA));
        expect(contrast(Colors.white, lightEnd), greaterThanOrEqualTo(kAA));
      });

      test('0.20 is still better than no panel at all', () {
        // The badge/pill SHAPE stays visible (the white border gives it a
        // crisp edge regardless), and the tint is still some improvement
        // over the bare gradient underneath.
        final lightEnd = Color.alphaBlend(
          Colors.black.withValues(alpha: 0.20),
          lightStop,
        );
        expect(
          contrast(Colors.white, lightEnd),
          greaterThan(contrast(Colors.white, lightStop)),
        );
      });
    });
  });

  group(
    'weather fill: known, accepted contrast failure — read before "fixing"',
    () {
      // History: shipped as #2D689B, self-sufficient (5.89:1 white onFill,
      // fill doubled as its own ink). Muted to #4E7FA3 (2026-08) at the
      // user's request for a look closer to the rest of the accent palette.
      // White onFill was kept, shown the resulting failing number (4.30:1)
      // first — not an oversight. Unlike price's terracotta, this ALSO
      // clears the 3:1 non-text floor (price's does not).

      test('fill is #4E7FA3, onFill is white', () {
        expect(AppTheme.accents.weather.fill, const Color(0xFF4E7FA3));
        expect(AppTheme.accents.weather.onFill, Colors.white);
      });

      test('white on fill fails the 4.5:1 AA floor, but clears 3:1', () {
        final c = contrast(Colors.white, AppTheme.accents.weather.fill);
        expect(c, lessThan(kAA));
        expect(
          c,
          greaterThanOrEqualTo(kAANonText),
          reason:
              '4.30:1 — worse than the old self-sufficient value, but still '
              'above the non-text floor, unlike price\'s 2.65:1.',
        );
      });

      test('the minimal-darkening alternative that DID pass is preserved', () {
        // #4C7B9F is the smallest HLS darkening of #4E7FA3 that gets white
        // onFill to clear AA (4.52:1) — kept as a literal in case this is
        // ever revisited.
        const passingAlternative = Color(0xFF4C7B9F);
        expect(
          contrast(Colors.white, passingAlternative),
          greaterThanOrEqualTo(kAA),
        );
      });
    },
  );

  group(
    'weather header gradient — known, accepted failure across both ends',
    () {
      // Same two-stop structure as price_screen's header (dark top-left ->
      // light bottom-right): fill (#4E7FA3) is the dark anchor, and the light
      // anchor is weather_screen's own private _headerGradientLight — same
      // +0.15 HLS lightness step used for price's light stop, hue/saturation
      // preserved.
      const lightStop = Color(0xFF7DA4C1);

      test(
        'the light end fails AA for white text, and worse than the dark end',
        () {
          expect(
            contrast(Colors.white, AppTheme.accents.weather.fill),
            lessThan(kAA),
          );
          expect(contrast(Colors.white, lightStop), lessThan(kAA));
          // The light end is worse, not better — same pattern as price's
          // gradient: lightening a colour that already fails only erodes white
          // contrast further, and here it also drops below the non-text floor.
          expect(
            contrast(Colors.white, lightStop),
            lessThan(contrast(Colors.white, AppTheme.accents.weather.fill)),
          );
          expect(contrast(Colors.white, lightStop), lessThan(kAANonText));
        },
      );

      group('icon badge / Week pill: glass panel, black@0.20', () {
        // Same _glassBadge treatment as price_screen (black@0.20 tint + a
        // faint white edge) — but unlike price, the DARK end here clears AA
        // outright once tinted; only the light corner stays a known failure.

        test('dark end + black@0.20 clears AA; light end does not', () {
          final darkEnd = Color.alphaBlend(
            Colors.black.withValues(alpha: 0.20),
            AppTheme.accents.weather.fill,
          );
          final lightEnd = Color.alphaBlend(
            Colors.black.withValues(alpha: 0.20),
            lightStop,
          );
          expect(contrast(Colors.white, darkEnd), greaterThanOrEqualTo(kAA));
          expect(contrast(Colors.white, lightEnd), lessThan(kAA));
          expect(
            contrast(Colors.white, lightEnd),
            greaterThanOrEqualTo(kAANonText),
          );
        });
      });
    },
  );

  test('primary actions stay on primaryDark, not on any accent', () {
    // Step 3's rule. primaryDark is the one action colour app-wide, and it
    // clears AA against white comfortably. price_screen's "Predict Price"
    // and weather_screen's "Get Forecast" buttons are now TWO explicit,
    // requested exceptions to this — see the 'Predict Price button' /
    // 'Get Forecast button' tests below — every other primary action,
    // including each screen's own "Ask AI about this", still follows this
    // rule.
    expect(
      contrast(Colors.white, AppTheme.login.primaryDark),
      greaterThanOrEqualTo(kAA),
    );
  });

  test(
    'Predict Price button: uses the price accent, KNOWN FAILING contrast',
    () {
      // The one exception to the rule above, and it inherits price.fill's
      // documented failure rather than being separately safe — see the
      // 'price fill: known, accepted contrast failure' group above.
      expect(
        contrast(Colors.white, AppTheme.accents.price.fill),
        lessThan(kAANonText),
      );
    },
  );

  test(
    'Get Forecast button: uses the weather accent, KNOWN FAILING contrast',
    () {
      // The SECOND explicit, requested exception to the rule above — see
      // weather_screen's _stickyForecastButton. Inherits weather.fill's
      // documented failure (4.30:1) rather than being separately safe — see
      // the 'weather fill: known, accepted contrast failure' group above.
      // Unlike price's button, this one still clears the 3:1 non-text
      // floor.
      final c = contrast(Colors.white, AppTheme.accents.weather.fill);
      expect(c, lessThan(kAA));
      expect(c, greaterThanOrEqualTo(kAANonText));
    },
  );

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

  group(
    'yield header glass badge — passes AA with real margin, no trade-off',
    () {
      // yield_screen's own header, NOT AppTheme.accents.yield (a different,
      // unrelated token defined for potential future use that page never
      // adopted) — the header actually renders AppTheme.primaryDark ->
      // AppTheme.primary. When price_screen's icon badge/Week pill got a
      // glass treatment (tint + white edge highlight), the same visual
      // structure was applied here too, at the user's request — but yield's
      // dark green fill means a WHITE tint (lightening) is what keeps the
      // icon/text legible, the opposite of price's black tint (darkening).
      // Unlike every price_screen test in this file, nothing here is a known
      // failure: both ends clear AA with real margin, so the badge needed no
      // alpha negotiation at all.
      const darkAnchor = AppTheme.primaryDark; // #0A3D0A
      const lightAnchor = AppTheme.primary; // #1B5E20

      test('the gradient itself clears AA with huge margin, both ends', () {
        expect(contrast(Colors.white, darkAnchor), greaterThanOrEqualTo(kAA));
        expect(contrast(Colors.white, lightAnchor), greaterThanOrEqualTo(kAA));
      });

      test('the white@0.15 glass tint clears AA at both gradient ends', () {
        final darkEnd = Color.alphaBlend(
          Colors.white.withValues(alpha: 0.15),
          darkAnchor,
        );
        final lightEnd = Color.alphaBlend(
          Colors.white.withValues(alpha: 0.15),
          lightAnchor,
        );
        expect(contrast(Colors.white, darkEnd), greaterThanOrEqualTo(kAA));
        expect(contrast(Colors.white, lightEnd), greaterThanOrEqualTo(kAA));
      });

      test(
        'a black tint (price_screen\'s choice) would be the wrong direction here',
        () {
          // Documents WHY this page uses white, not black: darkening an
          // already very dark fill doesn't hurt contrast, but it also isn't
          // what makes the badge visually distinct — lightening is, since the
          // fill is dark to begin with. This isn't a contrast failure, just
          // the opposite tool for the opposite starting colour.
          final blackTinted = Color.alphaBlend(
            Colors.black.withValues(alpha: 0.15),
            lightAnchor,
          );
          expect(
            contrast(Colors.white, blackTinted),
            greaterThanOrEqualTo(kAA),
          );
          // Still passes (the margin here is that large) — but reads as barely
          // different from the fill itself, the exact "can't see the badge"
          // failure mode price_screen hit with its own ink scrim.
          expect(
            contrast(blackTinted, lightAnchor),
            lessThan(3.0),
            reason:
                'A black tint would barely be distinguishable from the fill.',
          );
        },
      );
    },
  );
}
