// lib/screens/admin/shared/pages/pattern_detail_screen.dart
// Per-pattern analytics for one admin-approved routing override: how often it
// matched, what farmers thought of those turns, which matches look like false
// positives, and the verdict that follows. Pushed as its own route from the
// pattern management page (and from a "pattern may need revoking" notification).
//
// Pops `true` when the pattern was revoked here, so the caller reloads.

import 'package:flutter/material.dart';
import '../../../../models/pattern_models.dart';
import '../../../../services/admin_service.dart';
import '../../../../widgets/app_theme.dart';
import '../admin_ui.dart';
import '../widgets/pattern_ui.dart';

class PatternDetailScreen extends StatefulWidget {
  final String patternId;

  /// Revoking is superadmin-only server-side; a plain admin gets the read-only
  /// view rather than a button that would 403.
  final bool canRevoke;

  const PatternDetailScreen({
    super.key,
    required this.patternId,
    this.canRevoke = true,
  });

  @override
  State<PatternDetailScreen> createState() => _PatternDetailScreenState();
}

class _PatternDetailScreenState extends State<PatternDetailScreen> {
  final _admin = AdminService();

  bool _loading = true;
  bool _revoking = false;
  String? _error;
  PatternAnalytics? _analytics;
  bool _changed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final analytics = await _admin.getPatternAnalytics(widget.patternId);
      if (mounted) setState(() => _analytics = analytics);
    } catch (e) {
      if (mounted) {
        setState(
          () => _error = adminErrorMessage(e, access: 'Admin access required'),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _revoke() async {
    final pattern = _analytics?.pattern;
    if (pattern == null) return;
    final reason = await showRevokePatternDialog(
      context,
      phrase: pattern.phrase,
    );
    if (reason == null || !mounted) return;

    setState(() => _revoking = true);
    try {
      await _admin.revokePattern(widget.patternId, reason);
      if (!mounted) return;
      _changed = true;
      _snack('Pattern revoked.');
      await _load();
    } catch (e) {
      if (mounted) _snack(adminErrorMessage(e), error: true);
    } finally {
      if (mounted) setState(() => _revoking = false);
    }
  }

  void _snack(String msg, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: error ? AppTheme.error : AppTheme.primary,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) Navigator.of(context).pop(_changed);
      },
      child: Scaffold(
        backgroundColor: AppTheme.background,
        appBar: AppBar(
          backgroundColor: AppTheme.primary,
          foregroundColor: Colors.white,
          title: const Text('Pattern detail'),
          actions: [
            IconButton(
              tooltip: 'Refresh',
              icon: const Icon(Icons.refresh),
              onPressed: _loading ? null : _load,
            ),
          ],
        ),
        body: _buildBody(),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(color: AppTheme.primary),
      );
    }
    if (_error != null) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: AdminErrorCard(message: _error!, onRetry: _load),
      );
    }
    final analytics = _analytics;
    if (analytics == null) {
      return const AdminEmptyCard(message: 'Pattern not found.');
    }
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeaderCard(analytics),
          const SizedBox(height: 16),
          _buildStatsCard(analytics),
          const SizedBox(height: 16),
          _buildExampleHitsCard(analytics),
          const SizedBox(height: 16),
          _buildFalsePositiveCard(analytics),
          const SizedBox(height: 16),
          _buildHistoryCard(analytics),
          if (widget.canRevoke && !analytics.pattern.isRevoked) ...[
            const SizedBox(height: 20),
            _buildRevokeButton(),
          ],
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _buildHeaderCard(PatternAnalytics a) {
    final pattern = a.pattern;
    return AdminSectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 6,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              patternCategoryChip(pattern.category),
              patternVerdictChip(a.verdict),
              if (pattern.edited)
                patternEditedBadge(context, pattern.originalProposedPhrase),
              if (pattern.isRevoked)
                const PatternChip(
                  label: 'Revoked',
                  color: AppTheme.error,
                  icon: Icons.block,
                ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            '"${pattern.phrase}"',
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: AppTheme.textPrimary,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            patternCategoryHelp(pattern.category),
            style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary),
          ),
          const SizedBox(height: 10),
          Text(
            'Applied ${adminTimeAgo(pattern.appliedAt)} · '
            'proposed from ${pattern.evidenceCount} missed message'
            '${pattern.evidenceCount == 1 ? '' : 's'}',
            style: const TextStyle(fontSize: 11, color: AppTheme.textMuted),
          ),
          if (pattern.isRevoked && pattern.revokeReason != null) ...[
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppTheme.error.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                'Revoked ${adminTimeAgo(pattern.revokedAt)}: '
                '${pattern.revokeReason}',
                style: const TextStyle(fontSize: 12, color: AppTheme.error),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildStatsCard(PatternAnalytics a) {
    return AdminSectionCard(
      title: 'Performance',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 24,
            runSpacing: 12,
            children: [
              _stat('Total matches', '${a.hitCount}'),
              _stat('Matches per day', a.hitRatePerDay.toStringAsFixed(1)),
              _stat(
                'Last match',
                a.lastHit == null ? 'Never' : adminTimeAgo(a.lastHit),
              ),
              _stat(
                'Satisfaction',
                a.feedback.rated == 0
                    ? '—'
                    : '${(a.satisfactionRate * 100).toStringAsFixed(0)}%',
              ),
            ],
          ),
          const SizedBox(height: 16),
          PatternSatisfactionBar(
            thumbsUp: a.feedback.thumbsUp,
            thumbsDown: a.feedback.thumbsDown,
          ),
          const SizedBox(height: 10),
          Text(
            '👍 ${a.feedback.thumbsUp} · 👎 ${a.feedback.thumbsDown} · '
            '${a.feedback.noFeedback} unrated',
            style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary),
          ),
          if (a.verdict == 'insufficient_data') ...[
            const SizedBox(height: 10),
            const Text(
              'Needs at least 5 matches and one thumbs vote before a verdict '
              'can be trusted.',
              style: TextStyle(fontSize: 11, color: AppTheme.textMuted),
            ),
          ],
        ],
      ),
    );
  }

  Widget _stat(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 11, color: AppTheme.textSecondary),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: AppTheme.textPrimary,
          ),
        ),
      ],
    );
  }

  Widget _buildExampleHitsCard(PatternAnalytics a) {
    return AdminSectionCard(
      title: 'Recent matches',
      child: a.exampleHits.isEmpty
          ? _emptyLine('This pattern has not matched anything yet.')
          : Column(children: [for (final hit in a.exampleHits) _hitRow(hit)]),
    );
  }

  Widget _buildFalsePositiveCard(PatternAnalytics a) {
    return AdminSectionCard(
      title: 'Possible false positives',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Matches the farmer thumbed down — the clearest sign a phrase is '
            'catching real questions it should not.',
            style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
          ),
          const SizedBox(height: 10),
          if (a.falsePositiveCandidates.isEmpty)
            _emptyLine('None so far.')
          else
            for (final hit in a.falsePositiveCandidates) _hitRow(hit),
        ],
      ),
    );
  }

  Widget _hitRow(PatternHit hit) {
    final down = hit.feedback == 'down';
    final up = hit.feedback == 'up';
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: down
            ? AppTheme.error.withValues(alpha: 0.06)
            : AppTheme.background,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  hit.message,
                  style: const TextStyle(
                    fontSize: 13,
                    color: AppTheme.textPrimary,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  adminTimeAgo(hit.timestamp),
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppTheme.textMuted,
                  ),
                ),
              ],
            ),
          ),
          if (up || down) ...[
            const SizedBox(width: 8),
            Icon(
              up ? Icons.thumb_up_outlined : Icons.thumb_down_outlined,
              size: 16,
              color: up ? AppTheme.success : AppTheme.error,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildHistoryCard(PatternAnalytics a) {
    return AdminSectionCard(
      title: 'History',
      child: a.history.isEmpty
          ? _emptyLine('No recorded actions.')
          : Column(
              children: [
                for (final entry in a.history)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(
                          Icons.circle,
                          size: 8,
                          color: AppTheme.textMuted,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                patternAuditLabel(entry.action),
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: AppTheme.textPrimary,
                                ),
                              ),
                              Text(
                                '${adminFormatTimestamp(entry.timestamp)} · '
                                '${adminTruncate(entry.performedBy)}',
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: AppTheme.textMuted,
                                ),
                              ),
                              if (entry.details.isNotEmpty)
                                Text(
                                  adminFormatDetails(entry.details),
                                  style: const TextStyle(
                                    fontSize: 11,
                                    color: AppTheme.textSecondary,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
    );
  }

  Widget _buildRevokeButton() {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: _revoking ? null : _revoke,
        icon: _revoking
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: AppTheme.error,
                ),
              )
            : const Icon(Icons.block, size: 18),
        label: Text(_revoking ? 'Revoking…' : 'Revoke this pattern'),
        style: OutlinedButton.styleFrom(
          foregroundColor: AppTheme.error,
          side: const BorderSide(color: AppTheme.error),
          padding: const EdgeInsets.symmetric(vertical: 14),
        ),
      ),
    );
  }

  Widget _emptyLine(String text) => Text(
    text,
    style: const TextStyle(fontSize: 12, color: AppTheme.textMuted),
  );
}
