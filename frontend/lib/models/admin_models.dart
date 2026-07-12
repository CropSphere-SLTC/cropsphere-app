// lib/models/admin_models.dart
// Request and response models matching admin_router.py schemas exactly

class AdminStats {
  final double cpuPercent;
  final double ramTotalGb;
  final double ramUsedGb;
  final double ramPercent;
  final Map<String, bool> modelsLoaded;
  final int totalRequests;
  final Map<String, int> requestsByEndpoint;
  final String timestamp;

  AdminStats({
    required this.cpuPercent,
    required this.ramTotalGb,
    required this.ramUsedGb,
    required this.ramPercent,
    required this.modelsLoaded,
    required this.totalRequests,
    required this.requestsByEndpoint,
    required this.timestamp,
  });

  factory AdminStats.fromJson(Map<String, dynamic> json) => AdminStats(
    cpuPercent: (json['cpu_percent'] as num? ?? 0).toDouble(),
    ramTotalGb: (json['ram_total_gb'] as num? ?? 0).toDouble(),
    ramUsedGb: (json['ram_used_gb'] as num? ?? 0).toDouble(),
    ramPercent: (json['ram_percent'] as num? ?? 0).toDouble(),
    modelsLoaded: Map<String, bool>.from(json['models_loaded'] ?? {}),
    totalRequests: json['total_requests'] ?? 0,
    requestsByEndpoint: Map<String, int>.from(
      json['requests_by_endpoint'] ?? {},
    ),
    timestamp: json['timestamp'] ?? '',
  );
}

class AdminUser {
  final String uid;
  final String email;
  final String role;
  final bool isBanned;

  AdminUser({
    required this.uid,
    required this.email,
    required this.role,
    required this.isBanned,
  });

  factory AdminUser.fromJson(Map<String, dynamic> json) => AdminUser(
    uid: json['uid'] ?? '',
    email: json['email'] ?? '',
    role: json['role'] ?? 'user',
    isBanned: json['is_banned'] ?? false,
  );
}

class AuditLog {
  final String actorUid;
  final String actorRole;
  final String action;
  final String targetUid;
  final String timestamp;
  final Map<String, dynamic> details;

  AuditLog({
    required this.actorUid,
    required this.actorRole,
    required this.action,
    required this.targetUid,
    required this.timestamp,
    required this.details,
  });

  factory AuditLog.fromJson(Map<String, dynamic> json) => AuditLog(
    actorUid: json['actor_uid'] ?? '',
    actorRole: json['actor_role'] ?? '',
    action: json['action'] ?? '',
    targetUid: json['target_uid'] ?? '',
    timestamp: json['timestamp'] ?? '',
    details: Map<String, dynamic>.from(json['details'] ?? {}),
  );
}

class GapReport {
  final String period;
  final int totalInteractions;
  final Map<String, int> responseBreakdown;
  final List<RefusedQuestion> topRefusedQuestions;
  final List<MissingItem> missingCrops;
  final List<MissingItem> missingDistricts;
  final Map<String, int> confidenceDistribution;
  final Map<String, int> knowledgeLevelDistribution;
  final int avgResponseTimeMs;
  final double chipTapRate;
  final double avgSessionLength;

  GapReport({
    required this.period,
    required this.totalInteractions,
    required this.responseBreakdown,
    required this.topRefusedQuestions,
    required this.missingCrops,
    required this.missingDistricts,
    required this.confidenceDistribution,
    required this.knowledgeLevelDistribution,
    required this.avgResponseTimeMs,
    required this.chipTapRate,
    required this.avgSessionLength,
  });

  factory GapReport.fromJson(Map<String, dynamic> json) => GapReport(
    period: json['period'] ?? '',
    totalInteractions: json['total_interactions'] ?? 0,
    responseBreakdown: Map<String, int>.from(json['response_breakdown'] ?? {}),
    topRefusedQuestions: ((json['top_refused_questions'] ?? []) as List)
        .map((e) => RefusedQuestion.fromJson(Map<String, dynamic>.from(e)))
        .toList(),
    missingCrops: ((json['missing_crops'] ?? []) as List)
        .map((e) => MissingItem.fromJson(Map<String, dynamic>.from(e), 'crop'))
        .toList(),
    missingDistricts: ((json['missing_districts'] ?? []) as List)
        .map(
          (e) => MissingItem.fromJson(Map<String, dynamic>.from(e), 'district'),
        )
        .toList(),
    confidenceDistribution: Map<String, int>.from(
      json['confidence_distribution'] ?? {},
    ),
    knowledgeLevelDistribution: Map<String, int>.from(
      json['knowledge_level_distribution'] ?? {},
    ),
    avgResponseTimeMs: json['avg_response_time_ms'] ?? 0,
    chipTapRate: (json['chip_tap_rate'] as num? ?? 0).toDouble(),
    avgSessionLength: (json['avg_session_length'] as num? ?? 0).toDouble(),
  );
}

class RefusedQuestion {
  final String question;
  final int count;

  RefusedQuestion({required this.question, required this.count});

  factory RefusedQuestion.fromJson(Map<String, dynamic> json) =>
      RefusedQuestion(
        question: json['question'] ?? '',
        count: json['count'] ?? 0,
      );
}

class MissingItem {
  final String name;
  final int requestCount;

  MissingItem({required this.name, required this.requestCount});

  // `key` is 'crop' or 'district' — the two endpoints use different field names.
  factory MissingItem.fromJson(Map<String, dynamic> json, String key) =>
      MissingItem(
        name: json[key] ?? '',
        requestCount: json['request_count'] ?? 0,
      );
}

class SuperadminConfig {
  final int adminRateLimitPerMinute;
  final int superadminRateLimitPerMinute;
  final bool enableAdminApi;

  SuperadminConfig({
    required this.adminRateLimitPerMinute,
    required this.superadminRateLimitPerMinute,
    required this.enableAdminApi,
  });

  factory SuperadminConfig.fromJson(Map<String, dynamic> json) =>
      SuperadminConfig(
        adminRateLimitPerMinute: json['admin_rate_limit_per_minute'] ?? 10,
        superadminRateLimitPerMinute:
            json['superadmin_rate_limit_per_minute'] ?? 10,
        enableAdminApi: json['enable_admin_api'] ?? true,
      );
}
