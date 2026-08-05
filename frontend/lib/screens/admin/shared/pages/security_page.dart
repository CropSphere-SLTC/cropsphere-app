// lib/screens/admin/shared/pages/security_page.dart
// Security monitoring — both roles view; superadmin can force-logout a session.
// Stat cards + failed logins / rate violations / banned attempts / active
// sessions tables + a colour-coded combined event timeline.

import 'package:flutter/material.dart';
import '../../../../models/admin_models.dart';
import '../../../../services/admin_service.dart';
import '../../../../services/superadmin_service.dart';
import '../../../../widgets/app_theme.dart';
import '../admin_ui.dart';
import '../widgets/data_table_card.dart';
import '../widgets/search_filter_bar.dart';
import '../widgets/stat_card.dart';

class SecurityPage extends StatefulWidget {
  final String role;

  const SecurityPage({super.key, required this.role});

  @override
  State<SecurityPage> createState() => _SecurityPageState();
}

class _SecurityPageState extends State<SecurityPage> {
  final _admin = AdminService();
  final _superadmin = SuperadminService();

  bool _loading = true;
  bool _refreshing = false;

  SecuritySummary? _summary;
  List<SecurityEvent> _failed = [];
  List<SecurityEvent> _rate = [];
  List<SecurityEvent> _banned = [];
  List<ActiveSession> _sessions = [];

  final Set<String> _busyUids = {};
  String? _timelineType; // null = all

  bool get _isSuper => widget.role == 'superadmin';

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

  Future<void> _fetchAll() async {
    await Future.wait([
      _guard(() async => _summary = await _admin.getSecuritySummary()),
      _guard(() async => _failed = await _admin.getFailedLogins()),
      _guard(() async => _rate = await _admin.getRateViolations()),
      _guard(() async => _banned = await _admin.getBannedAttempts()),
      _guard(() async => _sessions = await _admin.getActiveSessions()),
    ]);
  }

  Future<void> _guard(Future<void> Function() fn) async {
    try {
      await fn();
    } catch (_) {
      // Best-effort per section.
    }
  }

