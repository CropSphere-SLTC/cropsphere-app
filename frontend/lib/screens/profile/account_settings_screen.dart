// lib/screens/profile/account_settings_screen.dart

import 'package:flutter/material.dart';
import '../../app_lang.dart';
import '../../models/profile_models.dart';
import '../../services/profile_service.dart';
import '../../widgets/app_theme.dart';
import '../../widgets/skeleton_loading.dart';

class AccountSettingsScreen extends StatefulWidget {
  const AccountSettingsScreen({super.key});

  @override
  State<AccountSettingsScreen> createState() => _AccountSettingsScreenState();
}

class _AccountSettingsScreenState extends State<AccountSettingsScreen> {
  final _profileService = ProfileService();

  bool _loading = true;
  bool _saving = false;
  String? _error;

  String _language = 'en';
  bool _priceAlerts = true;
  bool _weatherAlerts = true;
  bool _yieldRecommendations = true;

  static const _languages = [
    {'value': 'en', 'label': 'English'},
    {'value': 'si', 'label': 'සිංහල'},
    {'value': 'ta', 'label': 'தமிழ்'},
  ];

  @override
  void initState() {
    super.initState();
    _loadPreferences();
  }

  Future<void> _loadPreferences() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final prefs = await _profileService.getPreferences();
      if (!mounted) return;
      setState(() {
        _language = prefs.language;
        _priceAlerts = prefs.notifications.priceAlerts;
        _weatherAlerts = prefs.notifications.weatherAlerts;
        _yieldRecommendations = prefs.notifications.yieldRecommendations;
      });
    } catch (_) {
      if (mounted) setState(() => _error = 'Failed to load preferences');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final prefs = UserPreferences(
        language: _language,
        notifications: NotificationPreferences(
          priceAlerts: _priceAlerts,
          weatherAlerts: _weatherAlerts,
          yieldRecommendations: _yieldRecommendations,
        ),
      );
      await _profileService.updatePreferences(prefs);
      if (!mounted) return;

      // Keep the live app language in sync with the saved preference.
      final target = AppLang.values.firstWhere(
        (l) => l.name == _language,
        orElse: () => AppLang.en,
      );
      AppLangProvider.of(context).setLang(target);

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Preferences saved'),
          backgroundColor: AppTheme.success,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to save preferences'),
            backgroundColor: AppTheme.error,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// Outline pattern — a toggle/dropdown settings form on a single fast
  /// doc fetch; a bordered-only placeholder per field is low-emphasis
  /// enough not to overstate how long this actually takes.
  Widget _buildSkeleton() {
    Widget field() => const Padding(
      padding: EdgeInsets.only(bottom: 12),
      child: OutlineSkeletonBox(height: 44),
    );
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const OutlineSkeletonBox(width: 120, height: 18),
          const SizedBox(height: 12),
          field(),
          const SizedBox(height: 20),
          const OutlineSkeletonBox(width: 160, height: 18),
          const SizedBox(height: 12),
          field(),
          field(),
          field(),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(title: const Text('Account Settings')),
      body: _loading
          ? _buildSkeleton()
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (_error != null) ...[
                    _buildErrorCard(_error!),
                    const SizedBox(height: 16),
                  ],
                  _buildLanguageCard(),
                  const SizedBox(height: 16),
                  _buildNotificationsCard(),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton.icon(
                      onPressed: _saving ? null : _save,
                      icon: _saving
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.save),
                      label: Text(_saving ? 'Saving...' : 'Save'),
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildLanguageCard() {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Language',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _language,
              decoration: const InputDecoration(labelText: 'App language'),
              items: _languages
                  .map(
                    (l) => DropdownMenuItem(
                      value: l['value'],
                      child: Text(l['label']!),
                    ),
                  )
                  .toList(),
              onChanged: (v) {
                if (v != null) setState(() => _language = v);
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNotificationsCard() {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Text(
                'Notifications',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
              ),
            ),
            SwitchListTile(
              title: const Text('Price alerts'),
              subtitle: const Text('Get notified about crop price changes'),
              value: _priceAlerts,
              activeThumbColor: AppTheme.primary,
              onChanged: (v) => setState(() => _priceAlerts = v),
            ),
            SwitchListTile(
              title: const Text('Weather alerts'),
              subtitle: const Text('Get notified about severe weather'),
              value: _weatherAlerts,
              activeThumbColor: AppTheme.primary,
              onChanged: (v) => setState(() => _weatherAlerts = v),
            ),
            SwitchListTile(
              title: const Text('Yield recommendations'),
              subtitle: const Text('Get crop yield improvement tips'),
              value: _yieldRecommendations,
              activeThumbColor: AppTheme.primary,
              onChanged: (v) => setState(() => _yieldRecommendations = v),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorCard(String message) {
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
        ],
      ),
    );
  }
}
