import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// The chat screen's app nav must span the FULL window width regardless of
// whether the conversation sidebar is open.
//
// It used to be the first child of the column inside the sidebar Row's
// Expanded, so opening the 280px sidebar re-laid the nav out in
// (width - 280): the bar visibly resized as the panel slid, and its
// right-hand cluster tracked the moving edge. The fix hoists it above the
// Row. This pins the structure, without booting ChatScreen itself (it
// reaches for Firebase in initState).

/// The layout chat/build() uses: nav on top, sidebar+content beneath.
Widget _hoisted({required bool sidebarOpen}) => MaterialApp(
  home: Scaffold(
    body: Column(
      children: [
        const SizedBox(height: 56, key: Key('nav'), child: Placeholder()),
        Expanded(
          child: Row(
            children: [
              AnimatedContainer(
                duration: Duration.zero,
                width: sidebarOpen ? 280 : 0,
                child: const SizedBox.shrink(),
              ),
              const Expanded(child: SizedBox.shrink()),
            ],
          ),
        ),
      ],
    ),
  ),
);

/// The shape it had before: nav nested inside the Row's Expanded.
Widget _nested({required bool sidebarOpen}) => MaterialApp(
  home: Scaffold(
    body: Row(
      children: [
        AnimatedContainer(
          duration: Duration.zero,
          width: sidebarOpen ? 280 : 0,
          child: const SizedBox.shrink(),
        ),
        Expanded(
          child: Column(
            children: const [
              SizedBox(height: 56, key: Key('nav'), child: Placeholder()),
              Expanded(child: SizedBox.shrink()),
            ],
          ),
        ),
      ],
    ),
  ),
);

Future<double> _navWidth(
  WidgetTester tester,
  Widget Function({required bool sidebarOpen}) build, {
  required bool sidebarOpen,
}) async {
  tester.view.physicalSize = const Size(1280, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(build(sidebarOpen: sidebarOpen));
  await tester.pumpAndSettle();
  return tester.getSize(find.byKey(const Key('nav'))).width;
}

void main() {
  testWidgets('nav keeps the full window width with the sidebar open', (
    tester,
  ) async {
    final closed = await _navWidth(tester, _hoisted, sidebarOpen: false);
    final open = await _navWidth(tester, _hoisted, sidebarOpen: true);

    expect(closed, 1280);
    expect(open, 1280, reason: 'the sidebar must not resize the app nav');
    expect(open, closed);
  });

  testWidgets('the old nested shape is what shrank it — guards the fix', (
    tester,
  ) async {
    // If this ever stops shrinking, the test above has lost its teeth.
    final closed = await _navWidth(tester, _nested, sidebarOpen: false);
    final open = await _navWidth(tester, _nested, sidebarOpen: true);

    expect(closed, 1280);
    expect(open, 1000, reason: '1280 - 280px of sidebar');
  });
}
