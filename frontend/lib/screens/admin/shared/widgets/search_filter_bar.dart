// lib/screens/admin/shared/widgets/search_filter_bar.dart
// Reusable search input + filter chip rows. Pages supply their own filter
// widgets (usually FilterChipGroup) via [filters].

import 'package:flutter/material.dart';
import '../../../../widgets/app_theme.dart';

class SearchFilterBar extends StatelessWidget {
  final String hintText;
  final ValueChanged<String> onSearchChanged;
  final TextEditingController controller;

  /// Extra controls (filter chip groups, date-range button, etc.) laid out
  /// below the search field.
  final List<Widget> filters;

  const SearchFilterBar({
    super.key,
    required this.controller,
    required this.onSearchChanged,
    this.hintText = 'Search…',
    this.filters = const [],
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: controller,
          onChanged: onSearchChanged,
          decoration: InputDecoration(
            hintText: hintText,
            prefixIcon: const Icon(Icons.search, size: 20),
            isDense: true,
            suffixIcon: controller.text.isEmpty
                ? null
                : IconButton(
                    icon: const Icon(Icons.clear, size: 18),
                    onPressed: () {
                      controller.clear();
                      onSearchChanged('');
                    },
                  ),
          ),
        ),
        if (filters.isNotEmpty) ...[
          const SizedBox(height: 10),
          Wrap(spacing: 16, runSpacing: 8, children: filters),
        ],
      ],
    );
  }
}

/// A labelled single-select group of choice chips. `T` is the option value;
/// pass a null option (via a sentinel key) for an "All" choice in the map.
class FilterChipGroup<T> extends StatelessWidget {
  final String label;
  final T selected;
  final Map<T, String> options;
  final ValueChanged<T> onSelected;

  const FilterChipGroup({
    super.key,
    required this.label,
    required this.selected,
    required this.options,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: AppTheme.textSecondary,
          ),
        ),
        const SizedBox(height: 4),
        Wrap(
          spacing: 6,
          children: options.entries.map((e) {
            final isSelected = e.key == selected;
            return ChoiceChip(
              label: Text(e.value),
              selected: isSelected,
              onSelected: (_) => onSelected(e.key),
              labelStyle: TextStyle(
                fontSize: 12,
                color: isSelected ? AppTheme.primary : AppTheme.textSecondary,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
              ),
              selectedColor: AppTheme.primary.withValues(alpha: 0.12),
              backgroundColor: AppTheme.background,
              side: BorderSide(
                color: isSelected
                    ? AppTheme.primary.withValues(alpha: 0.4)
                    : const Color(0xFFE0EBE0),
              ),
              visualDensity: VisualDensity.compact,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            );
          }).toList(),
        ),
      ],
    );
  }
}
