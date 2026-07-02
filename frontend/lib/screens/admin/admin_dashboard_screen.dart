// lib/screens/admin/admin_dashboard_screen.dart

import 'package:dio/dio.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../../models/admin_models.dart';
import '../../services/admin_service.dart';
import '../../services/session_service.dart';
import '../../widgets/app_theme.dart';

class AdminDashboardScreen extends StatefulWidget {
  const AdminDashboardScreen({super.key});

  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen> {
  final _admin = AdminService();

  bool _loading = true;
  bool _headerRefreshing = false;
  AdminStats? _stats;
  List<AdminUser> _users = [];
  List<AuditLog> _logs = [];

  String? _statsError;
  String? _usersError;
  String? _logsError;

  // uids currently mid-action — disables their row controls
  final Set<String> _busyUids = {};

  static const _roles = ['user', 'admin', 'superadmin'];

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  Future<void> _loadAll() async {
    setState(() => _loading = true);
    await Future.wait([_loadStats(), _loadUsers(), _loadLogs()]);
    if (mounted) setState(() => _loading = false);
  }

  // Header refresh button — reloads all 4 sections without blanking the
  // whole screen (unlike _loadAll, which drives the pull-to-refresh spinner).
  Future<void> _refreshAll() async {
    if (_headerRefreshing) return;
    setState(() => _headerRefreshing = true);
    await Future.wait([_loadStats(), _loadUsers(), _loadLogs()]);
    if (mounted) setState(() => _headerRefreshing = false);
  }

  // Current user's role, derived from the already-loaded user list rather
  // than a separate call — AdminService.checkAdminAccess() only returns
  // whether the caller is an admin, not which admin tier they hold.
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

    // SessionService.logout() is the app's shared sign-out path (also used
    // for inactivity timeout) — it stops the timer and calls signOut().
    // main.dart's root StreamBuilder listens to authStateChanges and swaps
    // to LoginScreen automatically, so no manual navigation is needed here.
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

  Future<void> _loadLogs() async {
    try {
      final logs = await _admin.getAuditLogs();
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

  String _errorMessage(Object e) {
    if (e is DioException) {
      final detail = e.response?.data is Map
          ? e.response?.data['detail']
          : null;
      if (detail is String) return detail;
      if (e.response?.statusCode == 403) return 'Admin access required';
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
      _showSnack(nextBanned ? '${user.email} banned' : '${user.email} unbanned');
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

  String _truncate(String id) => id.length <= 10 ? id : '${id.substring(0, 8)}…';

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
            ? const Center(child: CircularProgressIndicator(color: AppTheme.primary))
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
                    _sectionTitle('User Management (${_users.length})'),
                    const SizedBox(height: 10),
                    if (_usersError != null)
                      _buildErrorCard(_usersError!)
                    else
                      _buildUsersTable(),
                    const SizedBox(height: 24),
                    _sectionTitle('Audit Logs'),
                    const SizedBox(height: 10),
                    if (_logsError != null)
                      _buildErrorCard(_logsError!)
                    else
                      _buildAuditLogsTable(),
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
        gradient: const LinearGradient(
          colors: [Color(0xFF1B5E20), Color(0xFF4CAF50)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          const Icon(Icons.admin_panel_settings, color: Colors.white, size: 32),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Flexible(
                      child: Text(
                        'Admin Dashboard',
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
                  'System stats, users & audit trail',
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
        final cardWidth =
            (constraints.maxWidth - (perRow - 1) * 12) / perRow;
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

  // ── Section 3: User management table ──────────────────────────────────────
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
            DataColumn(label: Text('UID')),
            DataColumn(label: Text('Email')),
            DataColumn(label: Text('Role')),
            DataColumn(label: Text('Banned')),
            DataColumn(label: Text('Actions')),
          ],
          rows: _users.map((user) {
            final busy = _busyUids.contains(user.uid);
            return DataRow(
              cells: [
                DataCell(
                  Tooltip(message: user.uid, child: Text(_truncate(user.uid))),
                ),
                DataCell(Text(user.email)),
                DataCell(
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
                ),
                DataCell(
                  Icon(
                    user.isBanned ? Icons.block : Icons.check_circle_outline,
                    color: user.isBanned ? AppTheme.error : AppTheme.success,
                    size: 20,
                  ),
                ),
                DataCell(
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      DropdownButton<String>(
                        value: user.role,
                        underline: const SizedBox.shrink(),
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
                      IconButton(
                        tooltip: user.isBanned ? 'Unban' : 'Ban',
                        icon: Icon(
                          user.isBanned
                              ? Icons.lock_open
                              : Icons.block,
                          size: 20,
                          color: user.isBanned
                              ? AppTheme.success
                              : AppTheme.warning,
                        ),
                        onPressed: busy ? null : () => _toggleBan(user),
                      ),
                      IconButton(
                        tooltip: 'Delete',
                        icon: const Icon(
                          Icons.delete_outline,
                          size: 20,
                          color: AppTheme.error,
                        ),
                        onPressed: busy ? null : () => _confirmDelete(user),
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

  // ── Section 4: Audit logs table ───────────────────────────────────────────
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
          ],
          rows: _logs.map((log) {
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
