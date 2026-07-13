// lib/screens/super_admin/pages/system_config_page.dart
// Superadmin-only runtime configuration — editable rate limits, a read-only
// Admin API toggle (env-var backed), and a save action.

import 'package:flutter/material.dart';
import '../../../models/admin_models.dart';
import '../../../services/superadmin_service.dart';
import '../../../widgets/app_theme.dart';
import '../../admin/shared/admin_ui.dart';

class SystemConfigPage extends StatefulWidget {
  const SystemConfigPage({super.key});

  @override
  State<SystemConfigPage> createState() => _SystemConfigPageState();
}

class _SystemConfigPageState extends State<SystemConfigPage> {
  final _superadmin = SuperadminService();
  final _adminLimitController = TextEditingController();
  final _superLimitController = TextEditingController();

  bool _loading = true;
  bool _saving = false;
  String? _error;
  SuperadminConfig? _config;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _adminLimitController.dispose();
    _superLimitController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final config = await _superadmin.getConfig();
      if (mounted) {
        setState(() {
          _config = config;
          _adminLimitController.text = '${config.adminRateLimitPerMinute}';
          _superLimitController.text = '${config.superadminRateLimitPerMinute}';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(
          () => _error =
              adminErrorMessage(e, access: 'Superadmin access required'),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
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

  Future<void> _save() async {
    final adminLimit = int.tryParse(_adminLimitController.text.trim());
    final superLimit = int.tryParse(_superLimitController.text.trim());
    if (adminLimit == null || superLimit == null) {
      _showSnack('Rate limits must be whole numbers', isError: true);
      return;
    }
    if (adminLimit < 1 || adminLimit > 1000 || superLimit < 1 || superLimit > 1000) {
      _showSnack('Rate limits must be between 1 and 1000', isError: true);
      return;
    }

    setState(() => _saving = true);
    try {
      final updated = await _superadmin.updateConfig(
        adminRateLimitPerMinute: adminLimit,
        superadminRateLimitPerMinute: superLimit,
      );
      if (mounted) setState(() => _config = updated);
      _showSnack('Configuration saved');
    } catch (e) {
      _showSnack(adminErrorMessage(e), isError: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(color: AppTheme.primary),
      );
    }
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        AdminPageHeader(
          title: 'System config',
          subtitle: 'Runtime rate limits & API toggle',
          onRefresh: _load,
        ),
        const SizedBox(height: 16),
        if (_error != null)
          AdminErrorCard(message: _error!, onRetry: _load)
        else ...[
          _buildRateLimits(),
          const SizedBox(height: 16),
          _buildApiToggle(),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _saving ? null : _save,
              icon: _saving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.save_outlined),
              label: Text(_saving ? 'Saving…' : 'Save configuration'),
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Note: the backend stores these values but does not yet re-target '
            'already-registered routes at runtime (see superadmin_service).',
            style: TextStyle(fontSize: 11, color: AppTheme.textMuted),
          ),
        ],
      ],
    );
  }

  Widget _buildRateLimits() {
    return AdminSectionCard(
      title: 'Rate limits (requests / minute)',
      child: LayoutBuilder(
        builder: (context, constraints) {
          final narrow = constraints.maxWidth < 480;
          final admin = _numberField('Admin', _adminLimitController);
          final sup = _numberField('Superadmin', _superLimitController);
          if (narrow) {
            return Column(
              children: [admin, const SizedBox(height: 12), sup],
            );
          }
          return Row(
            children: [
              Expanded(child: admin),
              const SizedBox(width: 12),
              Expanded(child: sup),
            ],
          );
        },
      ),
    );
  }

  Widget _numberField(String label, TextEditingController controller) {
    return TextField(
      controller: controller,
      keyboardType: TextInputType.number,
      decoration: InputDecoration(
        labelText: label,
        isDense: true,
        suffixText: '/min',
      ),
    );
  }

  Widget _buildApiToggle() {
    final enabled = _config?.enableAdminApi ?? false;
    return AdminSectionCard(
      child: Row(
        children: [
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Admin API',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                ),
                SizedBox(height: 2),
                Text(
                  'Set via ENABLE_ADMIN_API on the server — read only here.',
                  style: TextStyle(fontSize: 11, color: AppTheme.textSecondary),
                ),
              ],
            ),
          ),
          Switch(
            value: enabled,
            activeThumbColor: AppTheme.primary,
            onChanged: null, // env-var backed; not editable from the client
          ),
        ],
      ),
    );
  }
}
