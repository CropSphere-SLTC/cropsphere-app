// lib/services/session_service.dart
import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'profile_cache.dart';

class SessionService {
  static Timer? _inactivityTimer;
  static const Duration _timeout = Duration(minutes: 15);

  // Start inactivity timer
  static void startTimer() {
    _inactivityTimer?.cancel();
    _inactivityTimer = Timer(_timeout, _logout);
  }

  // Reset timer on user activity
  static void resetTimer() {
    startTimer();
  }

  // Stop timer
  static void stopTimer() {
    _inactivityTimer?.cancel();
    _inactivityTimer = null;
  }

  // Check if timer is active
  static bool isTimerActive() {
    return _inactivityTimer != null && _inactivityTimer!.isActive;
  }

  // Logout user
  static Future<void> _logout() async {
    await FirebaseAuth.instance.signOut();
    ProfileCache.instance.clear();
    stopTimer();
  }

  // Manual logout
  static Future<void> logout() async {
    stopTimer();
    await FirebaseAuth.instance.signOut();
    // So the next signed-in account never briefly shows the previous
    // user's cached name/photo before its own profile loads.
    ProfileCache.instance.clear();
  }
}
