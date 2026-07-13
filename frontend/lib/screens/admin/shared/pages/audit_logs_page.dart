// lib/screens/admin/shared/pages/audit_logs_page.dart
// Admin action audit trail with action-type / date-range / search filters and
// pagination. Admin sees only their own actions (backend restricts to
// admin-level actions; we further filter to this actor); superadmin sees the
// full unfiltered trail via SuperadminService.getFullAuditLogs().

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../../../../models/admin_models.dart';
import '../../../../services/admin_service.dart';
import '../../../../services/superadmin_service.dart';
import '../../../../widgets/app_theme.dart';
import '../admin_ui.dart';
import '../widgets/data_table_card.dart';
import '../widgets/search_filter_bar.dart';

class AuditLogsPage extends StatefulWidget {
  final String role;

  const AuditLogsPage({super.key, required this.role});

  @override
  State<AuditLogsPage> createState() => _AuditLogsPageState();
}

class _AuditLogsPageState extends State<AuditLogsPage> {
  static const _pageSize = 20;

  final _admin = AdminService();
  final _superadmin = SuperadminService();
  final _searchController = TextEditingController();

  bool _loading = true;
  bool _refreshing = false;
  String? _error;
  List<AuditLog> _logs = [];

  String _query = '';
  String? _actionFilter;
  DateTimeRange? _dateRange;
  int _page = 0;

  bool get _isSuper => widget.role == 'superadmin';

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
      final logs = _isSuper
          ? await _superadmin.getFullAuditLogs()
          : await _admin.getAuditLogs();
      if (mounted) {
        setState(() {
          _logs = logs;
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

  List<AuditLog> get _filtered {
    final myUid = FirebaseAuth.instance.currentUser?.uid;
    var list = _isSuper
        ? List<AuditLog>.from(_logs)
        // Admin sees only their own actions.
        : _logs.where((l) => l.actorUid == myUid).toList();

    if (_actionFilter != null) {
      list = list.where((l) => l.action == _actionFilter).toList();
    }
    if (_dateRange != null) {
      list = list.where((l) {
        final dt = DateTime.tryParse(l.timestamp)?.toLocal();
        if (dt == null) return false;
        final day = DateTime(dt.year, dt.month, dt.day);
        return !day.isBefore(_dateRange!.start) && !day.isAfter(_dateRange!.end);
      }).toList();
    }
    if (_query.isNotEmpty) {
      final q = _query.toLowerCase();
      list = list
          .where(
            (l) =>
                l.actorUid.toLowerCase().contains(q) ||
                l.targetUid.toLowerCase().contains(q),
          )
          .toList();
    }
    return list;
  }

  void _resetPage() => _page = 0;

  Future<void> _pickDateRange() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 2),
      lastDate: now,
      initialDateRange: _dateRange,
    );
    if (picked != null) {
      setState(() {
        _dateRange = picked;
        _resetPage();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(color: AppTheme.primary),
      );
    }
    final filtered = _filtered;
    final pageCount = (filtered.length / _pageSize).ceil();
    final safePage = _page.clamp(0, pageCount == 0 ? 0 : pageCount - 1);
    final pageItems = filtered
        .skip(safePage * _pageSize)
        .take(_pageSize)
        .toList();

    return RefreshIndicator(
      color: AppTheme.primary,
      onRefresh: _refresh,
      child: ListView(
        padding: const EdgeInsets.all(16),
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          AdminPageHeader(
            title: 'Audit logs',
            subtitle: _isSuper ? 'All admin actions' : 'Your admin actions',
            refreshing: _refreshing,
            onRefresh: _refresh,
          ),
          const SizedBox(height: 16),
          if (_error != null)
            AdminErrorCard(message: _error!, onRetry: _load)
          else ...[
            _buildFilters(),
            const SizedBox(height: 12),
            DataTableCard(
              emptyMessage: 'No audit logs match the current filters',
              columns: const [
                DataColumn(label: Text('Timestamp')),
                DataColumn(label: Text('Actor UID')),
                DataColumn(label: Text('Actor Role')),
                DataColumn(label: Text('Action')),
                DataColumn(label: Text('Target UID')),
                DataColumn(label: Text('Details')),
              ],
              rows: pageItems.map((log) {
                final detailsText = adminFormatDetails(log.details);
                return DataRow(
                  cells: [
                    DataCell(Text(adminFormatTimestamp(log.timestamp))),
                    DataCell(
                      Tooltip(
                        message: log.actorUid,
                        child: Text(adminTruncate(log.actorUid)),
                      ),
                    ),
                    DataCell(adminRoleBadge(log.actorRole)),
                    DataCell(Text(log.action)),
                    DataCell(
                      Tooltip(
                        message: log.targetUid,
                        child: Text(
                          log.targetUid.isEmpty
                              ? '—'
                              : adminTruncate(log.targetUid),
                        ),
                      ),
                    ),
                    DataCell(
                      Tooltip(
                        message: detailsText,
                        child: SizedBox(
                          width: 180,
                          child: Text(
                            detailsText,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              }).toList(),
            ),
            TablePager(
              page: safePage,
              pageCount: pageCount,
              totalItems: filtered.length,
              onPageChanged: (p) => setState(() => _page = p),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildFilters() {
    return AdminSectionCard(
      child: SearchFilterBar(
        controller: _searchController,
        hintText: 'Search by actor or target UID…',
        onSearchChanged: (v) => setState(() {
          _query = v;
          _resetPage();
        }),
        filters: [
          FilterChipGroup<String?>(
            label: 'ACTION',
            selected: _actionFilter,
            options: const {
              null: 'All',
              'ban_user': 'Ban',
              'unban_user': 'Unban',
              'delete_user': 'Delete',
              'update_role': 'Role',
              'force_logout': 'Force logout',
            },
            onSelected: (v) => setState(() {
              _actionFilter = v;
              _resetPage();
            }),
          ),
          _buildDateRangeControl(),
        ],
      ),
    );
  }

  Widget _buildDateRangeControl() {
    final hasRange = _dateRange != null;
    String label() {
      if (!hasRange) return 'Date range';
      String d(DateTime x) =>
          '${x.year}-${x.month.toString().padLeft(2, '0')}-${x.day.toString().padLeft(2, '0')}';
      return '${d(_dateRange!.start)} → ${d(_dateRange!.end)}';
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'DATE',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: AppTheme.textSecondary,
          ),
        ),
        const SizedBox(height: 4),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            OutlinedButton.icon(
              onPressed: _pickDateRange,
              icon: const Icon(Icons.date_range, size: 16),
              label: Text(label(), style: const TextStyle(fontSize: 12)),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppTheme.primary,
                side: const BorderSide(color: Color(0xFFE0EBE0)),
                padding: const EdgeInsets.symmetric(horizontal: 12),
                visualDensity: VisualDensity.compact,
              ),
            ),
            if (hasRange)
              IconButton(
                tooltip: 'Clear',
                icon: const Icon(Icons.clear, size: 16),
                onPressed: () => setState(() {
                  _dateRange = null;
                  _resetPage();
                }),
              ),
          ],
        ),
      ],
    );
  }
}
