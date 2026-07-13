// lib/screens/admin/shared/widgets/data_table_card.dart
// Reusable horizontally-scrollable DataTable inside a card. Every admin table
// (users, audit logs, prediction logs, security tables) renders through this,
// so the scroll/empty/pagination behaviour lives in one place.

import 'package:flutter/material.dart';
import '../admin_ui.dart';

class DataTableCard extends StatelessWidget {
  final List<DataColumn> columns;
  final List<DataRow> rows;
  final String emptyMessage;
  final int? sortColumnIndex;
  final bool sortAscending;

  const DataTableCard({
    super.key,
    required this.columns,
    required this.rows,
    this.emptyMessage = 'No data',
    this.sortColumnIndex,
    this.sortAscending = true,
  });

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) {
      return AdminEmptyCard(message: emptyMessage);
    }
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.all(8),
        child: DataTable(
          columns: columns,
          rows: rows,
          sortColumnIndex: sortColumnIndex,
          sortAscending: sortAscending,
        ),
      ),
    );
  }
}

/// Prev/next pager shown under a table. Hidden entirely when there is only a
/// single page. `page` is zero-based.
class TablePager extends StatelessWidget {
  final int page;
  final int pageCount;
  final int totalItems;
  final ValueChanged<int> onPageChanged;

  const TablePager({
    super.key,
    required this.page,
    required this.pageCount,
    required this.totalItems,
    required this.onPageChanged,
  });

  @override
  Widget build(BuildContext context) {
    if (pageCount <= 1) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          Text(
            '$totalItems total  •  page ${page + 1} of $pageCount',
            style: const TextStyle(fontSize: 12),
          ),
          IconButton(
            tooltip: 'Previous',
            icon: const Icon(Icons.chevron_left),
            onPressed: page > 0 ? () => onPageChanged(page - 1) : null,
          ),
          IconButton(
            tooltip: 'Next',
            icon: const Icon(Icons.chevron_right),
            onPressed: page < pageCount - 1
                ? () => onPageChanged(page + 1)
                : null,
          ),
        ],
      ),
    );
  }
}
