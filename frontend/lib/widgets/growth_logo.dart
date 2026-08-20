// lib/widgets/growth_logo.dart
// Staged growth animation for the CropSphere brand mark — paints the plant
// piece-by-piece (ground → stem → leaves → flower seeds) instead of scaling
// a static image.
//
// This is a direct port of BrandMark.jsx (the Cropsphere.ai Next.js site's
// inline-SVG sprout mark, viewBox 0-120): same colors, same bezier paths
// for the stem/leaves, same SEEDS array for the flower head, same relative
// stagger order — see _Stages for how the source's delays were scaled down
// to fit our fixed 1000ms window (source delays scaled by k = 1000/1410,
// anchored so the last seed's pop finishes exactly at t=1.0; source
// per-element durations weren't available — ground-in/leaf-unfurl 400ms,
// stem-grow 600ms, seed-pop 250ms were assumed and confirmed).
//
// Used by _LaunchScreen (lib/main.dart) for the launch animation, and at a
// fixed progress: 1.0 (fully bloomed, no animation) in the chat empty-state
// and the post-login welcome screen, for visual consistency with the
// launch mark.
//
// Not ported: BrandMark's `variant="loop"` breathing animation (starts
// 1600ms after grow, loops forever) — GrowthLogo is only ever driven once
// 0→1 or held static at 1.0, so there's nothing for a loop to attach to.

import 'package:flutter/material.dart';

/// Exact colors from BrandMark.jsx's `C` object.
class GrowthColors {
  GrowthColors._();
  static const background = Color(0xFFE5EFE3); // badge
  static const shadow = Color(0xFF31702F); // ground
  static const stem = Color(0xFF4AAD4E); // stem
  static const leafBack = Color(0xFFA8D3A0); // leafBack
  static const leafLeft = Color(0xFF2F8B3B); // leafLeft
  static const leafRight = Color(0xFF2A7F36); // leafRight
  static const vein = Color(0xFF1B3E20); // vein
  static const dew = Color(0xFFC9DDE3); // dew
  static const seed = Color(0xFFF5B921); // seed
}

/// Stage windows as fractions of overall progress [0,1] — the source's
/// {delay, assumed-duration} pairs scaled by k = 1000/1410. Z-order in
/// paint() matches document order in the JSX (ground, stem, leafBack,
/// leafLeft, leafRight, seeds), which is also already time order here, so
/// unlike the pre-port version there's no z-order/time-order split to
/// manage.
class _Stages {
  static const groundStart = 0.0709, groundEnd = 0.3546;
  static const stemStart = 0.1560, stemEnd = 0.5816;
  static const leafBackStart = 0.3262, leafBackEnd = 0.6099;
  static const leafLeftStart = 0.3688, leafLeftEnd = 0.6525;
  static const leafRightStart = 0.4539, leafRightEnd = 0.7376;
}

/// One flower seed: exact {cx, cy, r} from BrandMark.jsx's SEEDS array
/// (viewBox units, converted to 0-1 fractions by /120), plus its scaled
/// {start, end} bloom window. Array order is the pop order (bottom → left-
/// mid → right-mid → upper-left → upper-right → center → top) — the JSX
/// stagger is just `SEEDS.map((s, i) => ...delay: 800 + i*60)`, so index
/// order IS stagger order, no separate ordering needed.
class _Seed {
  final Offset position;
  final double radius;
  final double start;
  final double end;
  const _Seed(this.position, this.radius, this.start, this.end);
}

const _seeds = [
  _Seed(Offset(0.50167, 0.32083), 0.03333, 0.5674, 0.7447), // bottom
  _Seed(Offset(0.43333, 0.27917), 0.03333, 0.6099, 0.7872), // left-mid
  _Seed(Offset(0.57000, 0.27917), 0.03333, 0.6525, 0.8298), // right-mid
  _Seed(Offset(0.41667, 0.20417), 0.03333, 0.6950, 0.8723), // upper-left
  _Seed(Offset(0.58667, 0.20417), 0.03333, 0.7376, 0.9149), // upper-right
  _Seed(Offset(0.50167, 0.20833), 0.03750, 0.7801, 0.9574), // center, larger
  _Seed(Offset(0.50000, 0.13333), 0.02667, 0.8227, 1.0000), // top, smaller
];

/// Eased 0-1 progress within [start, end]; 0 before, 1 after. easeOut only
/// — no bounce/elastic anywhere in this animation, matching BrandMark.
double _stageT(double t, double start, double end) {
  if (t <= start) return 0.0;
  if (t >= end) return 1.0;
  return Curves.easeOut.transform((t - start) / (end - start));
}

/// Sized square widget painting the growth sequence at [progress] (0-1).
class GrowthLogo extends StatelessWidget {
  final double progress;
  final double size;
  const GrowthLogo({super.key, required this.progress, required this.size});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _GrowthLogoPainter(progress)),
    );
  }
}

class _GrowthLogoPainter extends CustomPainter {
  final double t;
  _GrowthLogoPainter(this.t);

