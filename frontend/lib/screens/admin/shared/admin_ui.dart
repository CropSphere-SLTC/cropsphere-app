// lib/screens/admin/shared/admin_ui.dart
// Shared formatting helpers, badges, and small cards used across every admin
// page. This is the single home for logic that was previously duplicated
// between admin_dashboard_screen.dart and superadmin_dashboard_screen.dart.

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import '../../../widgets/app_theme.dart';

// ── Role theming ──────────────────────────────────────────────────────────────

/// Header/sidebar gradient per role: green for admin, red for superadmin —
/// matching the existing dashboards' colour scheme.
LinearGradient adminRoleGradient(String role) {
  final colors = role == 'superadmin'
      ? const [Color(0xFF7B1616), Color(0xFFC62828)]
      : const [Color(0xFF1B5E20), Color(0xFF4CAF50)];
  return LinearGradient(
    colors: colors,
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
}

Color adminRoleColor(String role) {
  switch (role) {
    case 'superadmin':
      return AppTheme.error;
    case 'admin':
      return AppTheme.primary;
    default:
      return AppTheme.textSecondary;
  }
}

Widget adminRoleBadge(String role) {
  final color = adminRoleColor(role);
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(6),
    ),
    child: Text(
      role,
      style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w700),
    ),
  );
}

Widget adminStatusBadge(bool banned) {
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      color: banned ? AppTheme.error : AppTheme.success,
      borderRadius: BorderRadius.circular(6),
    ),
    child: Text(
      banned ? 'Banned' : 'Active',
      style: const TextStyle(
        color: Colors.white,
        fontSize: 12,
        fontWeight: FontWeight.w700,
      ),
    ),
  );
}

// ── Formatters ────────────────────────────────────────────────────────────────

String adminTruncate(String id) =>
    id.length <= 10 ? id : '${id.substring(0, 8)}…';

String adminTruncateHash(String hash) =>
    hash.length <= 12 ? hash : hash.substring(0, 12);

String adminFormatDetails(Map<String, dynamic> details) {
  if (details.isEmpty) return '—';
  return details.entries.map((e) => '${e.key}: ${e.value}').join(', ');
}

String adminFormatTimestamp(String iso) {
  final dt = DateTime.tryParse(iso);
  if (dt == null) return iso.isEmpty ? '—' : iso;
  final local = dt.toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${local.year}-${two(local.month)}-${two(local.day)} '
      '${two(local.hour)}:${two(local.minute)}';
}

/// Relative time for notification cards ("just now", "2 hours ago",
/// "yesterday"). Falls back to the absolute date beyond a week.
String adminTimeAgo(String? iso) {
  if (iso == null || iso.isEmpty) return '';
  final dt = DateTime.tryParse(iso);
  if (dt == null) return '';
  final diff = DateTime.now().difference(dt.toLocal());
  if (diff.isNegative || diff.inSeconds < 60) return 'just now';
  if (diff.inMinutes < 60) {
    final m = diff.inMinutes;
    return '$m minute${m == 1 ? '' : 's'} ago';
  }
  if (diff.inHours < 24) {
    final h = diff.inHours;
    return '$h hour${h == 1 ? '' : 's'} ago';
  }
  if (diff.inDays == 1) return 'yesterday';
  if (diff.inDays < 7) return '${diff.inDays} days ago';
  return adminFormatTimestamp(iso);
}

/// Maps a thrown error to a user-facing message, matching the existing
/// dashboards' behaviour (surfaces the backend's `detail`, 403 → access msg).
String adminErrorMessage(Object e, {String access = 'Admin access required'}) {
  if (e is DioException) {
    final detail = e.response?.data is Map ? e.response?.data['detail'] : null;
    if (detail is String) return detail;
    if (e.response?.statusCode == 403) return access;
  }
  return 'Failed to load data';
}

// ── Small shared widgets ──────────────────────────────────────────────────────

/// A titled card container — the `elevation: 2`, `borderRadius: 12` shell that
/// wraps most page sections.
class AdminSectionCard extends StatelessWidget {
  final String? title;
  final Widget child;
  final Widget? trailing;
  final EdgeInsets padding;

  const AdminSectionCard({
    super.key,
    this.title,
    required this.child,
    this.trailing,
    this.padding = const EdgeInsets.all(16),
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: padding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (title != null) ...[
              Row(
                children: [
                  Expanded(
                    child: Text(
                      title!,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                  ),
                  ?trailing,
                ],
              ),
              const SizedBox(height: 12),
            ],
            child,
          ],
        ),
      ),
    );
  }
}

/// A page title row with an optional subtitle and a refresh button. Every page
/// uses this so the loading affordance is consistent.
class AdminPageHeader extends StatelessWidget {
  final String title;
  final String? subtitle;
  final bool refreshing;
  final VoidCallback? onRefresh;
  final List<Widget> actions;

  const AdminPageHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.refreshing = false,
    this.onRefresh,
    this.actions = const [],
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.textPrimary,
                ),
              ),
              if (subtitle != null) ...[
                const SizedBox(height: 2),
                Text(
                  subtitle!,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppTheme.textSecondary,
                  ),
                ),
              ],
            ],
          ),
        ),
        ...actions,
        if (onRefresh != null)
          refreshing
              ? const Padding(
                  padding: EdgeInsets.all(12),
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AppTheme.primary,
                    ),
                  ),
                )
              : IconButton(
                  tooltip: 'Refresh',
                  icon: const Icon(Icons.refresh, color: AppTheme.primary),
                  onPressed: onRefresh,
                ),
      ],
    );
  }
}

class AdminErrorCard extends StatelessWidget {
  final String message;
  final VoidCallback? onRetry;

  const AdminErrorCard({super.key, required this.message, this.onRetry});

  @override
  Widget build(BuildContext context) {
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
          if (onRetry != null)
            TextButton(
              onPressed: onRetry,
              style: TextButton.styleFrom(foregroundColor: AppTheme.error),
              child: const Text('Retry'),
            ),
        ],
      ),
    );
  }
}

class AdminEmptyCard extends StatelessWidget {
  final String message;
  final IconData icon;

  const AdminEmptyCard({
    super.key,
    required this.message,
    this.icon = Icons.inbox_outlined,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: AppTheme.textMuted, size: 36),
              const SizedBox(height: 8),
              Text(
                message,
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppTheme.textSecondary),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
