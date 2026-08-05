// lib/screens/admin/shared/pages/prompt_tuning_page.dart
// Prompt Tuning — superadmin-only. Analyses recent chat analytics + feedback and
// proposes supplementary system-prompt instructions; the superadmin reviews and
// applies a subset, each of which then runs a trial before becoming permanent.
// Shell page (no Scaffold) rendered by admin_shell; the per-adjustment detail
// view is pushed as its own route.
// Backend contract: docs/prompt_tuning_api.md.

import 'package:flutter/material.dart';
import '../../../../models/admin_models.dart';
import '../../../../services/admin_service.dart';
import '../../../../services/superadmin_service.dart';
import '../../../../widgets/app_theme.dart';
import '../../../super_admin/pages/adjustment_detail_screen.dart';
import '../admin_ui.dart';
import '../widgets/tuning_ui.dart';

class PromptTuningPage extends StatefulWidget {
  const PromptTuningPage({super.key});

  @override
  State<PromptTuningPage> createState() => _PromptTuningPageState();
}

class _PromptTuningPageState extends State<PromptTuningPage> {
  final _admin = AdminService();
  final _superadmin = SuperadminService();
  int _days = 7;

  // Proposal state (top section).
  bool _analyzing = false;
  String? _analyzeError;
  PromptTuningProposal? _proposal;
  final Set<String> _selected = {}; // adjustment ids checked for apply
  bool _applying = false;

  // Active + trash state (bottom sections).
  bool _loadingActive = true;
  ActivePromptTuning? _active;
  List<TrashedAdjustment> _trash = [];
  bool _trashExpanded = false;

  @override
  void initState() {
    super.initState();
    _loadActive();
  }

  Future<void> _loadActive() async {
    setState(() => _loadingActive = true);
    try {
      final active = await _admin.getActivePromptTuning();
      if (mounted) setState(() => _active = active);
    } catch (_) {
      // Non-fatal: the "currently active" section just stays empty.
      if (mounted) setState(() => _active = null);
    } finally {
      if (mounted) setState(() => _loadingActive = false);
    }
    // Decoration around the main list — never let it block the active load.
    unawaitedLoad(_loadTrash);
  }

  /// Fire-and-forget a secondary load, swallowing its failure.
  void unawaitedLoad(Future<void> Function() load) {
    load().catchError((_) {});
  }

  Future<void> _loadTrash() async {
    final items = await _admin.getPromptTuningTrash();
    if (mounted) setState(() => _trash = items);
  }

  Future<void> _analyze() async {
    setState(() {
      _analyzing = true;
      _analyzeError = null;
    });
    try {
      final proposal = await _admin.analyzePromptTuning(days: _days);
      if (!mounted) return;
      setState(() {
        _proposal = proposal;
        // Pre-check the recommended adjustments (opt-in ones start unchecked).
        // Never pre-check one that is already applied: re-analysis re-proposes
        // conditions that are still true, and ticking those by default made
        // every run look like there was new work to do.
        _selected
          ..clear()
          ..addAll(
            proposal.adjustments
                .where((a) => a.recommended && !a.alreadyActive)
                .map((a) => a.id),
          );
      });
    } catch (e) {
      if (mounted) setState(() => _analyzeError = adminErrorMessage(e));
    } finally {
      if (mounted) setState(() => _analyzing = false);
    }
  }

  Future<void> _apply() async {
    if (_selected.isEmpty) return;
    setState(() => _applying = true);
    try {
      final result = await _admin.applyPromptTuning(
        _selected.toList(),
        days: _days,
      );
      if (!mounted) return;
      // applied_count is the source of truth — a proposal that stopped
      // triggering server-side is silently dropped, so it can be lower than
      // the number ticked. Call that out rather than quietly under-delivering.
      final n = result.appliedCount;
      final dropped = _selected.length - n - result.skippedIds.length;
      final extra = [
        if (result.skippedIds.isNotEmpty)
          '${result.skippedIds.length} already active',
        if (dropped > 0) '$dropped no longer triggered',
      ].join(', ');
      _snack(
        'Started $n trial${n == 1 ? '' : 's'}'
        '${extra.isEmpty ? '.' : ' ($extra).'}',
      );
      setState(() => _proposal = null); // clear the reviewed proposal
      await _loadActive();
    } catch (e) {
      if (mounted) _snack(adminErrorMessage(e), error: true);
    } finally {
      if (mounted) setState(() => _applying = false);
    }
  }

