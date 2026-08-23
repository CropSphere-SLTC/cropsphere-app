// lib/widgets/top_nav_items.dart
// ─────────────────────────────────────────────────────────────────────────────
//  The desktop/tablet top nav's 7-item row, shared by all six screens that
//  render their own top bar.
//
//  Extracted because a *sliding* active indicator needs each item's exact
//  offset and width. Items are variable-width (label text differs), so the
//  widths are measured with TextPainter using the same TextStyle the items
//  render with, then applied as explicit SizedBox widths. That makes the
//  indicator's geometry exact and deterministic rather than dependent on
//  post-frame measurement — and it means the row can be unit-tested.
//
//  Previously each screen carried its own copy of this Row; six copies had
//  already drifted once (Dashboard's label size differed from the rest).
//
//  ANIMATION
//  • Active indicator: one AnimatedPositioned pill that slides behind the
//    active item — 220ms easeInOutCubic. A single moving shape rather than
//    per-item backgrounds fading in and out, so it reads as one indicator
//    travelling, matching the floating bottom nav's pill.
//  • Hover: a very light tint fading in over 110ms, pointer devices only.
//    Never applied to the active item, whose pill already fills that space.
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';

import 'top_nav_metrics.dart';

/// Slide timing for the active indicator. Sits beside the floating bottom
/// nav's 230ms pill so the two navigations feel related.
const Duration kTopNavIndicatorDuration = Duration(milliseconds: 220);
const Curve kTopNavIndicatorCurve = Curves.easeInOutCubic;

/// Hover tint fade — matches the chat screen's message-hover action rows.
const Duration kTopNavHoverDuration = Duration(milliseconds: 110);

class TopNavItems extends StatefulWidget {
  final List<String> labels;
  final int activeIndex;

  /// Per-screen accent, unchanged from the previous inline implementation.
  final Color activeBg;
  final Color activeColor;

  final ValueChanged<int>? onNavigate;
  final TopNavMetrics metrics;

  const TopNavItems({
    super.key,
    required this.labels,
    required this.activeIndex,
    required this.activeBg,
    required this.activeColor,
    required this.onNavigate,
    required this.metrics,
  });

  static const Color inactiveColor = Color(0xFF555555);

  /// Laid-out width of one item: label + horizontal padding + both gaps.
  static double itemWidth(String label, TopNavMetrics m) =>
      _measure(label, m.labelSize) + m.itemPadH * 2 + m.itemGap * 2;

  /// Total width of the whole row — used by layout tests to verify the row
  /// still fits at the narrowest supported width.
  static double rowWidth(List<String> labels, TopNavMetrics m) =>
      labels.fold(0.0, (a, l) => a + itemWidth(l, m));

  @override
  State<TopNavItems> createState() => _TopNavItemsState();
}

/// Measured at the *active* weight so the indicator never has to resize
/// when a tab becomes bold — the pill would otherwise twitch on arrival.
double _measure(String label, double size) {
  final tp = TextPainter(
    text: TextSpan(
      text: label,
      style: TextStyle(fontSize: size, fontWeight: FontWeight.w700),
    ),
    textDirection: TextDirection.ltr,
  )..layout();
  return tp.width;
}

class _TopNavItemsState extends State<TopNavItems> {
  int? _hovered;

  @override
  Widget build(BuildContext context) {
    final m = widget.metrics;
    final widths = [
      for (final l in widget.labels) TopNavItems.itemWidth(l, m),
    ];

    // Left edge of each item, so the indicator can be positioned exactly.
    final offsets = <double>[];
    var running = 0.0;
    for (final w in widths) {
      offsets.add(running);
      running += w;
    }

    final safeIndex = widget.activeIndex >= 0 &&
            widget.activeIndex < widths.length
        ? widget.activeIndex
        : 0;
    final itemHeight = m.labelSize + m.itemPadV * 2;

    return SizedBox(
      width: running,
      height: itemHeight,
      child: Stack(
        children: [
          // The sliding indicator — one shape that travels, drawn behind
          // the labels.
          AnimatedPositioned(
            duration: kTopNavIndicatorDuration,
            curve: kTopNavIndicatorCurve,
            left: offsets[safeIndex] + m.itemGap,
            top: 0,
            width: widths[safeIndex] - m.itemGap * 2,
            height: itemHeight,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: widget.activeBg,
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
          for (var i = 0; i < widget.labels.length; i++)
            Positioned(
              left: offsets[i],
              top: 0,
              width: widths[i],
              height: itemHeight,
              child: _item(i, m, safeIndex),
            ),
        ],
      ),
    );
  }

  Widget _item(int i, TopNavMetrics m, int safeIndex) {
    final active = i == safeIndex;
    final enabled = widget.onNavigate != null;
    final hovered = _hovered == i && !active && enabled;

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: m.itemGap),
      child: MouseRegion(
        cursor: enabled ? SystemMouseCursors.click : MouseCursor.defer,
        // Pointer devices only — onEnter/onExit simply never fire for
        // touch, so this needs no platform check of its own.
        onEnter: (_) => setState(() => _hovered = i),
        onExit: (_) => setState(() => _hovered = null),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: enabled ? () => widget.onNavigate!(i) : null,
          child: AnimatedContainer(
            duration: kTopNavHoverDuration,
            curve: Curves.easeOut,
            decoration: BoxDecoration(
              // Very light tint — the indicator, not this, signals active.
              color: hovered
                  ? widget.activeColor.withValues(alpha: 0.07)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(8),
            ),
            alignment: Alignment.center,
            child: AnimatedDefaultTextStyle(
              duration: kTopNavIndicatorDuration,
              curve: kTopNavIndicatorCurve,
              style: TextStyle(
                fontSize: m.labelSize,
                fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                color: active
                    ? widget.activeColor
                    : TopNavItems.inactiveColor,
              ),
              child: Text(widget.labels[i], maxLines: 1),
            ),
          ),
        ),
      ),
    );
  }
}
