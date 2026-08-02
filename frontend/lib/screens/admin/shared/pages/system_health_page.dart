// lib/screens/admin/shared/pages/system_health_page.dart
// Detailed server metrics — CPU, RAM, model status, and requests by endpoint.
// Both roles. Data source: AdminService.getStats().

import 'package:flutter/material.dart';
import '../../../../models/admin_models.dart';
import '../../../../services/admin_service.dart';
import '../../../../widgets/app_theme.dart';
import '../admin_ui.dart';
import '../widgets/data_table_card.dart';
import '../widgets/model_status.dart';

class SystemHealthPage extends StatefulWidget {
  const SystemHealthPage({super.key});

  @override
  State<SystemHealthPage> createState() => _SystemHealthPageState();
}

class _SystemHealthPageState extends State<SystemHealthPage> {
  final _admin = AdminService();
  bool _loading = true;
  bool _refreshing = false;
  String? _error;
  AdminStats? _stats;

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
    await _fetch();
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _refresh() async {
    if (_refreshing) return;
    setState(() => _refreshing = true);
    await _fetch();
    if (mounted) setState(() => _refreshing = false);
  }

  Future<void> _fetch() async {
    try {
      final stats = await _admin.getStats();
      if (mounted) {
        setState(() {
          _stats = stats;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = adminErrorMessage(e));
    }
  }

  Color _cpuColor(double pct) {
    if (pct >= 80) return AppTheme.error;
    if (pct >= 60) return AppTheme.warning;
    return AppTheme.success;
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
            title: 'System health',
            subtitle: 'Live server metrics & model status',
            refreshing: _refreshing,
            onRefresh: _refresh,
          ),
          const SizedBox(height: 16),
          if (_error != null)
            AdminErrorCard(message: _error!, onRetry: _load)
          else ...[
            _buildResourceRow(),
            const SizedBox(height: 16),
            AdminSectionCard(
              title: 'Model status',
              child: ModelStatusGrid(models: _stats!.modelsLoaded),
            ),
            const SizedBox(height: 16),
            _buildEndpointsTable(),
          ],
        ],
      ),
    );
  }

  Widget _buildResourceRow() {
    final stats = _stats!;
    final cpuColor = _cpuColor(stats.cpuPercent);
    return LayoutBuilder(
      builder: (context, constraints) {
        final narrow = constraints.maxWidth < 600;
        final cpu = _cpuCard(stats, cpuColor);
        final ram = _ramCard(stats);
        if (narrow) {
          return Column(children: [cpu, const SizedBox(height: 12), ram]);
        }
        // IntrinsicHeight is load-bearing, not cosmetic. This row is a child
        // of the page's ListView, so it is laid out with an UNBOUNDED height,
        // and CrossAxisAlignment.stretch sizes children with
        // BoxConstraints.tightFor(height: constraints.maxHeight) — infinity
        // here, which throws "BoxConstraints forces an infinite height" and
        // renders the whole page blank. IntrinsicHeight gives the row a real
        // height (the taller of the two cards) so stretch still does what it
        // is here for: equal-height CPU and RAM cards.
        return IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: cpu),
              const SizedBox(width: 12),
              Expanded(child: ram),
            ],
          ),
        );
      },
    );
  }

  Widget _cpuCard(AdminStats stats, Color color) {
    return AdminSectionCard(
      title: 'CPU usage',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                '${stats.cpuPercent.toStringAsFixed(1)}%',
                style: TextStyle(
                  fontSize: 30,
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: (stats.cpuPercent / 100).clamp(0.0, 1.0),
              minHeight: 10,
              backgroundColor: AppTheme.background,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _ramCard(AdminStats stats) {
    final color = _cpuColor(stats.ramPercent);
    return AdminSectionCard(
      title: 'RAM usage',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${stats.ramUsedGb.toStringAsFixed(1)} / '
            '${stats.ramTotalGb.toStringAsFixed(1)} GB',
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: AppTheme.textPrimary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '${stats.ramPercent.toStringAsFixed(1)}% used',
            style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary),
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: (stats.ramPercent / 100).clamp(0.0, 1.0),
              minHeight: 10,
              backgroundColor: AppTheme.background,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEndpointsTable() {
    final stats = _stats!;
    final counts = stats.requestsByEndpoint.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    // The server bounds this breakdown to the most recent N audit logs, so say
    // so — otherwise the numbers read as all-time and quietly disagree with the
    // exact "total requests" figure on the dashboard.
    final sampled = stats.requestsSampled;
    final subtitle = sampled > 0 && sampled < stats.totalRequests
        ? 'From the last $sampled requests of ${stats.totalRequests} total'
        : null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Requests by endpoint',
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.bold,
            color: AppTheme.textPrimary,
          ),
        ),
        if (subtitle != null) ...[
          const SizedBox(height: 2),
          Text(
            subtitle,
            style: const TextStyle(
              fontSize: 12,
              color: AppTheme.textSecondary,
            ),
          ),
        ],
        const SizedBox(height: 10),
        DataTableCard(
          emptyMessage: 'No requests recorded yet',
          columns: const [
            DataColumn(label: Text('Endpoint')),
            DataColumn(label: Text('Requests'), numeric: true),
          ],
          rows: counts
              .map(
                (e) => DataRow(
                  cells: [DataCell(Text(e.key)), DataCell(Text('${e.value}'))],
                ),
              )
              .toList(),
        ),
      ],
    );
  }
}
