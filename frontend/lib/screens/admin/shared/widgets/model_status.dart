// lib/screens/admin/shared/widgets/model_status.dart
// Model load-status views shared by the Dashboard (compact pills) and the
// System Health page (full grid).

import 'package:flutter/material.dart';
import '../../../../widgets/app_theme.dart';

/// Full responsive grid of model name + loaded/not-loaded status.
class ModelStatusGrid extends StatelessWidget {
  final Map<String, bool> models;

  const ModelStatusGrid({super.key, required this.models});

  @override
  Widget build(BuildContext context) {
    final entries = models.entries.toList();
    return LayoutBuilder(
      builder: (context, constraints) {
        final perRow = constraints.maxWidth < 500
            ? 1
            : constraints.maxWidth < 800
            ? 2
            : 3;
        final itemWidth = (constraints.maxWidth - (perRow - 1) * 10) / perRow;
        return Wrap(
          spacing: 10,
          runSpacing: 10,
          children: entries.map((e) {
            final loaded = e.value;
            final color = loaded ? AppTheme.success : AppTheme.error;
            return SizedBox(
              width: itemWidth,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: color.withValues(alpha: 0.3)),
                ),
                child: Row(
                  children: [
                    Icon(
                      loaded ? Icons.check_circle : Icons.cancel,
                      color: color,
                      size: 18,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        e.key,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }).toList(),
        );
      },
    );
  }
}

/// Compact wrap of colored pills — green loaded, red not — for the dashboard
/// glance view.
class ModelStatusPills extends StatelessWidget {
  final Map<String, bool> models;

  const ModelStatusPills({super.key, required this.models});

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: models.entries.map((e) {
        final loaded = e.value;
        final color = loaded ? AppTheme.success : AppTheme.error;
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: color.withValues(alpha: 0.35)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              ),
              const SizedBox(width: 6),
              Text(
                e.key,
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }
}
