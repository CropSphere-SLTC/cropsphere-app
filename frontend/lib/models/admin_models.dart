// lib/models/admin_models.dart
// Request and response models matching admin_router.py schemas exactly

import 'conversation_models.dart';
import 'pattern_models.dart';

class AdminStats {
  final double cpuPercent;
  final double ramTotalGb;
  final double ramUsedGb;
  final double ramPercent;
  final Map<String, bool> modelsLoaded;
  final int totalRequests;
  final Map<String, int> requestsByEndpoint;

  /// How many audit-log documents `requestsByEndpoint` was computed from. The
  /// server bounds that breakdown to the most recent N requests (the
  /// collection grows without limit), while `totalRequests` stays exact. 0
  /// when the server didn't report it.
  final int requestsSampled;
  final String timestamp;

  AdminStats({
    required this.cpuPercent,
    required this.ramTotalGb,
    required this.ramUsedGb,
    required this.ramPercent,
    required this.modelsLoaded,
    required this.totalRequests,
    required this.requestsByEndpoint,
    required this.requestsSampled,
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
    requestsSampled: json['requests_sampled'] ?? 0,
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

  // Resolved by the backend at read time from the users collection. Empty when
  // the account has since been deleted — the UID is what the log actually
  // stores, so callers fall back to it rather than showing a blank cell.
  final String actorEmail;
  final String targetEmail;

  AuditLog({
    required this.actorUid,
    required this.actorRole,
    required this.action,
    required this.targetUid,
    required this.timestamp,
    required this.details,
    this.actorEmail = '',
    this.targetEmail = '',
  });

  factory AuditLog.fromJson(Map<String, dynamic> json) => AuditLog(
    actorUid: json['actor_uid'] ?? '',
    actorRole: json['actor_role'] ?? '',
    action: json['action'] ?? '',
    targetUid: json['target_uid'] ?? '',
    timestamp: json['timestamp'] ?? '',
    details: Map<String, dynamic>.from(json['details'] ?? {}),
    actorEmail: json['actor_email'] ?? '',
    targetEmail: json['target_email'] ?? '',
  );

  /// What to show for the actor: email when known, UID otherwise.
  String get actorLabel => actorEmail.isNotEmpty ? actorEmail : actorUid;

  /// What to show for the target: email when known, UID otherwise.
  String get targetLabel => targetEmail.isNotEmpty ? targetEmail : targetUid;
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
  final FeedbackSummary feedbackSummary;
  final FewshotInfo fewshot;
  final PatternHealth patternHealth;
  final ConversationHealth conversationHealth;

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
    required this.feedbackSummary,
    required this.fewshot,
    required this.patternHealth,
    required this.conversationHealth,
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
    feedbackSummary: FeedbackSummary.fromJson(
      Map<String, dynamic>.from(json['feedback_summary'] ?? {}),
    ),
    fewshot: FewshotInfo.fromJson(
      Map<String, dynamic>.from(json['fewshot'] ?? {}),
    ),
    patternHealth: PatternHealth.fromJson(
      Map<String, dynamic>.from(json['pattern_health'] ?? {}),
    ),
    conversationHealth: ConversationHealth.fromJson(
      Map<String, dynamic>.from(json['conversation_health'] ?? {}),
    ),
  );
}

class FewshotInfo {
  final bool fileExists;
  final String? updatedAt;
  final Map<String, int> counts; // per question_type
  final int total;

  FewshotInfo({
    required this.fileExists,
    required this.updatedAt,
    required this.counts,
    required this.total,
  });

  factory FewshotInfo.fromJson(Map<String, dynamic> json) => FewshotInfo(
    fileExists: json['file_exists'] ?? false,
    updatedAt: json['updated_at'],
    counts: Map<String, int>.from(json['counts'] ?? {}),
    total: json['total'] ?? 0,
  );
}

class FeedbackSummary {
  final int totalFeedback;
  final int thumbsUp;
  final int thumbsDown;
  final double satisfactionRate;
  final List<RefusedQuestion> mostDownvotedQuestions; // {question, count}

  FeedbackSummary({
    required this.totalFeedback,
    required this.thumbsUp,
    required this.thumbsDown,
    required this.satisfactionRate,
    required this.mostDownvotedQuestions,
  });

