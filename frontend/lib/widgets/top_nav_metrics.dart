// lib/widgets/top_nav_metrics.dart
// One source of truth for the desktop/tablet top bar's dimensions, shared
// by all six screens that render their own copy of that bar.
//
// WHY THESE ARE RESPONSIVE
// The 7-item nav row lives in a horizontal ScrollView, so oversizing it
// never throws — tabs simply sit off-screen. From 1024px up the floating
// bottom nav is hidden, which makes an off-screen tab unreachable rather
// than merely awkward. So the sizes are capped by what actually fits,
// measured against the longest-rendering language (Tamil):
//
//   available width = screen - logo - language control - theme toggle
//                     - avatar - gaps - bar padding   (wordmark hidden
//                     in the 600-1200 band, see BrandWordmark)
//
//   @1024px   fs 14 / pad 12 / logo 44  -> Tamil 728px vs 758px  (30px slack)
//   @1200px   fs 16 / pad 15 / logo 56  -> Tamil 844px vs 903px  (59px slack)
//
// Hence two steps: "compact" in the tight 1024-1200 band, "comfortable"
// from 1200 up where 1440/1920 monitors have room to spare. Raising any
// value here without re-running test/topnav_fit_test.dart will silently
// push tabs out of reach at the small end.

import 'package:flutter/widgets.dart';

class TopNavMetrics {
  /// Label size for the nav items.
  final double labelSize;

  /// Horizontal padding inside each nav button.
  final double itemPadH;

  /// Vertical padding inside each nav button.
  final double itemPadV;

  /// Gap between adjacent nav buttons (applied per side).
  final double itemGap;

  /// Diameter of the circular logo badge.
  final double logoSize;

  /// The SVG drawn inside the logo badge.
  final double logoGlyphSize;

  /// Overall bar height.
  final double barHeight;

  /// Profile avatar diameter.
  final double avatarSize;

  /// Theme-toggle icon size.
  final double toggleIconSize;

  /// Gap between the right-hand cluster's controls (language, theme
  /// toggle, avatar). Only the full web/tablet bar uses these metrics, so
  /// widening this never affects the compact mobile app bars.
  final double clusterGap;

  /// Font size for the language control's label.
  final double langLabelSize;

  const TopNavMetrics({
    required this.labelSize,
    required this.itemPadH,
    required this.itemPadV,
    required this.itemGap,
    required this.logoSize,
    required this.logoGlyphSize,
    required this.barHeight,
    required this.avatarSize,
    required this.toggleIconSize,
    required this.clusterGap,
    required this.langLabelSize,
  });

  /// Height shared by the nav items and every control in the right-hand
  /// cluster, so the language control, theme toggle and avatar line up
  /// with the nav labels instead of each sitting at its own height.
  double get controlHeight => labelSize + itemPadV * 2;

  /// 1024–1280px — the band where the nav row is tightest and is also the
  /// only navigation available.
  static const compact = TopNavMetrics(
    labelSize: 14,
    itemPadH: 12,
    itemPadV: 9,
    itemGap: 3,
    logoSize: 44,
    logoGlyphSize: 32,
    barHeight: 68,
    avatarSize: 36,
    toggleIconSize: 22,
    clusterGap: 14,
    langLabelSize: 12.5,
  );

  /// ≥1280px — room to breathe on real desktop monitors.
  static const comfortable = TopNavMetrics(
    labelSize: 16,
    itemPadH: 13,
    itemPadV: 11,
    itemGap: 4,
    logoSize: 56,
    logoGlyphSize: 40,
    barHeight: 78,
    avatarSize: 44,
    toggleIconSize: 28,
    clusterGap: 20,
    langLabelSize: 14,
  );

  /// Width at which the comfortable step becomes affordable.
  static const double comfortableFrom = 1280;

  static TopNavMetrics of(BuildContext context) =>
      MediaQuery.of(context).size.width >= comfortableFrom
      ? comfortable
      : compact;
}
