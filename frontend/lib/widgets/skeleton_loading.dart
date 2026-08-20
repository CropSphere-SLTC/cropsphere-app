// lib/widgets/skeleton_loading.dart
// Shared skeleton-loading building blocks, used in place of bare spinners
// and blank screens while data loads. Each pattern here maps to one entry
// in the loading-state inventory (chat, prediction, admin) worked out
// during the skeleton-loading rollout — see call sites for which pattern
// was chosen for which screen and why.
//
// Duration baseline: continuous loops run at 1000ms, matching the original
// sidebar pulse this file generalizes [PulseFade] out of.

import 'package:flutter/material.dart';
import 'app_theme.dart';

/// Pulse — uniform opacity "breathing". Originally private to
/// chat_screen.dart's sidebar skeleton; promoted here so every pattern
/// below (and any screen using Pulse directly) shares one implementation
/// instead of duplicating the AnimationController.
class PulseFade extends StatefulWidget {
  final Widget child;
  const PulseFade({super.key, required this.child});

  @override
  State<PulseFade> createState() => _PulseFadeState();
}

class _PulseFadeState extends State<PulseFade>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _opacity;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat(reverse: true);
    _opacity = Tween<double>(
      begin: 0.3,
      end: 0.6,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _opacity,
      builder: (context, child) =>
          Opacity(opacity: _opacity.value, child: child),
      child: widget.child,
    );
  }
}

/// A plain placeholder block — rounded rect, flat colour. The unit shape
/// every pattern below composes out of.
class SkeletonBox extends StatelessWidget {
  final double? width;
  final double height;
  final double radius;
  final double alpha;
  const SkeletonBox({
    super.key,
    this.width,
    this.height = 12,
    this.radius = 4,
    this.alpha = 0.3,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: AppTheme.textMuted.withValues(alpha: alpha),
        borderRadius: BorderRadius.circular(radius),
      ),
    );
  }
}

/// Staggered — items enter in sequence with a short delay between each,
/// then breathe in place via [PulseFade]. For list/table content: sidebar
/// conversations, notification panel, audit/user/prediction-log tables,
/// pattern-management and prompt-tuning lists.
class StaggeredSkeletonList extends StatelessWidget {
  final int itemCount;
  final Widget Function(BuildContext, int) itemBuilder;
  final Duration stagger;
  final ScrollPhysics physics;
  // Off by default (matches ListView's own default) — set true to embed
  // this inside another scrollable (e.g. a page-level SingleChildScrollView)
  // where it should size itself to its children instead of expanding.
  final bool shrinkWrap;

  const StaggeredSkeletonList({
    super.key,
    required this.itemCount,
    required this.itemBuilder,
    this.stagger = const Duration(milliseconds: 70),
    this.physics = const NeverScrollableScrollPhysics(),
    this.shrinkWrap = false,
  });

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      physics: physics,
      shrinkWrap: shrinkWrap,
      itemCount: itemCount,
      itemBuilder: (context, i) => _DelayedEntry(
        delay: stagger * i,
        slide: true,
        child: PulseFade(child: itemBuilder(context, i)),
      ),
    );
  }
}

/// Cascade — items fade in one after another; fade is the emphasis, not
/// position (no slide, unlike Staggered). For report-style pages mixing
/// cards/charts/lists as one flowing sequence: gap report, security
/// monitoring.
class CascadeSkeletonGroup extends StatelessWidget {
  final List<Widget> children;
  final Duration stagger;
  const CascadeSkeletonGroup({
    super.key,
    required this.children,
    this.stagger = const Duration(milliseconds: 90),
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < children.length; i++)
          _DelayedEntry(
            delay: stagger * i,
            slide: false,
            child: PulseFade(child: children[i]),
          ),
      ],
    );
  }
}

/// One-time entrance (fade, optionally + slight upward slide) after
/// [delay], shared by Staggered and Cascade — the difference between the
/// two patterns is entirely in whether `slide` is set and how long the
/// per-item `delay` gap is.
class _DelayedEntry extends StatefulWidget {
  final Duration delay;
  final bool slide;
  final Widget child;
  const _DelayedEntry({
    required this.delay,
    required this.slide,
    required this.child,
  });

