// lib/services/session_recovery.dart
// Shared handling for a 401 that a forced token refresh could not fix.

import 'package:firebase_auth/firebase_auth.dart';

// Refresh failures that mean the session is definitively over rather than
// temporarily unreachable. A superadmin force-logout revokes the refresh
// token, which surfaces here — as does a deleted or disabled account.
// Anything outside this set (notably network-request-failed) is treated as
// transient, because signing a user out over a dropped connection would be a
// worse bug than the one this fixes.
const _deadSessionCodes = {
  'user-token-expired',
  'user-disabled',
  'user-not-found',
  'invalid-user-token',
  'token-expired',
};

/// Sign out locally when a 401 retry proves the session is gone.
///
/// main.dart gates the whole app on authStateChanges, so signing out routes
/// the user to the login screen instead of stranding them in an app where
/// every request fails. Returns whether the session was ended.
Future<bool> endSessionIfRevoked(Object error) async {
  if (error is! FirebaseAuthException ||
      !_deadSessionCodes.contains(error.code)) {
    return false;
  }
  try {
    await FirebaseAuth.instance.signOut();
    return true;
  } catch (_) {
    // Nothing more we can do — the original 401 still reaches the caller.
    return false;
  }
}
