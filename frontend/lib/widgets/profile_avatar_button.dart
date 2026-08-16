// lib/widgets/profile_avatar_button.dart
// The one profile avatar shared by every top bar in the app — user
// dashboard, Price/Weather/Crop Rec./Demand screens, and the admin panel —
// so every account type (farmer, admin, superadmin) reaches profile /
// account settings / change password / logout the same way.
//
// Self-contained: it loads the profile itself (via ProfileCache) and pushes
// its own routes, so it drops into any top bar as `const ProfileAvatarButton()`
// with no props threaded through the screen that hosts it.

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../models/profile_models.dart';
import '../screens/profile/account_settings_screen.dart';
import '../screens/profile/change_password_screen.dart';
import '../services/profile_cache.dart';
import '../services/profile_service.dart';
import '../services/session_service.dart';
import 'app_theme.dart';

class ProfileAvatarButton extends StatefulWidget {
  final double diameter;

  const ProfileAvatarButton({super.key, this.diameter = 34});

  @override
  State<ProfileAvatarButton> createState() => _ProfileAvatarButtonState();
}

class _ProfileAvatarButtonState extends State<ProfileAvatarButton> {
  @override
  void initState() {
    super.initState();
    ProfileCache.instance.ensureLoaded();
  }

  String _initials(String name) {
    final parts = name
        .trim()
        .split(RegExp(r'\s+'))
        .where((p) => p.isNotEmpty)
        .toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first[0].toUpperCase();
    return (parts.first[0] + parts.last[0]).toUpperCase();
  }

