import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cropsphere_app/app_lang.dart';
import 'package:cropsphere_app/app_theme_mode.dart';
import 'package:cropsphere_app/screens/price/price_screen.dart';

// Renders the redesigned Price screen at the widths and languages it ships
// to. This repo has shipped RenderFlex overflows before (the top-nav row, the
// comparison meter), and this redesign narrows two fields by adding a suffix
// tick to them — exactly the change that overflowed the Season dropdown
// during development.

Widget harness(AppLang lang) => AppThemeModeProvider(
  notifier: AppThemeModeNotifier(),
  child: AppLangProvider(
    notifier: AppLangNotifier()..setLang(lang),
    child: const MaterialApp(home: Scaffold(body: PriceScreen())),
  ),
);

Future<void> pumpAt(WidgetTester tester, double w, AppLang lang) async {
  tester.view.physicalSize = Size(w, 1200);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(harness(lang));
  await tester.pump(const Duration(milliseconds: 400));
}

void main() {
  // 320 = smallest supported phone; 1024 = the two-column threshold; 1440 =
  // desktop. 1023/1024 bracket the breakpoint itself.
  const widths = [320.0, 600.0, 1023.0, 1024.0, 1440.0];
  const langs = [AppLang.en, AppLang.si, AppLang.ta];

  for (final w in widths) {
    for (final lang in langs) {
      testWidgets('renders without overflow @${w}px lang=${lang.name}', (
        tester,
      ) async {
        await pumpAt(tester, w, lang);
        expect(tester.takeException(), isNull);
        // Tear the tree down before the harness checks for pending timers:
        // AnimatedLangText keeps a controller running while it is mounted.
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(seconds: 1));
      });
    }
  }

  testWidgets('the tab bar is gone — this is a single view', (tester) async {
    await pumpAt(tester, 1440, AppLang.en);
    expect(find.byType(TabBar), findsNothing);
    expect(find.byType(TabBarView), findsNothing);
    expect(find.text('Selling Tips'), findsNothing);
    expect(find.text('Enter Details'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('quick-select chips and the checklist are gone', (tester) async {
    await pumpAt(tester, 1440, AppLang.en);
    expect(find.text('Quick select:'), findsNothing);
    expect(find.text('Complete these to predict:'), findsNothing);
    expect(find.text('Ready to predict!'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('required fields show an empty indicator before selection', (
    tester,
  ) async {
    await pumpAt(tester, 1440, AppLang.en);
    // Crop, District, Season — none chosen yet.
    expect(find.byIcon(Icons.radio_button_unchecked), findsNWidgets(3));
    expect(find.byIcon(Icons.check_circle), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('choosing a crop ticks that field and leaves the others', (
    tester,
  ) async {
    await pumpAt(tester, 1440, AppLang.en);
    await tester.tap(find.text('Select Crop'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('Carrot').last);
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byIcon(Icons.check_circle), findsOneWidget);
    expect(find.byIcon(Icons.radio_button_unchecked), findsNWidgets(2));
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('the Predict button stays disabled until all three are set', (
    tester,
  ) async {
    await pumpAt(tester, 1440, AppLang.en);
    expect(find.text('Complete 3 steps above first'), findsOneWidget);
    final btn = tester.widget<ElevatedButton>(
      find.ancestor(
        of: find.text('Complete 3 steps above first'),
        matching: find.byType(ElevatedButton),
      ),
    );
    expect(btn.onPressed, isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('crop search filters by typed text', (tester) async {
    await pumpAt(tester, 1440, AppLang.en);
    await tester.tap(find.text('Select Crop'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.enterText(find.byType(TextFormField).first, 'gram');
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Green gram'), findsWidgets);
    expect(find.text('Maize'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
  });
}
