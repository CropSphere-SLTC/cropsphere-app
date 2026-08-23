import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// Mirrors MainShell's crossfade: every screen keeps ONE permanent element
// (so its State survives a tab switch) and only its opacity animates, with
// the outgoing screen's start opacity captured so an interrupted fade
// continues from where it actually was.
class _Shell extends StatefulWidget {
  const _Shell();
  @override
  State<_Shell> createState() => _ShellState();
}

class _ShellState extends State<_Shell> with SingleTickerProviderStateMixin {
  static const dur = Duration(milliseconds: 150);
  int _index = 0;
  int? _outgoing;
  double _outgoingFrom = 1.0;

  late final AnimationController _c =
      AnimationController(vsync: this, duration: dur, value: 1.0);

  final _screens = const [
    _Counter(key: ValueKey('a'), label: 'A'),
    _Counter(key: ValueKey('b'), label: 'B'),
    _Counter(key: ValueKey('c'), label: 'C'),
  ];

  void go(int i) {
    if (i == _index) return;
    setState(() {
      _outgoing = _index;
      _outgoingFrom = _c.value;
      _index = i;
    });
    _c.forward(from: 0);
  }

  @override
  void dispose() { _c.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) => MaterialApp(
        home: Scaffold(
          body: AnimatedBuilder(
            animation: _c,
            builder: (context, _) {
              final t = _c.value;
              return Stack(
                fit: StackFit.expand,
                children: [
                  for (var i = 0; i < _screens.length; i++)
                    IgnorePointer(
                      ignoring: i != _index,
                      child: Opacity(
                        key: ValueKey('op$i'),
                        opacity: i == _index
                            ? t
                            : (i == _outgoing ? (1 - t) * _outgoingFrom : 0.0),
                        child: _screens[i],
                      ),
                    ),
                ],
              );
            },
          ),
          bottomNavigationBar: Row(children: [
            for (final e in {'A': 0, 'B': 1, 'C': 2}.entries)
              TextButton(onPressed: () => go(e.value), child: Text('go ${e.key}')),
          ]),
        ),
      );
}

class _Counter extends StatefulWidget {
  final String label;
  const _Counter({super.key, required this.label});
  @override
  State<_Counter> createState() => _CounterState();
}

class _CounterState extends State<_Counter> {
  int taps = 0;
  @override
  Widget build(BuildContext context) => Align(
        alignment: Alignment.topLeft,
        child: TextButton(
          onPressed: () => setState(() => taps++),
          child: Text('${widget.label}:$taps'),
        ),
      );
}

double op(WidgetTester t, int i) =>
    t.widget<Opacity>(find.byKey(ValueKey('op$i'))).opacity;

void main() {
  testWidgets('outgoing and incoming are both visible mid-crossfade',
      (t) async {
    await t.pumpWidget(const _Shell());
    expect(op(t, 0), 1.0);

    await t.tap(find.text('go B'));
    await t.pump();
    await t.pump(const Duration(milliseconds: 75)); // halfway

    // The defining property of a crossfade: both on screen at once.
    expect(op(t, 0), greaterThan(0.0), reason: 'outgoing still visible');
    expect(op(t, 0), lessThan(1.0));
    expect(op(t, 1), greaterThan(0.0), reason: 'incoming already visible');
    expect(op(t, 1), lessThan(1.0));

    await t.pumpAndSettle();
    expect(op(t, 1), 1.0);
    expect(op(t, 0), 0.0);
  });

  testWidgets('screen state survives switching away and back', (t) async {
    await t.pumpWidget(const _Shell());
    await t.tap(find.text('A:0'));
    await t.pumpAndSettle();
    expect(find.text('A:1'), findsOneWidget);

    await t.tap(find.text('go B'));
    await t.pumpAndSettle();
    await t.tap(find.text('go A'));
    await t.pumpAndSettle();

    // Preserved — an AnimatedSwitcher would have lost this.
    expect(find.text('A:1'), findsOneWidget);
  });

  testWidgets('rapid repeated taps leave no stuck or overlapping state',
      (t) async {
    await t.pumpWidget(const _Shell());

    // Interrupt each transition well before it finishes.
    await t.tap(find.text('go B'));
    await t.pump();
    await t.pump(const Duration(milliseconds: 40));
    await t.tap(find.text('go C'));
    await t.pump();
    await t.pump(const Duration(milliseconds: 40));
    await t.tap(find.text('go A'));
    await t.pump();
    await t.pump(const Duration(milliseconds: 40));
    await t.tap(find.text('go B'));

    await t.pumpAndSettle();

    // Exactly one screen fully visible, everything else fully gone.
    expect(op(t, 1), 1.0, reason: 'final destination settled opaque');
    expect(op(t, 0), 0.0, reason: 'no screen left stuck part-faded');
    expect(op(t, 2), 0.0, reason: 'no screen left stuck part-faded');
  });

  testWidgets('interrupting mid-fade never jumps opacity back up',
      (t) async {
    await t.pumpWidget(const _Shell());
    await t.tap(find.text('go B'));
    await t.pump();
    await t.pump(const Duration(milliseconds: 75));
    final bMid = op(t, 1);

    // B is now the outgoing screen — it must continue down from bMid, not
    // snap to 1.0 first.
    await t.tap(find.text('go C'));
    await t.pump();
    expect(op(t, 1), lessThanOrEqualTo(bMid + 0.001),
        reason: 'interrupted fade must not jump back to opaque');
  });

  testWidgets('only the destination receives taps mid-transition', (t) async {
    await t.pumpWidget(const _Shell());
    await t.tap(find.text('go B'));
    await t.pump();
    await t.pump(const Duration(milliseconds: 40));

    // A is still painted at ~0.7 opacity; its button must be inert.
    await t.tap(find.text('A:0'), warnIfMissed: false);
    await t.pumpAndSettle();
    expect(find.text('A:0'), findsOneWidget, reason: 'outgoing must not accept taps');
  });
}
