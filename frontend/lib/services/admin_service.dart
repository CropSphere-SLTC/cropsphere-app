// lib/services/admin_service.dart
// Real API calls to admin-only endpoints — requires admin/superadmin role.
// Same Dio + Firebase JWT pattern as api_service.dart.

import 'package:dio/dio.dart';
import 'auth_interceptor.dart';
import 'package:flutter/foundation.dart';
import '../config/app_config.dart';
import '../models/admin_models.dart';
import '../models/pattern_models.dart';

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
    _dio.interceptors.add(firebaseAuthInterceptor(_dio));
  }

  // One retry after the server's Retry-After window. A 429 is not a verdict
  // about the user or the data — it just means we asked too soon — so every
  // caller of a rate-limited admin endpoint should go through here rather
  // than surfacing the throttle as an error.
  Future<Response<T>> _getWithRetryOn429<T>(String path) async {
    try {
      return await _dio.get<T>(path);
    } on DioException catch (e) {
      if (e.response?.statusCode != 429) rethrow;
      final retryAfter =
          int.tryParse(e.response?.headers.value('retry-after') ?? '') ?? 3;
      debugPrint(
        'AdminService: $path rate limited, retrying in ${retryAfter}s',
      );
      await Future.delayed(Duration(seconds: retryAfter));
      return _dio.get<T>(path);
    }
  }

  // Gates the Admin nav item — 200 means admin/superadmin, 403 means not.
  //
  // Uses /api/admin/access (60/min), NOT /api/admin/stats. This gate re-runs on
  // app boot, on every foreground resume, and on every Home tap; pointing it at
  // the stats endpoint meant those checks ate the 10/min budget belonging to the
  // Dashboard and System health pages. /access does a role lookup and nothing
  // else — no CPU sampling, no Firestore reads.
  //
  // Only a 403 is a definitive "not admin" signal. A 429 gets one retry.
  Future<bool> checkAdminAccess() async {
    try {
      final response = await _getWithRetryOn429('/api/admin/access');
      return response.statusCode == 200;
    } on DioException catch (e) {
      debugPrint(
        'AdminService.checkAdminAccess denied: HTTP ${e.response?.statusCode}',
      );
      return false;
    } catch (e) {
      debugPrint('AdminService.checkAdminAccess failed: $e');
      return false;
    }
  }

  Future<AdminStats> getStats() async {
    final response = await _getWithRetryOn429('/api/admin/stats');
    return AdminStats.fromJson(response.data as Map<String, dynamic>);
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

  // ── Pattern overrides ────────────────────────────────────────────────────────
  // Analysis and every mutation are superadmin-only; the two read endpoints are
  // admin-readable so a plain admin can still inspect what is live.

  // Finds messages that should have matched a routing pattern but didn't, and
  // proposes phrases. Read-only — saves nothing.
  Future<PatternAnalysis> analyzePatterns({int days = 14}) async {
    final response = await _dio.post(
      '/api/admin/analyze-patterns',
      queryParameters: {'days': days},
    );
    return PatternAnalysis.fromJson(response.data);
  }

  // Approves the selected proposals. `phrase` may differ from what was
  // proposed — the admin can edit it — but the category and evidence count are
  // taken from the server's own analysis, and every phrase is re-validated
  // server-side. Rejected selections come back in `skipped` with a reason
  // rather than failing the whole call.
  Future<ApplyPatternsResult> applyPatterns(
    List<Map<String, dynamic>> patterns, {
    int days = 14,
  }) async {
    final response = await _dio.post(
      '/api/admin/apply-patterns',
      queryParameters: {'days': days},
      data: {'patterns': patterns},
    );
    return ApplyPatternsResult.fromJson(response.data);
  }

  Future<ActivePatterns> getActivePatterns() async {
    final response = await _dio.get('/api/admin/active-patterns');
    return ActivePatterns.fromJson(response.data);
  }

  Future<List<PatternOverride>> getRevokedPatterns() async {
    final response = await _dio.get('/api/admin/revoked-patterns');
    final items = response.data['revoked'] as List? ?? [];
    return items
        .map((r) => PatternOverride.fromJson(Map<String, dynamic>.from(r)))
        .toList();
  }

  Future<PatternAnalytics> getPatternAnalytics(String patternId) async {
    final response = await _dio.get('/api/admin/pattern-analytics/$patternId');
    return PatternAnalytics.fromJson(response.data);
  }

  // Retires an active pattern. The reason is mandatory server-side (3–500
  // chars) — a shorter one is rejected with 422.
  Future<void> revokePattern(String patternId, String reason) async {
    await _dio.post(
      '/api/admin/revoke-pattern/$patternId',
      data: {'reason': reason},
    );
  }

  // Brings a revoked pattern back with counters reset to zero. 409 if a
  // pattern with that id is already active.
  Future<void> restorePattern(String patternId) async {
    await _dio.post('/api/admin/restore-pattern/$patternId');
  }

  // Permanent — only works on revoked patterns, never on a live one.
  Future<void> deletePattern(String patternId) async {
    await _dio.delete('/api/admin/delete-pattern/$patternId');
  }

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
