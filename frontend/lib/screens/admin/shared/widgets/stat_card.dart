// lib/screens/admin/shared/widgets/stat_card.dart
// Reusable stat card — replaces the private _StatCard/_SummaryCard that were
// duplicated across the old admin and superadmin dashboards.

import 'package:flutter/material.dart';
import '../../../../widgets/app_theme.dart';

class StatCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;

  /// When set, the card becomes tappable and shows a chevron affordance —
  /// used on the Dashboard to drill into detail pages.
  final VoidCallback? onTap;

  const StatCard({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final content = Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 22),
              const Spacer(),
              if (onTap != null)
                const Icon(
                  Icons.chevron_right,
                  size: 18,
                  color: AppTheme.textMuted,
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: AppTheme.textPrimary,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: onTap == null
          ? content
          : InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: onTap,
              child: content,
            ),
    );
  }
}

/// Lays out stat cards in a responsive Wrap: 2 per row on narrow screens,
/// [widePerRow] per row otherwise. Keeps the sizing math in one place.
class StatCardGrid extends StatelessWidget {
  final List<Widget> cards;
  final int widePerRow;

  const StatCardGrid({super.key, required this.cards, this.widePerRow = 4});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final perRow = constraints.maxWidth < 600 ? 2 : widePerRow;
        final cardWidth = (constraints.maxWidth - (perRow - 1) * 12) / perRow;
        return Wrap(
          spacing: 12,
          runSpacing: 12,
          children: cards
              .map((c) => SizedBox(width: cardWidth, child: c))
              .toList(),
        );
      },
    );
  }
}