  @override
  State<_DelayedEntry> createState() => _DelayedEntryState();
}

class _DelayedEntryState extends State<_DelayedEntry> {
  bool _visible = false;

  @override
  void initState() {
    super.initState();
    Future.delayed(widget.delay, () {
      if (mounted) setState(() => _visible = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    final opacity = AnimatedOpacity(
      opacity: _visible ? 1 : 0,
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOut,
      child: widget.child,
    );
    if (!widget.slide) return opacity;
    return AnimatedSlide(
      offset: _visible ? Offset.zero : const Offset(0, 0.08),
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
      child: opacity,
    );
  }
}

/// Layered — card-shaped skeleton with a subtle shadow so it reads as
/// raised/stacked (depth). For card-based dashboard layouts: admin
/// dashboard, system health, pattern detail.
class LayeredSkeletonCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  const LayeredSkeletonCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
  });

  @override
  Widget build(BuildContext context) {
    return PulseFade(
      child: Container(
        padding: padding,
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: child,
      ),
    );
  }
}

/// Typewriter — text-shaped bars reveal left-to-right like text being
/// typed, then loop. For single text-heavy content blocks: prediction
/// result cards.
class TypewriterSkeleton extends StatefulWidget {
  final List<double> lineWidthFractions; // relative widths, 0-1
  final double lineHeight;
  final double gap;
  const TypewriterSkeleton({
    super.key,
    this.lineWidthFractions = const [1.0, 0.85, 0.6, 0.4],
    this.lineHeight = 12,
    this.gap = 10,
  });

  @override
  State<TypewriterSkeleton> createState() => _TypewriterSkeletonState();
}

class _TypewriterSkeletonState extends State<TypewriterSkeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  // Reveal phase types the lines out left-to-right; the clear phase then
  // fades everything out together before the next cycle's reveal starts,
  // so the loop reads as an intentional "clear and retype" rather than a
  // snap back to blank.
  static const _revealDuration = Duration(milliseconds: 1250);
  static const _clearDuration = Duration(milliseconds: 180);

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: _revealDuration + _clearDuration,
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final n = widget.lineWidthFractions.length;
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final elapsedMs =
            _controller.value *
            (_revealDuration + _clearDuration).inMilliseconds;
        // Reveal progress, 0-1 — clamps at 1 once the reveal window ends,
        // so lines just sit fully typed out through the clear phase.
        final revealT = (elapsedMs / _revealDuration.inMilliseconds).clamp(
          0.0,
          1.0,
        );
        // 1.0 through the whole reveal phase, then eases down to 0 over
        // the clear phase — applied to the already-revealed lines below.
        final clearT =
            ((elapsedMs - _revealDuration.inMilliseconds) /
                    _clearDuration.inMilliseconds)
                .clamp(0.0, 1.0);
        final opacity = 1.0 - Curves.easeIn.transform(clearT);
        return LayoutBuilder(
          builder: (context, constraints) {
            return Opacity(
              opacity: opacity,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (var i = 0; i < n; i++) ...[
                    if (i > 0) SizedBox(height: widget.gap),
                    _typedLine(
                      constraints.maxWidth * widget.lineWidthFractions[i],
                      i,
                      n,
                      revealT,
                    ),
                  ],
                ],
              ),
            );
          },
        );
      },
    );
  }

  // Each line gets its own slice of the loop so lines type out
  // left-to-right in sequence rather than all revealing at once.
  Widget _typedLine(double targetWidth, int index, int total, double revealT) {
    final start = index / (total + 1);
    final end = start + 1 / (total + 1);
    final local = ((revealT - start) / (end - start)).clamp(0.0, 1.0);
    final revealed = Curves.easeOut.transform(local);
    return ClipRect(
      child: Align(
        alignment: Alignment.centerLeft,
        widthFactor: revealed <= 0 ? 0.001 : revealed,
        child: SkeletonBox(
          width: targetWidth,
          height: widget.lineHeight,
          alpha: 0.35,
        ),
      ),
    );
  }
}

