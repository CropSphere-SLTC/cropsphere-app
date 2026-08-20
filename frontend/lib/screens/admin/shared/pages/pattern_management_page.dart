// lib/screens/admin/shared/pages/pattern_management_page.dart
// Pattern Management — superadmin-only. Analyses chat analytics for messages
// that SHOULD have matched one of the chatbot's routing patterns but didn't,
// proposes phrases for review (each editable before approval), then tracks how
// every approved phrase performs and lets it be revoked with a reason.
//
// Shell page (no Scaffold) rendered by admin_shell; the per-pattern detail view
// is pushed as its own route. Reached from the sidebar or the gap report's
// Pattern Health card.

import 'package:flutter/material.dart';
import '../../../../models/pattern_models.dart';
import '../../../../services/admin_service.dart';
import '../../../../widgets/app_theme.dart';
import '../../../../widgets/skeleton_loading.dart';
import '../admin_ui.dart';
import '../widgets/pattern_ui.dart';
import 'pattern_detail_screen.dart';

class PatternManagementPage extends StatefulWidget {
  const PatternManagementPage({super.key});

  @override
  State<PatternManagementPage> createState() => _PatternManagementPageState();
}

class _PatternManagementPageState extends State<PatternManagementPage> {
  final _admin = AdminService();
  int _days = 14;

  // Analysis state (top section).
  bool _analyzing = false;
  String? _analyzeError;
  PatternAnalysis? _analysis;
  final Set<String> _selected = {};

  /// One controller per proposal so the phrase stays editable in place. Keyed
  /// by proposal id and rebuilt on each analysis, since ids are stable for the
  /// same phrase but the set of proposals is not.
  final Map<String, TextEditingController> _phraseControllers = {};
  bool _applying = false;

  // Active + revoked state (bottom sections).
  bool _loadingActive = true;
  ActivePatterns? _active;
  List<PatternOverride> _revoked = [];
  bool _revokedExpanded = false;

  @override
  void initState() {
    super.initState();
    _loadActive();
  }

