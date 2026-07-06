// lib/services/superadmin_service.dart
// Real API calls to superadmin-only endpoints — requires superadmin role.
// Same Dio + Firebase JWT pattern as admin_service.dart.

import 'package:dio/dio.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../config/app_config.dart';
import '../models/admin_models.dart';

class SuperadminService {
  static final SuperadminService _instance = SuperadminService._internal();
  factory SuperadminService() => _instance;

  late final Dio _dio;

  SuperadminService._internal() {
    _dio = Dio(
      BaseOptions(
        baseUrl: AppConfig.baseUrl,
        connectTimeout: AppConfig.apiTimeout,
        receiveTimeout: AppConfig.apiTimeout,
        headers: {'Content-Type': 'application/json'},
      ),
    );

    // JWT interceptor — Firebase handles token refresh automatically
    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          final user = FirebaseAuth.instance.currentUser;
          if (user != null) {
            final token = await user.getIdToken();
            options.headers['Authorization'] = 'Bearer $token';
          }
          return handler.next(options);
        },
        onError: (DioException error, ErrorInterceptorHandler handler) async {
          if (error.response?.statusCode == 401) {
            final user = FirebaseAuth.instance.currentUser;
            if (user != null) {
              try {
                // Token may have expired — force a refresh and retry once.
                final newToken = await user.getIdToken(true);
                final opts = error.requestOptions;
                opts.headers['Authorization'] = 'Bearer $newToken';
                final response = await _dio.fetch(opts);
                return handler.resolve(response);
              } catch (_) {
                // Retry failed — fall through to original error.
              }
            }
          }
          return handler.next(error);
        },
      ),
    );
  }

  Future<SuperadminConfig> getConfig() async {
    final response = await _dio.get('/api/superadmin/config');
    return SuperadminConfig.fromJson(response.data);
  }

  // Only rate limits are actually mutable server-side right now —
  // enable_admin_api is sourced from an env var on the backend and isn't
  // accepted by PATCH /api/superadmin/config, so there's no parameter for
  // it here. See SuperadminDashboardScreen for how that's surfaced in the UI.
  Future<SuperadminConfig> updateConfig({
    int? adminRateLimitPerMinute,
    int? superadminRateLimitPerMinute,
  }) async {
    final response = await _dio.patch(
      '/api/superadmin/config',
      data: {
        'admin_rate_limit_per_minute': ?adminRateLimitPerMinute,
        'superadmin_rate_limit_per_minute': ?superadminRateLimitPerMinute,
      },
    );
    return SuperadminConfig.fromJson(response.data);
  }

  Future<List<AuditLog>> getFullAuditLogs() async {
    final response = await _dio.get('/api/superadmin/audit-logs');
    final logs = response.data['logs'] as List;
    return logs.map((l) => AuditLog.fromJson(l)).toList();
  }

  Future<Map<String, dynamic>> cleanupOldSessions() async {
    final response = await _dio.delete('/api/admin/sessions/cleanup-old');
    return Map<String, dynamic>.from(response.data);
  }
}
