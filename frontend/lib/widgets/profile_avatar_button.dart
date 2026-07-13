// lib/widgets/profile_avatar_button.dart
// The top-right avatar + profile popup, shared by MainShell (user app) and
// AdminShell (admin panel) so profile/settings/logout are reachable from both.

import 'package:flutter/material.dart';
import '../models/profile_models.dart';
import 'profile_popup.dart';

class ProfileAvatarButton extends StatelessWidget {
  final UserProfile? profile;
  final ValueChanged<UserProfile> onProfileUpdated;
  final VoidCallback onOpenSettings;
  final VoidCallback onOpenChangePassword;
  final VoidCallback onLogout;
  final double diameter;

  const ProfileAvatarButton({
    super.key,
    required this.profile,
    required this.onProfileUpdated,
    required this.onOpenSettings,
    required this.onOpenChangePassword,
    required this.onLogout,
    this.diameter = 36,
  });

  String get _initial {
    final name = profile?.name.trim() ?? '';
    return name.isNotEmpty ? name[0].toUpperCase() : '?';
  }

  Future<void> _showPopup(BuildContext context) async {
    final p = profile;
    if (p == null) return;
    await showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Profile',
      barrierColor: Colors.black.withValues(alpha: 0.05),
      transitionDuration: const Duration(milliseconds: 150),
      pageBuilder: (dialogContext, _, _) {
        return SafeArea(
          child: Align(
            alignment: Alignment.topRight,
            child: Padding(
              padding: const EdgeInsets.only(top: 8, right: 12),
              child: Material(
                color: Colors.transparent,
                child: ProfilePopup(
                  profile: p,
                  onProfileUpdated: onProfileUpdated,
                  onOpenSettings: () {
                    Navigator.of(dialogContext).pop();
                    onOpenSettings();
                  },
                  onOpenChangePassword: () {
                    Navigator.of(dialogContext).pop();
                    onOpenChangePassword();
                  },
                  onLogout: () {
                    Navigator.of(dialogContext).pop();
                    onLogout();
                  },
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final photoUrl = profile?.photoUrl;
    final hasPhoto = photoUrl != null && photoUrl.isNotEmpty;

    final initial = Text(
      _initial,
      style: const TextStyle(
        color: Colors.white,
        fontWeight: FontWeight.w700,
        fontSize: 15,
      ),
    );

    return GestureDetector(
      onTap: profile == null ? null : () => _showPopup(context),
      child: CircleAvatar(
        radius: diameter / 2,
        backgroundColor: Colors.white24,
        // Image.network (not backgroundImage) so errorBuilder can fall back
        // to the initial — same pattern as ProfilePopup's own avatar.
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
            : initial,
      ),
    );
  }
}