  Offset _p(Size size, double nx, double ny) =>
      Offset(nx * size.width, ny * size.height);

  // Builds the stem's exact cubic-bezier path (BrandMark's
  // "M60.8 93 C60.8 78 60 58 60.2 40.5"), then reveals only the leading
  // fraction `stemT` of its length via computeMetrics/extractPath — the
  // Flutter equivalent of the source's stroke-dashoffset draw-in.
  void _drawStem(Canvas canvas, Size size, double stemT) {
    if (stemT <= 0) return;
    final path = Path()
      ..moveTo(_p(size, 0.50667, 0.775).dx, _p(size, 0.50667, 0.775).dy)
      ..cubicTo(
        _p(size, 0.50667, 0.65).dx,
        _p(size, 0.50667, 0.65).dy,
        _p(size, 0.5, 0.48333).dx,
        _p(size, 0.5, 0.48333).dy,
        _p(size, 0.50167, 0.3375).dx,
        _p(size, 0.50167, 0.3375).dy,
      );
    final metrics = path.computeMetrics().toList();
    final totalLength = metrics.fold<double>(0, (sum, m) => sum + m.length);
    var remaining = totalLength * stemT;
    final revealed = Path();
    for (final metric in metrics) {
      if (remaining <= 0) break;
      final take = remaining.clamp(0, metric.length).toDouble();
      revealed.addPath(metric.extractPath(0, take), Offset.zero);
      remaining -= take;
    }
    canvas.drawPath(
      revealed,
      Paint()
        ..color = GrowthColors.stem
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.03833 * size.width
        ..strokeCap = StrokeCap.round,
    );
  }

  // A leaf "unfurls" as a scale-in (0→1) anchored at its own attach point
  // (BrandMark's CSS transform-origin pivot) — the exact filled outline
  // plus, for the two front leaves, its vein stroke and dew ellipse, all
  // scaled together since they're inside the same JSX <g>.
  void _drawLeaf(
    Canvas canvas,
    Size size,
    Offset pivotN,
    double growthT,
    Path Function(Size) buildOutline,
    Color fillColor, {
    double fillOpacity = 1.0,
    Path Function(Size)? buildVein,
    Offset? dewCenterN,
    double dewRxN = 0,
    double dewRyN = 0,
  }) {
    if (growthT <= 0) return;
    final pivot = _p(size, pivotN.dx, pivotN.dy);
    canvas.save();
    canvas.translate(pivot.dx, pivot.dy);
    canvas.scale(growthT);
    canvas.translate(-pivot.dx, -pivot.dy);

    canvas.drawPath(
      buildOutline(size),
      Paint()..color = fillColor.withValues(alpha: fillOpacity),
    );
    if (buildVein != null) {
      canvas.drawPath(
        buildVein(size),
        Paint()
          ..color = GrowthColors.vein.withValues(alpha: 0.26)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.00833 * size.width
          ..strokeCap = StrokeCap.round,
      );
    }
    if (dewCenterN != null) {
      final dewCenter = _p(size, dewCenterN.dx, dewCenterN.dy);
      canvas.drawOval(
        Rect.fromCenter(
          center: dewCenter,
          width: dewRxN * 2 * size.width,
          height: dewRyN * 2 * size.width,
        ),
        Paint()..color = GrowthColors.dew.withValues(alpha: 0.85),
      );
    }
    canvas.restore();
  }

  Path _leafBackOutline(Size size) {
    return Path()
      ..moveTo(_p(size, 0.5, 0.56667).dx, _p(size, 0.5, 0.56667).dy)
      ..cubicTo(
        _p(size, 0.45833, 0.48333).dx,
        _p(size, 0.45833, 0.48333).dy,
        _p(size, 0.40833, 0.35833).dx,
        _p(size, 0.40833, 0.35833).dy,
        _p(size, 0.41667, 0.23333).dx,
        _p(size, 0.41667, 0.23333).dy,
      )
      ..cubicTo(
        _p(size, 0.48333, 0.33333).dx,
        _p(size, 0.48333, 0.33333).dy,
        _p(size, 0.525, 0.45833).dx,
        _p(size, 0.525, 0.45833).dy,
        _p(size, 0.5, 0.56667).dx,
        _p(size, 0.5, 0.56667).dy,
      )
      ..close();
  }

  Path _leafLeftOutline(Size size) {
    return Path()
      ..moveTo(_p(size, 0.50417, 0.6).dx, _p(size, 0.50417, 0.6).dy)
      ..cubicTo(
        _p(size, 0.4, 0.575).dx,
        _p(size, 0.4, 0.575).dy,
        _p(size, 0.28333, 0.475).dx,
        _p(size, 0.28333, 0.475).dy,
        _p(size, 0.225, 0.34167).dx,
        _p(size, 0.225, 0.34167).dy,
      )
      ..cubicTo(
        _p(size, 0.35, 0.375).dx,
        _p(size, 0.35, 0.375).dy,
        _p(size, 0.46667, 0.46667).dx,
        _p(size, 0.46667, 0.46667).dy,
        _p(size, 0.50417, 0.6).dx,
        _p(size, 0.50417, 0.6).dy,
      )
      ..close();
  }

