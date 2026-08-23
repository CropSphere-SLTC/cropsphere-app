import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// Mirrors yield_screen's _searchableDropdown + _syncSearchField so the
// tap-to-open behaviour is pinned without dragging Firebase/services in.
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
    _cropFocus.addListener(
      () => _syncSearchField(_cropFocus, _cropCtrl, _crop),
    );
    _districtFocus.addListener(
      () => _syncSearchField(_districtFocus, _districtCtrl, _district),
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

  // Copy of yield_screen._syncSearchField.
  void _syncSearchField(
    FocusNode node,
    TextEditingController ctrl,
    String? selected,
  ) {
    if (node.hasFocus) {
      if (ctrl.text.isNotEmpty) {
        ctrl.clear();
      } else {
        ctrl.value = const TextEditingValue(text: ' ');
        ctrl.clear();
      }
      return;
    }
    final want = selected ?? '';
    if (ctrl.text != want) ctrl.text = want;
  }

  List<String> get _availableDistricts =>
      _crop != null ? (_districts[_crop!] ?? []) : [];

  Widget _dropdown({
    required String label,
    required String? value,
    required List<String> items,
    required ValueChanged<String?> onChanged,
    required TextEditingController controller,
    required FocusNode focusNode,
    bool enabled = true,
  }) => LayoutBuilder(
    builder: (ctx, bc) => RawAutocomplete<String>(
      textEditingController: controller,
      focusNode: focusNode,
      optionsBuilder: (TextEditingValue v) {
        if (!enabled) return const Iterable<String>.empty();
        final q = v.text.trim().toLowerCase();
        if (q.isEmpty || q == (value ?? '').toLowerCase()) return items;
        return items.where((e) => e.toLowerCase().contains(q));
      },
      onSelected: (sel) {
        onChanged(sel);
        focusNode.unfocus();
      },
      fieldViewBuilder: (ctx, ctrl, fn, onFieldSubmitted) => TextFormField(
        controller: ctrl,
        focusNode: fn,
        enabled: enabled,
        decoration: InputDecoration(labelText: label),
      ),
      optionsViewBuilder: (ctx, onSelected, options) => Align(
        alignment: Alignment.topLeft,
        child: Material(
          child: SizedBox(
            width: bc.maxWidth,
            child: ListView(
              shrinkWrap: true,
              children: [
                for (final o in options)
                  InkWell(
                    onTap: () => onSelected(o),
                    child: Padding(
                      padding: const EdgeInsets.all(8),
                      child: Text(o),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) => MaterialApp(
    home: Scaffold(
      body: Column(
        children: [
          _dropdown(
            label: 'Select Crop',
            value: _crop,
            items: _crops,
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
          _dropdown(
            label: 'Select District',
            value: _district,
            items: _availableDistricts,
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
      tester.widget<TextFormField>(
        find.widgetWithText(TextFormField, 'Select District'),
      ).controller?.text,
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
      tester.widget<TextFormField>(
        find.widgetWithText(TextFormField, 'Select District'),
      ).controller?.text,
      isEmpty,
    );

    await _tap(tester, 'Select District');
    expect(find.text('Anuradhapura'), findsOneWidget);
    expect(find.text('Nuwara Eliya'), findsNothing);
  });
}
