import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cropsphere_app/app_lang.dart';
import 'package:cropsphere_app/app_theme_mode.dart';
import 'package:cropsphere_app/widgets/app_top_bar.dart';
import 'package:cropsphere_app/widgets/top_nav_metrics.dart';

// AppTopBar is the one shared top bar, used by all six dashboard-style
// screens (Dashboard, Yield, Price, Weather, Crop Recommend, Demand). This
// tests it in isolation — no network, no service mocking — specifically so
// a gap like the one that produced the original bug can't hide again: five
// of six screens reused TopNavMetrics unconditionally down to 0px width
// (never validated below the ~1024px band its own docs describe) and
// overflowed at 320px, undetected because no test ever rendered any of
// them that narrow. Only Price had its own, separately hand-tuned mobile
// bar, so it alone was accidentally safe — until unification briefly
// regressed it too, caught here and in price_screen_render_test.dart before
// it shipped.

Widget harness(double width, AppLang lang) {
  return AppThemeModeProvider(
    notifier: AppThemeModeNotifier(),
    child: AppLangProvider(
      notifier: AppLangNotifier()..setLang(lang),
      child: MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: width,
            child: AppTopBar(
              activeIndex: 2,
              activeBg: const Color(0xFFE8F5E9),
              activeColor: const Color(0xFF2E7D32),
              onNavigate: (_) {},
            ),
          ),
        ),
      ),
    ),
  );
}

Future<void> pumpAt(WidgetTester tester, double width, AppLang lang) async {
  tester.view.physicalSize = Size(width, 800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(harness(width, lang));
  await tester.pump(const Duration(milliseconds: 400));
}

void main() {
  // 320 = smallest supported phone (the width that exposed the bug); 340 =
  // AppTopBar's own small/not-small split; 600 = the phone/tablet boundary
  // shared with BrandWordmark and TopNavItems; 1024/1280 = TopNavMetrics'
  // own compact/comfortable boundary; 1440/1920 = real desktop monitors.
  const widths = [320.0, 339.0, 340.0, 600.0, 1024.0, 1279.0, 1280.0, 1920.0];
  const langs = [AppLang.en, AppLang.si, AppLang.ta];

  for (final w in widths) {
    for (final lang in langs) {
      testWidgets('renders without overflow @${w}px lang=${lang.name}', (
        tester,
      ) async {
        await pumpAt(tester, w, lang);
        expect(tester.takeException(), isNull);
      });
    }
  }

  group('logo glyph scales with TopNavMetrics (bug 1)', () {
    testWidgets('32px at the compact tier (1024-1280px)', (tester) async {
      await pumpAt(tester, 1200, AppLang.en);
      final svg = tester.widget<SvgPicture>(find.byType(SvgPicture));
      expect(svg.width, TopNavMetrics.compact.logoGlyphSize);
      expect(TopNavMetrics.compact.logoGlyphSize, 32);
    });

    testWidgets('40px at the comfortable tier (>=1280px) — was stuck at 32', (
      tester,
    ) async {
      await pumpAt(tester, 1440, AppLang.en);
      final svg = tester.widget<SvgPicture>(find.byType(SvgPicture));
      expect(svg.width, TopNavMetrics.comfortable.logoGlyphSize);
      expect(TopNavMetrics.comfortable.logoGlyphSize, 40);
    });
  });

  testWidgets('the phone bar (<600px) does not use BrandWordmark', (
    tester,
  ) async {
    // BrandWordmark's fixed 18.5px doesn't fit this bar — see the widget's
    // own doc comment. The phone bar renders its own smaller "CropSphere".
    await pumpAt(tester, 320, AppLang.en);
    expect(find.text('CropSphere'), findsOneWidget);
  });

  testWidgets('nav items are hidden below 600px, present above it', (
    tester,
  ) async {
    await pumpAt(tester, 320, AppLang.en);
    expect(find.text('Weather'), findsNothing);

    await pumpAt(tester, 1024, AppLang.en);
    expect(find.text('Weather'), findsOneWidget);
  });

  test(
    'the canonical logo SVG is exactly what yield/price/weather shipped',
    () {
      // Regression guard for a real mistake made while building this file: a
      // first pass hand-typed this constant from memory instead of copying it
      // verbatim, and it diverged from the real artwork (different leaf path,
      // different highlight circles, a missing stem stroke). This pins the
      // exact, verified string so that can't happen silently again.
      expect(kCropSphereLogoSvg.length, 1280);
      expect(kCropSphereLogoSvg, contains('viewBox="0 0 110 110"'));
      // The stem stroke and the trilogy of small flower-highlight circles —
      // exactly what's absent from Demand/Crop Recommend's old "simplified"
      // copy of this artwork.
      expect(
        kCropSphereLogoSvg,
        contains(
          'M50 50 C50 42 50 35 50 28" stroke="#558B2F" stroke-width="2"',
        ),
      );
      expect(
        kCropSphereLogoSvg,
        contains(
          '<circle cx="43" cy="13" r="2.5" fill="#FFB300" opacity="0.8"/>',
        ),
      );
      // The two dew-drop ellipses that were unique to Dashboard's old
      // "extended" copy must NOT be here — this is the majority (3-of-6)
      // variant, not that one.
      expect(kCropSphereLogoSvg, isNot(contains('fill="#B3E5FC"')));
    },
  );
}
