// lib/widgets/brand_wordmark.dart
// The "CropSphere" wordmark that sits beside the logo in every screen's
// desktop/tablet top bar, including its leading gap.
//
// Self-hiding by width, because it competes directly with the nav labels:
// the wordmark measures ~185px at 18.5px w800 — more than two nav items.
// With it visible, the 7-item nav row needs ~1337px before every tab fits;
// without it, ~983px. Since the floating bottom nav is hidden from 1024px
// up, a tab scrolled out of view there is unreachable rather than merely
// inconvenient, so the branding yields to the navigation in that band.
//
//   < 600px   shown — mobile bars render no nav labels, so there is room
//   600–1200  hidden — labels are competing for the same row
//   ≥ 1200px  shown — enough width for both

import 'package:flutter/material.dart';

class BrandWordmark extends StatelessWidget {
  const BrandWordmark({super.key});

  /// Below this the wordmark yields to the nav labels.
  static const double showFrom = 1200;

  /// Mobile bars don't render nav labels, so nothing is competing.
  static const double navLabelsFrom = 600;

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.of(context).size.width;
    final show = w < navLabelsFrom || w >= showFrom;
    if (!show) return const SizedBox.shrink();

    return const Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(width: 10),
        Text(
          'CropSphere',
          style: TextStyle(
            color: Color(0xFF1B4D1B),
            fontSize: 18.5,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.3,
          ),
        ),
      ],
    );
  }
}
