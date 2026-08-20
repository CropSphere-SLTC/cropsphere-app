// lib/screens/admin/shared/pages/user_management_page.dart
// User table with search, role/status filters, sortable columns, and
// role-gated actions. Admin sees only regular users (dropdown user↔admin);
// superadmin sees everyone (dropdown user↔admin↔superadmin). All destructive
// actions confirm first; the backend enforces the real safeguards.

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../../../../models/admin_models.dart';
import '../../../../services/admin_service.dart';
import '../../../../widgets/app_theme.dart';
import '../../../../widgets/skeleton_loading.dart';
import '../admin_ui.dart';
import '../widgets/data_table_card.dart';
import '../widgets/search_filter_bar.dart';

class UserManagementPage extends StatefulWidget {
  final String role; // 'admin' | 'superadmin'

  const UserManagementPage({super.key, required this.role});

  @override
  State<UserManagementPage> createState() => _UserManagementPageState();
}

class _UserManagementPageState extends State<UserManagementPage> {
  final _admin = AdminService();
  final _searchController = TextEditingController();

  bool _loading = true;
  bool _refreshing = false;
  String? _error;
  List<AdminUser> _users = [];

  final Set<String> _busyUids = {};

  String _query = '';
  String? _roleFilter; // null = all
  String _statusFilter = 'all'; // all | active | banned
  int? _sortColIndex;
  bool _sortAsc = true;

  bool get _isSuper => widget.role == 'superadmin';

  List<String> get _roleOptions => _isSuper
      ? const ['user', 'admin', 'superadmin']
      : const ['user', 'admin'];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
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
      final users = await _admin.getUsers();
      if (mounted) {
        setState(() {
          _users = users;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(
          () => _error = adminErrorMessage(
            e,
            access: _isSuper
                ? 'Superadmin access required'
                : 'Admin access required',
          ),
        );
      }
    }
  }

  // Admin only manages regular users; superadmin manages everyone.
  List<AdminUser> get _filteredUsers {
    var list = _isSuper
        ? List<AdminUser>.from(_users)
        : _users.where((u) => u.role == 'user').toList();

    if (_roleFilter != null) {
      list = list.where((u) => u.role == _roleFilter).toList();
    }
    if (_statusFilter == 'active') {
      list = list.where((u) => !u.isBanned).toList();
    } else if (_statusFilter == 'banned') {
      list = list.where((u) => u.isBanned).toList();
    }
    if (_query.isNotEmpty) {
      final q = _query.toLowerCase();
      list = list
          .where(
            (u) =>
                u.email.toLowerCase().contains(q) ||
                u.uid.toLowerCase().contains(q),
          )
          .toList();
    }
    if (_sortColIndex != null) {
      list.sort((a, b) {
        final cmp = _sortColIndex == 2
            ? a.email.toLowerCase().compareTo(b.email.toLowerCase())
            : a.role.compareTo(b.role);
        return _sortAsc ? cmp : -cmp;
      });
    }
    return list;
  }