  Path _leafLeftVein(Size size) {
    return Path()
      ..moveTo(_p(size, 0.50417, 0.6).dx, _p(size, 0.50417, 0.6).dy)
      ..cubicTo(
        _p(size, 0.4, 0.54167).dx,
        _p(size, 0.4, 0.54167).dy,
        _p(size, 0.3, 0.45).dx,
        _p(size, 0.3, 0.45).dy,
        _p(size, 0.2375, 0.35417).dx,
        _p(size, 0.2375, 0.35417).dy,
      );
  }

  Path _leafRightOutline(Size size) {
    return Path()
      ..moveTo(_p(size, 0.50833, 0.55).dx, _p(size, 0.50833, 0.55).dy)
      ..cubicTo(
        _p(size, 0.60833, 0.525).dx,
        _p(size, 0.60833, 0.525).dy,
        _p(size, 0.71667, 0.43333).dx,
        _p(size, 0.71667, 0.43333).dy,
        _p(size, 0.775, 0.3).dx,
        _p(size, 0.775, 0.3).dy,
      )
      ..cubicTo(
        _p(size, 0.65833, 0.33333).dx,
        _p(size, 0.65833, 0.33333).dy,
        _p(size, 0.55, 0.425).dx,
        _p(size, 0.55, 0.425).dy,
        _p(size, 0.50833, 0.55).dx,
        _p(size, 0.50833, 0.55).dy,
      )
      ..close();
  }

  Path _leafRightVein(Size size) {
    return Path()
      ..moveTo(_p(size, 0.50833, 0.55).dx, _p(size, 0.50833, 0.55).dy)
      ..cubicTo(
        _p(size, 0.6, 0.5).dx,
        _p(size, 0.6, 0.5).dy,
        _p(size, 0.7, 0.41667).dx,
        _p(size, 0.7, 0.41667).dy,
        _p(size, 0.7625, 0.3125).dx,
        _p(size, 0.7625, 0.3125).dy,
      );
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (t <= 0) return;

    // Badge backdrop — always present once anything starts, not itself
    // part of the staged reveal (matches the JSX's unconditional <circle>
    // outside the animated <g>).
    canvas.drawCircle(
      _p(size, 0.5, 0.5),
      0.475 * size.width,
      Paint()..color = GrowthColors.background,
    );

    // Ground/shadow — scales and fades in from its own center, first in
    // both time and z-order (matches the JSX exactly: no split needed).
    final groundT = _stageT(t, _Stages.groundStart, _Stages.groundEnd);
    if (groundT > 0) {
      final center = _p(size, 0.50417, 0.775);
      canvas.drawOval(
        Rect.fromCenter(
          center: center,
          width: 0.22917 * 2 * size.width * groundT,
          height: 0.05333 * 2 * size.width * groundT,
        ),
        Paint()..color = GrowthColors.shadow.withValues(alpha: groundT),
      );
    }

    // Stem — progressive path-length draw.
    _drawStem(canvas, size, _stageT(t, _Stages.stemStart, _Stages.stemEnd));

    // Leaves — back (translucent) first, then left, then right.
    _drawLeaf(
      canvas,
      size,
      const Offset(0.5, 0.56667),
      _stageT(t, _Stages.leafBackStart, _Stages.leafBackEnd),
      _leafBackOutline,
      GrowthColors.leafBack,
      fillOpacity: 0.7,
    );
    _drawLeaf(
      canvas,
      size,
      const Offset(0.50417, 0.6),
      _stageT(t, _Stages.leafLeftStart, _Stages.leafLeftEnd),
      _leafLeftOutline,
      GrowthColors.leafLeft,
      buildVein: _leafLeftVein,
      dewCenterN: const Offset(0.36667, 0.475),
      dewRxN: 0.01917,
      dewRyN: 0.02417,
    );
    _drawLeaf(
      canvas,
      size,
      const Offset(0.50833, 0.55),
      _stageT(t, _Stages.leafRightStart, _Stages.leafRightEnd),
      _leafRightOutline,
      GrowthColors.leafRight,
      buildVein: _leafRightVein,
      dewCenterN: const Offset(0.63333, 0.41667),
      dewRxN: 0.01917,
      dewRyN: 0.02417,
    );

    // Flower seeds — pop in bottom-to-top, exact SEEDS positions/radii.
    for (final seed in _seeds) {
      final dotT = _stageT(t, seed.start, seed.end);
      if (dotT <= 0) continue;
      canvas.drawCircle(
        _p(size, seed.position.dx, seed.position.dy),
        seed.radius * size.width * dotT,
        Paint()..color = GrowthColors.seed,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _GrowthLogoPainter oldDelegate) =>
      oldDelegate.t != t;
}