/// Layered stat-card grid — mirrors `StatCardGrid`'s responsive Wrap (2 per
/// row narrow, [wideCount] per row otherwise) with placeholder icon/value/
/// label bars in place of each `StatCard`. Used by every admin page whose
/// initial load is a row of summary stat cards.
class AdminStatCardsSkeleton extends StatelessWidget {
  final int count;
  final int wideCount;
  const AdminStatCardsSkeleton({super.key, this.count = 4, this.wideCount = 4});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final perRow = constraints.maxWidth < 600 ? 2 : wideCount;
        final cardWidth = (constraints.maxWidth - (perRow - 1) * 12) / perRow;
        return Wrap(
          spacing: 12,
          runSpacing: 12,
          children: List.generate(
            count,
            (_) => SizedBox(
              width: cardWidth,
              child: LayeredSkeletonCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SkeletonBox(width: 22, height: 22, radius: 6),
                    const SizedBox(height: 12),
                    const SkeletonBox(width: 48, height: 15),
                    const SizedBox(height: 6),
                    const SkeletonBox(width: 80, height: 11),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// One placeholder table row, sized like a `DataTable` row — a lead cell
/// plus [cellCount] narrower trailing cells. Pair with [StaggeredSkeletonList]
/// (`shrinkWrap: true` when embedded in a page-level scroll view) for the
/// audit-log/user/prediction-log/security tables.
class AdminTableRowSkeleton extends StatelessWidget {
  final int cellCount;
  const AdminTableRowSkeleton({super.key, this.cellCount = 3});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          const SkeletonBox(width: 140, height: 12),
          for (var i = 0; i < cellCount; i++) ...[
            const SizedBox(width: 24),
            SkeletonBox(width: 70 + (i.isEven ? 0 : 20), height: 12),
          ],
        ],
      ),
    );
  }
}

/// A full table-shaped skeleton: an optional filter-bar placeholder above a
/// card of [rowCount] staggered [AdminTableRowSkeleton] rows. Used by the
/// audit-log/user/prediction-log tables, and by list-style admin pages
/// (pattern management, prompt tuning) via [rowBuilder].
class AdminTableSkeleton extends StatelessWidget {
  final int rowCount;
  final int cellCount;
  final bool showFilterBar;
  final Widget Function(BuildContext, int)? rowBuilder;

  const AdminTableSkeleton({
    super.key,
    this.rowCount = 6,
    this.cellCount = 3,
    this.showFilterBar = false,
    this.rowBuilder,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (showFilterBar) ...[
          PulseFade(
            child: Row(
              children: [
                Expanded(
                  child: SkeletonBox(height: 40, radius: 8, alpha: 0.15),
                ),
                const SizedBox(width: 12),
                const SkeletonBox(width: 120, height: 40, radius: 8),
              ],
            ),
          ),
          const SizedBox(height: 16),
        ],
        Card(
          elevation: 2,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: StaggeredSkeletonList(
              itemCount: rowCount,
              shrinkWrap: true,
              itemBuilder:
                  rowBuilder ??
                  (context, i) => AdminTableRowSkeleton(cellCount: cellCount),
            ),
          ),
        ),
      ],
    );
  }
}

/// Outline — shape shown as an outlined border only, no fill. Minimal /
/// low-emphasis, for settings-style forms (account settings, system
/// config) where a heavier skeleton would overstate a fast, simple load.
class OutlineSkeletonBox extends StatelessWidget {
  final double? width;
  final double height;
  final double radius;
  const OutlineSkeletonBox({
    super.key,
    this.width,
    this.height = 40,
    this.radius = 8,
  });

  @override
  Widget build(BuildContext context) {
    return PulseFade(
      child: Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          border: Border.all(color: AppTheme.textMuted.withValues(alpha: 0.4)),
          borderRadius: BorderRadius.circular(radius),
        ),
      ),
    );
  }
}

/// Gradient — static soft gradient block, no movement. For very fast,
/// small loads where animation would be distracting.
class GradientSkeletonBox extends StatelessWidget {
  final double? width;
  final double height;
  final double radius;
  const GradientSkeletonBox({
    super.key,
    this.width,
    this.height = 12,
    this.radius = 4,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        gradient: LinearGradient(
          colors: [
            AppTheme.textMuted.withValues(alpha: 0.22),
            AppTheme.textMuted.withValues(alpha: 0.35),
          ],
        ),
      ),
    );
  }
}
