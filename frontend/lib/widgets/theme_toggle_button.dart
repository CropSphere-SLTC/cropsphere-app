// lib/widgets/theme_toggle_button.dart
// Sun/moon dark-mode toggle for every screen's top-bar cluster, sitting
// between the language control and the profile avatar. UI-only for now —
// see app_theme_mode.dart for what "UI-only" means and where the state
// lives (an app-wide InheritedNotifier, ready for a real dark theme to
// read later).
//
// The icon swap spins between sun and moon (half turn + fade) rather than
// the plain scale+fade the copy button uses elsewhere — a toggle that
// visibly flips two opposite states reads better as a "turn" than a
// "pop", so this earns its own, slightly longer transition instead of
// reusing that convention verbatim.

import 'package:flutter/material.dart';

import '../app_theme_mode.dart';

class ThemeToggleButton extends StatelessWidget {
  final double size;
  final Color? color;

  const ThemeToggleButton({super.key, this.size = 20, this.color});

  @override
  Widget build(BuildContext context) {
    final isDark = AppThemeModeProvider.isDark(context);
    final iconColor = color ?? const Color(0xFF4A4A4A);

    return Semantics(
      button: true,
      label: isDark ? 'Switch to light mode' : 'Switch to dark mode',
      child: IconButton(
        icon: AnimatedSwitcher(
          duration: const Duration(milliseconds: 420),
          switchInCurve: Curves.easeInOut,
          switchOutCurve: Curves.easeInOut,
          transitionBuilder: (child, animation) {
            // Incoming icon spins in from -180° to 0° while fading in;
            // AnimatedSwitcher runs the outgoing icon's own transition in
            // reverse at the same time, so it spins out from 0° to +180°
            // — together they read as one continuous half-turn, sun
            // rotating away as the moon rotates into its place.
            final turns = Tween(
              begin: -0.5,
              end: 0.0,
            ).animate(animation);
            return RotationTransition(
              turns: turns,
              child: FadeTransition(opacity: animation, child: child),
            );
          },
          child: Icon(
            isDark ? Icons.dark_mode_rounded : Icons.light_mode_rounded,
            key: ValueKey(isDark),
            size: size,
            color: iconColor,
          ),
        ),
        onPressed: () => AppThemeModeProvider.of(context).toggle(),
        tooltip: isDark ? 'Switch to light mode' : 'Switch to dark mode',
        padding: EdgeInsets.zero,
        visualDensity: VisualDensity.compact,
        constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
      ),
    );
  }
}
