// lib/widgets/profile_popup.dart
// Dropdown-style profile panel shown when the top-right avatar is tapped.

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../models/profile_models.dart';
import '../services/profile_service.dart';
import 'app_theme.dart';

class ProfilePopup extends StatefulWidget {
  final UserProfile profile;
  final ValueChanged<UserProfile> onProfileUpdated;
  final VoidCallback onOpenSettings;
  final VoidCallback onOpenChangePassword;
  final VoidCallback onLogout;

  const ProfilePopup({
    super.key,
    required this.profile,
    required this.onProfileUpdated,
    required this.onOpenSettings,
    required this.onOpenChangePassword,
    required this.onLogout,
  });

  @override
  State<ProfilePopup> createState() => _ProfilePopupState();
}

class _ProfilePopupState extends State<ProfilePopup> {
  late final TextEditingController _nameCtrl;
  bool _editingName = false;
  bool _savingName = false;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.profile.name);
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

  Color get _roleColor => switch (widget.profile.role) {
    'superadmin' => AppTheme.success,
    'admin' => AppTheme.info,
    _ => AppTheme.textMuted,
  };

  String get _initials {
    final parts = widget.profile.name
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
    if (newName.isEmpty || newName == widget.profile.name) {
      setState(() => _editingName = false);
      return;
    }
    setState(() => _savingName = true);
    try {
      final confirmedName = await ProfileService().updateProfile(newName);
      widget.onProfileUpdated(widget.profile.copyWith(name: confirmedName));
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
    if (confirmed == true) widget.onLogout();
  }

  @override
  Widget build(BuildContext context) {
    final maxWidth = MediaQuery.of(context).size.width - 24;
    final width = maxWidth < 300 ? maxWidth : 300.0;

    return Container(
      width: width,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.15),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildAvatar(),
                const SizedBox(width: 12),
                Expanded(child: _buildNameSection()),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              widget.profile.email,
              style: const TextStyle(
                fontSize: 13,
                color: AppTheme.textSecondary,
              ),
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 10),
            _buildRoleBadge(),
            const Divider(height: 26),
            _infoRow(
              Icons.access_time,
              'Last login',
              _formatLastLogin(widget.profile.lastLogin),
            ),
            const SizedBox(height: 8),
            _infoRow(
              Icons.devices_outlined,
              'Active sessions',
              '${widget.profile.activeSessions}',
            ),
            const Divider(height: 26),
            _actionButton(
              icon: Icons.settings_outlined,
              label: 'Account Settings',
              onTap: widget.onOpenSettings,
            ),
            if (_isPasswordUser)
              _actionButton(
                icon: Icons.lock_outline,
                label: 'Change Password',
                onTap: widget.onOpenChangePassword,
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
    );
  }

  Widget _buildAvatar() {
    final photoUrl = widget.profile.photoUrl;
    final hasPhoto = photoUrl != null && photoUrl.isNotEmpty;
    return CircleAvatar(
      radius: 26,
      backgroundColor: AppTheme.primary.withValues(alpha: 0.15),
      backgroundImage: hasPhoto ? NetworkImage(photoUrl) : null,
      child: hasPhoto
          ? null
          : Text(
              _initials,
              style: const TextStyle(
                color: AppTheme.primary,
                fontWeight: FontWeight.w700,
                fontSize: 16,
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
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
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
            widget.profile.name,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const SizedBox(width: 4),
        IconButton(
          icon: const Icon(Icons.edit, size: 15, color: AppTheme.textMuted),
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
        widget.profile.role.toUpperCase(),
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
        Icon(icon, size: 15, color: AppTheme.textMuted),
        const SizedBox(width: 8),
        Text(
          '$label: ',
          style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(
              fontSize: 12,
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
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
        child: Row(
          children: [
            Icon(icon, size: 18, color: color ?? AppTheme.textPrimary),
            const SizedBox(width: 10),
            Text(
              label,
              style: TextStyle(
                fontSize: 14,
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