  factory FeedbackSummary.fromJson(
    Map<String, dynamic> json,
  ) => FeedbackSummary(
    totalFeedback: json['total_feedback'] ?? 0,
    thumbsUp: json['thumbs_up'] ?? 0,
    thumbsDown: json['thumbs_down'] ?? 0,
    satisfactionRate: (json['satisfaction_rate'] as num? ?? 0).toDouble(),
    mostDownvotedQuestions: ((json['most_downvoted_questions'] ?? []) as List)
        .map((e) => RefusedQuestion.fromJson(Map<String, dynamic>.from(e)))
        .toList(),
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

// ── Security monitoring (GET /api/admin/security/*) ──────────────────────────

class SecuritySummary {
  final int failedLogins;
  final int rateViolations;
  final int bannedAttempts;
  final int activeSessions;
  final int windowHours;

  SecuritySummary({
    required this.failedLogins,
    required this.rateViolations,
    required this.bannedAttempts,
    required this.activeSessions,
    required this.windowHours,
  });

  factory SecuritySummary.fromJson(Map<String, dynamic> json) =>
      SecuritySummary(
        failedLogins: json['failed_logins'] ?? 0,
        rateViolations: json['rate_violations'] ?? 0,
        bannedAttempts: json['banned_attempts'] ?? 0,
        activeSessions: json['active_sessions'] ?? 0,
        windowHours: json['window_hours'] ?? 24,
      );
}

class SecurityEvent {
  final String id;
  final String
  type; // failed_login | rate_limit_violation | banned_access_attempt
  final String uid;
  final String email;
  final String ipAddress;
  final String endpoint;
  final Map<String, dynamic> details;
  final String timestamp;

  SecurityEvent({
    required this.id,
    required this.type,
    required this.uid,
    required this.email,
    required this.ipAddress,
    required this.endpoint,
    required this.details,
    required this.timestamp,
  });

  factory SecurityEvent.fromJson(Map<String, dynamic> json) => SecurityEvent(
    id: json['id']?.toString() ?? '',
    type: json['type'] ?? '',
    uid: json['uid']?.toString() ?? '',
    email: json['email']?.toString() ?? '',
    ipAddress: json['ip_address']?.toString() ?? '',
    endpoint: json['endpoint']?.toString() ?? '',
    details: Map<String, dynamic>.from(json['details'] ?? {}),
    timestamp: json['timestamp']?.toString() ?? '',
  );

  // Identity a rejected token merely asserted. The backend keeps these out of
  // uid/email precisely because its signature never verified — anyone can mint
  // a JWT naming anyone, so this is a lead, not a fact.
  String get claimedEmail => details['claimed_email']?.toString() ?? '';
  String get claimedUid => details['claimed_uid']?.toString() ?? '';

  /// Whether the identity on this event was established by the backend rather
  /// than asserted by the rejected request.
  bool get identityVerified => uid.isNotEmpty || email.isNotEmpty;

  /// Who this event is about, for display. Never returns a claimed identity
  /// without saying so — an admin must not read a forged token's email as
  /// proof that account did anything.
  String get actorLabel {
    if (email.isNotEmpty) return email;
    if (uid.isNotEmpty) return uid;
    if (claimedEmail.isNotEmpty) return '$claimedEmail (unverified)';
    if (claimedUid.isNotEmpty) return '$claimedUid (unverified)';
    return details['reason'] == 'missing_or_malformed_authorization_header'
        ? 'anonymous · no token'
        : 'unidentified';
  }
}

/// Consecutive security events that are really one incident.
///
/// A burst of identical events — the same actor failing login from the same IP
/// eight times in a minute — is one thing that happened, but the raw timeline
/// renders it as eight indistinguishable lines that push everything else off
/// the page. Collapsing them makes the shape of an attack visible: a repeat
/// count is the signal, and the rows it no longer crowds out are the context.
class SecurityEventBurst {
  /// Newest event in the burst; carries the type, identity and endpoint shown.
  final SecurityEvent latest;

  /// Every event in the burst, newest first (length 1 for an ordinary row).
  final List<SecurityEvent> events;

  const SecurityEventBurst(this.latest, this.events);

  int get count => events.length;
  bool get isBurst => events.length > 1;
  String get type => latest.type;

  /// Timestamp of the oldest event — the start of the burst.
  String get firstTimestamp => events.last.timestamp;

  /// Endpoint to display: the shared one, or how many were hit. A spray across
  /// endpoints from one source is itself worth seeing.
  String get endpointLabel {
    final endpoints = events
        .map((e) => e.endpoint)
        .where((e) => e.isNotEmpty)
        .toSet();
    if (endpoints.isEmpty) return '';
    if (endpoints.length == 1) return endpoints.first;
    return '${endpoints.length} endpoints';
  }

  /// Longest gap tolerated between two events of the same burst. Beyond this
  /// they are separate incidents, however alike they look — a failed login
  /// today and an identical one last week are not one event.
  static const Duration window = Duration(minutes: 10);

  /// Collapse a newest-first event list into bursts, preserving order.
  ///
  /// Groups only *adjacent* events sharing type, actor and IP, so the timeline
  /// stays strictly chronological — nothing is reordered or hoisted.
  static List<SecurityEventBurst> group(List<SecurityEvent> events) {
    final out = <SecurityEventBurst>[];
    var current = <SecurityEvent>[];

    bool joins(SecurityEvent e) {
      if (current.isEmpty) return false;
      final prev = current.last;
      if (e.type != prev.type ||
          e.ipAddress != prev.ipAddress ||
          e.actorLabel != prev.actorLabel) {
        return false;
      }
      final a = DateTime.tryParse(prev.timestamp);
      final b = DateTime.tryParse(e.timestamp);
      // Unparseable timestamps only group with an identical neighbour when we
      // can measure the gap; otherwise keep them as their own row.
      if (a == null || b == null) return false;
      return a.difference(b).abs() <= window;
    }

    for (final e in events) {
      if (joins(e)) {
        current.add(e);
      } else {
        if (current.isNotEmpty) {
          out.add(SecurityEventBurst(current.first, current));
        }
        current = [e];
      }
    }
    if (current.isNotEmpty) out.add(SecurityEventBurst(current.first, current));
    return out;
  }
}

class ActiveSession {
  final String uid;
  final String email;
  final String role;
  final String deviceInfo;
  final String sessionStart;
  final String lastActivity;

  ActiveSession({
    required this.uid,
    required this.email,
    required this.role,
    required this.deviceInfo,
    required this.sessionStart,
    required this.lastActivity,
  });

  factory ActiveSession.fromJson(Map<String, dynamic> json) => ActiveSession(
    uid: json['uid']?.toString() ?? '',
    email: json['email']?.toString() ?? '',
    role: json['role']?.toString() ?? '',
    deviceInfo: json['device_info']?.toString() ?? '',
    sessionStart: json['session_start']?.toString() ?? '',
    lastActivity: json['last_activity']?.toString() ?? '',
  );
}

// ── Prompt tuning (superadmin-only, analytics-driven) ────────────────────────

/// One supplementary instruction — either a fresh proposal or a live
/// adjustment part-way through its lifecycle.
///
/// Proposals carry only the first five fields; everything from [status] down is
/// populated once the adjustment has been applied. `recommended` drives the
/// checkbox default in the review UI (false = opt-in).
class PromptTuningAdjustment {
  final String id;
  final String dimension;
  final String trigger;
  final String instruction;
  final bool recommended;

  // Validation contract. A null [validationMetric] or [baselineValue] means the
  // backend cannot judge this adjustment, so it will never be auto-promoted or
  // auto-removed — see [isMeasurable].
  final String? validationMetric;
  final double? baselineValue;

  // Lifecycle. `status` is 'trial' | 'permanent' for active adjustments, and
  // may be 'auto_removed' for one recovered from the trash.
  final String status;
  final String? appliedAt;
  final String? trialEndsAt;
  final int? trialPeriodDays;
  final int extensionsUsed;
  final String? validatedAt;
  final bool needsAttention;
  final String? attentionReason;

  PromptTuningAdjustment({
    required this.id,
    required this.dimension,
    required this.trigger,
    required this.instruction,
    required this.recommended,
    this.validationMetric,
    this.baselineValue,
    this.status = 'trial',
    this.appliedAt,
    this.trialEndsAt,
    this.trialPeriodDays,
    this.extensionsUsed = 0,
    this.validatedAt,
    this.needsAttention = false,
    this.attentionReason,
  });

  /// True when auto-validation can actually judge this one. When false the
  /// adjustment stays live as a trial until a superadmin decides, and the UI
  /// must show "awaiting decision" rather than a trial countdown.
  bool get isMeasurable => validationMetric != null && baselineValue != null;

  bool get isPermanent => status == 'permanent';

  factory PromptTuningAdjustment.fromJson(Map<String, dynamic> json) =>
      PromptTuningAdjustment(
        id: json['id'] ?? '',
        dimension: json['dimension'] ?? '',
        trigger: json['trigger'] ?? '',
        instruction: json['instruction'] ?? '',
        recommended: json['recommended'] ?? true,
        validationMetric: json['validation_metric'],
        baselineValue: _toDouble(json['baseline_value']),
        status: json['status'] ?? 'trial',
        appliedAt: json['applied_at'],
        trialEndsAt: json['trial_ends_at'],
        trialPeriodDays: json['trial_period_days'],
        extensionsUsed: json['extensions_used'] ?? 0,
        validatedAt: json['validated_at'],
        needsAttention: json['needs_attention'] ?? false,
        attentionReason: json['attention_reason'],
      );
}

/// JSON numbers arrive as int or double depending on the value; metric values
/// are always treated as doubles client-side.
double? _toDouble(dynamic value) => value is num ? value.toDouble() : null;

/// One item in the prompt-tuning trash, with its retention deadline.
class TrashedAdjustment {
  final PromptTuningAdjustment adjustment;
  final String trashedAt;
  final String trashedBy;

  /// 'auto_validation_failed' (the system removed it) or 'manual_removal'.
  final String reason;
  final String comment;
  final String? retentionUntil;
  final bool canRestore;

  TrashedAdjustment({
    required this.adjustment,
    required this.trashedAt,
    required this.trashedBy,
    required this.reason,
    required this.comment,
    required this.retentionUntil,
    required this.canRestore,
  });

  bool get wasAutoRemoved => reason == 'auto_validation_failed';

  factory TrashedAdjustment.fromJson(Map<String, dynamic> json) =>
      TrashedAdjustment(
        adjustment: PromptTuningAdjustment.fromJson(
          Map<String, dynamic>.from(json['adjustment'] ?? {}),
        ),
        trashedAt: json['trashed_at'] ?? '',
        trashedBy: json['trashed_by'] ?? '',
        reason: json['reason'] ?? 'manual_removal',
        comment: json['comment'] ?? '',
        retentionUntil: json['retention_until'],
        canRestore: json['can_restore'] ?? true,
      );
}

/// One measurement of a validation metric, at baseline or at "now".
class TuningMetricPoint {
  final String? metricName;
  final double? value;
  final String? measuredAt;

  /// 'improving' | 'stable' | 'worsened' | 'unknown'. Only set on the current
  /// point; the baseline has nothing to compare against.
  final String trend;

  /// Signed so POSITIVE always means better, including for metrics where the
  /// raw number falling is the good outcome (refusal_rate).
  final double? relativeChange;

  TuningMetricPoint({
    required this.metricName,
    required this.value,
    required this.measuredAt,
    this.trend = 'unknown',
    this.relativeChange,
  });

  factory TuningMetricPoint.fromJson(Map<String, dynamic> json) =>
      TuningMetricPoint(
        metricName: json['metric_name'],
        value: _toDouble(json['value']),
        measuredAt: json['measured_at'],
        trend: json['trend'] ?? 'unknown',
        relativeChange: _toDouble(json['relative_change']),
      );
}

/// One entry in an adjustment's audit history.
class TuningAuditEntry {
  final String action;
  final String performedBy;
  final String timestamp;
  final String comment;
  final Map<String, dynamic> details;

  TuningAuditEntry({
    required this.action,
    required this.performedBy,
    required this.timestamp,
    required this.comment,
    required this.details,
  });

  bool get bySystem => performedBy == 'system';

  factory TuningAuditEntry.fromJson(Map<String, dynamic> json) =>
      TuningAuditEntry(
        action: json['action'] ?? '',
        performedBy: json['performed_by'] ?? 'system',
        timestamp: json['timestamp'] ?? '',
        comment: json['comment'] ?? '',
        details: Map<String, dynamic>.from(json['details'] ?? {}),
      );
}

/// GET /api/superadmin/adjustment-analytics/{id} — the before/after comparison
/// behind the adjustment detail screen.
class AdjustmentAnalytics {
  final PromptTuningAdjustment adjustment;

  /// 'trial' | 'permanent' | 'auto_removed' | 'removed'.
  final String status;

  /// Pre-rendered by the backend, e.g. "Day 8 of 14", "Permanent", or
  /// "Day 3 — awaiting manual decision".
  final String trialProgress;
  final int trialDay;
  final int? trialTotalDays;

  final int interactionsDuringTrial;
  final int minSampleRequired;
  final bool sampleMet;
  final int extensionsUsed;
  final int maxExtensions;
  final bool needsAttention;
  final String? attentionReason;

  final TuningMetricPoint baseline;
  final TuningMetricPoint current;

  /// 'on_track_for_permanent' | 'at_risk_of_removal' | 'insufficient_data' |
  /// 'not_measurable' | 'validated_permanent' | 'removed'.
  final String verdict;

  final TrashedAdjustment? trashed;
  final List<TuningAuditEntry> history;

  AdjustmentAnalytics({
    required this.adjustment,
    required this.status,
    required this.trialProgress,
    required this.trialDay,
    required this.trialTotalDays,
    required this.interactionsDuringTrial,
    required this.minSampleRequired,
    required this.sampleMet,
    required this.extensionsUsed,
    required this.maxExtensions,
    required this.needsAttention,
    required this.attentionReason,
    required this.baseline,
    required this.current,
    required this.verdict,
    required this.trashed,
    required this.history,
  });

  bool get isTrial => status == 'trial';
  bool get isRemoved => status == 'auto_removed' || status == 'removed';

  /// Fraction of the trial elapsed, or null when there is no clock to show
  /// (unmeasurable adjustment, or already resolved).
  double? get trialFraction {
    final total = trialTotalDays;
    if (!isTrial || total == null || total <= 0) return null;
    if (adjustment.trialEndsAt == null) return null;
    return (trialDay / total).clamp(0.0, 1.0);
  }

  factory AdjustmentAnalytics.fromJson(Map<String, dynamic> json) =>
      AdjustmentAnalytics(
        adjustment: PromptTuningAdjustment.fromJson(
          Map<String, dynamic>.from(json['adjustment'] ?? {}),
        ),
        status: json['status'] ?? 'trial',
        trialProgress: json['trial_progress'] ?? '',
        trialDay: json['trial_day'] ?? 0,
        trialTotalDays: json['trial_total_days'],
        interactionsDuringTrial: json['interactions_during_trial'] ?? 0,
        minSampleRequired: json['min_sample_required'] ?? 0,
        sampleMet: json['sample_met'] ?? false,
        extensionsUsed: json['extensions_used'] ?? 0,
        maxExtensions: json['max_extensions'] ?? 2,
        needsAttention: json['needs_attention'] ?? false,
        attentionReason: json['attention_reason'],
        baseline: TuningMetricPoint.fromJson(
          Map<String, dynamic>.from(json['baseline'] ?? {}),
        ),
        current: TuningMetricPoint.fromJson(
          Map<String, dynamic>.from(json['current'] ?? {}),
        ),
        verdict: json['verdict'] ?? 'insufficient_data',
        trashed: json['trashed'] == null
            ? null
            : TrashedAdjustment.fromJson(
                Map<String, dynamic>.from(json['trashed']),
              ),
        history: ((json['history'] ?? []) as List)
            .map((e) => TuningAuditEntry.fromJson(Map<String, dynamic>.from(e)))
            .toList(),
      );
}

/// The four superadmin-adjustable lifecycle settings.
class PromptTuningConfig {
  final int minSampleSize;
  final int trialPeriodDays;
  final int trialExtensionDays;
  final int trashRetentionDays;

  PromptTuningConfig({
    required this.minSampleSize,
    required this.trialPeriodDays,
    required this.trialExtensionDays,
    required this.trashRetentionDays,
  });

  factory PromptTuningConfig.fromJson(Map<String, dynamic> json) =>
      PromptTuningConfig(
        minSampleSize: json['min_sample_size'] ?? 20,
        trialPeriodDays: json['trial_period_days'] ?? 14,
        trialExtensionDays: json['trial_extension_days'] ?? 7,
        trashRetentionDays: json['trash_retention_days'] ?? 14,
      );
}

/// A general admin-bell notification (prompt-tuning decision, analytics alert,
/// or any system event). Backed by GET /api/admin/notifications.
class AdminNotification {
  final String id;
  final String type;
  final String title;
  final String message;

  /// 'info' | 'success' | 'warning' | 'error' — drives the card's icon/colour.
  final String severity;
  final bool read;
  final String? createdAt;

  /// e.g. an adjustment_id — carried so a tap can deep-link.
  final String? relatedId;

  /// Client route to open on tap, e.g. '/adjustment/dim1' or '/gap-report'.
  final String? actionUrl;

  AdminNotification({
    required this.id,
    required this.type,
    required this.title,
    required this.message,
    required this.severity,
    required this.read,
    required this.createdAt,
    required this.relatedId,
    required this.actionUrl,
  });

  /// `read` is authoritative from the server; this copy lets the panel show a
  /// card as read immediately after a tap without a refetch.
  AdminNotification copyWith({bool? read}) => AdminNotification(
    id: id,
    type: type,
    title: title,
    message: message,
    severity: severity,
    read: read ?? this.read,
    createdAt: createdAt,
    relatedId: relatedId,
    actionUrl: actionUrl,
  );

  factory AdminNotification.fromJson(Map<String, dynamic> json) =>
      AdminNotification(
        id: json['id'] ?? '',
        type: json['type'] ?? '',
        title: json['title'] ?? '',
        message: json['message'] ?? '',
        severity: json['severity'] ?? 'info',
        read: json['read'] ?? false,
        createdAt: json['created_at'],
        relatedId: json['related_id'],
        actionUrl: json['action_url'],
      );
}

/// Result of POST /analyze-prompt-tuning — proposals, not yet applied.
class PromptTuningProposal {
  final List<PromptTuningAdjustment> adjustments;
  final int periodDays;
  final int sampleSize;

  PromptTuningProposal({
    required this.adjustments,
    required this.periodDays,
    required this.sampleSize,
  });

  factory PromptTuningProposal.fromJson(Map<String, dynamic> json) =>
      PromptTuningProposal(
        adjustments: ((json['proposed_adjustments'] ?? []) as List)
            .map(
              (e) =>
                  PromptTuningAdjustment.fromJson(Map<String, dynamic>.from(e)),
            )
            .toList(),
        periodDays: json['period_days'] ?? 0,
        sampleSize: json['sample_size'] ?? 0,
      );
}

/// Result of GET /active-prompt-tuning — what is live in the prompt now
/// (trial + permanent), plus the counts that drive the section badges.
class ActivePromptTuning {
  final List<PromptTuningAdjustment> adjustments;
  final int count;
  final int trialCount;
  final int permanentCount;
  final int trashCount;
  final String? updatedAt;

  ActivePromptTuning({
    required this.adjustments,
    required this.count,
    required this.trialCount,
    required this.permanentCount,
    required this.trashCount,
    required this.updatedAt,
  });

  factory ActivePromptTuning.fromJson(Map<String, dynamic> json) =>
      ActivePromptTuning(
        adjustments: ((json['active_adjustments'] ?? []) as List)
            .map(
              (e) =>
                  PromptTuningAdjustment.fromJson(Map<String, dynamic>.from(e)),
            )
            .toList(),
        count: json['count'] ?? 0,
        trialCount: json['trial_count'] ?? 0,
        permanentCount: json['permanent_count'] ?? 0,
        trashCount: json['trash_count'] ?? 0,
        updatedAt: json['updated_at'],
      );
}

/// Result of POST /apply-prompt-tuning. `appliedCount` is the source of truth —
/// an approved id that no longer triggers appears in neither list, and one that
/// was already active appears in `skippedIds`.
class ApplyTuningResult {
  final int appliedCount;
  final List<String> appliedIds;
  final List<String> skippedIds;

  ApplyTuningResult({
    required this.appliedCount,
    required this.appliedIds,
    required this.skippedIds,
  });

  factory ApplyTuningResult.fromJson(Map<String, dynamic> json) =>
      ApplyTuningResult(
        appliedCount: json['applied_count'] ?? 0,
        appliedIds: List<String>.from(json['applied_ids'] ?? []),
        skippedIds: List<String>.from(json['skipped_ids'] ?? []),
      );
}
