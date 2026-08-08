// test/admin_sidebar_test.dart
// The sidebar must be a Material surface, not a coloured box. ListTile paints
// its background and ink splash onto the nearest Material ancestor, so an
// opaque box in between hides them — Flutter 3.43+ reports that as a framework
// error, which this pins so the Container form cannot come back.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cropsphere_app/screens/admin/shared/widgets/admin_sidebar.dart';

/// Pump the sidebar and return every framework error it raised, individually.
///
/// Errors are intercepted at FlutterError.onError rather than read back with
/// takeException, which collapses several errors into one "Multiple exceptions
/// were detected" summary and hides the individual messages this test needs.
///
/// They are collected rather than asserted away wholesale because this widget
/// legitimately overflows under test: widget tests render with Ahem, whose
/// glyphs are fixed-width squares, so nav labels measure far wider than in a
/// real font and the 250px rail cannot fit them. That is a test-environment
/// artifact — the app does not overflow at runtime — so the assertions below
/// name the error they care about instead of demanding silence.
Future<List<String>> _pumpSidebar(
  WidgetTester tester, {
  String role = 'superadmin',
}) async {
  final errors = <String>[];
  final previousHandler = FlutterError.onError;
  FlutterError.onError = (details) => errors.add(details.exceptionAsString());
  try {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Row(
            children: [
              AdminSidebar(
                role: role,
                current: AdminPage.dashboard,
                onSelect: (_) {},
                onLogout: () {},
              ),
              const Expanded(child: SizedBox()),
            ],
          ),
        ),
      ),
    );
  } finally {
    FlutterError.onError = previousHandler;
  }
  return errors;
}

void main() {
  group('AdminSidebar', () {
    testWidgets('raises no ListTile-under-ColoredBox error', (tester) async {
      final errors = await _pumpSidebar(tester);

      expect(
        errors.where((e) => e.contains('ink splashes may be invisible')),
        isEmpty,
        reason: 'the Logout tile must find a Material before any opaque box',
      );
    });

    testWidgets('reaches Material before any opaque box above Logout', (
      tester,
    ) async {
      await _pumpSidebar(tester);

      // Walk the Logout tile's ancestors exactly as ListTile does: whatever
      // paints a background must not come before the Material.
      final BuildContext tileContext = tester.element(
        find.widgetWithText(ListTile, 'Logout'),
      );
      Widget? blocker;
      tileContext.visitAncestorElements((ancestor) {
        if (ancestor.widget is Material) return false;
        final widget = ancestor.widget;
        if (widget is ColoredBox && widget.color.a > 0) {
          blocker = widget;
          return false;
        }
        if (widget is DecoratedBox) {
          final decoration = widget.decoration;
          if (decoration is BoxDecoration && (decoration.color?.a ?? 0) > 0) {
            blocker = widget;
            return false;
          }
        }
        return true;
      });

      expect(blocker, isNull);
    });

    testWidgets('keeps its fixed width', (tester) async {
      await _pumpSidebar(tester);
      expect(tester.getSize(find.byType(AdminSidebar)).width, 250);
    });

    testWidgets('hides superadmin-only items from an admin', (tester) async {
      await _pumpSidebar(tester, role: 'admin');

      expect(find.text('Dashboard'), findsOneWidget);
      expect(find.text('Prompt tuning'), findsNothing);
      expect(find.text('System config'), findsNothing);
    });
  });
}
