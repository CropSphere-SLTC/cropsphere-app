// lib/widgets/app_theme.dart
// CropSphere design system — green/teal agricultural theme

import 'package:flutter/material.dart';

class AppTheme {
  // Primary palette — deep agricultural green
  static const Color primary = Color(0xFF1B5E20);
  static const Color primaryLight = Color(0xFF4CAF50);
  static const Color primaryDark = Color(0xFF0A3D0A);

  // Accent — warm harvest amber
  static const Color accent = Color(0xFFFF8F00);
  static const Color accentLight = Color(0xFFFFB74D);

  // Surface
  static const Color surface = Color(0xFFF9FBF9);
  static const Color background = Color(0xFFF1F7F1);
  static const Color surfaceCard = Color(0xFFFFFFFF);
  static const Color surfaceDark = Color(0xFF1C2B1C);

  // Text
  static const Color textPrimary = Color(0xFF1A2B1A);
  static const Color textSecondary = Color(0xFF5A7A5A);
  static const Color textMuted = Color(0xFF8FA88F);

  // Status
  static const Color success = Color(0xFF2E7D32);
  static const Color warning = Color(0xFFF57F17);
  static const Color error = Color(0xFFC62828);
  static const Color info = Color(0xFF01579B);

  // On-colour — text/icons drawn ON a filled primary surface. Distinct from
  // surfaceCard, which happens to be the same white but means "a card's
  // background"; screens were reaching for a bare Colors.white here.
  static const Color onPrimary = Color(0xFFFFFFFF);

  // Disabled — a control that is present but not actionable. Neutral rather
  // than green-tinted, so a disabled button reads as inert instead of as a
  // washed-out brand colour.
  static const Color disabled = Color(0xFFBDBDBD);
  static const Color disabledSurface = Color(0x0A9E9E9E);

  // Hairlines. `border` outlines cards and inputs; `divider` is the heavier
  // rule between layout columns. Both were previously per-screen literals.
  static const Color border = Color(0xFFE0EBE0);
  static const Color divider = Color(0xFFE4EEE4);

  // A recessive surface for a panel nested INSIDE a card, where surfaceCard
  // would disappear against its parent.
  static const Color surfaceMuted = Color(0xFFF4F9F4);

  // ── Categorical data colours ──────────────────────────────────────────────
  //
  // Identity only — which chemical, which series. Assign in slot order and
  // never cycle; a sixth category folds into "Other" rather than inventing a
  // hue. Status colours (success/warning/error) are RESERVED for state and
  // must never be borrowed as a categorical slot: a reader cannot tell
  // "this is the third chemical" from "this one is dangerous".
  //
  // Validated as a categorical palette on the white card surface: OKLCH
  // lightness band and chroma floor pass, contrast >= 3:1, and the worst
  // ADJACENT pair separates by dE 18.6 (OKLab x100) under simulated
  // protanopia and deuteranopia. The set this replaced failed outright —
  // its green and orange collapsed to dE 2.3 under protanopia, i.e. they
  // were the same colour to a protan reader.
  //
  // Adjacent-pairs is the right test here because these tint a vertical LIST
  // of cards, each carrying its product name as a direct label, so identity
  // is never colour-alone. Do not reuse this set for a scatter or map
  // without re-validating with --pairs all, which it does not pass.
  static const Color data1 = Color(0xFF0F8A4F); // green
  static const Color data2 = Color(0xFF8E24AA); // purple
  static const Color data3 = Color(0xFFB26500); // amber
  static const Color data4 = Color(0xFF1565C0); // blue
  static const Color data5 = Color(0xFFAD1457); // crimson

  // Login/auth screen palette — see AppLoginTheme below.
  static const AppLoginTheme login = AppLoginTheme._();

  // Per-feature accent palette — see AppFeatureAccents below. Plural: the
  // singular `accent` above is the pre-existing harvest-amber token, still
  // used by the chat and admin screens.
  static const AppFeatureAccents accents = AppFeatureAccents._();

