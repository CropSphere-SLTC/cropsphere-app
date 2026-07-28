// lib/screens/admin/shared/pages/gap_report_page.dart
// Gap Report — visualises chat_analytics aggregates to reveal what data users
// ask for that CropSphere can't answer yet. Relocated from the old
// gap_report_screen.dart: same content and charts, now a shell page (no
// Scaffold/AppBar — the day selector moved into the page header). Both roles.

import 'package:flutter/material.dart';
import '../../../../models/admin_models.dart';
import '../../../../models/pattern_models.dart';
import '../../../../services/admin_service.dart';
import '../../../../widgets/app_theme.dart';
import '../admin_ui.dart';
import '../widgets/admin_sidebar.dart';
import '../widgets/stat_card.dart';

class GapReportPage extends StatefulWidget {
  // role + onNavigate are optional so the page still works standalone; the
  // shell passes them so the superadmin-only "Prompt tuning" card can appear
  // and navigate. Both roles see the gap report itself.
  final String role;
  final ValueChanged<AdminPage>? onNavigate;

  const GapReportPage({super.key, this.role = 'admin', this.onNavigate});

  @override
  State<GapReportPage> createState() => _GapReportPageState();
}

class _GapReportPageState extends State<GapReportPage> {
  final _admin = AdminService();
  int _days = 7;
  bool _loading = true;
  String? _error;
  GapReport? _report;
  int? _tuningCount; // active prompt-tuning adjustments (superadmin only)

  bool get _isSuper => widget.role == 'superadmin';

  @override
  void initState() {
    super.initState();
    _load();
    if (_isSuper) _loadTuningCount();
  }

