// lib/screens/super_admin/pages/system_config_page.dart
// Superadmin-only runtime configuration — editable rate limits, a read-only
// Admin API toggle (env-var backed), the prompt-tuning lifecycle settings, and
// save actions.
//
// The two config blocks are backed by different endpoints and saved
// separately: rate limits are in-memory server-side, while the prompt-tuning
// values are persisted to Firestore because running trials depend on them
// across restarts.

import 'package:flutter/material.dart';
import '../../../models/admin_models.dart';
import '../../../services/superadmin_service.dart';
import '../../../widgets/app_theme.dart';
import '../../../widgets/skeleton_loading.dart';
import '../../admin/shared/admin_ui.dart';

class SystemConfigPage extends StatefulWidget {
  const SystemConfigPage({super.key});

  @override
  State<SystemConfigPage> createState() => _SystemConfigPageState();
}

/// One editable prompt-tuning setting: its controller and the inclusive bounds
/// the backend enforces, kept together so the client can reject a bad value
/// before the request instead of surfacing a 422.
class _TuningField {
  final String label;
  final String help;
  final int min;
  final int max;
  final TextEditingController controller = TextEditingController();

  _TuningField(this.label, this.help, this.min, this.max);
}

class _SystemConfigPageState extends State<SystemConfigPage> {
  final _superadmin = SuperadminService();
  final _adminLimitController = TextEditingController();
  final _superLimitController = TextEditingController();

  // Bounds mirror system_config_service._BOUNDS on the backend.
  final _minSample = _TuningField(
    'Min sample size',
    'Interactions needed before a trial can be judged',
    1,
    10000,
  );
  final _trialPeriod = _TuningField(
    'Trial period',
    'Days a new adjustment runs before validation',
    1,
    90,
  );
  final _trialExtension = _TuningField(
    'Trial extension',
    'Days added when there is too little data (max 2 times)',
    1,
    30,
  );
  final _trashRetention = _TuningField(
    'Trash retention',
    'Days a removed adjustment stays restorable',
    1,
    365,
  );

  late final List<_TuningField> _tuningFields = [
    _minSample,
    _trialPeriod,
    _trialExtension,
    _trashRetention,
  ];

  bool _loading = true;
  bool _saving = false;
  bool _savingTuning = false;
  String? _error;
  SuperadminConfig? _config;
  PromptTuningConfig? _tuningConfig;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _adminLimitController.dispose();
    _superLimitController.dispose();
    for (final f in _tuningFields) {
      f.controller.dispose();
    }
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
          () => _error = adminErrorMessage(
            e,
            access: 'Superadmin access required',
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
    // Loaded separately so a prompt-tuning failure never blanks the rate-limit
    // section (and vice versa) — they're independent endpoints.
    await _loadTuningConfig();
  }

