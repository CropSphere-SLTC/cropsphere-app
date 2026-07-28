// lib/screens/admin/shared/widgets/tuning_ui.dart
// Shared vocabulary for the prompt-tuning screens: dimension labels, lifecycle
// status badges, metric names, and trend arrows. Lives here so the tuning list
// page and the adjustment detail screen can never drift on what a status or a
// verdict is called.

import 'package:flutter/material.dart';
import '../../../../widgets/app_theme.dart';

// ── Vocabulary ────────────────────────────────────────────────────────────────

String tuningDimensionLabel(String dimension) {
  switch (dimension) {
    case 'language_complexity':
      return 'Language Complexity';
    case 'problem_areas':
      return 'Problem Areas';
    case 'missing_topics':
      return 'Missing Topics';
    case 'conversation_patterns':
      return 'Conversation Patterns';
    case 'earnings_effectiveness':
      return 'Earnings Offer';
    default:
      return dimension;
  }
}

/// Backend metric key → something a human reads. Metric names are open-ended
/// (`satisfaction_rate_<type>`, `refusal_rate`), so unknown keys are humanised
/// rather than dropped.
String tuningMetricLabel(String? metric) {
  if (metric == null || metric.isEmpty) return 'Not measurable';
  switch (metric) {
    case 'beginner_satisfaction_rate':
      return 'Beginner satisfaction';
    case 'intermediate_satisfaction_rate':
      return 'Intermediate satisfaction';
    case 'advanced_satisfaction_rate':
      return 'Advanced satisfaction';
    case 'refusal_rate':
      return 'Refusal rate';
    case 'avg_session_length':
      return 'Avg. session length';
    case 'chip_tap_rate':
      return 'Follow-up chip taps';
    case 'earnings_followup_rate':
      return 'Earnings follow-through';
  }
  if (metric.startsWith('satisfaction_rate_')) {
    final type = metric.substring('satisfaction_rate_'.length);
    return '${type[0].toUpperCase()}${type.substring(1)} satisfaction';
  }
  return metric.replaceAll('_', ' ');
}

/// Rates are shown as percentages; counts (session length) as plain numbers.
String tuningFormatMetric(double? value, String? metric) {
  if (value == null) return '—';
  final isRate = metric != null && metric.endsWith('rate');
  return isRate
      ? '${(value * 100).toStringAsFixed(0)}%'
      : value.toStringAsFixed(1);
}

String tuningVerdictLabel(String verdict) {
  switch (verdict) {
    case 'on_track_for_permanent':
      return 'On track to become permanent';
    case 'at_risk_of_removal':
      return 'At risk of being auto-removed';
    case 'insufficient_data':
      return 'Not enough data yet';
    case 'not_measurable':
      return 'Cannot be measured automatically';
    case 'validated_permanent':
      return 'Validated and permanent';
    case 'removed':
      return 'Removed';
    default:
      return verdict;
  }
}

Color tuningVerdictColor(String verdict) {
  switch (verdict) {
    case 'on_track_for_permanent':
    case 'validated_permanent':
      return AppTheme.success;
    case 'at_risk_of_removal':
    case 'removed':
      return AppTheme.error;
    default:
      return AppTheme.warning;
  }
}

String tuningAuditLabel(String action) {
  switch (action) {
    case 'applied':
      return 'Applied';
    case 'promoted':
      return 'Made permanent';
    case 'auto_removed':
      return 'Auto-removed';
    case 'manually_removed':
      return 'Removed';
    case 'restored':
      return 'Restored';
    case 'deleted':
      return 'Deleted permanently';
    case 'trial_extended':
      return 'Trial extended';
    default:
      return action;
  }
}

// ── Badges ────────────────────────────────────────────────────────────────────

/// A small pill. The shared base for every badge below.
class TuningChip extends StatelessWidget {
  final String label;
  final Color color;
  final IconData? icon;

