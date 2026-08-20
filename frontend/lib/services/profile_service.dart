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

  Future<void> updatePreferences(UserPreferences preferences) async {
    await _dio.patch('/api/user/preferences', data: preferences.toJson());
  }
}
