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
