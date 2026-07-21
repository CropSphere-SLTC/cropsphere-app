// lib/screens/super_admin/pages/maintenance_page.dart
// Superadmin-only maintenance — session cleanup plus a visually distinct
// "dangerous actions" area with double confirmation, and disabled future
// placeholders.

import 'package:flutter/material.dart';
import '../../../services/superadmin_service.dart';
import '../../../widgets/app_theme.dart';
import '../../admin/shared/admin_ui.dart';

class MaintenancePage extends StatefulWidget {
  const MaintenancePage({super.key});

  @override
  State<MaintenancePage> createState() => _MaintenancePageState();
}

class _MaintenancePageState extends State<MaintenancePage> {
  final _superadmin = SuperadminService();
  bool _cleaning = false;

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

  Future<void> _confirmCleanup() async {
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

    setState(() => _cleaning = true);
    try {
      final result = await _superadmin.cleanupOldSessions();
      _showSnack('Deleted ${result['deleted'] ?? 0} old session(s)');
    } catch (e) {
      _showSnack(adminErrorMessage(e), isError: true);
    } finally {
      if (mounted) setState(() => _cleaning = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const AdminPageHeader(
          title: 'Maintenance',
          subtitle: 'Housekeeping & dangerous actions',
        ),
        const SizedBox(height: 16),
        _buildSessionCleanup(),
        const SizedBox(height: 20),
        _buildDangerZone(),
        const SizedBox(height: 20),
        _buildFuturePlaceholders(),
      ],
    );
  }

  Widget _buildSessionCleanup() {
    return AdminSectionCard(
      title: 'Session cleanup',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Remove session records older than 30 days to keep the sessions '
            'collection lean.',
            style: TextStyle(fontSize: 13, color: AppTheme.textSecondary),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _cleaning ? null : _confirmCleanup,
              style: OutlinedButton.styleFrom(
                foregroundColor: AppTheme.primary,
                side: const BorderSide(color: AppTheme.primary),
              ),
              icon: _cleaning
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppTheme.primary,
                      ),
                    )
                  : const Icon(Icons.cleaning_services_outlined),
              label: Text(_cleaning ? 'Cleaning up…' : 'Clean Old Sessions'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDangerZone() {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.error.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.error.withValues(alpha: 0.4)),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: const [
              Icon(
                Icons.warning_amber_rounded,
                color: AppTheme.error,
                size: 20,
              ),
              SizedBox(width: 8),
              Text(
                'Dangerous actions',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.error,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            'These operations are irreversible and require an extra confirmation.',
            style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: () => _doubleConfirm(
              title: 'Purge ALL old sessions',
              body:
                  'This performs the session cleanup immediately after a second '
                  'confirmation. Continue?',
              onConfirmed: _confirmCleanup,
            ),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppTheme.error,
              side: const BorderSide(color: AppTheme.error),
            ),
            icon: const Icon(Icons.delete_sweep_outlined),
            label: const Text('Purge old sessions now'),
          ),
        ],
      ),
    );
  }

  // First confirmation here; the invoked action shows its own second dialog.
  Future<void> _doubleConfirm({
    required String title,
    required String body,
    required Future<void> Function() onConfirmed,
  }) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: AppTheme.error),
            child: const Text('Continue'),
          ),
        ],
      ),
    );
    if (ok == true) await onConfirmed();
  }

  Widget _buildFuturePlaceholders() {
    return AdminSectionCard(
      title: 'Coming soon',
      child: Column(
        children: [
          _placeholder(Icons.refresh, 'Force model reload'),
          const Divider(height: 20),
          _placeholder(Icons.download_outlined, 'Export audit logs (CSV)'),
        ],
      ),
    );
  }

  Widget _placeholder(IconData icon, String label) {
    return Opacity(
      opacity: 0.5,
      child: Row(
        children: [
          Icon(icon, size: 20, color: AppTheme.textMuted),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 14,
                color: AppTheme.textSecondary,
              ),
            ),
          ),
          const Text(
            'Soon',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: AppTheme.textMuted,
            ),
          ),
        ],
      ),
    );
  }
}
