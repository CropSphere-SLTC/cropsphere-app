// lib/screens/admin/gap_report_screen.dart
// Admin-only Gap Report — visualises chat_analytics aggregates to reveal what
// data users ask for that CropSphere can't answer yet. Native widgets only
// (proportional Container bars) — no charting package.

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import '../../models/admin_models.dart';
import '../../services/admin_service.dart';
import '../../widgets/app_theme.dart';

class GapReportScreen extends StatefulWidget {
  const GapReportScreen({super.key});

  @override
  State<GapReportScreen> createState() => _GapReportScreenState();
}

class _GapReportScreenState extends State<GapReportScreen> {
  final _admin = AdminService();
  int _days = 7;
  bool _loading = true;
  String? _error;
  GapReport? _report;

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
      final report = await _admin.getGapReport(days: _days);
      if (mounted) setState(() => _report = report);
    } catch (e) {
      if (mounted) setState(() => _error = _errorMessage(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _changeDays(int? days) async {
    if (days == null || days == _days) return;
    setState(() => _days = days);
    await _load();
  }

  String _errorMessage(Object e) {
    if (e is DioException) {
      final detail = e.response?.data is Map ? e.response?.data['detail'] : null;
      if (detail is String) return detail;
      if (e.response?.statusCode == 403) return 'Admin access required';
    }
    return 'Failed to load gap report';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: const Text('Gap Report'),
        backgroundColor: AppTheme.primary,
        foregroundColor: Colors.white,
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<int>(
                value: _days,
                dropdownColor: AppTheme.primary,
                iconEnabledColor: Colors.white,
                style: const TextStyle(color: Colors.white, fontSize: 14),
                items: const [
                  DropdownMenuItem(value: 7, child: Text('7 days')),
                  DropdownMenuItem(value: 14, child: Text('14 days')),
                  DropdownMenuItem(value: 30, child: Text('30 days')),
                ],
                onChanged: _loading ? null : _changeDays,
              ),
            ),
          ),
        ],
      ),
      body: _buildBody(),
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
            _buildSessionCard(report),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  // ── Summary cards ─────────────────────────────────────────────────────────
  Widget _buildSummaryCards(GapReport report) {
    final total = report.totalInteractions;
    final answers = report.responseBreakdown['answer'] ?? 0;
    final answerRate = total == 0 ? 0 : (answers / total * 100).round();
    final cards = [
      _SummaryCard(
        label: 'Total interactions',
        value: '$total',
        icon: Icons.chat_bubble_outline,
        color: AppTheme.primary,
      ),
      _SummaryCard(
        label: 'Answer rate',
        value: '$answerRate%',
        icon: Icons.check_circle_outline,
        color: AppTheme.success,
      ),
      _SummaryCard(
        label: 'Avg response time',
        value: _formatMs(report.avgResponseTimeMs),
        icon: Icons.timer_outlined,
        color: AppTheme.info,
      ),
      _SummaryCard(
        label: 'Chip tap rate',
        value: '${(report.chipTapRate * 100).round()}%',
        icon: Icons.touch_app_outlined,
        color: AppTheme.accent,
      ),
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        final perRow = constraints.maxWidth < 600 ? 2 : 4;
        final w = (constraints.maxWidth - (perRow - 1) * 12) / perRow;
        return Wrap(
          spacing: 12,
          runSpacing: 12,
          children: cards.map((c) => SizedBox(width: w, child: c)).toList(),
        );
      },
    );
  }

  // ── Missing crops & districts, side by side ───────────────────────────────
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

  // ── Reusable pieces ───────────────────────────────────────────────────────
  Widget _sectionCard(String title, Widget child) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.bold,
                color: AppTheme.textPrimary,
              ),
            ),
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
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

class _SummaryCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;

  const _SummaryCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color, size: 22),
            const SizedBox(height: 8),
            Text(
              value,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: AppTheme.textPrimary,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: const TextStyle(
                fontSize: 12,
                color: AppTheme.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