  void _showSnack(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? AppTheme.error : AppTheme.success,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _confirmForceLogout(ActiveSession session) async {
    final who = session.email.isNotEmpty ? session.email : session.uid;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Force logout?'),
        content: Text(
          'This signs $who out of every device and clears their active '
          'sessions. Takes effect within a minute; they can sign in again '
          'afterwards unless you also ban the account.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: AppTheme.error),
            child: const Text('Force Logout'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _busyUids.add(session.uid));
    try {
      await _superadmin.forceLogout(session.uid);
      // The backend clears their session documents, so re-fetch rather than
      // leaving a row that makes the button look like it did nothing.
      await _fetchAll();
      _showSnack('Revoked sessions for $who');
    } catch (e) {
      _showSnack(adminErrorMessage(e), isError: true);
    } finally {
      if (mounted) setState(() => _busyUids.remove(session.uid));
    }
  }

  Color _eventColor(String type) {
    switch (type) {
      case 'failed_login':
        return AppTheme.error;
      case 'rate_limit_violation':
        return AppTheme.warning;
      case 'banned_access_attempt':
        return AppTheme.accent;
      default:
        return AppTheme.textMuted;
    }
  }

  String _eventLabel(String type) {
    switch (type) {
      case 'failed_login':
        return 'Failed login';
      case 'rate_limit_violation':
        return 'Rate limit';
      case 'banned_access_attempt':
        return 'Banned access';
      default:
        return type;
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
            title: 'Security',
            subtitle: _isSuper
                ? 'Monitoring & session control'
                : 'Monitoring (view only)',
            refreshing: _refreshing,
            onRefresh: _refresh,
          ),
          const SizedBox(height: 16),
          _buildStatCards(),
          const SizedBox(height: 20),
          _buildFailedLogins(),
          const SizedBox(height: 20),
          _buildRateViolations(),
          const SizedBox(height: 20),
          _buildBannedAttempts(),
          const SizedBox(height: 20),
          _buildActiveSessions(),
          const SizedBox(height: 20),
          _buildTimeline(),
        ],
      ),
    );
  }

  String _int(int? v) => v?.toString() ?? '—';

  Widget _buildStatCards() {
    final s = _summary;
    return StatCardGrid(
      cards: [
        StatCard(
          label: 'Failed logins (24h)',
          value: _int(s?.failedLogins),
          icon: Icons.gpp_bad_outlined,
          color: AppTheme.error,
        ),
        StatCard(
          label: 'Rate limit hits (24h)',
          value: _int(s?.rateViolations),
          icon: Icons.speed,
          color: AppTheme.warning,
        ),
        StatCard(
          label: 'Banned attempts (24h)',
          value: _int(s?.bannedAttempts),
          icon: Icons.block,
          color: AppTheme.accent,
        ),
        StatCard(
          label: 'Active sessions',
          value: _int(s?.activeSessions),
          icon: Icons.people_alt_outlined,
          color: AppTheme.info,
        ),
      ],
    );
  }

  Widget _section(String title, Widget child) {
    return Column(
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
        const SizedBox(height: 10),
        child,
      ],
    );
  }

  /// Identity cell for a security event. An event the backend could attribute
  /// renders like every other admin table; an identity only *claimed* by a
  /// rejected token is marked in warning colour and spelled out in the
  /// tooltip, so it can never be mistaken for proof that account did anything.
  Widget _eventIdentity(SecurityEvent e) {
    if (e.identityVerified) return adminIdentityCell(e.email, e.uid);
    final claimed = e.claimedEmail.isNotEmpty ? e.claimedEmail : e.claimedUid;
    if (claimed.isEmpty) {
      return Text(
        e.actorLabel,
        style: const TextStyle(color: AppTheme.textMuted),
      );
    }
    return Tooltip(
      message:
          'Claimed by a token that failed signature verification — '
          'not proof this account was involved.\n$claimed',
      child: SizedBox(
        width: 200,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.help_outline, size: 14, color: AppTheme.warning),
            const SizedBox(width: 4),
            Flexible(
              child: Text(
                claimed,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: AppTheme.warning),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFailedLogins() {
    return _section(
      'Failed login attempts',
      DataTableCard(
        emptyMessage: 'No failed logins recorded',
        columns: const [
          DataColumn(label: Text('Timestamp')),
          DataColumn(label: Text('User')),
          DataColumn(label: Text('IP Address')),
          DataColumn(label: Text('Reason')),
        ],
        rows: _failed.map((e) {
          return DataRow(
            cells: [
              DataCell(Text(adminFormatTimestamp(e.timestamp))),
              DataCell(_eventIdentity(e)),
              DataCell(Text(e.ipAddress.isEmpty ? '—' : e.ipAddress)),
              DataCell(Text(e.details['reason']?.toString() ?? '—')),
            ],
          );
        }).toList(),
      ),
    );
  }

  Widget _buildRateViolations() {
    return _section(
      'Rate limit violations',
      DataTableCard(
        emptyMessage: 'No rate limit violations recorded',
        columns: const [
          DataColumn(label: Text('Timestamp')),
          DataColumn(label: Text('User')),
          DataColumn(label: Text('IP Address')),
          DataColumn(label: Text('Endpoint')),
          DataColumn(label: Text('Limit')),
        ],
        rows: _rate.map((e) {
          return DataRow(
            cells: [
              DataCell(Text(adminFormatTimestamp(e.timestamp))),
              // Empty for the global limit, which is enforced before auth —
              // there the IP beside it is the only identity there is.
              DataCell(_eventIdentity(e)),
              DataCell(Text(e.ipAddress.isEmpty ? '—' : e.ipAddress)),
              DataCell(Text(e.endpoint.isEmpty ? '—' : e.endpoint)),
              DataCell(Text(e.details['limit']?.toString() ?? '—')),
            ],
          );
        }).toList(),
      ),
    );
  }

  Widget _buildBannedAttempts() {
    return _section(
      'Banned user access attempts',
      DataTableCard(
        emptyMessage: 'No banned access attempts recorded',
        columns: const [
          DataColumn(label: Text('Timestamp')),
          DataColumn(label: Text('User')),
          DataColumn(label: Text('IP Address')),
          DataColumn(label: Text('Endpoint')),
        ],
        rows: _banned.map((e) {
          return DataRow(
            cells: [
              DataCell(Text(adminFormatTimestamp(e.timestamp))),
              DataCell(_eventIdentity(e)),
              DataCell(Text(e.ipAddress.isEmpty ? '—' : e.ipAddress)),
              DataCell(Text(e.endpoint.isEmpty ? '—' : e.endpoint)),
            ],
          );
        }).toList(),
      ),
    );
  }

  Widget _buildActiveSessions() {
    final columns = <DataColumn>[
      const DataColumn(label: Text('UID')),
      const DataColumn(label: Text('Email')),
      const DataColumn(label: Text('Role')),
      const DataColumn(label: Text('Last Activity')),
      const DataColumn(label: Text('Session Start')),
      if (_isSuper) const DataColumn(label: Text('Actions')),
    ];
    return _section(
      'Active sessions',
      DataTableCard(
        emptyMessage: 'No active sessions',
        columns: columns,
        rows: _sessions.map((s) {
          final busy = _busyUids.contains(s.uid);
          return DataRow(
            cells: [
              DataCell(
                Tooltip(
                  message: s.uid,
                  child: Text(s.uid.isEmpty ? '—' : adminTruncate(s.uid)),
                ),
              ),
              DataCell(Text(s.email.isEmpty ? '—' : s.email)),
              DataCell(
                s.role.isEmpty ? const Text('—') : adminRoleBadge(s.role),
              ),
              DataCell(Text(adminFormatTimestamp(s.lastActivity))),
              DataCell(Text(adminFormatTimestamp(s.sessionStart))),
              if (_isSuper)
                DataCell(
                  TextButton(
                    onPressed: busy ? null : () => _confirmForceLogout(s),
                    style: TextButton.styleFrom(
                      foregroundColor: AppTheme.error,
                    ),
                    child: const Text('Force Logout'),
                  ),
                ),
            ],
          );
        }).toList(),
      ),
    );
  }

  Widget _buildTimeline() {
    final all = <SecurityEvent>[..._failed, ..._rate, ..._banned]
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
    final filtered = _timelineType == null
        ? all
        : all.where((e) => e.type == _timelineType).toList();

    return AdminSectionCard(
      title: 'Security event timeline',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          FilterChipGroup<String?>(
            label: 'EVENT TYPE',
            selected: _timelineType,
            options: const {
              null: 'All',
              'failed_login': 'Failed login',
              'rate_limit_violation': 'Rate limit',
              'banned_access_attempt': 'Banned access',
            },
            onSelected: (v) => setState(() => _timelineType = v),
          ),
          const SizedBox(height: 12),
          if (filtered.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Text(
                'No events for this filter',
                style: TextStyle(color: AppTheme.textMuted),
              ),
            )
          else
            ...filtered.take(50).map(_timelineRow),
        ],
      ),
    );
  }

  Widget _timelineRow(SecurityEvent e) {
    final color = _eventColor(e.type);
    // actorLabel already spells out an unverified claim and distinguishes
    // "no token at all" from "we could not attribute this".
    final who = e.identityVerified && e.email.isEmpty
        ? adminTruncate(e.uid)
        : e.actorLabel;
    final where = e.endpoint.isNotEmpty
        ? ' · ${e.endpoint}'
        : (e.ipAddress.isNotEmpty ? ' · ${e.ipAddress}' : '');
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            margin: const EdgeInsets.only(top: 3),
            width: 9,
            height: 9,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      _eventLabel(e.type),
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: color,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '$who$where',
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppTheme.textSecondary,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                Text(
                  adminFormatTimestamp(e.timestamp),
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppTheme.textMuted,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
