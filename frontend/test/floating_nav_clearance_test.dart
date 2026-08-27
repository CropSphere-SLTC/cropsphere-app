import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cropsphere_app/widgets/floating_bottom_nav.dart';

// FloatingBottomNav.reservedHeight is what keeps the chat input clear of the
// floating nav. MainShell sets Scaffold.extendBody, so the nav floats OVER
// every screen's body — a screen with something pinned to its bottom edge has
// to reserve this much or the nav lands on top of it, which is exactly what
// was happening to the chat input on every phone.

Future<double> _reserved(
  WidgetTester tester, {
  required Size size,
  required double bottomInset,
}) async {
  late double result;
  await tester.pumpWidget(
    MediaQuery(
      data: MediaQueryData(
        size: size,
        padding: EdgeInsets.only(bottom: bottomInset),
      ),
      child: Builder(
        builder: (context) {
          result = FloatingBottomNav.reservedHeight(context);
          return const SizedBox();
        },
      ),
    ),
  );
  return result;
}

void main() {
  testWidgets('reserves the capsule plus its margin on a phone with no inset', (
    tester,
  ) async {
    expect(
      await _reserved(tester, size: const Size(390, 844), bottomInset: 0),
      FloatingBottomNav.capsuleHeight + FloatingBottomNav.bottomMargin,
    );
  });

  testWidgets('a home-indicator inset larger than the margin wins', (
    tester,
  ) async {
    // SafeArea(minimum:) takes the LARGER of the two, so they must not sum.
    expect(
      await _reserved(tester, size: const Size(390, 844), bottomInset: 34),
      FloatingBottomNav.capsuleHeight + 34,
    );
  });

  testWidgets(
    'an inset smaller than the margin does not shrink the clearance',
    (tester) async {
      expect(
        await _reserved(tester, size: const Size(390, 844), bottomInset: 4),
        FloatingBottomNav.capsuleHeight + FloatingBottomNav.bottomMargin,
      );
    },
  );

  testWidgets('reserves nothing at 1024px, where MainShell hides the nav', (
    tester,
  ) async {
    // Same threshold as MainShell.showFloatingNav and chat's _wideBreakpoint.
    expect(
      await _reserved(tester, size: const Size(1024, 800), bottomInset: 0),
      0,
    );
    expect(
      await _reserved(tester, size: const Size(1440, 900), bottomInset: 0),
      0,
    );
  });

  testWidgets('still reserves at 1023px, one pixel below the threshold', (
    tester,
  ) async {
    expect(
      await _reserved(tester, size: const Size(1023, 800), bottomInset: 0),
      FloatingBottomNav.capsuleHeight + FloatingBottomNav.bottomMargin,
    );
  });
}
