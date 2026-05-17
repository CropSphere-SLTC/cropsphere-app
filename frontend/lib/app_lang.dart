// lib/app_lang.dart
// ─────────────────────────────────────────────────────────────────────────────
//  Global language state — single source of truth for EN / SI / TA
//  Used by: LoginScreen, MainShell, DashboardScreen, and every other screen.
//
//  HOW IT WORKS
//  ┌──────────────────────────────────────────────────────────────┐
//  │  AppLangNotifier (ChangeNotifier)                            │
//  │    • holds current AppLang                                   │
//  │    • setLang(AppLang) → notifyListeners()                    │
//  │                                                              │
//  │  AppLangProvider (InheritedNotifier<AppLangNotifier>)        │
//  │    • wraps the whole app in main.dart                        │
//  │    • AppLangProvider.of(context) → AppLangNotifier           │
//  │    • AppLangProvider.lang(context) → current AppLang         │
//  └──────────────────────────────────────────────────────────────┘
//
//  USAGE IN ANY WIDGET
//    final lang = AppLangProvider.lang(context);       // read
//    AppLangProvider.of(context).setLang(AppLang.si);  // write
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';

// Re-export so every file only needs to import app_lang.dart
export 'package:flutter/foundation.dart' show ChangeNotifier;

// ── Enum ──────────────────────────────────────────────────────────────────────
enum AppLang { en, si, ta }

extension AppLangLabel on AppLang {
  String get label => switch (this) {
        AppLang.en => 'EN',
        AppLang.si => 'සිං',
        AppLang.ta => 'தமிழ்',
      };

  String get fullName => switch (this) {
        AppLang.en => 'English',
        AppLang.si => 'සිංහල',
        AppLang.ta => 'தமிழ்',
      };
}

// ── Notifier ─────────────────────────────────────────────────────────────────
class AppLangNotifier extends ChangeNotifier {
  AppLang _lang = AppLang.en;

  AppLang get lang => _lang;

  void setLang(AppLang l) {
    if (l == _lang) return;
    _lang = l;
    notifyListeners();
  }
}

// ── Provider ─────────────────────────────────────────────────────────────────
class AppLangProvider extends InheritedNotifier<AppLangNotifier> {
  const AppLangProvider({
    super.key,
    required AppLangNotifier notifier,
    required super.child,
  }) : super(notifier: notifier);

  /// Read the notifier (for writing / listening).
  static AppLangNotifier of(BuildContext context) {
    final provider =
        context.dependOnInheritedWidgetOfExactType<AppLangProvider>();
    assert(provider != null,
        'AppLangProvider not found. Wrap your app with AppLangProvider in main.dart.');
    return provider!.notifier!;
  }

  /// Convenience: just read current language.
  static AppLang lang(BuildContext context) => of(context).lang;
}
