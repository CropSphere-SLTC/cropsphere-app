import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cropsphere_app/widgets/top_nav_items.dart';
import 'package:cropsphere_app/widgets/top_nav_metrics.dart';

// Phones navigate with MainShell's FloatingBottomNav alone; the top nav row
// steps aside below 600px so the two don't stack on the screen with the least
// vertical room. Pinned here because the row lives in a shared widget used by
// six screens — a regression would hit all of them at once.

const _labels = [
  'Home',
  'Yield',
  'Price',
  'Weather',
  'Crop',
  'Demand',
  'Chat',
];

Future<void> _pumpAt(WidgetTester tester, double width) async {
  tester.view.physicalSize = Size(width, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (ctx) => TopNavItems(
            labels: _labels,
            activeIndex: 1,
            activeBg: const Color(0xFFE8F5E9),
            activeColor: const Color(0xFF2E7D32),
            onNavigate: (_) {},
            metrics: TopNavMetrics.of(ctx),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('phone widths render no nav items at all', (tester) async {
    await _pumpAt(tester, 390); // iPhone-class
    for (final label in _labels) {
      expect(find.text(label), findsNothing, reason: '$label should be hidden');
    }
    expect(tester.getSize(find.byType(TopNavItems)), Size.zero);
  });

  testWidgets('just below the boundary still hides the row', (tester) async {
    await _pumpAt(tester, kTopNavRowMinWidth - 1);
    expect(find.text('Yield'), findsNothing);
  });

  testWidgets('tablet widths render the full row', (tester) async {
    await _pumpAt(tester, kTopNavRowMinWidth);
    for (final label in _labels) {
      expect(find.text(label), findsOneWidget);
    }
    expect(tester.getSize(find.byType(TopNavItems)).width, greaterThan(0));
  });

  testWidgets('desktop widths render the full row', (tester) async {
    await _pumpAt(tester, 1440);
    expect(find.text('Home'), findsOneWidget);
    expect(find.text('Chat'), findsOneWidget);
  });
}
