// lib/services/admin_service.dart
// Real API calls to admin-only endpoints — requires admin/superadmin role.
// Same Dio + Firebase JWT pattern as api_service.dart.

import 'package:dio/dio.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import '../config/app_config.dart';
import '../models/admin_models.dart';

class AdminService {
  static final AdminService _instance = AdminService._internal();
  factory AdminService() => _instance;

  late final Dio _dio;

  AdminService._internal() {
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

  // Gates the Admin nav item — 200 means admin/superadmin, 403 means not.
  //
  // /api/admin/stats is capped at 10 req/min server-side. This same endpoint
  // is hit here (nav check) AND by the dashboard's own stats load, so a 429
  // is a real possibility during normal use (e.g. hot-restarts in dev, or a
  // quick nav-check-then-open-dashboard sequence) — it does NOT mean the
  // user isn't an admin. Only a 403 is a definitive "not admin" signal;
  // a 429 gets one retry after the server's Retry-After window.
  Future<bool> checkAdminAccess() async {
    try {
      final response = await _dio.get('/api/admin/stats');
      return response.statusCode == 200;
    } on DioException catch (e) {
      final status = e.response?.statusCode;
      if (status == 429) {
        final retryAfter =
            int.tryParse(e.response?.headers.value('retry-after') ?? '') ?? 3;
        debugPrint(
          'AdminService.checkAdminAccess: rate limited, retrying in ${retryAfter}s',
        );
        await Future.delayed(Duration(seconds: retryAfter));
        try {
          final retryResponse = await _dio.get('/api/admin/stats');
          return retryResponse.statusCode == 200;
        } catch (retryError) {
          debugPrint('AdminService.checkAdminAccess retry failed: $retryError');
          return false;
        }
      }
      debugPrint('AdminService.checkAdminAccess denied: HTTP $status');
      return false;
    } catch (e) {
      debugPrint('AdminService.checkAdminAccess failed: $e');
      return false;
    }
  }

  Future<AdminStats> getStats() async {
    final response = await _dio.get('/api/admin/stats');
    return AdminStats.fromJson(response.data);
  }

  Future<List<AdminUser>> getUsers() async {
    final response = await _dio.get('/api/admin/users');
    final users = response.data['users'] as List;
    return users.map((u) => AdminUser.fromJson(u)).toList();
  }

  Future<void> updateUserRole(String uid, String role) async {
    await _dio.patch('/api/admin/users/$uid/role', data: {'role': role});
  }

  Future<void> setUserBanned(String uid, bool isBanned) async {
    await _dio.patch(
      '/api/admin/users/$uid/ban',
      data: {'is_banned': isBanned},
    );
  }

  Future<void> deleteUser(String uid) async {
    await _dio.delete('/api/admin/users/$uid');
  }

  Future<List<AuditLog>> getAuditLogs() async {
    final response = await _dio.get('/api/admin/audit-logs');
    final logs = response.data['logs'] as List;
    return logs.map((l) => AuditLog.fromJson(l)).toList();
  }

  Future<List<Map<String, dynamic>>> getPredictionLogs() async {
    final response = await _dio.get('/api/admin/prediction-logs');
    final logs = response.data['logs'] as List;
    return logs.map((l) => Map<String, dynamic>.from(l)).toList();
  }

  Future<GapReport> getGapReport({int days = 7}) async {
    final response = await _dio.get(
      '/api/admin/gap-report',
      queryParameters: {'days': days},
    );
    return GapReport.fromJson(response.data);
  }

  // ── Prompt tuning (require_superadmin — superadmin only) ─────────────────────

  // Runs the analysis and returns proposed adjustments. Saves nothing.
  Future<PromptTuningProposal> analyzePromptTuning({int days = 7}) async {
    final response = await _dio.post(
      '/api/admin/analyze-prompt-tuning',
      queryParameters: {'days': days},
    );
    return PromptTuningProposal.fromJson(response.data);
  }

  // Starts a trial for each approved id. The server re-derives the analysis and
  // keeps only the approved subset, so fewer may be applied than requested if a
  // proposal stopped triggering. `trialPeriodDays` overrides the configured
  // trial length for this apply only.
  Future<ApplyTuningResult> applyPromptTuning(
    List<String> approvedIds, {
    int days = 7,
    int? trialPeriodDays,
  }) async {
    final response = await _dio.post(
      '/api/admin/apply-prompt-tuning',
      queryParameters: {'days': days},
      data: {
        'approved_ids': approvedIds,
        'trial_period_days': ?trialPeriodDays,
      },
    );
    return ApplyTuningResult.fromJson(response.data);
  }

  Future<ActivePromptTuning> getActivePromptTuning() async {
    final response = await _dio.get('/api/admin/active-prompt-tuning');
    return ActivePromptTuning.fromJson(response.data);
  }

  // Moves everything active to the trash — recoverable until retention
  // expires, not a permanent delete. Returns how many were cleared.
  Future<int> clearPromptTuning() async {
    final response = await _dio.delete('/api/admin/clear-prompt-tuning');
    return response.data['cleared_count'] ?? 0;
  }

  Future<List<TrashedAdjustment>> getPromptTuningTrash() async {
    final response = await _dio.get('/api/admin/prompt-tuning-trash');
    final items = response.data['trash'] as List? ?? [];
    return items
        .map((t) => TrashedAdjustment.fromJson(Map<String, dynamic>.from(t)))
        .toList();
  }

  // Restores a trashed adjustment as a FRESH trial (new clock, extensions
  // reset). 409 if an adjustment with that id is already active.
  Future<void> restoreFromTrash(String adjustmentId) async {
    await _dio.post('/api/admin/restore-from-trash/$adjustmentId');
  }

  // Note: prompt-tuning auto-validation events (promote / auto-remove / extend /
  // needs-review) now surface through the general admin notification bell
  // (NotificationService), not a bespoke tuning feed.

  // ── Email alert preference (per admin) ───────────────────────────────────────

  // Whether this admin receives email alerts for critical events. Defaults to
  // true server-side when never set.
  Future<bool> getEmailPreference() async {
    final response = await _dio.get('/api/admin/email-preferences');
    return response.data['email_notifications'] ?? true;
  }

  // Returns the new value the server persisted.
  Future<bool> setEmailPreference(bool enabled) async {
    final response = await _dio.patch(
      '/api/admin/email-preferences',
      data: {'email_notifications': enabled},
    );
    return response.data['email_notifications'] ?? enabled;
  }

  // ── Security monitoring (require_admin — both admin and superadmin) ──────────

  Future<SecuritySummary> getSecuritySummary() async {
    final response = await _dio.get('/api/admin/security/summary');
    return SecuritySummary.fromJson(response.data);
  }

  Future<List<SecurityEvent>> getFailedLogins() async {
    final response = await _dio.get('/api/admin/security/failed-logins');
    return _parseEvents(response.data);
  }

  Future<List<SecurityEvent>> getRateViolations() async {
    final response = await _dio.get('/api/admin/security/rate-violations');
    return _parseEvents(response.data);
  }

  Future<List<SecurityEvent>> getBannedAttempts() async {
    final response = await _dio.get('/api/admin/security/banned-attempts');
    return _parseEvents(response.data);
  }

  Future<List<ActiveSession>> getActiveSessions() async {
    final response = await _dio.get('/api/admin/security/active-sessions');
    final sessions = response.data['sessions'] as List? ?? [];
    return sessions
        .map((s) => ActiveSession.fromJson(Map<String, dynamic>.from(s)))
        .toList();
  }

  List<SecurityEvent> _parseEvents(dynamic data) {
    final events = data['events'] as List? ?? [];
    return events
        .map((e) => SecurityEvent.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }
}
