// lib/screens/super_admin/superadmin_dashboard_screen.dart
//
// Full-access counterpart to AdminDashboardScreen. Shows everything the
// admin screen shows, unfiltered, plus session cleanup and a system
// configuration panel. See AdminDashboardScreen for the restricted view.

import 'package:dio/dio.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../../models/admin_models.dart';
import '../../services/admin_service.dart';
import '../../services/session_service.dart';
import '../../services/superadmin_service.dart';
import '../../widgets/app_theme.dart';

class SuperadminDashboardScreen extends StatefulWidget {
  const SuperadminDashboardScreen({super.key});

  @override
  State<SuperadminDashboardScreen> createState() =>
      _SuperadminDashboardScreenState();
}

class _SuperadminDashboardScreenState extends State<SuperadminDashboardScreen>
    with SingleTickerProviderStateMixin {
  final _admin = AdminService();
  final _superadmin = SuperadminService();

  bool _loading = true;
  bool _headerRefreshing = false;
  bool _cleaningUpSessions = false;

  AdminStats? _stats;
  List<AdminUser> _users = [];
  List<AuditLog> _logs = [];
  List<Map<String, dynamic>> _predictionLogs = [];
  SuperadminConfig? _config;

  String? _statsError;
  String? _usersError;
  String? _logsError;
  String? _predictionLogsError;
  String? _configError;

  late final TabController _logsTabController;

  // uids currently mid-action — disables their row controls
  final Set<String> _busyUids = {};

  // Full role range — unlike AdminDashboardScreen, superadmin is a valid
  // target here.
  static const _roles = ['user', 'admin', 'superadmin'];

  @override
  void initState() {
    super.initState();
    _logsTabController = TabController(length: 2, vsync: this)
      ..addListener(() {
        if (!_logsTabController.indexIsChanging) setState(() {});
      });
    _loadAll();
  }

  @override
  void dispose() {
    _logsTabController.dispose();
    super.dispose();
  }

  Future<void> _loadAll() async {
    setState(() => _loading = true);
    await Future.wait([
      _loadStats(),
      _loadUsers(),
      _loadLogs(),
      _loadPredictionLogs(),
      _loadConfig(),
    ]);
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _refreshAll() async {
    if (_headerRefreshing) return;
    setState(() => _headerRefreshing = true);
    await Future.wait([
      _loadStats(),
      _loadUsers(),
      _loadLogs(),
      _loadPredictionLogs(),
      _loadConfig(),
    ]);
    if (mounted) setState(() => _headerRefreshing = false);
  }

  String? get _myRole {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return null;
    for (final u in _users) {
      if (u.uid == uid) return u.role;
    }
    return null;
  }

  Future<void> _confirmLogout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Logout'),
        content: const Text('Are you sure you want to logout?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: AppTheme.error),
            child: const Text('Logout'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await SessionService.logout();
  }

  Future<void> _loadStats() async {
    try {
      final stats = await _admin.getStats();
      if (mounted) {
        setState(() {
          _stats = stats;
          _statsError = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _statsError = _errorMessage(e));
    }
  }

  Future<void> _loadUsers() async {
    try {
      final users = await _admin.getUsers();
      if (mounted) {
        setState(() {
          _users = users;
          _usersError = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _usersError = _errorMessage(e));
    }
  }

  // Unfiltered — GET /api/superadmin/audit-logs, unlike the admin screen's
  // GET /api/admin/audit-logs (which the backend itself filters).
  Future<void> _loadLogs() async {
    try {
      final logs = await _superadmin.getFullAuditLogs();
      if (mounted) {
        setState(() {
          _logs = logs;
          _logsError = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _logsError = _errorMessage(e));
    }
  }

  Future<void> _loadPredictionLogs() async {
    try {
      final logs = await _admin.getPredictionLogs();
      if (mounted) {
        setState(() {
          _predictionLogs = logs;
          _predictionLogsError = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _predictionLogsError = _errorMessage(e));
    }
  }

  Future<void> _loadConfig() async {
    try {
      final config = await _superadmin.getConfig();
      if (mounted) {
        setState(() {
          _config = config;
          _configError = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _configError = _errorMessage(e));
    }
  }

  String _errorMessage(Object e) {
    if (e is DioException) {
      final detail = e.response?.data is Map
          ? e.response?.data['detail']
          : null;
      if (detail is String) return detail;
      if (e.response?.statusCode == 403) return 'Superadmin access required';
    }
    return 'Failed to load data';
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

  Future<void> _changeRole(AdminUser user, String role) async {
    if (role == user.role) return;
    setState(() => _busyUids.add(user.uid));
    try {
      await _admin.updateUserRole(user.uid, role);
      _showSnack('${user.email} role updated to $role');
      await _loadUsers();
    } catch (e) {
      _showSnack(_errorMessage(e), isError: true);
    } finally {
      if (mounted) setState(() => _busyUids.remove(user.uid));
    }
  }

  Future<void> _toggleBan(AdminUser user) async {
    final nextBanned = !user.isBanned;
    setState(() => _busyUids.add(user.uid));
    try {
      await _admin.setUserBanned(user.uid, nextBanned);
      _showSnack(
        nextBanned ? '${user.email} banned' : '${user.email} unbanned',
      );
      await _loadUsers();
    } catch (e) {
      _showSnack(_errorMessage(e), isError: true);
    } finally {
      if (mounted) setState(() => _busyUids.remove(user.uid));
    }
  }

  Future<void> _confirmDelete(AdminUser user) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete user?'),
        content: Text(
          'This will permanently delete ${user.email}. This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: AppTheme.error),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _busyUids.add(user.uid));
    try {
      await _admin.deleteUser(user.uid);
      _showSnack('${user.email} deleted');
      await _loadUsers();
    } catch (e) {
      _showSnack(_errorMessage(e), isError: true);
    } finally {
      if (mounted) setState(() => _busyUids.remove(user.uid));
    }
  }

  Future<void> _confirmCleanupSessions() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clean up old sessions?'),
        content: const Text(
          'This permanently deletes session records older than 30 days. '
          'This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: AppTheme.error),
            child: const Text('Clean Up'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _cleaningUpSessions = true);
    try {
      final result = await _superadmin.cleanupOldSessions();
      _showSnack('Deleted ${result['deleted'] ?? 0} old session(s)');
    } catch (e) {
      _showSnack(_errorMessage(e), isError: true);
    } finally {
      if (mounted) setState(() => _cleaningUpSessions = false);
    }
  }

  String _truncate(String id) =>
      id.length <= 10 ? id : '${id.substring(0, 8)}…';

  String _truncateHash(String hash) =>
      hash.length <= 12 ? hash : hash.substring(0, 12);

  String _formatDetails(Map<String, dynamic> details) {
    if (details.isEmpty) return '—';
    return details.entries.map((e) => '${e.key}: ${e.value}').join(', ');
  }

  String _formatTimestamp(String iso) {
    final dt = DateTime.tryParse(iso);
    if (dt == null) return iso;
    final local = dt.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${local.year}-${two(local.month)}-${two(local.day)} '
        '${two(local.hour)}:${two(local.minute)}';
  }

  Color _roleColor(String role) {
    switch (role) {
      case 'superadmin':
        return AppTheme.error;
      case 'admin':
        return AppTheme.primary;
      default:
        return AppTheme.textSecondary;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      body: RefreshIndicator(
        color: AppTheme.primary,
        onRefresh: _loadAll,
        child: _loading
            ? const Center(
                child: CircularProgressIndicator(color: AppTheme.primary),
              )
            : SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildHeader(),
                    const SizedBox(height: 20),
                    if (_statsError != null)
                      _buildErrorCard(_statsError!)
                    else ...[
                      _buildStatsRow(),
                      const SizedBox(height: 20),
                      _buildModelGrid(),
                    ],
                    const SizedBox(height: 24),
                    _sectionTitle('System Configuration'),
                    const SizedBox(height: 10),
                    if (_configError != null)
                      _buildErrorCard(_configError!)
                    else
                      _buildConfigSection(),
                    const SizedBox(height: 24),
                    _sectionTitle('User Management (${_users.length})'),
                    const SizedBox(height: 10),
                    if (_usersError != null)
                      _buildErrorCard(_usersError!)
                    else
                      _buildUsersTable(),
                    const SizedBox(height: 24),
                    _sectionTitle('Logs'),
                    const SizedBox(height: 10),
                    _buildLogsTabBar(),
                    const SizedBox(height: 10),
                    _logsTabController.index == 0
                        ? (_logsError != null
                              ? _buildErrorCard(_logsError!)
                              : _buildAuditLogsTable())
                        : (_predictionLogsError != null
                              ? _buildErrorCard(_predictionLogsError!)
                              : _buildPredictionLogsTable()),
                    const SizedBox(height: 20),
                  ],
                ),
              ),
      ),
    );
  }

  Widget _buildHeader() {
    final role = _myRole;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        // Deep red gradient — visually distinct from AdminDashboardScreen's
        // green, matching the red used for the superadmin role badge
        // elsewhere in the app.
        gradient: const LinearGradient(
          colors: [Color(0xFF7B1616), Color(0xFFC62828)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.admin_panel_settings,
            color: Colors.white,
            size: 32,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Flexible(
                      child: Text(
                        'Superadmin Dashboard',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (role != null) ...[
                      const SizedBox(width: 8),
                      _buildRoleBadge(role),
                    ],
                  ],
                ),
                const Text(
                  'Full system access — users, logs & configuration',
                  style: TextStyle(color: Colors.white70, fontSize: 12),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Logout',
            icon: const Icon(Icons.logout, color: Colors.white),
            onPressed: _confirmLogout,
          ),
          _headerRefreshing
              ? const Padding(
                  padding: EdgeInsets.all(12),
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  ),
                )
              : IconButton(
                  tooltip: 'Refresh',
                  icon: const Icon(Icons.refresh, color: Colors.white),
                  onPressed: _refreshAll,
                ),
        ],
      ),
    );
  }

  Widget _buildRoleBadge(String role) {
    final color = role == 'superadmin' ? AppTheme.success : AppTheme.info;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        role.toUpperCase(),
        style: const TextStyle(
          color: Colors.white,
          fontSize: 10,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.3,
        ),
      ),
    );
  }

  Widget _sectionTitle(String title) {
    return Text(
      title,
      style: const TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.bold,
        color: AppTheme.textPrimary,
      ),
    );
  }

  // ── Section 1: Stats cards ────────────────────────────────────────────────
  Widget _buildStatsRow() {
    final stats = _stats;
    if (stats == null) return const SizedBox.shrink();
    final loadedCount = stats.modelsLoaded.values.where((v) => v).length;
    final totalModels = stats.modelsLoaded.length;

    final cards = [
      _StatCard(
        label: 'CPU',
        value: '${stats.cpuPercent.toStringAsFixed(1)}%',
        icon: Icons.memory,
        color: AppTheme.info,
      ),
      _StatCard(
        label: 'RAM',
        value:
            '${stats.ramUsedGb.toStringAsFixed(1)} / ${stats.ramTotalGb.toStringAsFixed(1)} GB',
        icon: Icons.sd_storage,
        color: AppTheme.warning,
      ),
      _StatCard(
        label: 'Total Requests',
        value: '${stats.totalRequests}',
        icon: Icons.swap_horiz,
        color: AppTheme.primary,
      ),
      _StatCard(
        label: 'Models Loaded',
        value: '$loadedCount / $totalModels',
        icon: Icons.model_training,
        color: AppTheme.success,
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final perRow = constraints.maxWidth < 600 ? 2 : 4;
        final cardWidth = (constraints.maxWidth - (perRow - 1) * 12) / perRow;
        return Wrap(
          spacing: 12,
          runSpacing: 12,
          children: cards
              .map((c) => SizedBox(width: cardWidth, child: c))
              .toList(),
        );
      },
    );
  }

  // ── Section 2: Model status grid ──────────────────────────────────────────
  Widget _buildModelGrid() {
    final stats = _stats;
    if (stats == null) return const SizedBox.shrink();
    final entries = stats.modelsLoaded.entries.toList();

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Model Status',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            LayoutBuilder(
              builder: (context, constraints) {
                final perRow = constraints.maxWidth < 500
                    ? 1
                    : constraints.maxWidth < 800
                    ? 2
                    : 3;
                final itemWidth =
                    (constraints.maxWidth - (perRow - 1) * 10) / perRow;
                return Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: entries.map((e) {
                    final loaded = e.value;
                    return SizedBox(
                      width: itemWidth,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: (loaded ? AppTheme.success : AppTheme.error)
                              .withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: (loaded ? AppTheme.success : AppTheme.error)
                                .withValues(alpha: 0.3),
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              loaded ? Icons.check_circle : Icons.cancel,
                              color: loaded ? AppTheme.success : AppTheme.error,
                              size: 18,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                e.key,
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }).toList(),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  // ── Section: System configuration ─────────────────────────────────────────
  Widget _buildConfigSection() {
    final config = _config;
    if (config == null) return const SizedBox.shrink();

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Rate Limits',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _configStat(
                    'Admin',
                    '${config.adminRateLimitPerMinute}/min',
                  ),
                ),
                Expanded(
                  child: _configStat(
                    'Superadmin',
                    '${config.superadminRateLimitPerMinute}/min',
                  ),
                ),
              ],
            ),
            const Divider(height: 28),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Admin API',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Set via ENABLE_ADMIN_API on the server — not '
                        'editable from here yet',
                        style: TextStyle(
                          fontSize: 11,
                          color: AppTheme.textSecondary.withValues(
                            alpha: 0.9,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Switch(
                  value: config.enableAdminApi,
                  activeThumbColor: AppTheme.primary,
                  // Read-only — the backend's PATCH /api/superadmin/config
                  // doesn't accept this field (it's env-var-backed), so
                  // there's nothing to wire this up to yet.
                  onChanged: null,
                ),
              ],
            ),
            const Divider(height: 28),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _cleaningUpSessions ? null : _confirmCleanupSessions,
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppTheme.error,
                  side: const BorderSide(color: AppTheme.error),
                ),
                icon: _cleaningUpSessions
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AppTheme.error,
                        ),
                      )
                    : const Icon(Icons.cleaning_services_outlined),
                label: Text(
                  _cleaningUpSessions
                      ? 'Cleaning up...'
                      : 'Clean Old Sessions',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _configStat(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          value,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: AppTheme.textPrimary,
          ),
        ),
        Text(
          label,
          style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary),
        ),
      ],
    );
  }

  // ── Section: User management table (full, unfiltered) ────────────────────
  Widget _buildUsersTable() {
    if (_users.isEmpty) {
      return _buildEmptyCard('No users found');
    }
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.all(8),
        child: DataTable(
          columns: const [
            DataColumn(label: Text('No.')),
            DataColumn(label: Text('UID')),
            DataColumn(label: Text('Email')),
            DataColumn(label: Text('Role')),
            DataColumn(label: Text('Status')),
            DataColumn(label: Text('Actions')),
          ],
          rows: _users.asMap().entries.map((entry) {
            final rowNumber = entry.key + 1;
            final user = entry.value;
            final busy = _busyUids.contains(user.uid);
            return DataRow(
              cells: [
                DataCell(Text('$rowNumber')),
                DataCell(
                  Tooltip(message: user.uid, child: Text(_truncate(user.uid))),
                ),
                DataCell(Text(user.email)),
                DataCell(
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: _roleColor(user.role).withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          user.role,
                          style: TextStyle(
                            color: _roleColor(user.role),
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      DropdownButton<String>(
                        value: user.role,
                        underline: const SizedBox.shrink(),
                        isDense: true,
                        items: _roles
                            .map(
                              (r) =>
                                  DropdownMenuItem(value: r, child: Text(r)),
                            )
                            .toList(),
                        onChanged: busy
                            ? null
                            : (r) {
                                if (r != null) _changeRole(user, r);
                              },
                      ),
                    ],
                  ),
                ),
                DataCell(
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: user.isBanned ? AppTheme.error : AppTheme.success,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      user.isBanned ? 'Banned' : 'Active',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
                DataCell(
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextButton(
                        onPressed: busy ? null : () => _toggleBan(user),
                        style: TextButton.styleFrom(
                          foregroundColor: user.isBanned
                              ? AppTheme.success
                              : AppTheme.warning,
                        ),
                        child: Text(user.isBanned ? 'Unban' : 'Ban'),
                      ),
                      TextButton(
                        onPressed: busy ? null : () => _confirmDelete(user),
                        style: TextButton.styleFrom(
                          foregroundColor: AppTheme.error,
                        ),
                        child: const Text('Delete'),
                      ),
                    ],
                  ),
                ),
              ],
            );
          }).toList(),
        ),
      ),
    );
  }

  // ── Section: Logs (tabbed) ────────────────────────────────────────────────
  Widget _buildLogsTabBar() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE0EBE0)),
      ),
      child: TabBar(
        controller: _logsTabController,
        labelColor: AppTheme.primary,
        unselectedLabelColor: AppTheme.textSecondary,
        indicatorColor: AppTheme.primary,
        tabs: const [
          Tab(text: 'All Actions'),
          Tab(text: 'Prediction Logs'),
        ],
      ),
    );
  }

  // Tab 1 — ALL admin actions, from GET /api/superadmin/audit-logs (unfiltered)
  Widget _buildAuditLogsTable() {
    if (_logs.isEmpty) {
      return _buildEmptyCard('No audit logs found');
    }
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.all(8),
        child: DataTable(
          columns: const [
            DataColumn(label: Text('Timestamp')),
            DataColumn(label: Text('Actor UID')),
            DataColumn(label: Text('Actor Role')),
            DataColumn(label: Text('Action')),
            DataColumn(label: Text('Target UID')),
            DataColumn(label: Text('Details')),
          ],
          rows: _logs.map((log) {
            final detailsText = _formatDetails(log.details);
            return DataRow(
              cells: [
                DataCell(Text(_formatTimestamp(log.timestamp))),
                DataCell(
                  Tooltip(
                    message: log.actorUid,
                    child: Text(_truncate(log.actorUid)),
                  ),
                ),
                DataCell(
                  Text(
                    log.actorRole,
                    style: TextStyle(
                      color: _roleColor(log.actorRole),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                DataCell(Text(log.action)),
                DataCell(
                  Tooltip(
                    message: log.targetUid,
                    child: Text(
                      log.targetUid.isEmpty ? '—' : _truncate(log.targetUid),
                    ),
                  ),
                ),
                DataCell(
                  Tooltip(
                    message: detailsText,
                    child: SizedBox(
                      width: 180,
                      child: Text(detailsText, overflow: TextOverflow.ellipsis),
                    ),
                  ),
                ),
              ],
            );
          }).toList(),
        ),
      ),
    );
  }

  // Tab 2 — prediction logs, from GET /api/admin/prediction-logs
  Widget _buildPredictionLogsTable() {
    if (_predictionLogs.isEmpty) {
      return _buildEmptyCard('No prediction logs found');
    }
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.all(8),
        child: DataTable(
          columns: const [
            DataColumn(label: Text('Timestamp')),
            DataColumn(label: Text('User ID')),
            DataColumn(label: Text('Endpoint')),
            DataColumn(label: Text('Input Hash')),
          ],
          rows: _predictionLogs.map((log) {
            final timestamp = log['timestamp']?.toString() ?? '';
            final userId = log['user_id']?.toString() ?? '';
            final endpoint = log['endpoint']?.toString() ?? '';
            final inputHash = log['input_hash']?.toString() ?? '';
            return DataRow(
              cells: [
                DataCell(Text(_formatTimestamp(timestamp))),
                DataCell(Text(userId)),
                DataCell(Text(endpoint)),
                DataCell(
                  Tooltip(
                    message: inputHash,
                    child: Text(_truncateHash(inputHash)),
                  ),
                ),
              ],
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildEmptyCard(String message) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: Text(
            message,
            style: const TextStyle(color: AppTheme.textSecondary),
          ),
        ),
      ),
    );
  }

  Widget _buildErrorCard(String message) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.error.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppTheme.error.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline, color: AppTheme.error),
          const SizedBox(width: 8),
          Expanded(
            child: Text(message, style: const TextStyle(color: AppTheme.error)),
          ),
        ],
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;

  const _StatCard({
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
