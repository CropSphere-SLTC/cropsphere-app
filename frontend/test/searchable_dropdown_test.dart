import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cropsphere_app/widgets/app_theme.dart';
import 'package:cropsphere_app/widgets/searchable_dropdown.dart';

// Drives the REAL SearchableDropdown + syncSearchField from
// lib/widgets/searchable_dropdown.dart.
//
// This harness used to re-implement both, because they only existed as
// private methods inside yield_screen, which could not be imported without
// dragging Firebase/services into the test. Now that they are extracted into
// a widget whose only dependency is app_theme.dart, the test exercises the
// shipping code instead of a copy of it — so a regression in the widget fails
// here rather than passing against a stale mirror.
//
// The bug this guards: RawAutocomplete recomputes its options ONLY when the
// field text changes (framework autocomplete.dart, `_onChangedField`), never
// on focus. Selecting a crop enables the District field and swaps its option
// set but changes no text — so tapping District opened onto an empty list.

class _Harness extends StatefulWidget {
  const _Harness();
  @override
  State<_Harness> createState() => _HarnessState();
}

class _HarnessState extends State<_Harness> {
  static const _crops = ['Carrot', 'Maize', 'Green gram'];
  static const _districts = {
    'Carrot': ['Nuwara Eliya', 'Badulla'],
    'Maize': ['Anuradhapura', 'Ampara', 'Badulla'],
  };

  String? _crop;
  String? _district;
  final _cropCtrl = TextEditingController();
  final _districtCtrl = TextEditingController();
  final _cropFocus = FocusNode();
  final _districtFocus = FocusNode();

  @override
  void initState() {
    super.initState();
    _cropFocus.addListener(() => syncSearchField(_cropFocus, _cropCtrl, _crop));
    _districtFocus.addListener(
      () => syncSearchField(_districtFocus, _districtCtrl, _district),
    );
  }

  @override
  void dispose() {
    _cropCtrl.dispose();
    _districtCtrl.dispose();
    _cropFocus.dispose();
    _districtFocus.dispose();
    super.dispose();
  }

  List<String> get _availableDistricts =>
      _crop != null ? (_districts[_crop!] ?? []) : [];

  @override
  Widget build(BuildContext context) => MaterialApp(
    home: Scaffold(
      body: Column(
        children: [
          SearchableDropdown(
            label: 'Select Crop',
            value: _crop,
            items: _crops,
            icon: Icons.eco,
            accent: AppTheme.accents.yield,
            searchHint: 'Type to search',
            controller: _cropCtrl,
            focusNode: _cropFocus,
            onChanged: (val) {
              _districtCtrl.clear();
              setState(() {
                _crop = val;
                _district = null;
              });
            },
          ),
          SearchableDropdown(
            label: 'Select District',
            value: _district,
            items: _availableDistricts,
            icon: Icons.location_on,
            accent: AppTheme.accents.yield,
            searchHint: 'Type to search',
            controller: _districtCtrl,
            focusNode: _districtFocus,
            enabled: _crop != null,
            onChanged: (val) => setState(() => _district = val),
          ),
        ],
      ),
    ),
  );
}

