import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cropsphere_app/screens/chat/chat_screen.dart';

// Drives the real ChatInputControls at real widths.
//
// Send is no longer part of this row — it moved inside the text field, so
// its states (hidden when empty, stop while generating) are not covered here.
//
// Flutter's RenderFlex reports overflow as a FlutterError, which fails the
// test — so "the row fits at 320dp with Tamil selected" is verified here
// rather than asserted in a comment. The widths below are the four the
// restyle had to hold at, plus 320 for the smallest phones still in use.

const _kTamilContext = 'நுவரெலியா · வேர்க்கடலை'; // Nuwara Eliya · Groundnut
const _kTamilModel = 'விரிவான பதில்'; // Detailed answer
const _kLongContext = 'Nuwara Eliya · Finger millet';

Future<void> _pump(
  WidgetTester tester, {
  required double width,
  String contextLabel = _kLongContext,
  bool hasContext = true,
  String modelLabel = 'Detailed answer',
}) async {
  tester.view.physicalSize = Size(width, 800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Align(
          alignment: Alignment.bottomCenter,
          // Mirrors _buildInputBar: 12px page padding either side, and the
          // reading column's 760 cap.
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 760),
              child: ChatInputControls(
                contextLabel: contextLabel,
                hasContext: hasContext,
                onContextTap: () {},
                modelLabel: modelLabel,
                modelIsDefault: false,
                onModelTap: () {},
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

/// Width of the pill wrapping [label], via its own Text.
double _pillWidth(WidgetTester tester, String label) =>
    tester.getSize(find.text(label)).width;

void main() {
  group('fits without overflow', () {
    // Any RenderFlex overflow throws, so reaching the expect is the check.
    for (final width in <double>[320, 375, 414, 600, 768, 1000, 1440]) {
      testWidgets('at ${width.toInt()}dp with the longest English strings', (
        tester,
      ) async {
        await _pump(tester, width: width);
        expect(tester.takeException(), isNull);
      });

      testWidgets('at ${width.toInt()}dp with Tamil strings', (tester) async {
        await _pump(
          tester,
          width: width,
          contextLabel: _kTamilContext,
          modelLabel: _kTamilModel,
        );
        expect(tester.takeException(), isNull);
      });
    }
  });

  group('mobile (<600) shows the context icon alone', () {
    testWidgets('the context label is not rendered at 375dp', (tester) async {
      await _pump(tester, width: 375);
      expect(find.text(_kLongContext), findsNothing);
      // The model selector KEEPS its label at this width — it was the
      // context label that made the row tight, not this one.
      expect(find.text('Detailed answer'), findsOneWidget);
    });

    testWidgets('the model label survives 320dp in Tamil too', (tester) async {
      await _pump(
        tester,
        width: 320,
        contextLabel: _kTamilContext,
        modelLabel: _kTamilModel,
      );
      expect(find.text(_kTamilContext), findsNothing);
      expect(find.text(_kTamilModel), findsOneWidget);
    });

    testWidgets('a selection is still discoverable with no label', (
      tester,
    ) async {
      // The dot is the non-colour channel saying "something is set"; the
      // tooltip carries what it actually is.
      await _pump(tester, width: 375, hasContext: true);
      expect(
        find.byWidgetPredicate(
          (w) => w is Tooltip && w.message == _kLongContext,
        ),
        findsOneWidget,
      );
      final setDots = find.byKey(const ValueKey('context-active-dot'));
      expect(setDots, findsOneWidget);
    });

    testWidgets('and absent when nothing is set', (tester) async {
      await _pump(
        tester,
        width: 375,
        hasContext: false,
        contextLabel: 'Set context',
      );
      expect(find.byKey(const ValueKey('context-active-dot')), findsNothing);
    });
  });

  group('desktop/tablet (>=600) shows full text', () {
    testWidgets('context and model labels are both rendered at 768dp', (
      tester,
    ) async {
      await _pump(tester, width: 768);
      expect(find.text(_kLongContext), findsOneWidget);
      expect(find.text('Detailed answer'), findsOneWidget);
      // Icon-only affordances belong to the compact layout only.
      expect(find.byKey(const ValueKey('context-active-dot')), findsNothing);
    });

    testWidgets('600dp exactly is NOT compact — the boundary is inclusive', (
      tester,
    ) async {
      await _pump(tester, width: 600 + 24); // +24 for the page padding
      expect(find.text(_kLongContext), findsOneWidget);
    });
  });

  group('step 6 — the intermediate case truncates rather than overflows', () {
    testWidgets('a long label is ellipsised, not clipped or overflowing', (
      tester,
    ) async {
      await _pump(tester, width: 640, contextLabel: _kLongContext);
      final text = tester.widget<Text>(find.text(_kLongContext));
      expect(text.overflow, TextOverflow.ellipsis);
      expect(text.maxLines, 1);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a short label keeps the pill at its natural width', (
      tester,
    ) async {
      // Flexible is loose, so only a label that cannot fit is ever cut —
      // "Badulla" must not be stretched to fill the slot.
      await _pump(tester, width: 1000, contextLabel: 'Badulla');
      final short = _pillWidth(tester, 'Badulla');
      await _pump(tester, width: 1000, contextLabel: _kLongContext);
      final long = _pillWidth(tester, _kLongContext);
      expect(short, lessThan(long));
    });
  });
}