  Future<void> _openSheet() async {
    final profile = ProfileCache.instance.profile;
    if (profile == null) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _ProfileSheet(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: ProfileCache.instance,
      builder: (context, _) {
        final profile = ProfileCache.instance.profile;
        final diameter = widget.diameter;
        final photoUrl = profile?.photoUrl;
        final hasPhoto = photoUrl != null && photoUrl.isNotEmpty;

        final initial = Text(
          profile == null ? '?' : _initials(profile.name),
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w700,
            fontSize: diameter * 0.4,
          ),
        );

        return GestureDetector(
          onTap: profile == null ? null : _openSheet,
          child: CircleAvatar(
            radius: diameter / 2,
            backgroundColor: AppTheme.primary,
            // Image.network (not backgroundImage) so errorBuilder can fall
            // back to the initials if the photo URL 404s/expires.
            child: hasPhoto
                ? ClipOval(
                    child: Image.network(
                      photoUrl,
                      width: diameter,
                      height: diameter,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) => initial,
                    ),
                  )
                : (ProfileCache.instance.loading && profile == null)
                ? SizedBox(
                    width: diameter * 0.45,
                    height: diameter * 0.45,
                    child: const CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : initial,
          ),
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────
//  Bottom sheet — name, email, role, last login/active sessions, actions.
// ─────────────────────────────────────────────────────────────────────────
class _ProfileSheet extends StatefulWidget {
  const _ProfileSheet();

  @override
  State<_ProfileSheet> createState() => _ProfileSheetState();
}

class _ProfileSheetState extends State<_ProfileSheet> {
  late final TextEditingController _nameCtrl;
  bool _editingName = false;
  bool _savingName = false;

  UserProfile get _profile => ProfileCache.instance.profile!;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: _profile.name);
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  bool get _isPasswordUser {
    final providers = FirebaseAuth.instance.currentUser?.providerData ?? [];
    return providers.any((p) => p.providerId == 'password');
  }

  Color get _roleColor => switch (_profile.role) {
    'superadmin' => AppTheme.success,
    'admin' => AppTheme.info,
    _ => AppTheme.textMuted,
  };

  String _initials(String name) {
    final parts = name
        .trim()
        .split(RegExp(r'\s+'))
        .where((p) => p.isNotEmpty)
        .toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first[0].toUpperCase();
    return (parts.first[0] + parts.last[0]).toUpperCase();
  }

  String _formatLastLogin(String? iso) {
    if (iso == null) return 'Never';
    final dt = DateTime.tryParse(iso);
    if (dt == null) return iso;
    final local = dt.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${local.year}-${two(local.month)}-${two(local.day)} '
        '${two(local.hour)}:${two(local.minute)}';
  }

  Future<void> _saveName() async {
    final newName = _nameCtrl.text.trim();
    if (newName.isEmpty || newName == _profile.name) {
      setState(() => _editingName = false);
      return;
    }
    setState(() => _savingName = true);
    try {
      final confirmedName = await ProfileService().updateProfile(newName);
      ProfileCache.instance.update(_profile.copyWith(name: confirmedName));
      if (mounted) setState(() => _editingName = false);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to update name'),
            backgroundColor: AppTheme.error,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _savingName = false);
    }
  }

  Future<void> _confirmLogout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Logout'),
        content: const Text('Are you sure you want to logout?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: AppTheme.error),
            child: const Text('Logout'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    if (mounted) Navigator.of(context).pop(); // close the sheet first
    await SessionService.logout(); // clears ProfileCache itself
  }

  void _openSettings() {
    Navigator.of(context).pop();
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const AccountSettingsScreen()));
  }

  void _openChangePassword() {
    Navigator.of(context).pop();
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const ChangePasswordScreen()));
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final photoUrl = _profile.photoUrl;
    final hasPhoto = photoUrl != null && photoUrl.isNotEmpty;
    const avatarDiameter = 56.0;

    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: SafeArea(
        top: false,
        child: Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Drag handle
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE0E0E0),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CircleAvatar(
                    radius: avatarDiameter / 2,
                    backgroundColor: AppTheme.primary.withValues(alpha: 0.15),
                    child: hasPhoto
                        ? ClipOval(
                            child: Image.network(
                              photoUrl,
                              width: avatarDiameter,
                              height: avatarDiameter,
                              fit: BoxFit.cover,
                              errorBuilder: (context, error, stackTrace) =>
                                  Text(
                                    _initials(_profile.name),
                                    style: const TextStyle(
                                      color: AppTheme.primary,
                                      fontWeight: FontWeight.w700,
                                      fontSize: 18,
                                    ),
                                  ),
                            ),
                          )
                        : Text(
                            _initials(_profile.name),
                            style: const TextStyle(
                              color: AppTheme.primary,
                              fontWeight: FontWeight.w700,
                              fontSize: 18,
                            ),
                          ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(child: _buildNameSection()),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                _profile.email,
                style: const TextStyle(
                  fontSize: 13,
                  color: AppTheme.textSecondary,
                ),
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 10),
              _buildRoleBadge(),
              const Divider(height: 28),
              _infoRow(
                Icons.access_time,
                'Last login',
                _formatLastLogin(_profile.lastLogin),
              ),
              const SizedBox(height: 8),
              _infoRow(
                Icons.devices_outlined,
                'Active sessions',
                '${_profile.activeSessions}',
              ),
              const Divider(height: 28),
              _actionButton(
                icon: Icons.settings_outlined,
                label: 'Account Settings',
                onTap: _openSettings,
              ),
              if (_isPasswordUser)
                _actionButton(
                  icon: Icons.lock_outline,
                  label: 'Change Password',
                  onTap: _openChangePassword,
                ),
              _actionButton(
                icon: Icons.logout,
                label: 'Logout',
                color: AppTheme.error,
                onTap: _confirmLogout,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNameSection() {
    if (_editingName) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: TextField(
              controller: _nameCtrl,
              autofocus: true,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              decoration: const InputDecoration(
                isDense: true,
                contentPadding: EdgeInsets.symmetric(
                  vertical: 6,
                  horizontal: 8,
                ),
              ),
              onSubmitted: (_) => _saveName(),
            ),
          ),
          _savingName
              ? const Padding(
                  padding: EdgeInsets.all(8),
                  child: SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
              : IconButton(
                  icon: const Icon(
                    Icons.check,
                    size: 18,
                    color: AppTheme.success,
                  ),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  onPressed: _saveName,
                ),
        ],
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Text(
            _profile.name,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const SizedBox(width: 4),
        IconButton(
          icon: const Icon(Icons.edit, size: 16, color: AppTheme.textMuted),
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(),
          onPressed: () => setState(() => _editingName = true),
        ),
      ],
    );
  }

  Widget _buildRoleBadge() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: _roleColor,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        _profile.role.toUpperCase(),
        style: const TextStyle(
          color: Colors.white,
          fontSize: 10,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.3,
        ),
      ),
    );
  }

  Widget _infoRow(IconData icon, String label, String value) {
    return Row(
      children: [
        Icon(icon, size: 16, color: AppTheme.textMuted),
        const SizedBox(width: 8),
        Text(
          '$label: ',
          style: const TextStyle(fontSize: 13, color: AppTheme.textSecondary),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppTheme.textPrimary,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  Widget _actionButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    Color? color,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 11, horizontal: 4),
        child: Row(
          children: [
            Icon(icon, size: 19, color: color ?? AppTheme.textPrimary),
            const SizedBox(width: 12),
            Text(
              label,
              style: TextStyle(
                fontSize: 14.5,
                fontWeight: FontWeight.w600,
                color: color ?? AppTheme.textPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
