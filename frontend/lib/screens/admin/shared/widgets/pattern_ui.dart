// lib/screens/admin/shared/widgets/pattern_ui.dart
// Shared vocabulary for the pattern-override screens: category labels and
// colours, confidence/verdict badges, the satisfaction bar, and the revoke
// dialog. Lives here so the management page and the detail screen can never
// drift on what a category, confidence level, or verdict is called.

import 'package:flutter/material.dart';
import '../../../../widgets/app_theme.dart';

// ── Vocabulary ────────────────────────────────────────────────────────────────

String patternCategoryLabel(String category) {
  switch (category) {
    case 'reformulation':
      return 'Reformulation';
    case 'context_statement':
      return 'Context';
    case 'capability':
      return 'Capability';
    case 'agricultural_intent':
      return 'Intent';
    default:
      return category.replaceAll('_', ' ');
  }
}

/// Colour-coded per the category, so a row's type reads at a glance:
/// reformulation=blue, context=green, capability=purple, intent=orange.
Color patternCategoryColor(String category) {
  switch (category) {
    case 'reformulation':
      return const Color(0xFF1565C0);
    case 'context_statement':
      return AppTheme.success;
    case 'capability':
      return const Color(0xFF6A1B9A);
    case 'agricultural_intent':
      return AppTheme.accent;
    default:
      return AppTheme.textSecondary;
  }
}

/// What each category actually changes about routing — shown as section help so
/// an admin knows what they are switching on.
String patternCategoryHelp(String category) {
  switch (category) {
    case 'reformulation':
      return 'Rewrites the previous answer instead of running a new search.';
    case 'context_statement':
      return 'Acknowledges the farmer\'s situation instead of answering it.';
    case 'capability':
      return 'Replies with what the bot covers, from dataset metadata.';
    case 'agricultural_intent':
      return 'Asks a clarifying question instead of refusing as out of scope.';
    default:
      return '';
  }
}

String patternVerdictLabel(String verdict) {
  switch (verdict) {
    case 'working_well':
      return 'Working well';
    case 'needs_review':
      return 'Needs review';
    case 'likely_problematic':
      return 'Likely problematic';
    case 'insufficient_data':
      return 'Not enough data yet';
    default:
      return verdict.replaceAll('_', ' ');
  }
}

Color patternVerdictColor(String verdict) {
  switch (verdict) {
    case 'working_well':
      return AppTheme.success;
    case 'likely_problematic':
      return AppTheme.error;
    case 'needs_review':
      return AppTheme.warning;
    default:
      return AppTheme.textSecondary;
  }
}

IconData patternVerdictIcon(String verdict) {
  switch (verdict) {
    case 'working_well':
      return Icons.verified_outlined;
    case 'likely_problematic':
      return Icons.gpp_bad_outlined;
    case 'needs_review':
      return Icons.report_problem_outlined;
    default:
      return Icons.hourglass_empty;
  }
}

Color patternConfidenceColor(String confidence) {
  switch (confidence) {
    case 'high':
      return AppTheme.success;
    case 'medium':
      return AppTheme.warning;
    default:
      return AppTheme.textSecondary;
  }
}

String patternAuditLabel(String action) {
  switch (action) {
    case 'approved':
      return 'Approved';
    case 'approved_with_edit':
      return 'Approved with an edit';
    case 'revoked':
      return 'Revoked';
    case 'restored':
      return 'Restored';
    case 'deleted':
      return 'Deleted permanently';
    case 'auto_deleted':
      return 'Auto-deleted after retention';
    default:
      return action.replaceAll('_', ' ');
  }
}

// ── Badges ────────────────────────────────────────────────────────────────────

/// A small pill — the shared base for every badge below.
class PatternChip extends StatelessWidget {
  final String label;
  final Color color;
  final IconData? icon;

  const PatternChip({
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

Widget patternCategoryChip(String category) => PatternChip(
  label: patternCategoryLabel(category),
  color: patternCategoryColor(category),
);

Widget patternConfidenceChip(String confidence, int evidenceCount) =>
    PatternChip(
      label: '$confidence · $evidenceCount seen',
      color: patternConfidenceColor(confidence),
    );

Widget patternVerdictChip(String verdict) => PatternChip(
  label: patternVerdictLabel(verdict),
  color: patternVerdictColor(verdict),
  icon: patternVerdictIcon(verdict),
);

/// Marks a phrase the admin changed before approving. The original is shown on
/// tap so the edit is always auditable from the UI.
Widget patternEditedBadge(BuildContext context, String original) => InkWell(
  onTap: () => ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text('Originally proposed as "$original"'),
      backgroundColor: AppTheme.primary,
    ),
  ),
  borderRadius: BorderRadius.circular(6),
  child: const PatternChip(
    label: 'Edited',
    color: AppTheme.info,
    icon: Icons.edit_outlined,
  ),
);

// ── Satisfaction bar ──────────────────────────────────────────────────────────

/// Thumbs up vs. down as a single proportional bar, green/orange/red by the
/// same thresholds the backend's verdict uses. Renders a muted "no feedback
/// yet" track when nothing has been rated — an unrated pattern is not a bad
/// one, and must not read as 0%.
class PatternSatisfactionBar extends StatelessWidget {
  final int thumbsUp;
  final int thumbsDown;
  final bool compact;

  const PatternSatisfactionBar({
    super.key,
    required this.thumbsUp,
    required this.thumbsDown,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final rated = thumbsUp + thumbsDown;
    if (rated == 0) {
      return Row(
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: 0,
                minHeight: compact ? 4 : 6,
                backgroundColor: AppTheme.background,
                valueColor: const AlwaysStoppedAnimation(AppTheme.textMuted),
              ),
            ),
          ),
          const SizedBox(width: 8),
          const Text(
            'No feedback yet',
            style: TextStyle(fontSize: 11, color: AppTheme.textMuted),
          ),
        ],
      );
    }
    final satisfaction = thumbsUp / rated;
    final color = satisfaction >= 0.7
        ? AppTheme.success
        : satisfaction >= 0.4
        ? AppTheme.warning
        : AppTheme.error;
    return Row(
      children: [
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: satisfaction,
              minHeight: compact ? 4 : 6,
              backgroundColor: AppTheme.error.withValues(alpha: 0.18),
              valueColor: AlwaysStoppedAnimation(color),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          '${(satisfaction * 100).toStringAsFixed(0)}%  '
          '👍 $thumbsUp  👎 $thumbsDown',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: color,
          ),
        ),
      ],
    );
  }
}

// ── Revoke dialog ─────────────────────────────────────────────────────────────

/// Asks for the mandatory revoke reason. Returns the reason, or null if the
/// admin cancelled. Submit stays disabled under 3 characters, matching the
/// server-side rule so the admin never gets a surprise 422.
Future<String?> showRevokePatternDialog(
  BuildContext context, {
  required String phrase,
}) {
  final controller = TextEditingController();
  return showDialog<String>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) {
        final valid = controller.text.trim().length >= 3;
        return AlertDialog(
          title: const Text('Revoke pattern'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '"$phrase" stops matching immediately. It can be restored '
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
                  hintText: 'e.g. Too broad — matched real questions',
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
              child: const Text('Revoke'),
            ),
          ],
        );
      },
    ),
  ).whenComplete(controller.dispose);
}
