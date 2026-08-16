// lib/services/profile_cache.dart
// App-wide cache for the signed-in user's profile so every ProfileAvatarButton
// (one instance per screen's top bar — dashboard, price, weather, crop rec.,
// demand, admin panel) shows the same name/photo/role instantly instead of
// each doing its own fetch-and-flicker on every screen switch.

import 'package:flutter/foundation.dart';
import '../models/profile_models.dart';
import 'profile_service.dart';

class ProfileCache extends ChangeNotifier {
  ProfileCache._internal();
  static final ProfileCache instance = ProfileCache._internal();

  UserProfile? profile;
  bool loading = false;

  Future<void>? _inFlight;

  /// Fetch once; safe to call from every avatar button's initState —
  /// concurrent callers all await the same in-flight request.
  Future<void> ensureLoaded() {
    if (profile != null) return Future.value();
    return _inFlight ??= _load();
  }

  Future<void> refresh() => _load();

  Future<void> _load() async {
    loading = true;
    notifyListeners();
    try {
      profile = await ProfileService().getProfile();
    } catch (e) {
      debugPrint('ProfileCache: failed to load profile: $e');
    } finally {
      loading = false;
      _inFlight = null;
      notifyListeners();
    }
  }

  void update(UserProfile updated) {
    profile = updated;
    notifyListeners();
  }

  /// Called on logout so the next signed-in account never briefly shows the
  /// previous user's name/photo before its own profile loads.
  void clear() {
    profile = null;
    _inFlight = null;
    notifyListeners();
  }
}