  // Best-effort badge for the prompt-tuning card — never blocks the report.
  Future<void> _loadTuningCount() async {
    try {
      final active = await _admin.getActivePromptTuning();
      if (mounted) setState(() => _tuningCount = active.count);
    } catch (_) {
      // Leave the badge off if this fails; the card still navigates.
    }
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final report = await _admin.getGapReport(days: _days);
      if (mounted) setState(() => _report = report);
    } catch (e) {
      if (mounted) setState(() => _error = adminErrorMessage(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _changeDays(int? days) async {
    if (days == null || days == _days) return;
    setState(() => _days = days);
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          child: AdminPageHeader(
            title: 'Gap report',
            subtitle: 'Chatbot usage & missing-data insights',
            actions: [_buildDaySelector()],
          ),
        ),
        Expanded(child: _buildBody()),
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
          onChanged: _loading ? null : _changeDays,
        ),
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
      return _centeredMessage(
        Icons.error_outline,
        AppTheme.error,
        _error!,
        retry: true,
      );
    }
    final report = _report;
    if (report == null || report.totalInteractions == 0) {
      return _centeredMessage(
        Icons.insights,
        AppTheme.textMuted,
        'No chatbot analytics data found.\n'
        'Start chatting to see insights here!',
      );
    }
    return RefreshIndicator(
      color: AppTheme.primary,
      onRefresh: _load,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSummaryCards(report),
            const SizedBox(height: 20),
            _sectionCard(
              'Response breakdown',
              _barList(report.responseBreakdown, _responseColor),
            ),
            const SizedBox(height: 16),
            _sectionCard(
              'Top refused questions',
              _refusedList(report.topRefusedQuestions),
            ),
            const SizedBox(height: 16),
            _buildMissingRow(report),
            const SizedBox(height: 16),
            _sectionCard(
              'Confidence distribution',
              _barList(report.confidenceDistribution, _confidenceColor),
            ),
            const SizedBox(height: 16),
            _sectionCard(
              'Knowledge level distribution',
              _barList(report.knowledgeLevelDistribution, _levelColor),
            ),
            const SizedBox(height: 16),
            _buildFeedbackCard(report.feedbackSummary),
            const SizedBox(height: 16),
            _buildFewshotCard(report.fewshot),
            const SizedBox(height: 16),
            _buildPatternHealthCard(report.patternHealth),
            if (_isSuper && widget.onNavigate != null) ...[
              const SizedBox(height: 16),
              _buildPromptTuningCard(),
            ],
            const SizedBox(height: 16),
            _buildSessionCard(report),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  // Thumbs up/down summary from chat_feedback (Step 8).
  Widget _buildFeedbackCard(FeedbackSummary fb) {
    if (fb.totalFeedback == 0) {
      return _sectionCard('Feedback', _emptyLine('No feedback yet.'));
    }
    return _sectionCard(
      'Feedback',
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 20,
            runSpacing: 12,
            children: [
              _feedbackStat(
                '${(fb.satisfactionRate * 100).round()}%',
                'satisfaction',
                Icons.sentiment_satisfied_alt,
                AppTheme.success,
              ),
              _feedbackStat(
                '${fb.thumbsUp}',
                'thumbs up',
                Icons.thumb_up,
                AppTheme.success,
              ),
              _feedbackStat(
                '${fb.thumbsDown}',
                'thumbs down',
                Icons.thumb_down,
                AppTheme.accent,
              ),
            ],
          ),
          if (fb.mostDownvotedQuestions.isNotEmpty) ...[
            const SizedBox(height: 14),
            const Text(
              'Most downvoted questions',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppTheme.textSecondary,
              ),
            ),
            const SizedBox(height: 6),
            _refusedList(fb.mostDownvotedQuestions),
          ],
        ],
      ),
    );
  }

  Widget _feedbackStat(String value, String label, IconData icon, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(width: 6),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              value,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: AppTheme.textPrimary,
              ),
            ),
            Text(
              label,
              style: const TextStyle(
                fontSize: 11,
                color: AppTheme.textSecondary,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildSummaryCards(GapReport report) {
    final total = report.totalInteractions;
    final answers = report.responseBreakdown['answer'] ?? 0;
    final answerRate = total == 0 ? 0 : (answers / total * 100).round();
    return StatCardGrid(
      cards: [
        StatCard(
          label: 'Total interactions',
          value: '$total',
          icon: Icons.chat_bubble_outline,
          color: AppTheme.primary,
        ),
        StatCard(
          label: 'Answer rate',
          value: '$answerRate%',
          icon: Icons.check_circle_outline,
          color: AppTheme.success,
        ),
        StatCard(
          label: 'Avg response time',
          value: _formatMs(report.avgResponseTimeMs),
          icon: Icons.timer_outlined,
          color: AppTheme.info,
        ),
        StatCard(
          label: 'Chip tap rate',
          value: '${(report.chipTapRate * 100).round()}%',
          icon: Icons.touch_app_outlined,
          color: AppTheme.accent,
        ),
      ],
    );
  }

  Widget _buildMissingRow(GapReport report) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: _sectionCard(
            'Missing crops',
            _missingList(report.missingCrops, Icons.grass),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _sectionCard(
            'Missing districts',
            _missingList(report.missingDistricts, Icons.location_on),
          ),
        ),
      ],
    );
  }

  // Few-shot examples file status (Step 6): total, per-type counts, updated_at.
  Widget _buildFewshotCard(FewshotInfo fs) {
    if (!fs.fileExists) {
      return _sectionCard(
        'Few-shot examples',
        _emptyLine(
          'No examples file yet — run "Rebuild few-shot" to create it.',
        ),
      );
    }
    final types = ['yield', 'price', 'season', 'earnings', 'general'];
    return _sectionCard(
      'Few-shot examples',
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                '${fs.total}',
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.textPrimary,
                ),
              ),
              const SizedBox(width: 6),
              const Text(
                'examples loaded',
                style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final t in types)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: AppTheme.background,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '$t: ${fs.counts[t] ?? 0}',
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
            ],
          ),
          if (fs.updatedAt != null) ...[
            const SizedBox(height: 8),
            Text(
              'Updated: ${fs.updatedAt}',
              style: const TextStyle(fontSize: 11, color: AppTheme.textMuted),
            ),
          ],
        ],
      ),
    );
  }

  // Pattern Health: how the admin-approved routing overrides are performing.
  // Visible to admins too (the underlying reads are admin-readable), but only a
  // superadmin gets the tap-through, since managing them is superadmin-only.
  Widget _buildPatternHealthCard(PatternHealth health) {
    final canManage = _isSuper && widget.onNavigate != null;
    final needsReview = health.needsReviewCount;
    final body = Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppTheme.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.rule, color: AppTheme.primary),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Pattern health',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'Admin-approved phrases supplementing the routing rules',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              if (needsReview > 0) ...[
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: AppTheme.warning.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    '$needsReview need review',
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.warning,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
              ],
              if (canManage)
                const Icon(Icons.chevron_right, color: AppTheme.textMuted),
            ],
          ),
          const SizedBox(height: 14),
          if (health.activeCount == 0)
            _emptyLine(
              'No pattern overrides yet — the chatbot is running on its '
              'built-in routing rules alone.',
            )
          else
            Wrap(
              spacing: 24,
              runSpacing: 12,
              children: [
                _patternStat('Active', '${health.activeCount}'),
                _patternStat('Matches this period', '${health.hitsThisPeriod}'),
                _patternStat('Matches all time', '${health.totalHits}'),
                _patternStat(
                  'Avg. satisfaction',
                  health.avgSatisfaction == 0
                      ? '—'
                      : '${(health.avgSatisfaction * 100).toStringAsFixed(0)}%',
                ),
                _patternStat('Revoked', '${health.revokedCount}'),
              ],
            ),
          const SizedBox(height: 10),
          Text(
            health.lastAnalysisAt == null
                ? 'Never analysed'
                : 'Last analysed ${adminTimeAgo(health.lastAnalysisAt)}',
            style: const TextStyle(fontSize: 11, color: AppTheme.textMuted),
          ),
        ],
      ),
    );

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: canManage
          ? InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () => widget.onNavigate?.call(AdminPage.patternManagement),
              child: body,
            )
          : body,
    );
  }

  Widget _patternStat(String label, String value) {
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

  // Step 7: superadmin shortcut into the Prompt Tuning screen, with a live
  // badge of how many adjustments are currently active.
  Widget _buildPromptTuningCard() {
    final count = _tuningCount;
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => widget.onNavigate?.call(AdminPage.promptTuning),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppTheme.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.tune, color: AppTheme.primary),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Prompt tuning',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'Adjust the chatbot prompt from usage patterns',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              if (count != null && count > 0) ...[
                _countBadge(count),
                const SizedBox(width: 4),
                const Text(
                  'active',
                  style: TextStyle(fontSize: 11, color: AppTheme.textSecondary),
                ),
                const SizedBox(width: 8),
              ],
              const Icon(Icons.chevron_right, color: AppTheme.textMuted),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSessionCard(GapReport report) {
    return _sectionCard(
      'Average session length',
      Row(
        children: [
          const Icon(Icons.forum, color: AppTheme.primary),
          const SizedBox(width: 10),
          Text(
            '${report.avgSessionLength}',
            style: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: AppTheme.textPrimary,
            ),
          ),
          const SizedBox(width: 6),
          const Text(
            'messages per conversation',
            style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
          ),
        ],
      ),
    );
  }

  Widget _sectionCard(String title, Widget child) {
    return AdminSectionCard(title: title, child: child);
  }

  Widget _barList(Map<String, int> data, Color Function(String) colorFn) {
    if (data.isEmpty) return _emptyLine('No data');
    final entries = data.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final max = entries.first.value;
    return Column(
      children: entries
          .map((e) => _bar(_prettyLabel(e.key), e.value, max, colorFn(e.key)))
          .toList(),
    );
  }

  Widget _bar(String label, int count, int max, Color color) {
    final frac = max <= 0 ? 0.0 : (count / max).clamp(0.0, 1.0);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 110,
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 12,
                color: AppTheme.textSecondary,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Stack(
              children: [
                Container(
                  height: 20,
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: AppTheme.background,
                    borderRadius: BorderRadius.circular(6),
                  ),
                ),
                FractionallySizedBox(
                  widthFactor: frac,
                  child: Container(
                    height: 20,
                    decoration: BoxDecoration(
                      color: color,
                      borderRadius: BorderRadius.circular(6),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 34,
            child: Text(
              '$count',
              textAlign: TextAlign.right,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  Widget _refusedList(List<RefusedQuestion> items) {
    if (items.isEmpty) {
      return _emptyLine('No refused questions in this period.');
    }
    return Column(
      children: items
          .map(
            (q) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      q.question,
                      style: const TextStyle(fontSize: 13),
                    ),
                  ),
                  const SizedBox(width: 8),
                  _countBadge(q.count),
                ],
              ),
            ),
          )
          .toList(),
    );
  }

  Widget _missingList(List<MissingItem> items, IconData icon) {
    if (items.isEmpty) return _emptyLine('None 🎉');
    return Column(
      children: items
          .map(
            (m) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  Icon(icon, size: 15, color: AppTheme.textMuted),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(m.name, style: const TextStyle(fontSize: 13)),
                  ),
                  _countBadge(m.requestCount),
                ],
              ),
            ),
          )
          .toList(),
    );
  }

  Widget _countBadge(int count) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: AppTheme.primary.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        '$count',
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: AppTheme.primary,
        ),
      ),
    );
  }

  Widget _emptyLine(String text) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Text(
      text,
      style: const TextStyle(fontSize: 13, color: AppTheme.textMuted),
    ),
  );

  Widget _centeredMessage(
    IconData icon,
    Color color,
    String text, {
    bool retry = false,
  }) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48, color: color),
            const SizedBox(height: 12),
            Text(
              text,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 14,
                color: AppTheme.textSecondary,
              ),
            ),
            if (retry) ...[
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: _load,
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primary,
                  foregroundColor: Colors.white,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _formatMs(int ms) =>
      ms >= 1000 ? '${(ms / 1000).toStringAsFixed(1)}s' : '${ms}ms';

  String _prettyLabel(String key) {
    if (key.isEmpty) return key;
    final spaced = key.replaceAll('_', ' ');
    return spaced[0].toUpperCase() + spaced.substring(1);
  }

  Color _responseColor(String k) {
    switch (k) {
      case 'answer':
        return AppTheme.success;
      case 'refusal':
        return AppTheme.error;
      case 'near_miss':
        return AppTheme.warning;
      case 'clarification':
        return AppTheme.info;
      case 'capability':
        return AppTheme.primaryLight;
      case 'context_ack':
        return AppTheme.accent;
      case 'reformulation':
        return AppTheme.accentLight;
      default:
        return AppTheme.textMuted;
    }
  }

  Color _confidenceColor(String k) {
    switch (k) {
      case 'High confidence':
        return AppTheme.success;
      case 'Moderate confidence':
        return AppTheme.info;
      case 'Low confidence':
        return AppTheme.warning;
      case 'Out of scope':
        return AppTheme.error;
      default:
        return AppTheme.textMuted;
    }
  }

  Color _levelColor(String k) {
    switch (k) {
      case 'beginner':
        return AppTheme.info;
      case 'intermediate':
        return AppTheme.primaryLight;
      case 'advanced':
        return AppTheme.accent;
      default:
        return AppTheme.textMuted;
    }
  }
}
