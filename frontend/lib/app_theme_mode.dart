// lib/app_theme_mode.dart
// ─────────────────────────────────────────────────────────────────────────────
//  Global dark/light TOGGLE state — UI-only for now (see note below).
//  Mirrors app_lang.dart's notifier/provider shape so it's a familiar,
//  drop-in pattern for whoever wires up the real theme switch later.
//
//  HOW IT WORKS
//  ┌──────────────────────────────────────────────────────────────┐
//  │  AppThemeModeNotifier (ChangeNotifier)                        │
//  │    • holds current isDark (bool)                              │
//  │    • toggle() / setDark(bool) → notifyListeners()              │
//  │    • persists to shared_preferences so the toggle's position   │
//  │      survives an app restart                                   │
//  │                                                                │
//  │  AppThemeModeProvider (InheritedNotifier<AppThemeModeNotifier>)│
//  │    • wraps the whole app in main.dart, next to AppLangProvider │
//  │    • AppThemeModeProvider.of(context) → AppThemeModeNotifier   │
//  │    • AppThemeModeProvider.isDark(context) → current bool       │
//  └──────────────────────────────────────────────────────────────┘
//
//  USAGE IN ANY WIDGET
//    final isDark = AppThemeModeProvider.isDark(context);            // read
//    AppThemeModeProvider.of(context).toggle();                      // write
//
//  IMPORTANT — this is UI state only. Nothing reads `isDark` to swap
//  AppTheme.lightTheme for a dark variant yet; MaterialApp.theme in
//  main.dart is still hard-wired to AppTheme.lightTheme. A future dark
//  theme just needs to read AppThemeModeProvider.isDark(context) there —
//  the toggle button, its persistence, and this notifier are already in
//  place for that.
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _themeModePrefsKey = 'app_theme_mode_is_dark';

// ── Notifier ─────────────────────────────────────────────────────────────────
class AppThemeModeNotifier extends ChangeNotifier {
  bool _isDark = false;

  bool get isDark => _isDark;

  /// Loads the last-saved toggle position, if any — called once from
  /// main.dart at startup. A missing/unreadable prefs value silently keeps
  /// the light default rather than failing app boot over a cosmetic toggle.
  Future<void> loadSaved() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getBool(_themeModePrefsKey);
      if (saved != null && saved != _isDark) {
        _isDark = saved;
        notifyListeners();
      }
    } catch (_) {
      // Keep the light default.
    }
  }

  void toggle() => setDark(!_isDark);

  void setDark(bool dark) {
    if (dark == _isDark) return;
    _isDark = dark;
    notifyListeners();
    _persist(dark);
  }

  Future<void> _persist(bool dark) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_themeModePrefsKey, dark);
    } catch (_) {
      // Best-effort — a failed save just means the toggle resets to light
      // next launch, not a functional loss.
    }
  }
}

// ── Provider ─────────────────────────────────────────────────────────────────
class AppThemeModeProvider extends InheritedNotifier<AppThemeModeNotifier> {
  const AppThemeModeProvider({
    super.key,
    required AppThemeModeNotifier notifier,
    required super.child,
  }) : super(notifier: notifier);

  /// Read the notifier (for writing / listening).
  static AppThemeModeNotifier of(BuildContext context) {
    final provider = context
        .dependOnInheritedWidgetOfExactType<AppThemeModeProvider>();
    assert(
      provider != null,
      'AppThemeModeProvider not found. Wrap your app with '
      'AppThemeModeProvider in main.dart.',
    );
    return provider!.notifier!;
  }

  /// Convenience: just read the current toggle position.
  static bool isDark(BuildContext context) => of(context).isDark;
}