  // Confidence colors
  static Color confidenceColor(String confidence) {
    switch (confidence.toLowerCase()) {
      case 'high':
        return success;
      case 'medium':
        return warning;
      default:
        return error;
    }
  }

  // Trend colors
  static Color trendColor(String trend) {
    switch (trend.toLowerCase()) {
      case 'rising':
        return success;
      case 'falling':
        return error;
      default:
        return info;
    }
  }

  static ThemeData get lightTheme => ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(
      seedColor: primary,
      brightness: Brightness.light,
    ),
    scaffoldBackgroundColor: surface,
    appBarTheme: const AppBarTheme(
      backgroundColor: primary,
      foregroundColor: Colors.white,
      elevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(
        color: Colors.white,
        fontSize: 18,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.3,
      ),
    ),
    cardTheme: CardThemeData(
      color: surfaceCard,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: Color(0xFFE0EBE0), width: 1),
      ),
      margin: const EdgeInsets.symmetric(horizontal: 0, vertical: 4),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: primary,
        foregroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 24),
        textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: const Color(0xFFF1F7F1),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: Color(0xFFBDD6BD)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: Color(0xFFBDD6BD)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: primary, width: 2),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      labelStyle: const TextStyle(color: textSecondary),
    ),
    bottomNavigationBarTheme: const BottomNavigationBarThemeData(
      backgroundColor: surfaceCard,
      selectedItemColor: primary,
      unselectedItemColor: textMuted,
      type: BottomNavigationBarType.fixed,
      elevation: 8,
    ),
  );
}

// ─── LOGIN / AUTH SCREEN TOKENS ────────────────────────────────────────────
// Scoped palette for the light, warm login/sign-in restyle (2026-08). Kept
// separate from AppTheme's own primary/surface/text tokens above — those
// are still used by other screens' cardTheme/inputDecorationTheme and must
// not shift. Nest under AppTheme.login.* so call sites read as
// AppTheme.login.background, etc.
class AppLoginTheme {
  const AppLoginTheme._();

  // Instance getters (not static) so callers can write AppTheme.login.background
  // through the single const AppTheme.login instance above.
  Color get background => const Color(0xFFFCFBF6); // warm off-white card bg
  Color get primaryGreen =>
      const Color(0xFF3A8943); // Sea Green — primary actions
  Color get primaryDark =>
      const Color(0xFF306534); // Hunter Green — hover/pressed
  Color get borderSubtle =>
      const Color(0xFFE4E8E0); // soft input borders/dividers
  Color get textPrimary => const Color(0xFF1F2A1F); // main text on light bg
  Color get textSecondary => const Color(0xFF6B7A6B); // subtitles/placeholders
  // Midpoint between textSecondary and textPrimary — textSecondary alone,
  // especially with alpha applied, fell short of AA contrast for small
  // divider labels like "or" on the light card background (~8:1 at full
  // opacity here vs. well under 4.5:1 for the old faded textMuted usage).
  Color get dividerText => const Color(0xFF455245);
  // Muted text sitting directly on the outer page background (_bgOutside,
  // not the white card) — tagline subtitle, footer's second line. Computed
  // independently against that different backdrop (~6.43:1 here) since it's
  // not the same background dividerText was checked against; happens to
  // land on the same tone.
  Color get outsideMutedText => const Color(0xFF455245);
  Color get errorMuted => const Color(0xFFC0473F); // muted validation errors
  Color get focusRing => const Color(0xFF80B080); // Muted Olive — input focus
}