  Future<void> _loadTuningConfig() async {
    try {
      final config = await _superadmin.getPromptTuningConfig();
      if (!mounted) return;
      setState(() {
        _tuningConfig = config;
        _minSample.controller.text = '${config.minSampleSize}';
        _trialPeriod.controller.text = '${config.trialPeriodDays}';
        _trialExtension.controller.text = '${config.trialExtensionDays}';
        _trashRetention.controller.text = '${config.trashRetentionDays}';
      });
    } catch (_) {
      // Section renders its own unavailable state.
      if (mounted) setState(() => _tuningConfig = null);
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
    if (adminLimit < 1 ||
        adminLimit > 1000 ||
        superLimit < 1 ||
        superLimit > 1000) {
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

  Future<void> _saveTuning() async {
    // Validate every field before sending, so one bad value doesn't half-apply
    // the section (PATCH would accept the others).
    final values = <_TuningField, int>{};
    for (final f in _tuningFields) {
      final parsed = int.tryParse(f.controller.text.trim());
      if (parsed == null) {
        _showSnack('${f.label} must be a whole number', isError: true);
        return;
      }
      if (parsed < f.min || parsed > f.max) {
        _showSnack(
          '${f.label} must be between ${f.min} and ${f.max}',
          isError: true,
        );
        return;
      }
      values[f] = parsed;
    }

    setState(() => _savingTuning = true);
    try {
      final updated = await _superadmin.updatePromptTuningConfig(
        minSampleSize: values[_minSample],
        trialPeriodDays: values[_trialPeriod],
        trialExtensionDays: values[_trialExtension],
        trashRetentionDays: values[_trashRetention],
      );
      if (mounted) setState(() => _tuningConfig = updated);
      _showSnack('Prompt tuning settings saved');
    } catch (e) {
      _showSnack(adminErrorMessage(e), isError: true);
    } finally {
      if (mounted) setState(() => _savingTuning = false);
    }
  }

  /// Outline pattern — a toggle/number-field-heavy settings form on a
  /// single fast doc fetch; a bordered-only placeholder per field is
  /// low-emphasis enough not to overstate how long this actually takes.
  Widget _buildSkeleton() {
    Widget field() => const Padding(
      padding: EdgeInsets.only(bottom: 12),
      child: OutlineSkeletonBox(height: 44),
    );
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const OutlineSkeletonBox(width: 160, height: 22),
        const SizedBox(height: 20),
        field(),
        field(),
        const SizedBox(height: 8),
        const OutlineSkeletonBox(height: 60),
        const SizedBox(height: 20),
        field(),
        field(),
        field(),
        field(),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return _buildSkeleton();
    }
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        AdminPageHeader(
          title: 'System config',
          subtitle: 'Runtime rate limits, API toggle & prompt tuning',
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
              label: Text(_saving ? 'Saving…' : 'Save rate limits'),
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Note: the backend stores these values but does not yet re-target '
            'already-registered routes at runtime (see superadmin_service).',
            style: TextStyle(fontSize: 11, color: AppTheme.textMuted),
          ),
          const SizedBox(height: 24),
          _buildPromptTuningSettings(),
        ],
      ],
    );
  }

  // ── Prompt tuning lifecycle settings ───────────────────────────────────────

  Widget _buildPromptTuningSettings() {
    if (_tuningConfig == null) {
      return AdminSectionCard(
        title: 'Prompt tuning',
        child: Row(
          children: [
            const Expanded(
              child: Text(
                'Could not load prompt-tuning settings.',
                style: TextStyle(fontSize: 13, color: AppTheme.textSecondary),
              ),
            ),
            TextButton(
              onPressed: _loadTuningConfig,
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }
    return AdminSectionCard(
      title: 'Prompt tuning lifecycle',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Controls how long an applied adjustment is trialled before the '
            'system promotes or removes it, and how long removed adjustments '
            'stay restorable. Changes apply to trials started from now on.',
            style: TextStyle(fontSize: 13, color: AppTheme.textSecondary),
          ),
          const SizedBox(height: 14),
          LayoutBuilder(
            builder: (context, constraints) {
              final narrow = constraints.maxWidth < 480;
              final fields = _tuningFields.map(_tuningNumberField).toList();
              if (narrow) {
                return Column(
                  children: [
                    for (var i = 0; i < fields.length; i++) ...[
                      if (i > 0) const SizedBox(height: 12),
                      fields[i],
                    ],
                  ],
                );
              }
              return Column(
                children: [
                  Row(
                    children: [
                      Expanded(child: fields[0]),
                      const SizedBox(width: 12),
                      Expanded(child: fields[1]),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(child: fields[2]),
                      const SizedBox(width: 12),
                      Expanded(child: fields[3]),
                    ],
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _savingTuning ? null : _saveTuning,
              icon: _savingTuning
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.save_outlined),
              label: Text(
                _savingTuning ? 'Saving…' : 'Save prompt tuning settings',
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _tuningNumberField(_TuningField field) {
    final isDays = field.label != 'Min sample size';
    return TextField(
      controller: field.controller,
      keyboardType: TextInputType.number,
      decoration: InputDecoration(
        labelText: field.label,
        helperText: field.help,
        helperMaxLines: 2,
        isDense: true,
        suffixText: isDays ? 'days' : null,
      ),
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
            return Column(children: [admin, const SizedBox(height: 12), sup]);
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
