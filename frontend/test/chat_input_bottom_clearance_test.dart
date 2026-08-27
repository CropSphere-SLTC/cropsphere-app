import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cropsphere_app/app_lang.dart';
import 'package:cropsphere_app/app_theme_mode.dart';
import 'package:cropsphere_app/widgets/floating_bottom_nav.dart';

// Clearance between a bottom-pinned input and the floating nav.
//
// This replaces a test that checked FloatingBottomNav.reservedHeight — a
// helper that computed the nav's height itself and was WRONG, because
// Scaffold.extendBody already inflates the body's MediaQuery.padding.bottom
// to cover the bottom bar. Adding the nav height to that padding double-
// counted it and left ~160px of dead space under the chat input on phones.
//
// The old test passed anyway: it exercised the formula in isolation, never
// through a Scaffold, so it could only ever confirm the arithmetic it was
// built from. These tests go through the real widget tree instead — a real
// Scaffold with extendBody and the real FloatingBottomNav — so the thing
// being measured is the gap a farmer actually sees.

const _kInputKey = ValueKey('input');

Future<double> _gapBelowInput(
  WidgetTester tester, {
  required Size size,
  double bottomInset = 0,
  double keyboardInset = 0,
  bool showNav = true,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  tester.view.padding = FakeViewPadding(bottom: bottomInset);
  tester.view.viewInsets = FakeViewPadding(bottom: keyboardInset);
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    AppThemeModeProvider(
      notifier: AppThemeModeNotifier(),
      child: AppLangProvider(
        notifier: AppLangNotifier(),
        child: MaterialApp(
          home: Scaffold(
            extendBody: true,
            bottomNavigationBar: showNav
                ? FloatingBottomNav(
                    selectedIndex: 6,
                    onTap: (_) {},
                    lang: AppLang.en,
                  )
                : null,
            body: Column(
              children: [
                const Expanded(child: SizedBox()),
                // Stands in for _buildInputBar's wrapper.
                SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Container(key: _kInputKey, height: 48),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();

  final inputBottom = tester.getBottomLeft(find.byKey(_kInputKey)).dy;
  final screenBottom = size.height - keyboardInset;
  return screenBottom - inputBottom;
}

void main() {
  testWidgets('phone: the input sits just above the nav, not 160px above it', (
    tester,
  ) async {
    final gap = await _gapBelowInput(
      tester,
      size: const Size(390, 844),
      bottomInset: 34,
    );
    // Nav is 64 capsule + 34 inset = 98, plus the input's own 12 padding.
    // Anything approaching 98+64 would be the double-count returning.
    expect(gap, closeTo(98 + 12, 1));
    expect(gap, lessThan(140));
  });

  testWidgets('phone with no home indicator', (tester) async {
    final gap = await _gapBelowInput(tester, size: const Size(390, 800));
    // SafeArea(minimum: bottom 10) floors the inset at the nav's own margin.
    expect(gap, closeTo(64 + 10 + 12, 1));
  });

  testWidgets('tablet keeps the same clearance', (tester) async {
    final gap = await _gapBelowInput(
      tester,
      size: const Size(768, 1024),
      bottomInset: 20,
    );
    expect(gap, closeTo(64 + 20 + 12, 1));
    expect(gap, lessThan(140));
  });

  testWidgets('desktop has no nav, so only the input padding remains', (
    tester,
  ) async {
    final gap = await _gapBelowInput(
      tester,
      size: const Size(1440, 900),
      showNav: false,
    );
    expect(gap, closeTo(12, 1));
  });

  testWidgets('keyboard open: the input sits on the keyboard, not on a gap', (
    tester,
  ) async {
    // Flutter does NOT lift bottomNavigationBar above the keyboard — measured,
    // the nav's top stays at y=746 while the keyboard starts at y=508, so the
    // nav is simply behind it and out of play. The right result is therefore
    // the input resting directly on the keyboard with only its own padding,
    // NOT reserving nav clearance it no longer needs.
    final gap = await _gapBelowInput(
      tester,
      size: const Size(390, 844),
      bottomInset: 34,
      keyboardInset: 336,
    );
    expect(gap, closeTo(12, 1));
  });

  testWidgets('keyboard open: the input never overlaps the nav', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    tester.view.padding = const FakeViewPadding(bottom: 34);
    tester.view.viewInsets = const FakeViewPadding(bottom: 336);
    addTearDown(tester.view.reset);
    await _gapBelowInput(
      tester,
      size: const Size(390, 844),
      bottomInset: 34,
      keyboardInset: 336,
    );
    final navTop = tester.getTopLeft(find.byType(FloatingBottomNav)).dy;
    final inputBottom = tester.getBottomLeft(find.byKey(_kInputKey)).dy;
    expect(inputBottom, lessThan(navTop));
  });
}