Future<void> _tap(WidgetTester tester, String label) async {
  await tester.tap(find.widgetWithText(TextFormField, label));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('tapping Crop opens the full list without typing', (
    tester,
  ) async {
    await tester.pumpWidget(const _Harness());
    await _tap(tester, 'Select Crop');

    expect(find.text('Carrot'), findsOneWidget);
    expect(find.text('Maize'), findsOneWidget);
    expect(find.text('Green gram'), findsOneWidget);
  });

  testWidgets('typing filters the list in real time', (tester) async {
    await tester.pumpWidget(const _Harness());
    await _tap(tester, 'Select Crop');
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Select Crop'),
      'ma',
    );
    await tester.pumpAndSettle();

    expect(find.text('Maize'), findsOneWidget);
    expect(find.text('Carrot'), findsNothing);
  });

  testWidgets('District is inert until a crop is chosen', (tester) async {
    await tester.pumpWidget(const _Harness());
    await _tap(tester, 'Select District');
    expect(find.text('Badulla'), findsNothing);
    expect(find.text('Nuwara Eliya'), findsNothing);
  });

  testWidgets('tapping District after choosing a crop opens its full list', (
    tester,
  ) async {
    // THE REGRESSION: choosing a crop enables District and swaps its options
    // but changes no text, so RawAutocomplete never rebuilt the list and the
    // tap opened onto nothing.
    await tester.pumpWidget(const _Harness());
    await _tap(tester, 'Select Crop');
    await tester.tap(find.text('Carrot').last);
    await tester.pumpAndSettle();

    await _tap(tester, 'Select District');
    expect(find.text('Nuwara Eliya'), findsOneWidget);
    expect(find.text('Badulla'), findsOneWidget);
    // Anuradhapura belongs to Maize only — the gate still holds.
    expect(find.text('Anuradhapura'), findsNothing);
  });

  testWidgets('re-tapping a chosen District re-offers every option', (
    tester,
  ) async {
    await tester.pumpWidget(const _Harness());
    await _tap(tester, 'Select Crop');
    await tester.tap(find.text('Carrot').last);
    await tester.pumpAndSettle();

    await _tap(tester, 'Select District');
    await tester.tap(find.text('Badulla').last);
    await tester.pumpAndSettle();

    // Blur restored the committed selection into the field.
    expect(
      tester
          .widget<TextFormField>(
            find.widgetWithText(TextFormField, 'Select District'),
          )
          .controller
          ?.text,
      'Badulla',
    );

    // Re-opening must offer the whole list again, not just the last filter.
    await _tap(tester, 'Select District');
    expect(find.text('Nuwara Eliya'), findsOneWidget);
  });

  testWidgets('changing crop clears the district field and its options', (
    tester,
  ) async {
    await tester.pumpWidget(const _Harness());
    await _tap(tester, 'Select Crop');
    await tester.tap(find.text('Carrot').last);
    await tester.pumpAndSettle();
    await _tap(tester, 'Select District');
    await tester.tap(find.text('Badulla').last);
    await tester.pumpAndSettle();

    // Switch to Maize.
    await _tap(tester, 'Select Crop');
    await tester.tap(find.text('Maize').last);
    await tester.pumpAndSettle();

    expect(
      tester
          .widget<TextFormField>(
            find.widgetWithText(TextFormField, 'Select District'),
          )
          .controller
          ?.text,
      isEmpty,
    );

    await _tap(tester, 'Select District');
    expect(find.text('Anuradhapura'), findsOneWidget);
    expect(find.text('Nuwara Eliya'), findsNothing);
  });

  // The extraction's own guarantee: itemLabel translates what is RENDERED
  // while the English key stays the committed value, and the filter matches
  // either script. Yield relies on the identity default (options stay
  // English); the other five screens pass a real label function.
  testWidgets('itemLabel renders translations but keeps English keys', (
    tester,
  ) async {
    String? committed;
    final ctrl = TextEditingController();
    final focus = FocusNode();
    addTearDown(ctrl.dispose);
    addTearDown(focus.dispose);
    focus.addListener(() => syncSearchField(focus, ctrl, committed));

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SearchableDropdown(
            label: 'Crop',
            value: committed,
            items: const ['Carrot', 'Maize'],
            icon: Icons.eco,
            accent: AppTheme.accents.price,
            searchHint: 'Type to search',
            itemLabel: (c) => const {'Carrot': 'කැරට්', 'Maize': 'බඩඉරිඟු'}[c]!,
            controller: ctrl,
            focusNode: focus,
            onChanged: (v) => committed = v,
          ),
        ),
      ),
    );

    await _tap(tester, 'Crop');
    expect(find.text('කැරට්'), findsOneWidget);
    expect(find.text('Carrot'), findsNothing);

    // Typing the English key still finds the crop whose label is Sinhala.
    await tester.enterText(find.widgetWithText(TextFormField, 'Crop'), 'carr');
    await tester.pumpAndSettle();
    expect(find.text('කැරට්'), findsOneWidget);
    expect(find.text('බඩඉරිඟු'), findsNothing);

    await tester.tap(find.text('කැරට්').last);
    await tester.pumpAndSettle();
    expect(committed, 'Carrot');
  });
}
