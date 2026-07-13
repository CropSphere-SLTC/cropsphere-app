// lib/screens/admin/shared/pages/dashboard_page.dart
// Summary overview — a quick glance, not detail. Both roles. Stat cards, a
// tappable CPU/RAM mini-indicator, model pills, recent audit activity, and a
// security-alerts summary — each drilling into its detail page via onNavigate.

import 'package:flutter/material.dart';
import '../../../../models/admin_models.dart';
import '../../../../services/admin_service.dart';
import '../../../../widgets/app_theme.dart';
import '../admin_ui.dart';
import '../widgets/admin_sidebar.dart';
import '../widgets/model_status.dart';
import '../widgets/stat_card.dart';

class DashboardPage extends StatefulWidget {
  final String role;
  final ValueChanged<AdminPage> onNavigate;

  const DashboardPage({
    super.key,
    required this.role,
    required this.onNavigate,
  });

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  final _admin = AdminService();

  bool _loading = true;
  bool _refreshing = false;

  AdminStats? _stats;
  List<AdminUser>? _users;
  List<AuditLog>? _logs;
  SecuritySummary? _summary;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    await _fetchAll();
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _refresh() async {
    if (_refreshing) return;
    setState(() => _refreshing = true);
    await _fetchAll();
    if (mounted) setState(() => _refreshing = false);
  }

  // Each source is guarded independently — a single failing endpoint leaves
  // the rest of the glance intact rather than blanking the page.
  Future<void> _fetchAll() async {
    await Future.wait([
      _guard(() async => _stats = await _admin.getStats()),
      _guard(() async => _users = await _admin.getUsers()),
      _guard(() async => _logs = await _admin.getAuditLogs()),
      _guard(() async => _summary = await _admin.getSecuritySummary()),
    ]);
  }

  Future<void> _guard(Future<void> Function() fn) async {
    try {
      await fn();
    } catch (_) {
      // Best-effort — the corresponding widget shows a placeholder.
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(color: AppTheme.primary),
      );
    }
    return RefreshIndicator(
      color: AppTheme.primary,
      onRefresh: _refresh,
      child: ListView(
        padding: const EdgeInsets.all(16),
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          AdminPageHeader(
            title: 'Dashboard',
            subtitle: 'System overview',
            refreshing: _refreshing,
            onRefresh: _refresh,
          ),
          const SizedBox(height: 16),
          _buildStatCards(),
          const SizedBox(height: 16),
          _buildServerAndPills(),
          const SizedBox(height: 16),
          _buildSecurityAlerts(),
          const SizedBox(height: 16),
          _buildRecentActivity(),
        ],
      ),
    );
  }

  String _int(int? v) => v?.toString() ?? '—';

  Widget _buildStatCards() {
    final users = _users;
    final banned = users?.where((u) => u.isBanned).length;
    return StatCardGrid(
      cards: [
        StatCard(
          label: 'Total users',
          value: _int(users?.length),
          icon: Icons.people_outline,
          color: AppTheme.primary,
          onTap: () => widget.onNavigate(AdminPage.users),
        ),
        StatCard(
          label: 'Active (24h)',
          value: _int(_summary?.activeSessions),
          icon: Icons.bolt_outlined,
          color: AppTheme.info,
        ),
        StatCard(
          label: 'Banned users',
          value: _int(banned),
          icon: Icons.block,
          color: AppTheme.error,
          onTap: () => widget.onNavigate(AdminPage.users),
        ),
        StatCard(
          label: 'Total predictions',
          value: _int(_stats?.totalRequests),
          icon: Icons.model_training,
          color: AppTheme.success,
          onTap: () => widget.onNavigate(AdminPage.predictionLogs),
        ),
      ],
    );
  }

  Widget _buildServerAndPills() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final narrow = constraints.maxWidth < 700;
        final server = _buildServerCard();
        final pills = _buildModelPillsCard();
        if (narrow) {
          return Column(
            children: [server, const SizedBox(height: 12), pills],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(width: 240, child: server),
            const SizedBox(width: 12),
            Expanded(child: pills),
          ],
        );
      },
    );
  }

  Widget _buildServerCard() {
    final stats = _stats;
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => widget.onNavigate(AdminPage.systemHealth),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Server',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                  ),
                  const Icon(
                    Icons.chevron_right,
                    size: 18,
                    color: AppTheme.textMuted,
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _miniMetric('CPU', stats?.cpuPercent),
              const SizedBox(height: 10),
              _miniMetric('RAM', stats?.ramPercent),
            ],
          ),
        ),
      ),
    );
  }

  Widget _miniMetric(String label, double? pct) {
    final value = pct ?? 0;
    final color = value >= 80
        ? AppTheme.error
        : value >= 60
        ? AppTheme.warning
        : AppTheme.success;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              label,
              style: const TextStyle(
                fontSize: 12,
                color: AppTheme.textSecondary,
              ),
            ),
            Text(
              pct == null ? '—' : '${value.toStringAsFixed(0)}%',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: color,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: (value / 100).clamp(0.0, 1.0),
            minHeight: 6,
            backgroundColor: AppTheme.background,
            color: color,
          ),
        ),
      ],
    );
  }

  Widget _buildModelPillsCard() {
    final models = _stats?.modelsLoaded;
    return AdminSectionCard(
      title: 'Model status',
      child: models == null || models.isEmpty
          ? const Text(
              'Unavailable',
              style: TextStyle(color: AppTheme.textMuted),
            )
          : ModelStatusPills(models: models),
    );
  }

  Widget _buildSecurityAlerts() {
    final summary = _summary;
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => widget.onNavigate(AdminPage.security),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppTheme.warning.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.shield_outlined,
                  color: AppTheme.warning,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Security alerts (24h)',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      summary == null
                          ? 'Unavailable'
                          : '${summary.failedLogins} failed logins  •  '
                                '${summary.rateViolations} rate-limit hits',
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: AppTheme.textMuted),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRecentActivity() {
    final logs = _logs ?? [];
    final recent = logs.take(5).toList();
    return AdminSectionCard(
      title: 'Recent activity',
      trailing: TextButton(
        onPressed: () => widget.onNavigate(AdminPage.auditLogs),
        child: const Text('View all'),
      ),
      child: recent.isEmpty
          ? const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Text(
                'No recent admin actions',
                style: TextStyle(color: AppTheme.textMuted),
              ),
            )
          : Column(
              children: recent.map((log) {
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.chevron_right,
                        size: 16,
                        color: AppTheme.textMuted,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          log.action,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      if (log.targetUid.isNotEmpty) ...[
                        Text(
                          adminTruncate(log.targetUid),
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppTheme.textSecondary,
                          ),
                        ),
                        const SizedBox(width: 10),
                      ],
                      Text(
                        adminFormatTimestamp(log.timestamp),
                        style: const TextStyle(
                          fontSize: 11,
                          color: AppTheme.textMuted,
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
    );
  }
}
