// lib/screens/super_admin/pages/adjustment_detail_screen.dart
// Superadmin-only detail view for one prompt-tuning adjustment: what it does,
// how its validation metric has moved since it was applied, and the manual
// override actions. Pushed as its own route (with a Scaffold) from the active
// list on the Prompt Tuning page, so the shell's sidebar stays put behind it.
//
// Backend contract: docs/prompt_tuning_api.md §5–6.

import 'package:flutter/material.dart';
import '../../../models/admin_models.dart';
import '../../../services/superadmin_service.dart';
import '../../../widgets/app_theme.dart';
import '../../admin/shared/admin_ui.dart';
import '../../admin/shared/widgets/tuning_ui.dart';

class AdjustmentDetailScreen extends StatefulWidget {
  final String adjustmentId;

  const AdjustmentDetailScreen({super.key, required this.adjustmentId});

  @override
  State<AdjustmentDetailScreen> createState() => _AdjustmentDetailScreenState();
}

class _AdjustmentDetailScreenState extends State<AdjustmentDetailScreen> {
  final _superadmin = SuperadminService();

  bool _loading = true;
  bool _acting = false;
  String? _error;
  AdjustmentAnalytics? _data;

  // Set when an override succeeds, so the caller knows to refresh its list.
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
      final data = await _superadmin.getAdjustmentAnalytics(
        widget.adjustmentId,
      );
      if (mounted) setState(() => _data = data);
    } catch (e) {
      if (mounted) {
        setState(
          () => _error = adminErrorMessage(
            e,
            access: 'Superadmin access required',
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _snack(String msg, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: error ? AppTheme.error : AppTheme.success,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _makePermanent() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Make permanent?'),
        content: const Text(
          'This skips auto-validation and keeps the adjustment in the prompt '
          'indefinitely. You can still remove it later.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Make permanent'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _acting = true);
    try {
      await _superadmin.forcePermanent(widget.adjustmentId);
      _changed = true;
      _snack('Adjustment is now permanent.');
      await _load();
    } catch (e) {
      _snack(adminErrorMessage(e), error: true);
    } finally {
      if (mounted) setState(() => _acting = false);
    }
  }

  Future<void> _remove() async {
    final comment = await showTuningRemovalDialog(
      context,
      adjustmentId: widget.adjustmentId,
    );
    if (comment == null) return;

    setState(() => _acting = true);
    try {
      await _superadmin.removeAdjustment(widget.adjustmentId, comment);
      _changed = true;
      _snack('Moved to trash.');
      await _load();
    } catch (e) {
      _snack(adminErrorMessage(e), error: true);
    } finally {
      if (mounted) setState(() => _acting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // PopScope reports back whether anything changed, so the list behind this
    // screen only refetches when it actually needs to.
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) Navigator.pop(context, _changed);
      },
      child: Scaffold(
        backgroundColor: AppTheme.background,
        appBar: AppBar(
          backgroundColor: const Color(0xFF7B1616),
          foregroundColor: Colors.white,
          elevation: 0,
          title: const Text('Adjustment'),
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
    final data = _data;
    if (data == null) {
      return const AdminEmptyCard(message: 'Adjustment not found.');
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _buildHeaderCard(data),
        const SizedBox(height: 16),
        _buildProgressCard(data),
        const SizedBox(height: 16),
        _buildMetricsCard(data),
        if (data.trashed != null) ...[
          const SizedBox(height: 16),
          _buildTrashedCard(data.trashed!),
        ],
        const SizedBox(height: 16),
        _buildHistoryCard(data),
        const SizedBox(height: 20),
        if (!data.isRemoved) _buildActions(data),
        const SizedBox(height: 24),
      ],
    );
  }

  // ── Header: what it is and what the system thinks of it ────────────────────

  Widget _buildHeaderCard(AdjustmentAnalytics data) {
    final adj = data.adjustment;
    return AdminSectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              tuningDimensionChip(adj.dimension),
              tuningStatusBadge(data.status),
              if (data.needsAttention) tuningAttentionBadge(),
              if (!adj.isMeasurable) tuningManualOnlyBadge(),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            adj.id,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: AppTheme.textSecondary,
            ),
          ),
          const SizedBox(height: 8),
          if (adj.trigger.isNotEmpty) ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.insights_outlined,
                  size: 14,
                  color: AppTheme.textMuted,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    adj.trigger,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
          ],
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppTheme.background,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              adj.instruction,
              style: const TextStyle(fontSize: 13, height: 1.45),
            ),
          ),
          const SizedBox(height: 12),
          _verdictRow(data),
          if (data.attentionReason != null) ...[
            const SizedBox(height: 8),
            Text(
              data.attentionReason!,
              style: const TextStyle(fontSize: 12, color: AppTheme.error),
            ),
          ],
        ],
      ),
    );
  }

  Widget _verdictRow(AdjustmentAnalytics data) {
    final color = tuningVerdictColor(data.verdict);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(Icons.flag_outlined, size: 16, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              tuningVerdictLabel(data.verdict),
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: color,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Trial progress + sample size ───────────────────────────────────────────

  Widget _buildProgressCard(AdjustmentAnalytics data) {
    final fraction = data.trialFraction;
    return AdminSectionCard(
      title: 'Trial progress',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            data.trialProgress,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: AppTheme.textPrimary,
            ),
          ),
          // No bar when there is no clock — an unmeasurable adjustment isn't
          // counting down to anything, it's waiting on a person.
          if (fraction != null) ...[
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: fraction,
                minHeight: 6,
                backgroundColor: AppTheme.background,
                valueColor: const AlwaysStoppedAnimation(AppTheme.primary),
              ),
            ),
          ] else if (data.isTrial) ...[
            const SizedBox(height: 6),
            const Text(
              'This adjustment has no measurable metric, so it will never be '
              'promoted or removed automatically.',
              style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
            ),
          ],
          if (data.extensionsUsed > 0) ...[
            const SizedBox(height: 8),
            Text(
              'Extended ${data.extensionsUsed} of ${data.maxExtensions} times '
              '(too little data at the original deadline).',
              style: const TextStyle(
                fontSize: 12,
                color: AppTheme.textSecondary,
              ),
            ),
          ],
          const SizedBox(height: 14),
          TuningSampleProgress(
            interactions: data.interactionsDuringTrial,
            required: data.minSampleRequired,
          ),
          if (data.adjustment.appliedAt != null) ...[
            const SizedBox(height: 12),
            Text(
              'Applied ${adminFormatTimestamp(data.adjustment.appliedAt!)}',
              style: const TextStyle(fontSize: 11, color: AppTheme.textMuted),
            ),
          ],
        ],
      ),
    );
  }

  // ── Before vs after ────────────────────────────────────────────────────────

  Widget _buildMetricsCard(AdjustmentAnalytics data) {
    final metric = data.baseline.metricName ?? data.current.metricName;
    return AdminSectionCard(
      title: 'Before vs after',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            tuningMetricLabel(metric),
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: AppTheme.textPrimary,
            ),
          ),
          const SizedBox(height: 14),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: _metricBlock(
                  'Before',
                  data.baseline.value,
                  metric,
                  data.baseline.measuredAt,
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: TuningTrendArrow(
                  trend: data.current.trend,
                  relativeChange: data.current.relativeChange,
                  size: 22,
                ),
              ),
              Expanded(
                child: _metricBlock(
                  'Now',
                  data.current.value,
                  metric,
                  data.current.measuredAt,
                ),
              ),
            ],
          ),
          if (data.current.value == null) ...[
            const SizedBox(height: 12),
            const Text(
              'Not enough observations to measure this metric yet.',
              style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
            ),
          ],
        ],
      ),
    );
  }

  Widget _metricBlock(
    String label,
    double? value,
    String? metric,
    String? measuredAt,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
      decoration: BoxDecoration(
        color: AppTheme.background,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          Text(
            label,
            style: const TextStyle(fontSize: 11, color: AppTheme.textSecondary),
          ),
          const SizedBox(height: 4),
          Text(
            tuningFormatMetric(value, metric),
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: AppTheme.textPrimary,
            ),
          ),
          if (measuredAt != null) ...[
            const SizedBox(height: 4),
            Text(
              adminFormatTimestamp(measuredAt),
              style: const TextStyle(fontSize: 10, color: AppTheme.textMuted),
              textAlign: TextAlign.center,
            ),
          ],
        ],
      ),
    );
  }

  // ── Trash details (when viewing a removed adjustment) ──────────────────────

  Widget _buildTrashedCard(TrashedAdjustment trashed) {
    return AdminSectionCard(
      title: trashed.wasAutoRemoved ? 'Auto-removed' : 'Removed',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (trashed.comment.isNotEmpty)
            Text(
              trashed.comment,
              style: const TextStyle(fontSize: 13, height: 1.4),
            ),
          const SizedBox(height: 10),
          _kv('When', adminFormatTimestamp(trashed.trashedAt)),
          _kv(
            'By',
            trashed.trashedBy == 'system'
                ? 'System (auto-validation)'
                : adminTruncate(trashed.trashedBy),
          ),
          if (trashed.retentionUntil != null)
            _kv('Deleted after', adminFormatTimestamp(trashed.retentionUntil!)),
        ],
      ),
    );
  }

  Widget _kv(String key, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(
              key,
              style: const TextStyle(
                fontSize: 12,
                color: AppTheme.textSecondary,
              ),
            ),
          ),
          Expanded(child: Text(value, style: const TextStyle(fontSize: 12))),
        ],
      ),
    );
  }

  // ── Audit history ──────────────────────────────────────────────────────────

  Widget _buildHistoryCard(AdjustmentAnalytics data) {
    if (data.history.isEmpty) {
      return const AdminSectionCard(
        title: 'History',
        child: Text(
          'No recorded actions yet.',
          style: TextStyle(fontSize: 13, color: AppTheme.textMuted),
        ),
      );
    }
    // Newest first reads better here even though the backend stores oldest-first.
    final entries = data.history.reversed.toList();
    return AdminSectionCard(
      title: 'History',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < entries.length; i++) ...[
            if (i > 0) const Divider(height: 16),
            _historyRow(entries[i]),
          ],
        ],
      ),
    );
  }

  Widget _historyRow(TuningAuditEntry entry) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          entry.bySystem ? Icons.smart_toy_outlined : Icons.person_outline,
          size: 15,
          color: AppTheme.textMuted,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      tuningAuditLabel(entry.action),
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Text(
                    adminFormatTimestamp(entry.timestamp),
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppTheme.textMuted,
                    ),
                  ),
                ],
              ),
              Text(
                entry.bySystem ? 'System' : adminTruncate(entry.performedBy),
                style: const TextStyle(
                  fontSize: 11,
                  color: AppTheme.textSecondary,
                ),
              ),
              if (entry.comment.isNotEmpty) ...[
                const SizedBox(height: 3),
                Text(
                  entry.comment,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppTheme.textSecondary,
                    height: 1.35,
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  // ── Manual override ────────────────────────────────────────────────────────

  Widget _buildActions(AdjustmentAnalytics data) {
    return Row(
      children: [
        if (!data.adjustment.isPermanent)
          Expanded(
            child: ElevatedButton.icon(
              onPressed: _acting ? null : _makePermanent,
              icon: const Icon(Icons.verified_outlined, size: 18),
              label: const Text('Make permanent'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.success,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ),
        if (!data.adjustment.isPermanent) const SizedBox(width: 12),
        Expanded(
          child: OutlinedButton.icon(
            onPressed: _acting ? null : _remove,
            icon: const Icon(Icons.delete_outline, size: 18),
            label: const Text('Remove'),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppTheme.error,
              side: const BorderSide(color: AppTheme.error),
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
          ),
        ),
      ],
    );
  }
}
