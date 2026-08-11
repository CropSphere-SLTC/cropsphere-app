// lib/screens/admin/shared/widgets/email_alerts_card.dart
// A self-contained "Email Alerts" toggle card for the admin dashboard. Loads
// the admin's current email-notification preference and persists changes on
// toggle. Both admin and superadmin see it — email alerts are per-admin.
//
// Backend: GET/PATCH /api/admin/email-preferences.

import 'package:flutter/material.dart';
import '../../../../services/admin_service.dart';
import '../../../../widgets/app_theme.dart';
import '../admin_ui.dart';

class EmailAlertsCard extends StatefulWidget {
  const EmailAlertsCard({super.key});

  @override
  State<EmailAlertsCard> createState() => _EmailAlertsCardState();
}

class _EmailAlertsCardState extends State<EmailAlertsCard> {
  final _admin = AdminService();

  bool _loading = true;
  bool _saving = false;
  bool? _enabled; // null while loading or if the load failed

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final value = await _admin.getEmailPreference();
      if (mounted) setState(() => _enabled = value);
    } catch (_) {
      // Leave the switch disabled if we couldn't read the preference.
      if (mounted) setState(() => _enabled = null);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _toggle(bool value) async {
    final previous = _enabled;
    // Optimistic — flip immediately, roll back if the save fails.
    setState(() {
      _enabled = value;
      _saving = true;
    });
    try {
      final saved = await _admin.setEmailPreference(value);
      if (mounted) setState(() => _enabled = saved);
    } catch (e) {
      if (mounted) setState(() => _enabled = previous);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(adminErrorMessage(e)),
            backgroundColor: AppTheme.error,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AdminSectionCard(
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppTheme.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(
              Icons.mark_email_unread_outlined,
              color: AppTheme.primary,
            ),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Email Alerts',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
                ),
                SizedBox(height: 2),
                Text(
                  'Receive email notifications for critical system events '
                  '(auto-removals, high refusal rate, low satisfaction).',
                  style: TextStyle(fontSize: 11, color: AppTheme.textSecondary),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          if (_loading || _saving)
            const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: AppTheme.primary,
              ),
            )
          else
            Switch(
              value: _enabled ?? false,
              activeThumbColor: AppTheme.primary,
              // Disabled (null onChanged) when the preference couldn't load.
              onChanged: _enabled == null ? null : _toggle,
            ),
        ],
      ),
    );
  }
}
