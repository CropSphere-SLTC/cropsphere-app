// lib/screens/admin/shared/pages/prediction_logs_page.dart
// ML prediction audit logs with endpoint / date-range / user-id filters and
// pagination. Both roles. Data source: AdminService.getPredictionLogs()
// (records store an input hash, never raw input).

import 'package:flutter/material.dart';
import '../../../../services/admin_service.dart';
import '../../../../widgets/app_theme.dart';
import '../admin_ui.dart';
import '../widgets/data_table_card.dart';
import '../widgets/search_filter_bar.dart';

class PredictionLogsPage extends StatefulWidget {
  const PredictionLogsPage({super.key});

  @override
  State<PredictionLogsPage> createState() => _PredictionLogsPageState();
}

class _PredictionLogsPageState extends State<PredictionLogsPage> {
  static const _pageSize = 20;

  final _admin = AdminService();
  final _searchController = TextEditingController();

  bool _loading = true;
  bool _refreshing = false;
  String? _error;
  List<Map<String, dynamic>> _logs = [];

  String _query = '';
  String? _endpointFilter;
  DateTimeRange? _dateRange;
  int _page = 0;

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
      final logs = await _admin.getPredictionLogs();
      if (mounted) {
        setState(() {
          _logs = logs;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = adminErrorMessage(e));
    }
  }

  String _s(Map<String, dynamic> m, String k) => m[k]?.toString() ?? '';

  List<Map<String, dynamic>> get _filtered {
    var list = List<Map<String, dynamic>>.from(_logs);
    if (_endpointFilter != null) {
      list = list
          .where(
            (l) => _s(l, 'endpoint').toLowerCase().contains(_endpointFilter!),
          )
          .toList();
    }
    if (_dateRange != null) {
      list = list.where((l) {
        final dt = DateTime.tryParse(_s(l, 'timestamp'))?.toLocal();
        if (dt == null) return false;
        final day = DateTime(dt.year, dt.month, dt.day);
        return !day.isBefore(_dateRange!.start) &&
            !day.isAfter(_dateRange!.end);
      }).toList();
    }
    if (_query.isNotEmpty) {
      final q = _query.toLowerCase();
      list = list
          .where((l) => _s(l, 'user_id').toLowerCase().contains(q))
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
            title: 'Prediction logs',
            subtitle: 'ML request audit trail (hashed inputs)',
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
              emptyMessage: 'No prediction logs match the current filters',
              columns: const [
                DataColumn(label: Text('Timestamp')),
                DataColumn(label: Text('User ID')),
                DataColumn(label: Text('Endpoint')),
                DataColumn(label: Text('Input Hash')),
              ],
              rows: pageItems.map((log) {
                final inputHash = _s(log, 'input_hash');
                return DataRow(
                  cells: [
                    DataCell(Text(adminFormatTimestamp(_s(log, 'timestamp')))),
                    DataCell(Text(_s(log, 'user_id'))),
                    DataCell(Text(_s(log, 'endpoint'))),
                    DataCell(
                      Tooltip(
                        message: inputHash,
                        child: Text(adminTruncateHash(inputHash)),
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
        hintText: 'Search by user ID…',
        onSearchChanged: (v) => setState(() {
          _query = v;
          _resetPage();
        }),
        filters: [
          FilterChipGroup<String?>(
            label: 'ENDPOINT',
            selected: _endpointFilter,
            options: const {
              null: 'All',
              'yield': 'Yield',
              'price': 'Price',
              'weather': 'Weather',
              'demand': 'Demand',
              'recommend': 'Recommend',
              'chat': 'Chat',
            },
            onSelected: (v) => setState(() {
              _endpointFilter = v;
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
