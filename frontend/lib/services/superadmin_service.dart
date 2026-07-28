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
  // it here. See SystemConfigPage for how that's surfaced in the UI.
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

  // ── Prompt tuning lifecycle (superadmin only) ────────────────────────────

  Future<PromptTuningConfig> getPromptTuningConfig() async {
    final response = await _dio.get('/api/superadmin/prompt-tuning-config');
    return PromptTuningConfig.fromJson(response.data);
  }

  // PATCH semantics — only the fields passed here are changed server-side.
  Future<PromptTuningConfig> updatePromptTuningConfig({
    int? minSampleSize,
    int? trialPeriodDays,
    int? trialExtensionDays,
    int? trashRetentionDays,
  }) async {
    final response = await _dio.patch(
      '/api/superadmin/prompt-tuning-config',
      data: {
        'min_sample_size': ?minSampleSize,
        'trial_period_days': ?trialPeriodDays,
        'trial_extension_days': ?trialExtensionDays,
        'trash_retention_days': ?trashRetentionDays,
      },
    );
    return PromptTuningConfig.fromJson(response.data);
  }

  // Before/after comparison for one adjustment. Works for trashed adjustments
  // too — their measurement window freezes at the time they were removed.
  Future<AdjustmentAnalytics> getAdjustmentAnalytics(
    String adjustmentId,
  ) async {
    final response = await _dio.get(
      '/api/superadmin/adjustment-analytics/$adjustmentId',
    );
    return AdjustmentAnalytics.fromJson(response.data);
  }

  // Skips auto-validation and locks the adjustment in. 409 if already permanent.
  Future<void> forcePermanent(String adjustmentId) async {
    await _dio.post('/api/superadmin/force-permanent/$adjustmentId');
  }

  // Moves an adjustment to the trash. The comment is mandatory server-side
  // (3–500 chars) — a shorter one is rejected with 422.
  Future<void> removeAdjustment(String adjustmentId, String comment) async {
    await _dio.post(
      '/api/superadmin/remove-adjustment/$adjustmentId',
      data: {'comment': comment},
    );
  }

  // Deletes trash past its retention deadline; `allItems` empties it outright.
  // Returns how many were permanently deleted.
  Future<int> clearTrash({bool allItems = false}) async {
    final response = await _dio.delete(
      '/api/superadmin/clear-trash',
      queryParameters: {'all_items': allItems},
    );
    return response.data['deleted_count'] ?? 0;
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

  // Revokes the target user's Firebase refresh tokens server-side. Their
  // already-issued ID token stays valid until it expires (~1h), per the
  // backend's force_logout docstring.
  Future<void> forceLogout(String uid) async {
    await _dio.post('/api/superadmin/security/force-logout/$uid');
  }
}
