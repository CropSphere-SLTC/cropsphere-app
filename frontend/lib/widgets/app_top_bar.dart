// lib/widgets/app_top_bar.dart
// ─────────────────────────────────────────────────────────────────────────────
//  The ONE top nav bar, shared by every dashboard-style screen (Dashboard,
//  Yield, Price, Weather, Crop Recommend, Demand).
//
//  WHY THIS EXISTS
//  top_nav_items.dart already extracted the 7-item nav ROW for exactly this
//  reason ("six copies had already drifted once"). Everything AROUND that
//  row — the bar's own height, the logo badge, its glyph, the wordmark, the
//  language/theme/avatar cluster — was still six independent copies, and had
//  drifted the same way: two screens (Dashboard, Price) had grown an entire
//  second, hand-tuned "mobile" bar (different height, different logo size,
//  a hand-rolled "CropSphere" text instead of BrandWordmark, none of it
//  wired to TopNavMetrics); Yield and Price hardcoded the logo glyph at a
//  fixed 32px instead of scaling with TopNavMetrics.logoGlyphSize (so it
//  stays undersized on any monitor ≥1280px, where the badge around it does
//  grow); and three DIFFERENT versions of the logo artwork itself were in
//  circulation (Demand/Crop Recommend's was missing two vein strokes and
//  three flower highlights; Dashboard's had two extra dew-drop ellipses
//  none of the others carried). This file is the fix for the whole class of
//  bug, not just the specific symptom: one widget, one logo, one metrics
//  source, six call sites.
//
//  No separate mobile variant. TopNavItems already self-hides below
//  kTopNavRowMinWidth (600px) — see top_nav_items.dart — so the Expanded
//  wrapping it can stay unconditional at every width: an Expanded around a
//  zero-size child still claims the space, which is what pushes the
//  language/theme/avatar cluster to the right on a phone exactly as it does
//  on a desktop. That is what let Yield's original _buildTopBar do this
//  correctly with no isMobile branching at all — this widget follows that
//  shape rather than the extra-LayoutBuilder pattern some other screens used
//  defensively on top of the same self-hiding behaviour.
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../app_lang.dart';
import 'app_theme.dart';
import 'brand_wordmark.dart';
import 'language_control.dart';
import 'profile_avatar_button.dart';
import 'theme_toggle_button.dart';
import 'top_nav_items.dart';
import 'top_nav_metrics.dart';

/// The circular badge's glyph. Picked as the canonical version because it
/// was already the majority (Yield, Price, Weather agreed) — Demand and Crop
/// Recommend's simplified copy and Dashboard's extended one both move onto
/// this rather than the reverse, so four of six screens change and three
/// keep their exact current pixels.
const String kCropSphereLogoSvg =
    '''<svg viewBox="0 0 110 110" xmlns="http://www.w3.org/2000/svg">
  <ellipse cx="55" cy="96" rx="36" ry="7" fill="#1B4D1B" opacity="0.7"/>
  <path d="M55 95 C55 80 52 65 50 50" stroke="#4CAF50" stroke-width="2.5" stroke-linecap="round" fill="none"/>
  <path d="M50 65 C35 58 22 42 28 28 C38 40 48 55 50 65Z" fill="#388E3C" opacity="0.9"/>
  <path d="M50 65 C42 58 35 44 28 28" stroke="#2E7D32" stroke-width="1" fill="none" opacity="0.6"/>
  <path d="M52 58 C67 50 80 36 74 22 C64 34 55 50 52 58Z" fill="#4CAF50" opacity="0.9"/>
  <path d="M52 58 C62 50 70 36 74 22" stroke="#388E3C" stroke-width="1" fill="none" opacity="0.6"/>
  <path d="M50 50 C38 44 30 32 34 20 C42 30 48 42 50 50Z" fill="#66BB6A" opacity="0.8"/>
  <circle cx="50" cy="28" r="3.5" fill="#FFC107" opacity="0.9"/>
  <circle cx="44" cy="22" r="3" fill="#FFB300" opacity="0.85"/>
  <circle cx="56" cy="20" r="3" fill="#FFC107" opacity="0.9"/>
  <circle cx="50" cy="14" r="3.5" fill="#FFD54F" opacity="0.95"/>
  <circle cx="43" cy="13" r="2.5" fill="#FFB300" opacity="0.8"/>
  <circle cx="57" cy="12" r="2.5" fill="#FFC107" opacity="0.85"/>
  <circle cx="50" cy="8" r="2" fill="#FFD54F" opacity="0.9"/>
  <path d="M50 50 C50 42 50 35 50 28" stroke="#558B2F" stroke-width="2" stroke-linecap="round" fill="none"/>
</svg>''';

/// Every screen's nav row shows the same 7 labels, in the app's active
/// language. Was six copies of this exact trilingual array (one already
/// drifted — Dashboard's built the English list with a multi-line literal
/// where the others used one line, purely cosmetic, but drift is drift).
List<String> topNavLabels(BuildContext context) {
  final lang = AppLangProvider.lang(context);
  return switch (lang) {
    AppLang.si => ['මුල', 'අස්වැන්න', 'මිල', 'කාලගුණ', 'භෝග', 'ඉල්ලුම', 'AI'],
    AppLang.ta => [
      'முகப்பு',
      'விளைச்சல்',
      'விலை',
      'வானிலை',
      'பயிர்',
      'தேவை',
      'AI',
    ],
    _ => ['Home', 'Yield', 'Price', 'Weather', 'Crop', 'Demand', 'Chat'],
  };
}