// ─── PER-FEATURE ACCENTS ─────────────────────────────────────────────────────
// One accent per feature screen, so Price/Weather/Demand read as distinct
// places in the app while every neutral, surface and primary action stays on
// AppTheme.login.*.
//
// WHERE ACCENTS MAY BE USED
//   • the feature's header card background        -> accent.X.fill  (+ onFill)
//   • that screen's section labels                -> accent.X.ink
//   • small icon tints within that screen         -> accent.X.ink
//
// WHERE THEY MAY NOT
//   • primary action buttons — those stay AppTheme.login.primaryDark app-wide,
//     so "press this to proceed" looks the same everywhere and keeps its
//     verified 6.92:1 contrast.
//   • page backgrounds, card surfaces, body text, borders, inputs — all stay
//     on the AppTheme.login.* neutrals.
//
// WHY THREE TOKENS AND NOT ONE
// A saturated fill and a readable ink are different jobs and, for four of
// these six hues, different colours. The identity hues were measured against
// both white and textPrimary (#1F2A1F) on the fill, and against the page
// background (#FCFBF6) as text:
//
//   fill      white   #1F2A1F   as text on #FCFBF6
//   #3A8943   4.34✗   3.43✗     4.19✗     Sea Green — fails BOTH on the fill
//   #DF8A58   2.65✗   5.62✓     2.56✗     Terracotta
//   #2D689B   5.89✓   2.53✗     5.69✓     Deep Blue — the only self-sufficient one
//   #7CA759   2.79✗   5.34✓     2.69✗     Muted Olive
//   #BA9454   2.82✗   5.29✓     2.72✗     Ochre
//
// So [fill] keeps the identity hue, [onFill] is whichever of white/textPrimary
// actually clears 4.5:1 on it, and [ink] is that hue darkened in HLS — hue and
// saturation preserved — until it clears 4.5:1 as TEXT on #FCFBF6. That last
// threshold is the binding one: anything passing it also clears 4.5:1 against
// white, so one ink token covers labels, icons and any white-on-accent surface.
//
// Sea Green is the exception. At 4.34:1 on white and 3.43:1 on textPrimary it
// carries no small text in either direction, so yield/chat use the existing,
// already-verified login.primaryDark (#306534, 6.92:1 white / 6.67:1 on the
// page background) rather than a newly invented green. #3A8943 remains correct
// where it is used today — as a button fill behind white, and as
// login.primaryGreen — it just cannot be a header carrying a 12px subtitle.
class FeatureAccent {
  /// Header-card background. The feature's identity colour.
  final Color fill;

  /// Text and icons drawn ON [fill]. Whichever of white / login.textPrimary
  /// reaches AA there — never assume white.
  final Color onFill;

  /// Section labels and small icon tints on the page background. Always AA
  /// against #FCFBF6, so it is also safe as a fill behind white.
  final Color ink;

  const FeatureAccent({
    required this.fill,
    required this.onFill,
    required this.ink,
  });
}

class AppFeatureAccents {
  const AppFeatureAccents._();

  static const Color _onLight = Color(0xFF1F2A1F); // == login.textPrimary
  static const Color _hunter = Color(0xFF306534); // == login.primaryDark

  /// Sea Green identity, but see the class comment: #3A8943 carries no small
  /// text, so the header falls back to Hunter Green.
  FeatureAccent get yield => const FeatureAccent(
    fill: _hunter,
    onFill: Colors.white, // 6.92:1
    ink: _hunter, // 6.67:1 on #FCFBF6
  );

  /// Terracotta.
  FeatureAccent get price => const FeatureAccent(
    fill: Color(0xFFDF8A58),
    onFill: _onLight, // 5.62:1
    ink: Color(0xFFB75A23), // 4.50:1 on #FCFBF6
  );

  /// Deep Blue — dark enough to take white text and to serve as its own ink.
  FeatureAccent get weather => const FeatureAccent(
    fill: Color(0xFF2D689B),
    onFill: Colors.white, // 5.89:1
    ink: Color(0xFF2D689B), // 5.69:1 on #FCFBF6
  );

