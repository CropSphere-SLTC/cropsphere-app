// lib/services/profile_service.dart
// Real API calls to user profile & preferences endpoints.
// Same Dio + Firebase JWT pattern as api_service.dart.

import 'package:dio/dio.dart';
import 'auth_interceptor.dart';
import '../config/app_config.dart';
import '../models/profile_models.dart';

class ProfileService {
  static final ProfileService _instance = ProfileService._internal();
  factory ProfileService() => _instance;

  late final Dio _dio;

  ProfileService._internal() {
    _dio = Dio(
      BaseOptions(
        baseUrl: AppConfig.baseUrl,
        connectTimeout: AppConfig.apiTimeout,
        receiveTimeout: AppConfig.apiTimeout,
        headers: {'Content-Type': 'application/json'},
      ),
    );

    // JWT interceptor — Firebase handles token refresh automatically
    _dio.interceptors.add(firebaseAuthInterceptor(_dio));
  }

  Future<UserProfile> getProfile() async {
    final response = await _dio.get('/api/user/profile');
    return UserProfile.fromJson(response.data);
  }

  // Returns the confirmed display name from the server response so the
  // caller can merge it into its cached UserProfile via copyWith.
  Future<String> updateProfile(String displayName) async {
    final response = await _dio.patch(
      '/api/user/profile',
      data: {'display_name': displayName},
    );
    return response.data['display_name'] as String? ?? displayName;
  }

  Future<UserPreferences> getPreferences() async {
    final response = await _dio.get('/api/user/preferences');
    return UserPreferences.fromJson(response.data);
  }

  /// Saves preferences and verifies the server actually stored the farm
  /// fields, rather than trusting the 200.
  ///
  /// A backend older than the one that introduced preferred_district /
  /// preferred_crop drops them as unknown request fields (Pydantic defaults
  /// to extra='ignore') and still answers 200 — which made a save look
  /// successful while nothing persisted, so the values were gone on the
  /// next load. The PATCH response echoes both fields back, so comparing
  /// the echo against what was sent catches exactly that case at the point
  /// it happens instead of leaving it to surface as a mystery later.
  Future<PreferencesSaveResult> updatePreferences(
    UserPreferences preferences,
  ) async {
    final response = await _dio.patch(
      '/api/user/preferences',
      data: preferences.toJson(),
    );

    final data = response.data is Map
        ? Map<String, dynamic>.from(response.data as Map)
        : const <String, dynamic>{};

    // Only the fields actually sent are checked — an omitted field is meant
    // to be left untouched server-side, so no echo is expected for it.
    final unconfirmed = <PreferenceField>[];
    if (preferences.preferredDistrict != null &&
        data['preferred_district'] != preferences.preferredDistrict) {
      unconfirmed.add(PreferenceField.district);
    }
    if (preferences.preferredCrop != null &&
        data['preferred_crop'] != preferences.preferredCrop) {
      unconfirmed.add(PreferenceField.crop);
    }
    return PreferencesSaveResult(unconfirmed);
  }
}

enum PreferenceField { district, crop }

/// Outcome of a preferences save — [unconfirmed] lists fields the server
/// did not echo back, meaning they were NOT stored despite a 200 response.
class PreferencesSaveResult {
  final List<PreferenceField> unconfirmed;

  const PreferencesSaveResult(this.unconfirmed);

  bool get fullyConfirmed => unconfirmed.isEmpty;
}