  @override
  void dispose() {
    for (final controller in _phraseControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _loadActive() async {
    setState(() => _loadingActive = true);
    try {
      final active = await _admin.getActivePatterns();
      if (mounted) setState(() => _active = active);
    } catch (_) {
      // Non-fatal: the "active" section just stays empty.
      if (mounted) setState(() => _active = null);
    } finally {
      if (mounted) setState(() => _loadingActive = false);
    }
    // Decoration around the main list — never let it block the active load.
    try {
      final items = await _admin.getRevokedPatterns();
      if (mounted) setState(() => _revoked = items);
    } catch (_) {
      // Non-fatal: the collapsible revoked section just stays empty.
    }
  }

  Future<void> _analyze() async {
    setState(() {
      _analyzing = true;
      _analyzeError = null;
    });
    try {
      final analysis = await _admin.analyzePatterns(days: _days);
      if (!mounted) return;
      setState(() {
        _analysis = analysis;
        _resetControllers(analysis.proposedPatterns);
        // Pre-check the recommended proposals; the rest start unchecked.
        _selected
          ..clear()
          ..addAll(
            analysis.proposedPatterns
                .where((p) => p.recommended)
                .map((p) => p.id),
          );
      });
    } catch (e) {
      if (mounted) setState(() => _analyzeError = adminErrorMessage(e));
    } finally {
      if (mounted) setState(() => _analyzing = false);
    }
  }

  void _resetControllers(List<ProposedPattern> proposals) {
    for (final controller in _phraseControllers.values) {
      controller.dispose();
    }
    _phraseControllers
      ..clear()
      ..addEntries(
        proposals.map(
          (p) => MapEntry(p.id, TextEditingController(text: p.proposedPhrase)),
        ),
      );
  }

  Future<void> _apply() async {
    final analysis = _analysis;
    if (analysis == null || _selected.isEmpty) return;

    final payload = <Map<String, dynamic>>[];
    for (final proposal in analysis.proposedPatterns) {
      if (!_selected.contains(proposal.id)) continue;
      final edited =
          (_phraseControllers[proposal.id]?.text ?? proposal.proposedPhrase)
              .trim();
      if (edited.isEmpty) continue;
      payload.add({
        'id': proposal.id,
        'phrase': edited,
        'edited': edited.toLowerCase() != proposal.proposedPhrase,
        'original_phrase': proposal.proposedPhrase,
      });
    }
    if (payload.isEmpty) return;

    setState(() => _applying = true);
    try {
      final result = await _admin.applyPatterns(payload, days: _days);
      if (!mounted) return;
      final n = result.appliedCount;
      // Surface why anything was dropped rather than quietly under-delivering:
      // an edited phrase can still fail server-side validation.
      final skipped = result.skipped.isEmpty
          ? ''
          : ' (${result.skipped.length} skipped: '
                '${result.skipped.first.reason})';
      _snack('Applied $n pattern${n == 1 ? '' : 's'}.$skipped');
      setState(() => _analysis = null);
      await _loadActive();
    } catch (e) {
      if (mounted) _snack(adminErrorMessage(e), error: true);
    } finally {
      if (mounted) setState(() => _applying = false);
    }
  }

  Future<void> _openDetail(String patternId) async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => PatternDetailScreen(patternId: patternId),
      ),
    );
    if (changed == true) await _loadActive();
  }

  Future<void> _revoke(PatternOverride pattern) async {
    final reason = await showRevokePatternDialog(
      context,
      phrase: pattern.phrase,
    );
    if (reason == null || !mounted) return;
    try {
      await _admin.revokePattern(pattern.id, reason);
      if (!mounted) return;
      _snack('Revoked "${pattern.phrase}".');
      await _loadActive();
    } catch (e) {
      if (mounted) _snack(adminErrorMessage(e), error: true);
    }
  }

  Future<void> _restore(PatternOverride pattern) async {
    try {
      await _admin.restorePattern(pattern.id);
      if (!mounted) return;
      _snack('Restored with fresh counters.');
      await _loadActive();
    } catch (e) {
      if (mounted) _snack(adminErrorMessage(e), error: true);
    }
  }

  Future<void> _delete(PatternOverride pattern) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete permanently?'),
        content: Text(
          '"${pattern.phrase}" and its match history are removed for good. '
          'This cannot be undone.',
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
      await _admin.deletePattern(pattern.id);
      if (!mounted) return;
      _snack('Deleted.');
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
            title: 'Pattern management',
            subtitle: 'Teach the chatbot phrasings its routing rules miss',
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
                _buildRevokedSection(),
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

  // ── Analyse / review / apply ────────────────────────────────────────────────

  Widget _buildAnalyzeSection() {
    return AdminSectionCard(
      title: 'Analyse pattern gaps',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Scans recent chats for messages that landed on the wrong branch — '
            'a rephrase request that got refused, a farmer introducing '
            'themselves that got searched. Nothing changes until you review, '
            'edit and apply below.',
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
                  : const Icon(Icons.travel_explore, size: 18),
              label: Text(_analyzing ? 'Analysing…' : 'Analyse patterns'),
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
          if (_analysis != null) ...[
            const SizedBox(height: 16),
            _buildAnalysisResult(_analysis!),
          ],
        ],
      ),
    );
  }

  Widget _buildAnalysisResult(PatternAnalysis analysis) {
    if (analysis.proposedPatterns.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppTheme.background,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          analysis.totalAnalyzed == 0
              ? 'No chats in the last ${analysis.periodDays} days to analyse.'
              : 'No gaps found — the ${analysis.totalAnalyzed} messages in the '
                    'last ${analysis.periodDays} days all routed correctly.',
          style: const TextStyle(fontSize: 13, color: AppTheme.textSecondary),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${analysis.proposedPatterns.length} proposed · '
          '${analysis.totalAnalyzed} messages over ${analysis.periodDays} days',
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: AppTheme.textSecondary,
          ),
        ),
        const SizedBox(height: 8),
        for (final proposal in analysis.proposedPatterns)
          _proposalTile(proposal),
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
            _applying ? 'Applying…' : 'Apply selected (${_selected.length})',
          ),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppTheme.success,
            foregroundColor: Colors.white,
          ),
        ),
      ],
    );
  }

  Widget _proposalTile(ProposedPattern proposal) {
    final checked = _selected.contains(proposal.id);
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
          leading: Checkbox(
            value: checked,
            activeColor: AppTheme.primary,
            onChanged: (v) => setState(() {
              if (v == true) {
                _selected.add(proposal.id);
              } else {
                _selected.remove(proposal.id);
              }
            }),
          ),
          title: Wrap(
            spacing: 6,
            runSpacing: 4,
            children: [
              patternCategoryChip(proposal.category),
              patternConfidenceChip(
                proposal.confidence,
                proposal.evidenceCount,
              ),
            ],
          ),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 6, bottom: 6),
            child: TextField(
              controller: _phraseControllers[proposal.id],
              maxLength: 50,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: AppTheme.textPrimary,
              ),
              decoration: const InputDecoration(
                isDense: true,
                counterText: '',
                prefixIcon: Icon(Icons.edit_outlined, size: 16),
                prefixIconConstraints: BoxConstraints(minWidth: 28),
                border: OutlineInputBorder(),
                contentPadding: EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 8,
                ),
              ),
              // Tick the row as soon as it is edited — an admin who bothers to
              // reword a phrase clearly intends to apply it.
              onChanged: (_) {
                if (!_selected.contains(proposal.id)) {
                  setState(() => _selected.add(proposal.id));
                }
              },
            ),
          ),
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                patternCategoryHelp(proposal.category),
                style: const TextStyle(
                  fontSize: 12,
                  color: AppTheme.textSecondary,
                ),
              ),
            ),
            const SizedBox(height: 8),
            const Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Real messages this was drawn from',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.textSecondary,
                ),
              ),
            ),
            const SizedBox(height: 6),
            for (final message in proposal.exampleMessages)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(
                      Icons.chat_bubble_outline,
                      size: 12,
                      color: AppTheme.textMuted,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        message,
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppTheme.textPrimary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  // ── Active patterns ─────────────────────────────────────────────────────────

  Widget _buildActiveSection() {
    if (_loadingActive) {
      // Staggered pattern — this section resolves to a list of pattern
      // rows, so the loading state previews that shape rather than a
      // centered spinner.
      return AdminSectionCard(
        title: 'Active patterns',
        child: StaggeredSkeletonList(
          itemCount: 4,
          shrinkWrap: true,
          itemBuilder: (context, i) =>
              const AdminTableRowSkeleton(cellCount: 2),
        ),
      );
    }
    final active = _active;
    if (active == null || active.active.isEmpty) {
      return const AdminSectionCard(
        title: 'Active patterns',
        child: Text(
          'No pattern overrides applied yet. The chatbot is running on its '
          'built-in routing rules alone.',
          style: TextStyle(fontSize: 13, color: AppTheme.textSecondary),
        ),
      );
    }

    final categories = active.byCategory.entries
        .where((e) => e.value.isNotEmpty)
        .toList();
    return AdminSectionCard(
      title: 'Active patterns (${active.active.length})',
      trailing: active.lastAnalysisAt == null
          ? null
          : Text(
              'Analysed ${adminTimeAgo(active.lastAnalysisAt)}',
              style: const TextStyle(fontSize: 11, color: AppTheme.textMuted),
            ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final entry in categories) ...[
            Padding(
              padding: const EdgeInsets.only(top: 4, bottom: 6),
              child: patternCategoryChip(entry.key),
            ),
            for (final pattern in entry.value) _activeTile(pattern),
            const SizedBox(height: 6),
          ],
        ],
      ),
    );
  }

  Widget _activeTile(PatternOverride pattern) {
    return InkWell(
      onTap: () => _openDetail(pattern.id),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: AppTheme.background,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '"${pattern.phrase}"',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                ),
                if (pattern.edited) ...[
                  patternEditedBadge(context, pattern.originalProposedPhrase),
                  const SizedBox(width: 6),
                ],
                patternVerdictChip(pattern.verdict),
                IconButton(
                  tooltip: 'Revoke',
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.block, size: 18),
                  color: AppTheme.error,
                  onPressed: () => _revoke(pattern),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              '${pattern.hitCount} match${pattern.hitCount == 1 ? '' : 'es'}'
              '${pattern.lastHit == null ? '' : ' · last ${adminTimeAgo(pattern.lastHit)}'}',
              style: const TextStyle(
                fontSize: 11,
                color: AppTheme.textSecondary,
              ),
            ),
            const SizedBox(height: 6),
            PatternSatisfactionBar(
              thumbsUp: pattern.feedback.thumbsUp,
              thumbsDown: pattern.feedback.thumbsDown,
              compact: true,
            ),
          ],
        ),
      ),
    );
  }

  // ── Revoked patterns ────────────────────────────────────────────────────────

  Widget _buildRevokedSection() {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          initiallyExpanded: _revokedExpanded,
          onExpansionChanged: (v) => setState(() => _revokedExpanded = v),
          tilePadding: const EdgeInsets.symmetric(horizontal: 16),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          title: Text(
            'Revoked patterns (${_revoked.length})',
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.bold,
              color: AppTheme.textPrimary,
            ),
          ),
          subtitle: const Text(
            'Restorable until their retention period ends',
            style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
          ),
          children: [
            if (_revoked.isEmpty)
              const Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Nothing revoked.',
                  style: TextStyle(fontSize: 12, color: AppTheme.textMuted),
                ),
              )
            else
              for (final pattern in _revoked) _revokedTile(pattern),
          ],
        ),
      ),
    );
  }

  Widget _revokedTile(PatternOverride pattern) {
    final performance = pattern.performanceAtRevoke;
    final days = pattern.daysRemaining;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppTheme.background,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '"${pattern.phrase}"',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textPrimary,
                  ),
                ),
              ),
              patternCategoryChip(pattern.category),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            pattern.revokeReason ?? 'No reason recorded',
            style: const TextStyle(fontSize: 12, color: AppTheme.error),
          ),
          if (performance != null) ...[
            const SizedBox(height: 4),
            Text(
              'At revoke: ${performance.hitCount} matches · '
              '👍 ${performance.thumbsUp} · 👎 ${performance.thumbsDown} · '
              '${(performance.satisfaction * 100).toStringAsFixed(0)}% '
              'satisfaction',
              style: const TextStyle(
                fontSize: 11,
                color: AppTheme.textSecondary,
              ),
            ),
          ],
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: Text(
                  days == null
                      ? 'Retention unknown'
                      : days == 0
                      ? 'Expires today'
                      : 'Expires in $days day${days == 1 ? '' : 's'}',
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppTheme.textMuted,
                  ),
                ),
              ),
              TextButton.icon(
                onPressed: () => _restore(pattern),
                icon: const Icon(Icons.restore, size: 16),
                label: const Text('Restore'),
                style: TextButton.styleFrom(
                  foregroundColor: AppTheme.primary,
                  visualDensity: VisualDensity.compact,
                ),
              ),
              TextButton.icon(
                onPressed: () => _delete(pattern),
                icon: const Icon(Icons.delete_outline, size: 16),
                label: const Text('Delete'),
                style: TextButton.styleFrom(
                  foregroundColor: AppTheme.error,
                  visualDensity: VisualDensity.compact,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