  Future<void> _clearAll() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clear all tuning?'),
        content: const Text(
          'The chatbot will revert to its default prompt. Everything moves to '
          'the trash and can be restored until its retention period ends.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: AppTheme.error),
            child: const Text('Clear all'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      final n = await _admin.clearPromptTuning();
      if (!mounted) return;
      _snack('Moved $n adjustment${n == 1 ? '' : 's'} to the trash.');
      await _loadActive();
    } catch (e) {
      if (mounted) _snack(adminErrorMessage(e), error: true);
    }
  }

  Future<void> _openDetail(String adjustmentId) async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => AdjustmentDetailScreen(adjustmentId: adjustmentId),
      ),
    );
    if (changed == true) await _loadActive();
  }

  Future<void> _restore(String adjustmentId) async {
    try {
      await _admin.restoreFromTrash(adjustmentId);
      if (!mounted) return;
      _snack('Restored as a fresh trial.');
      await _loadActive();
    } catch (e) {
      if (mounted) _snack(adminErrorMessage(e), error: true);
    }
  }

  Future<void> _emptyTrash() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Empty the trash?'),
        content: const Text(
          'This permanently deletes every trashed adjustment, including ones '
          'whose retention period has not ended. This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: AppTheme.error),
            child: const Text('Delete permanently'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      final n = await _superadmin.clearTrash(allItems: true);
      if (!mounted) return;
      _snack('Deleted $n item${n == 1 ? '' : 's'}.');
      await _loadActive();
    } catch (e) {
      if (mounted) _snack(adminErrorMessage(e), error: true);
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          child: AdminPageHeader(
            title: 'Prompt tuning',
            subtitle: 'Adjust the chatbot prompt from real usage patterns',
            actions: [_buildDaySelector()],
            onRefresh: _loadingActive ? null : _loadActive,
          ),
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildAnalyzeSection(),
                const SizedBox(height: 20),
                _buildActiveSection(),
                const SizedBox(height: 20),
                _buildTrashSection(),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDaySelector() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: AppTheme.background,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE0EBE0)),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<int>(
          value: _days,
          isDense: true,
          items: const [
            DropdownMenuItem(value: 7, child: Text('7 days')),
            DropdownMenuItem(value: 14, child: Text('14 days')),
            DropdownMenuItem(value: 30, child: Text('30 days')),
          ],
          onChanged: (_analyzing || _applying)
              ? null
              : (d) => setState(() => _days = d ?? _days),
        ),
      ),
    );
  }

  // ── Analyze / review / apply ────────────────────────────────────────────────

  Widget _buildAnalyzeSection() {
    return AdminSectionCard(
      title: 'Analyse usage',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Scans the last window of chatbot analytics and feedback and '
            'proposes prompt adjustments. Nothing is applied until you select '
            'and confirm below — and everything you apply runs a trial first.',
            style: TextStyle(fontSize: 13, color: AppTheme.textSecondary),
          ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerLeft,
            child: ElevatedButton.icon(
              onPressed: _analyzing ? null : _analyze,
              icon: _analyzing
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.analytics_outlined, size: 18),
              label: Text(_analyzing ? 'Analysing…' : 'Analyse'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primary,
                foregroundColor: Colors.white,
              ),
            ),
          ),
          if (_analyzeError != null) ...[
            const SizedBox(height: 12),
            AdminErrorCard(message: _analyzeError!, onRetry: _analyze),
          ],
          if (_proposal != null) ...[
            const SizedBox(height: 16),
            _buildProposal(_proposal!),
          ],
        ],
      ),
    );
  }

  Widget _buildProposal(PromptTuningProposal p) {
    if (p.adjustments.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppTheme.background,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          p.sampleSize < 30
              ? 'Not enough data yet (${p.sampleSize} interactions in the '
                    'last ${p.periodDays} days). Try a wider window or check '
                    'back once more farmers have chatted.'
              : 'No adjustments proposed — usage looks healthy over the last '
                    '${p.periodDays} days (${p.sampleSize} interactions).',
          style: const TextStyle(fontSize: 13, color: AppTheme.textSecondary),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          [
            'Proposed adjustments · ${p.sampleSize} interactions over '
                '${p.periodDays} days',
            // Says why fewer rows are ticked than listed, so a re-analysis
            // does not read as a page full of new findings.
            if (p.alreadyActiveCount > 0)
              '${p.alreadyActiveCount} already active',
          ].join(' · '),
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: AppTheme.textSecondary,
          ),
        ),
        const SizedBox(height: 8),
        for (final a in p.adjustments) _proposalTile(a),
        const SizedBox(height: 12),
        ElevatedButton.icon(
          onPressed: (_applying || _selected.isEmpty) ? null : _apply,
          icon: _applying
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Icon(Icons.check, size: 18),
          label: Text(
            _applying
                ? 'Applying…'
                : 'Start trial for selected (${_selected.length})',
          ),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppTheme.success,
            foregroundColor: Colors.white,
          ),
        ),
      ],
    );
  }

  Widget _proposalTile(PromptTuningAdjustment a) {
    final checked = _selected.contains(a.id);
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      decoration: BoxDecoration(
        color: AppTheme.background,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: checked
              ? AppTheme.primary.withValues(alpha: 0.4)
              : const Color(0xFFE0EBE0),
        ),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 8),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          // Already applied: the tick would be a no-op server-side, so disable
          // it rather than let an admin believe they just did something.
          leading: Checkbox(
            value: checked,
            activeColor: AppTheme.primary,
            onChanged: a.alreadyActive
                ? null
                : (v) => setState(() {
                    if (v == true) {
                      _selected.add(a.id);
                    } else {
                      _selected.remove(a.id);
                    }
                  }),
          ),
          title: Wrap(
            spacing: 6,
            runSpacing: 4,
            children: [
              tuningDimensionChip(a.dimension),
              if (a.alreadyActive) _alreadyActiveChip(),
              if (!a.recommended && !a.alreadyActive) _optInChip(),
              // Warn up front: this one will sit in trial until decided.
              if (!a.isMeasurable) tuningManualOnlyBadge(),
            ],
          ),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              a.trigger,
              style: const TextStyle(
                fontSize: 12,
                color: AppTheme.textSecondary,
              ),
            ),
          ),
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                a.instruction,
                style: const TextStyle(fontSize: 13, height: 1.4),
              ),
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                a.isMeasurable
                    ? 'Will be judged on ${tuningMetricLabel(a.validationMetric)} '
                          '(now ${tuningFormatMetric(a.baselineValue, a.validationMetric)})'
                    : 'No measurable metric — this will stay in trial until you '
                          'decide.',
                style: const TextStyle(fontSize: 11, color: AppTheme.textMuted),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Currently active ────────────────────────────────────────────────────────

  Widget _buildActiveSection() {
    final active = _active;
    final count = active?.count ?? 0;
    return AdminSectionCard(
      title: 'Currently active',
      trailing: (count > 0)
          ? TextButton.icon(
              onPressed: _clearAll,
              icon: const Icon(Icons.delete_outline, size: 18),
              label: const Text('Clear all'),
              style: TextButton.styleFrom(foregroundColor: AppTheme.error),
            )
          : null,
      child: _loadingActive
          ? const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Center(
                child: CircularProgressIndicator(color: AppTheme.primary),
              ),
            )
          : (active == null || active.adjustments.isEmpty)
          ? const Padding(
              padding: EdgeInsets.symmetric(vertical: 4),
              child: Text(
                'No tuning active — the chatbot is using its default prompt.',
                style: TextStyle(fontSize: 13, color: AppTheme.textMuted),
              ),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${active.trialCount} in trial · '
                  '${active.permanentCount} permanent',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textSecondary,
                  ),
                ),
                if (active.updatedAt != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 2, bottom: 8),
                    child: Text(
                      'Updated: ${adminFormatTimestamp(active.updatedAt!)}',
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppTheme.textMuted,
                      ),
                    ),
                  ),
                for (final a in active.adjustments) _activeTile(a),
              ],
            ),
    );
  }

  Widget _activeTile(PromptTuningAdjustment a) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      decoration: BoxDecoration(
        color: AppTheme.background,
        borderRadius: BorderRadius.circular(8),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () => _openDetail(a.id),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        tuningDimensionChip(a.dimension),
                        tuningStatusBadge(a.status),
                        if (a.needsAttention) tuningAttentionBadge(),
                        if (!a.isMeasurable && !a.isPermanent)
                          tuningManualOnlyBadge(),
                      ],
                    ),
                  ),
                  const Icon(
                    Icons.chevron_right,
                    size: 18,
                    color: AppTheme.textMuted,
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                a.instruction,
                style: const TextStyle(fontSize: 13, height: 1.4),
              ),
              if (a.status == 'trial') ...[
                const SizedBox(height: 6),
                Text(
                  _trialSubtitle(a),
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppTheme.textMuted,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// One line of trial context under an active adjustment. A null
  /// trial_ends_at is normal, not an error — it means nothing will happen
  /// automatically, so say that rather than showing a countdown.
  String _trialSubtitle(PromptTuningAdjustment a) {
    final endsAt = a.trialEndsAt;
    if (endsAt == null) {
      return 'Awaiting your decision — no automatic validation';
    }
    final end = DateTime.tryParse(endsAt);
    if (end == null) return 'Trial in progress';
    final remaining = end.difference(DateTime.now()).inDays;
    if (remaining < 0) return 'Trial ended — validating shortly';
    if (remaining == 0) return 'Trial ends today';
    return 'Trial ends in $remaining day${remaining == 1 ? '' : 's'}';
  }

  // ── Trash ───────────────────────────────────────────────────────────────────

  Widget _buildTrashSection() {
    final count = _trash.length;
    return AdminSectionCard(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: EdgeInsets.zero,
          childrenPadding: const EdgeInsets.only(bottom: 12),
          initiallyExpanded: _trashExpanded,
          onExpansionChanged: (v) => setState(() => _trashExpanded = v),
          leading: const Icon(
            Icons.delete_outline,
            color: AppTheme.textSecondary,
          ),
          title: Text(
            'Trash${count > 0 ? ' ($count)' : ''}',
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.bold,
              color: AppTheme.textPrimary,
            ),
          ),
          subtitle: const Text(
            'Removed adjustments, restorable until retention ends',
            style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
          ),
          children: [
            if (_trash.isEmpty)
              const Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Nothing in the trash.',
                  style: TextStyle(fontSize: 13, color: AppTheme.textMuted),
                ),
              )
            else ...[
              for (final t in _trash) _trashTile(t),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: _emptyTrash,
                  icon: const Icon(Icons.delete_forever_outlined, size: 18),
                  label: const Text('Empty trash'),
                  style: TextButton.styleFrom(foregroundColor: AppTheme.error),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _trashTile(TrashedAdjustment t) {
    final a = t.adjustment;
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppTheme.background,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: [
              tuningDimensionChip(a.dimension),
              TuningChip(
                label: t.wasAutoRemoved ? 'Auto-removed' : 'Removed by admin',
                color: t.wasAutoRemoved
                    ? AppTheme.error
                    : AppTheme.textSecondary,
                icon: t.wasAutoRemoved
                    ? Icons.gpp_bad_outlined
                    : Icons.person_outline,
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            a.instruction,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 13, height: 1.4),
          ),
          if (t.comment.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              t.comment,
              style: const TextStyle(
                fontSize: 11,
                color: AppTheme.textSecondary,
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: Text(
                  t.retentionUntil == null
                      ? 'Removed ${adminFormatTimestamp(t.trashedAt)}'
                      : 'Deleted after '
                            '${adminFormatTimestamp(t.retentionUntil!)}',
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppTheme.textMuted,
                  ),
                ),
              ),
              TextButton.icon(
                onPressed: t.canRestore ? () => _restore(a.id) : null,
                icon: const Icon(Icons.restore, size: 16),
                label: const Text('Restore'),
                style: TextButton.styleFrom(
                  foregroundColor: AppTheme.primary,
                  visualDensity: VisualDensity.compact,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _optInChip() =>
      const TuningChip(label: 'opt-in', color: AppTheme.warning);

  /// Marks a proposal that is already applied. It is still listed, because a
  /// condition that keeps triggering while an adjustment for it is live means
  /// that adjustment is not working yet — but it cannot be applied again.
  Widget _alreadyActiveChip() =>
      const TuningChip(label: 'already active', color: AppTheme.info);
}