  const TuningChip({
    super.key,
    required this.label,
    required this.color,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 12, color: color),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

Widget tuningDimensionChip(String dimension) =>
    TuningChip(label: tuningDimensionLabel(dimension), color: AppTheme.primary);

/// Trial / Permanent / Auto-removed. `status` accepts any backend value; a
/// removed adjustment recovered from the trash reports 'auto_removed'.
Widget tuningStatusBadge(String status) {
  switch (status) {
    case 'permanent':
      return const TuningChip(
        label: 'Permanent',
        color: AppTheme.success,
        icon: Icons.verified_outlined,
      );
    case 'auto_removed':
      return const TuningChip(
        label: 'Auto-removed',
        color: AppTheme.error,
        icon: Icons.gpp_bad_outlined,
      );
    case 'removed':
      return const TuningChip(
        label: 'Removed',
        color: AppTheme.error,
        icon: Icons.delete_outline,
      );
    default:
      return const TuningChip(
        label: 'Trial',
        color: AppTheme.warning,
        icon: Icons.science_outlined,
      );
  }
}

/// Shown when a trial exhausted its extensions without enough data — it is
/// still live, but the system has given up trying to judge it.
Widget tuningAttentionBadge() => const TuningChip(
  label: 'Needs decision',
  color: AppTheme.error,
  icon: Icons.help_outline,
);

/// Shown on an adjustment auto-validation can't judge at all (no metric, or no
/// baseline to compare against). It never auto-promotes or auto-removes.
Widget tuningManualOnlyBadge() => const TuningChip(
  label: 'Manual only',
  color: AppTheme.textSecondary,
  icon: Icons.pan_tool_outlined,
);

// ── Trend ─────────────────────────────────────────────────────────────────────

/// ↑ improved · → stable · ↓ worsened · — unknown.
///
/// `relativeChange` is already signed so positive means better, including for
/// metrics where the raw number falling is the good outcome — so the arrow is
/// driven by `trend` alone and never needs to know the metric's direction.
class TuningTrendArrow extends StatelessWidget {
  final String trend;
  final double? relativeChange;
  final double size;

  const TuningTrendArrow({
    super.key,
    required this.trend,
    this.relativeChange,
    this.size = 18,
  });

  @override
  Widget build(BuildContext context) {
    late final IconData icon;
    late final Color color;
    switch (trend) {
      case 'improving':
        icon = Icons.arrow_upward;
        color = AppTheme.success;
      case 'worsened':
        icon = Icons.arrow_downward;
        color = AppTheme.error;
      case 'stable':
        icon = Icons.arrow_forward;
        color = AppTheme.textSecondary;
      default:
        icon = Icons.remove;
        color = AppTheme.textMuted;
    }
    final change = relativeChange;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: size, color: color),
        if (change != null && trend != 'unknown') ...[
          const SizedBox(width: 4),
          Text(
            '${change >= 0 ? '+' : ''}${(change * 100).toStringAsFixed(0)}%',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
      ],
    );
  }
}

// ── Sample-size progress ──────────────────────────────────────────────────────

/// "45 / 20 interactions ✅" — how close a trial is to being judgeable.
class TuningSampleProgress extends StatelessWidget {
  final int interactions;
  final int required;

  const TuningSampleProgress({
    super.key,
    required this.interactions,
    required this.required,
  });

  @override
  Widget build(BuildContext context) {
    final met = required > 0 && interactions >= required;
    final fraction = required > 0
        ? (interactions / required).clamp(0.0, 1.0)
        : 0.0;
    final color = met ? AppTheme.success : AppTheme.warning;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Sample size',
                style: const TextStyle(
                  fontSize: 12,
                  color: AppTheme.textSecondary,
                ),
              ),
            ),
            Text(
              '$interactions / $required interactions',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: color,
              ),
            ),
            const SizedBox(width: 4),
            Icon(
              met ? Icons.check_circle : Icons.pending_outlined,
              size: 14,
              color: color,
            ),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: fraction,
            minHeight: 6,
            backgroundColor: AppTheme.background,
            valueColor: AlwaysStoppedAnimation(color),
          ),
        ),
      ],
    );
  }
}

// ── Removal dialog ────────────────────────────────────────────────────────────

/// Asks for the mandatory removal comment. Returns the comment, or null if the
/// admin cancelled. Submit stays disabled under 3 characters, matching the
/// server-side rule so the admin never gets a surprise 422.
Future<String?> showTuningRemovalDialog(
  BuildContext context, {
  required String adjustmentId,
}) {
  final controller = TextEditingController();
  return showDialog<String>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) {
        final valid = controller.text.trim().length >= 3;
        return AlertDialog(
          title: const Text('Remove adjustment'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'This moves "$adjustmentId" to the trash. It can be restored '
                'until its retention period ends.',
                style: const TextStyle(
                  fontSize: 13,
                  color: AppTheme.textSecondary,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                autofocus: true,
                maxLines: 3,
                maxLength: 500,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  labelText: 'Reason (required)',
                  hintText: 'Why is this being removed?',
                  isDense: true,
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: valid
                  ? () => Navigator.pop(ctx, controller.text.trim())
                  : null,
              style: TextButton.styleFrom(foregroundColor: AppTheme.error),
              child: const Text('Remove'),
            ),
          ],
        );
      },
    ),
  ).whenComplete(controller.dispose);
}