  void _onSort(int colIndex, bool asc) {
    setState(() {
      _sortColIndex = colIndex;
      _sortAsc = asc;
    });
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
      await _fetch();
    } catch (e) {
      _showSnack(adminErrorMessage(e), isError: true);
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
      await _fetch();
    } catch (e) {
      _showSnack(adminErrorMessage(e), isError: true);
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
          'This will permanently delete ${user.email}. '
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
      await _fetch();
    } catch (e) {
      _showSnack(adminErrorMessage(e), isError: true);
    } finally {
      if (mounted) setState(() => _busyUids.remove(user.uid));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: AdminTableSkeleton(
          rowCount: 8,
          cellCount: 3,
          showFilterBar: true,
        ),
      );
    }
    final users = _filteredUsers;
    return RefreshIndicator(
      color: AppTheme.primary,
      onRefresh: _refresh,
      child: ListView(
        padding: const EdgeInsets.all(16),
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          AdminPageHeader(
            title: 'Users',
            subtitle: _isSuper
                ? 'All accounts (${users.length})'
                : 'Regular users (${users.length})',
            refreshing: _refreshing,
            onRefresh: _refresh,
          ),
          const SizedBox(height: 16),
          if (_error != null)
            AdminErrorCard(message: _error!, onRetry: _load)
          else ...[
            _buildFilters(),
            const SizedBox(height: 12),
            _buildTable(users),
          ],
        ],
      ),
    );
  }

  Widget _buildFilters() {
    final roleChipOptions = <String?, String>{null: 'All'};
    for (final r in _roleOptions) {
      roleChipOptions[r] = r[0].toUpperCase() + r.substring(1);
    }
    return AdminSectionCard(
      child: SearchFilterBar(
        controller: _searchController,
        hintText: 'Search by email or UID…',
        onSearchChanged: (v) => setState(() => _query = v),
        filters: [
          FilterChipGroup<String?>(
            label: 'ROLE',
            selected: _roleFilter,
            options: roleChipOptions,
            onSelected: (v) => setState(() => _roleFilter = v),
          ),
          FilterChipGroup<String>(
            label: 'STATUS',
            selected: _statusFilter,
            options: const {
              'all': 'All',
              'active': 'Active',
              'banned': 'Banned',
            },
            onSelected: (v) => setState(() => _statusFilter = v),
          ),
        ],
      ),
    );
  }

  Widget _buildTable(List<AdminUser> users) {
    final myUid = FirebaseAuth.instance.currentUser?.uid;
    return DataTableCard(
      emptyMessage: 'No users match the current filters',
      sortColumnIndex: _sortColIndex,
      sortAscending: _sortAsc,
      columns: [
        const DataColumn(label: Text('No.')),
        const DataColumn(label: Text('UID')),
        DataColumn(label: const Text('Email'), onSort: _onSort),
        DataColumn(label: const Text('Role'), onSort: _onSort),
        const DataColumn(label: Text('Status')),
        const DataColumn(label: Text('Actions')),
      ],
      rows: users.asMap().entries.map((entry) {
        final rowNumber = entry.key + 1;
        final user = entry.value;
        final busy = _busyUids.contains(user.uid);
        final isSelf = user.uid == myUid;
        return DataRow(
          cells: [
            DataCell(Text('$rowNumber')),
            DataCell(
              Tooltip(message: user.uid, child: Text(adminTruncate(user.uid))),
            ),
            DataCell(Text(user.email)),
            DataCell(_roleCell(user, busy, isSelf)),
            DataCell(adminStatusBadge(user.isBanned)),
            DataCell(_actionsCell(user, busy, isSelf)),
          ],
        );
      }).toList(),
    );
  }

  Widget _roleCell(AdminUser user, bool busy, bool isSelf) {
    // Value must always exist in the dropdown item set.
    final options = _roleOptions.contains(user.role)
        ? _roleOptions
        : [user.role, ..._roleOptions];
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        adminRoleBadge(user.role),
        const SizedBox(width: 6),
        DropdownButton<String>(
          value: user.role,
          underline: const SizedBox.shrink(),
          isDense: true,
          // Cannot change your own role (also enforced by the backend).
          onChanged: (busy || isSelf)
              ? null
              : (r) {
                  if (r != null) _changeRole(user, r);
                },
          items: options
              .map((r) => DropdownMenuItem(value: r, child: Text(r)))
              .toList(),
        ),
      ],
    );
  }

  Widget _actionsCell(AdminUser user, bool busy, bool isSelf) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        TextButton(
          onPressed: (busy || isSelf) ? null : () => _toggleBan(user),
          style: TextButton.styleFrom(
            foregroundColor: user.isBanned
                ? AppTheme.success
                : AppTheme.warning,
          ),
          child: Text(user.isBanned ? 'Unban' : 'Ban'),
        ),
        TextButton(
          onPressed: (busy || isSelf) ? null : () => _confirmDelete(user),
          style: TextButton.styleFrom(foregroundColor: AppTheme.error),
          child: const Text('Delete'),
        ),
      ],
    );
  }
}
