import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// Mirrors MainShell's transition: a fade-through over an IndexedStack whose
// children are never swapped, so their State survives the switch.
class _Shell extends StatefulWidget {
  const _Shell();
  @override
  State<_Shell> createState() => _ShellState();
}

class _ShellState extends State<_Shell>
    with SingleTickerProviderStateMixin {
  int _index = 0;
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 200),
    reverseDuration: const Duration(milliseconds: 110),
    value: 1.0,
  );
  late final Animation<double> _fade = CurvedAnimation(
    parent: _c, curve: Curves.easeOut, reverseCurve: Curves.easeIn);

  final _screens = const [_Counter(key: ValueKey('a'), label: 'A'),
                          _Counter(key: ValueKey('b'), label: 'B')];

  Future<void> go(int i) async {
    if (i != _index) {
      await _c.reverse();
      if (!mounted) return;
      setState(() => _index = i);
      _c.forward();
    }
  }

  @override
  void dispose() { _c.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) => MaterialApp(
        home: Scaffold(
          body: FadeTransition(
            key: const ValueKey('pageFade'),
            opacity: _fade,
            child: IndexedStack(index: _index, children: _screens),
          ),
          bottomNavigationBar: Row(children: [
            TextButton(onPressed: () => go(0), child: const Text('go A')),
            TextButton(onPressed: () => go(1), child: const Text('go B')),
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
  Widget build(BuildContext context) => TextButton(
        onPressed: () => setState(() => taps++),
        child: Text('${widget.label}:$taps'),
      );
}

double opacityOf(WidgetTester t) => t
    .widget<FadeTransition>(find.byKey(const ValueKey('pageFade')))
    .opacity
    .value;

void main() {
  testWidgets('content fades out then back in on tab switch', (t) async {
    await t.pumpWidget(const _Shell());
    expect(opacityOf(t), 1.0);

    await t.tap(find.text('go B'));
    await t.pump(); // let the controller start ticking

    await t.pump(const Duration(milliseconds: 50));
    final midOut = opacityOf(t);
    expect(midOut, lessThan(1.0), reason: 'should be fading out');
    expect(midOut, greaterThan(0.0));

    await t.pump(const Duration(milliseconds: 120));
    expect(opacityOf(t), closeTo(0.0, 0.01), reason: 'fade-out completes');

    await t.pump(const Duration(milliseconds: 60));
    final midIn = opacityOf(t);
    expect(midIn, greaterThan(0.0), reason: 'should be fading back in');
    expect(midIn, lessThan(1.0));

    await t.pumpAndSettle();
    expect(opacityOf(t), 1.0);
  });

  testWidgets('screen state survives switching away and back', (t) async {
    await t.pumpWidget(const _Shell());

    await t.tap(find.text('A:0'));           // bump A's counter
    await t.pumpAndSettle();
    expect(find.text('A:1'), findsOneWidget);

    await t.tap(find.text('go B'));          // leave
    await t.pumpAndSettle();
    await t.tap(find.text('go A'));          // come back
    await t.pumpAndSettle();

    // State preserved — this is what an AnimatedSwitcher would have lost.
    expect(find.text('A:1'), findsOneWidget);
  });

  testWidgets('re-tapping the current tab does not animate', (t) async {
    await t.pumpWidget(const _Shell());
    await t.tap(find.text('go A'));
    await t.pump();
    await t.pump(const Duration(milliseconds: 60));
    expect(opacityOf(t), 1.0); // never dipped
  });
}
