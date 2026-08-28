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
//     verified 6.92:1 contrast. ONE explicit, requested exception exists:
//     price_screen's "Predict Price" button uses accents.price.fill instead
//     (white on it is 5.18:1, separately verified) — see that button's own
//     comment. Every other screen's primary action, and Price's own
//     secondary "Ask AI about this" actions, still follow this rule.
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
//   #DF8A58   2.65✗   5.62✓     2.56✗     Terracotta — see price's entry below:
//                                          reverted here from a deepened
//                                          #AB5524 (5.18✓ white) that existed
//                                          specifically to fix this row. White
//                                          onFill was kept anyway, by request —
//                                          this is now a KNOWN, ACCEPTED
//                                          failure, not an oversight.
//   #4E7FA3   4.30✗   3.47✗     4.15✗     Deep Blue, muted (2026-08) — no
//                                          longer self-sufficient; see
//                                          weather's own entry below. Was
//                                          #2D689B (5.89✓ white, 2.53✗
//                                          #1F2A1F, 5.69✓ as text), the only
//                                          self-sufficient hue before this
//                                          revision.
//   #7CA759   2.79✗   5.34✓     2.69✗     Muted Olive
//   #613298   8.69✓   1.72✗     8.38✓     Rebecca Purple (2026-08) — the ONLY
//                                          hue here that clears AA in BOTH
//                                          directions at once. Replaced #BA9454
//                                          Ochre (2.82✗ / 5.29✓ / 2.72✗), which
//                                          the demand screen never actually
//                                          rendered — that page was hardcoded
//                                          indigo. See demand's entry below.
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

  // NOTE: there was a `_onLight` (#1F2A1F, == login.textPrimary) here until
  // demand moved to Rebecca Purple. It was that accent's onFill and its last
  // consumer — dark ink measures 1.72:1 on the new fill — so it is gone
  // rather than left dangling. The class doc above still measures every hue
  // against #1F2A1F as one of the two candidate text colours; that is a
  // reference point for choosing an onFill, not a token anything now uses.
  static const Color _hunter = Color(0xFF306534); // == login.primaryDark

  /// Sea Green identity, but see the class comment: #3A8943 carries no small
  /// text, so the header falls back to Hunter Green.
  FeatureAccent get yield => const FeatureAccent(
    fill: _hunter,
    onFill: Colors.white, // 6.92:1
    ink: _hunter, // 6.67:1 on #FCFBF6
  );

  /// Terracotta.
  ///
  /// KNOWN, ACCEPTED CONTRAST FAILURE — read before touching this again.
  /// This shipped once already as a deepened #AB5524 specifically so white
  /// onFill would clear AA (5.18:1). By explicit request this was reverted
  /// to the original #DF8A58, WITH onFill kept at white — which measures
  /// 2.65:1 here, under even the 3:1 non-text floor. That is not a bug in
  /// this getter; it is what was asked for, twice, after the trade-off (and
  /// its downstream effects — the header gradient's light stop, the icon
  /// badge scrim, the Predict Price button) was shown with numbers each
  /// time. If this needs to pass AA again, #AB5524 is the value that did —
  /// see git history for this file around "deepen the header fill".
  ///
  /// ink is unaffected either way: it was independently verified against
  /// the page background, not against fill.
  FeatureAccent get price => const FeatureAccent(
    fill: Color(0xFFDF8A58),
    onFill: Colors.white, // 2.65:1 — FAILS AA, accepted, see above
    ink: Color(0xFFB75A23), // 4.50:1 on #FCFBF6, unaffected by fill
  );

  /// Deep Blue, muted (2026-08 revision from #2D689B — more muted, closer to
  /// the rest of the accent palette, by explicit request).
  ///
  /// KNOWN, ACCEPTED CONTRAST FAILURE — read before touching this again.
  /// #2D689B was self-sufficient: fill doubled as its own ink, and white
  /// onFill cleared AA with real margin (5.89:1). This muted revision no
  /// longer does — white onFill measures 4.30:1, login.textPrimary onFill
  /// 3.47:1, BOTH under the 4.5:1 text floor (white still clears the 3:1
  /// non-text floor, textPrimary does not). White was kept anyway, shown
  /// both failing numbers first — same shape of trade-off as price's
  /// terracotta above, not an oversight. If this needs to pass AA again,
  /// #4C7B9F is the minimal darkening that gets white onFill to 4.52:1 (see
  /// git history around this comment if revisited).
  ///
  /// ink is a SEPARATE, independently-darkened value for the first time on
  /// this accent (previously == fill) — same HLS-darkening method used for
  /// cropRec/demand's ink tokens, verified only against the page background.
  FeatureAccent get weather => const FeatureAccent(
    fill: Color(0xFF4E7FA3),
    onFill: Colors.white, // 4.30:1 — FAILS AA, accepted, see above
    ink: Color(0xFF4A799B), // 4.50:1 on #FCFBF6
  );

  /// Deep Olive (2026-08 revision from the lighter #7CA759, by request —
  /// that header read as washed out).
  ///
  /// This accent CARRIES ITS TEXT, unlike price and weather: off-white on
  /// #3D5A3D measures 7.43:1, and 4.97:1 on the header's light gradient stop.
  /// Both clear AA with margin, so there is no accepted-failure caveat here.
  ///
  /// onFill is the app's warm off-white (== login.background), not pure white:
  /// it matches the page ground the rest of the UI is built on, and it costs
  /// almost nothing against it (7.43 vs 7.70 for #FFFFFF).
  ///
  /// The previous value could NOT simply be darkened. onFill was dark ink
  /// (#1F2A1F) at 5.34:1, and darkening a mid-green erodes dark-on-it
  /// contrast fast — it fell under AA by -0.05 lightness (4.40:1), long
  /// before the fill looked meaningfully darker. Going dark enough to read as
  /// fixed meant flipping the text to off-white, which is why this is a
  /// two-part change rather than one hex.
  ///
  /// ink is UNCHANGED and unaffected: it was verified as text against the
  /// page background, never against fill.
  FeatureAccent get cropRec => const FeatureAccent(
    fill: Color(0xFF3D5A3D),
    onFill: Color(0xFFFCFBF6), // 7.43:1 on fill, 4.97:1 on the light stop
    ink: Color(0xFF5D7D42), // 4.53:1 on #FCFBF6
  );

  /// Rebecca Purple (2026-08 revision from the ochre #BA9454, by request).
  ///
  /// SELF-SUFFICIENT, and the only accent in this class that currently is:
  /// #613298 measures 8.38:1 as text on the page background, so `ink` needs
  /// no separate HLS darkening at all — fill doubles as its own ink, the way
  /// weather's #2D689B did before it was muted. yield/chat also ship
  /// ink == fill, but by falling back to primaryDark rather than by passing
  /// on their own hue's merits.
  ///
  /// Nothing here is a known-accepted failure. Both gradient ends clear AA
  /// for normal-size text with real margin:
  ///
  ///   #613298 (dark anchor, == fill)      onFill 8.38:1
  ///   #8751C6 (light stop, +0.15 HLS L)   onFill 5.04:1
  ///
  /// onFill is the app's warm off-white (== login.background), matching
  /// cropRec's reasoning rather than price/weather's pure white — it costs
  /// almost nothing against it (8.38 vs 8.69 for #FFFFFF) and matches the
  /// page ground the rest of the UI is built on. The old _onLight (#1F2A1F)
  /// is NOT an option on this hue: it measures 1.72:1, far under any floor.
  ///
  /// WHY THIS ACCENT MOVED AT ALL. The ochre it replaces was never rendered.
  /// demand_screen predated the accent system and hardcoded #283593/#3F51B5
  /// indigo in six places, so accents.demand had exactly one reference in
  /// the whole repo — accent_contrast_test.dart. This revision is the first
  /// time the token reaches the screen.
  FeatureAccent get demand => const FeatureAccent(
    fill: Color(0xFF613298),
    onFill: Color(0xFFFCFBF6), // 8.38:1 on fill, 5.04:1 on the light stop
    ink: Color(0xFF613298), // == fill; 8.38:1 on #FCFBF6, no darkening needed
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