  /// Muted Olive.
  FeatureAccent get cropRec => const FeatureAccent(
    fill: Color(0xFF7CA759),
    onFill: _onLight, // 5.34:1
    ink: Color(0xFF5D7D42), // 4.53:1 on #FCFBF6
  );

  /// Ochre.
  FeatureAccent get demand => const FeatureAccent(
    fill: Color(0xFFBA9454),
    onFill: _onLight, // 5.29:1
    ink: Color(0xFF8F6F3A), // 4.50:1 on #FCFBF6
  );

  /// Core brand green — same Sea Green caveat as [yield].
  FeatureAccent get chat => const FeatureAccent(
    fill: _hunter,
    onFill: Colors.white, // 6.92:1
    ink: _hunter, // 6.67:1 on #FCFBF6
  );
}

// ─── REUSABLE WIDGETS ────────────────────────────────────────────────────────

class CsCard extends StatelessWidget {
  final Widget child;
  final EdgeInsets? padding;
  final VoidCallback? onTap;

  const CsCard({super.key, required this.child, this.padding, this.onTap});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: padding ?? const EdgeInsets.all(16),
          child: child,
        ),
      ),
    );
  }
}

class CsDropdown extends StatelessWidget {
  final String label;
  final String? value;
  final List<String> items;
  final ValueChanged<String?> onChanged;

  const CsDropdown({
    super.key,
    required this.label,
    required this.value,
    required this.items,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<String>(
      initialValue: value,
      decoration: InputDecoration(labelText: label),
      items: items
          .map((item) => DropdownMenuItem(value: item, child: Text(item)))
          .toList(),
      onChanged: onChanged,
    );
  }
}

class CsSlider extends StatelessWidget {
  final String label;
  final double value;
  final double min;
  final double max;
  final String unit;
  final ValueChanged<double> onChanged;
  final int divisions;

  const CsSlider({
    super.key,
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.unit,
    required this.onChanged,
    this.divisions = 100,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              label,
              style: const TextStyle(
                fontSize: 13,
                color: AppTheme.textSecondary,
              ),
            ),
            Text(
              '${value.toStringAsFixed(1)} $unit',
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppTheme.primary,
              ),
            ),
          ],
        ),
        Slider(
          value: value,
          min: min,
          max: max,
          divisions: divisions,
          activeColor: AppTheme.primary,
          onChanged: onChanged,
        ),
      ],
    );
  }
}

class CsLoadingOverlay extends StatelessWidget {
  final bool isLoading;
  final Widget child;

  const CsLoadingOverlay({
    super.key,
    required this.isLoading,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        child,
        if (isLoading)
          Container(
            color: Colors.black12,
            child: const Center(
              child: CircularProgressIndicator(color: AppTheme.primary),
            ),
          ),
      ],
    );
  }
}

class CsMockBadge extends StatelessWidget {
  const CsMockBadge({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: AppTheme.warning.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: AppTheme.warning.withValues(alpha: 0.4)),
      ),
      child: const Text(
        'MOCK DATA',
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: AppTheme.warning,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

class CsConfidenceBadge extends StatelessWidget {
  final String confidence;

  const CsConfidenceBadge({super.key, required this.confidence});

  @override
  Widget build(BuildContext context) {
    final color = AppTheme.confidenceColor(confidence);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(
        confidence.toUpperCase(),
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: color,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

class CsErrorWidget extends StatelessWidget {
  final String message;
  final VoidCallback? onRetry;

  const CsErrorWidget({super.key, required this.message, this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, color: AppTheme.error, size: 48),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppTheme.textSecondary),
            ),
            if (onRetry != null) ...[
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh, size: 16),
                label: const Text('Retry'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class CsEmptyState extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;

  const CsEmptyState({
    super.key,
    required this.title,
    required this.subtitle,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: AppTheme.textMuted, size: 64),
            const SizedBox(height: 16),
            Text(
              title,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: AppTheme.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppTheme.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}