class AppTopBar extends StatelessWidget {
  /// Which of the 7 nav items is this screen (0 = Home … 6 = Chat).
  final int activeIndex;

  /// Per-screen accent for the active nav pill. Unchanged from what each
  /// screen already used — this widget unifies the STRUCTURE, not the
  /// per-feature identity colour.
  final Color activeBg;
  final Color activeColor;

  final ValueChanged<int>? onNavigate;

  const AppTopBar({
    super.key,
    required this.activeIndex,
    required this.activeBg,
    required this.activeColor,
    required this.onNavigate,
  });

  /// Below this, TopNavMetrics.compact's numbers (44px logo, 68px bar, 36px
  /// avatar, plus the wordmark) genuinely don't fit — TopNavMetrics was
  /// measured only for the desktop/tablet range where the nav row is
  /// visible (see its own file header: "@1024px ... @1200px ..."), never
  /// for a phone. Below 600 is exactly where BrandWordmark switches back on
  /// and TopNavItems self-hides, so it's the natural second threshold here
  /// too. Same value Price's old mobile-only bar used — this is that sizing,
  /// generalised to every screen instead of being one screen's private copy.
  static const double _phoneBreakpoint = 600;

  @override
  Widget build(BuildContext context) {
    final isPhone = MediaQuery.of(context).size.width < _phoneBreakpoint;
    return isPhone ? _buildPhone(context) : _buildDesktop(context);
  }

  Widget _buildDesktop(BuildContext context) {
    final m = TopNavMetrics.of(context);
    return Container(
      height: m.barHeight,
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: AppTheme.divider)),
        boxShadow: [
          BoxShadow(
            color: Color(0x0A000000),
            blurRadius: 6,
            offset: Offset(0, 2),
          ),
        ],
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: Row(
        children: [
          Container(
            width: m.logoSize,
            height: m.logoSize,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: const Color(0xFF4CAF50).withValues(alpha: 0.15),
            ),
            child: Center(
              child: SvgPicture.string(
                kCropSphereLogoSvg,
                width: m.logoGlyphSize,
                height: m.logoGlyphSize,
              ),
            ),
          ),
          const BrandWordmark(),
          Expanded(
            child: Center(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: TopNavItems(
                  labels: topNavLabels(context),
                  activeIndex: activeIndex,
                  activeBg: activeBg,
                  activeColor: activeColor,
                  onNavigate: onNavigate,
                  metrics: m,
                ),
              ),
            ),
          ),
          LanguageControl(labelSize: m.langLabelSize, height: m.controlHeight),
          SizedBox(width: m.clusterGap),
          ThemeToggleButton(size: m.toggleIconSize, height: m.controlHeight),
          SizedBox(width: m.clusterGap),
          ProfileAvatarButton(diameter: m.avatarSize),
        ],
      ),
    );
  }

  /// Phone bar: logo + wordmark + language/theme/avatar only — no nav row
  /// (TopNavItems self-hides here anyway; navigation is MainShell's
  /// FloatingBottomNav). Sized to actually fit a 320px viewport, which
  /// TopNavMetrics.compact does not: even the pre-unification screens that
  /// reused TopNavMetrics unconditionally down to 0px width overflowed at
  /// 320px the same way Price's OWN old mobile bar was written to avoid —
  /// this is that same, narrower sizing, now shared by every screen instead
  /// of living only in Price's file.
  Widget _buildPhone(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final bool isSmall = width < 340;
    return Container(
      height: 56,
      padding: EdgeInsets.symmetric(horizontal: isSmall ? 10 : 14),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: AppTheme.divider)),
      ),
      child: Row(
        children: [
          Container(
            width: isSmall ? 34 : 38,
            height: isSmall ? 34 : 38,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: const Color(0xFF4CAF50).withValues(alpha: 0.15),
            ),
            child: Center(
              child: SvgPicture.string(
                kCropSphereLogoSvg,
                width: isSmall ? 22 : 26,
                height: isSmall ? 22 : 26,
              ),
            ),
          ),
          const SizedBox(width: 8),
          // Flexible, not fixed: at 320dp the wordmark's intrinsic width
          // plus the three trailing controls overran the bar. It gives way
          // first. Not BrandWordmark here — that widget's 18.5px size is
          // desktop/tablet-only and doesn't fit this bar either.
          Flexible(
            child: Text(
              'CropSphere',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: const Color(0xFF1B4D1B),
                fontSize: isSmall ? 14.5 : 16,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.2,
              ),
            ),
          ),
          const Spacer(),
          const LanguageControl(),
          const SizedBox(width: 8),
          const ThemeToggleButton(),
          const SizedBox(width: 8),
          const ProfileAvatarButton(diameter: 32),
        ],
      ),
    );
  }
}
