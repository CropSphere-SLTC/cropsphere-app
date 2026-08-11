// lib/models/pattern_models.dart
// Models for the pattern-override feature — admin-approved routing phrases that
// supplement the chatbot's hardcoded pattern lists.
//
// Lifecycle mirrored from the backend (pattern_override_store):
//   proposed ──approve──> active ──revoke──> revoked ──retention──> deleted
//                            ▲                   │
//                            └─────restore───────┘
//
// Every fromJson is defensive about missing keys: these screens must render
// against an overrides file that has never been written.

/// One phrase the analyzer suggests adding, before any admin decision.
class ProposedPattern {
  final String id;
  final String category;
  final String proposedPhrase;
  final String patternType;
  final int evidenceCount;
  final List<String> exampleMessages;
  final String confidence; // high | medium | low
  final bool recommended;

  ProposedPattern({
    required this.id,
    required this.category,
    required this.proposedPhrase,
    required this.patternType,
    required this.evidenceCount,
    required this.exampleMessages,
    required this.confidence,
    required this.recommended,
  });

  factory ProposedPattern.fromJson(Map<String, dynamic> json) =>
      ProposedPattern(
        id: json['id'] ?? '',
        category: json['category'] ?? '',
        proposedPhrase: json['proposed_phrase'] ?? '',
        patternType: json['pattern_type'] ?? 'phrase',
        evidenceCount: json['evidence_count'] ?? 0,
        exampleMessages: List<String>.from(
          json['example_messages'] ?? const [],
        ),
        confidence: json['confidence'] ?? 'low',
        recommended: json['recommended'] ?? false,
      );
}

class PatternAnalysis {
  final String analyzedAt;
  final int periodDays;
  final int totalAnalyzed;
  final List<ProposedPattern> proposedPatterns;

  PatternAnalysis({
    required this.analyzedAt,
    required this.periodDays,
    required this.totalAnalyzed,
    required this.proposedPatterns,
  });

  factory PatternAnalysis.fromJson(Map<String, dynamic> json) =>
      PatternAnalysis(
        analyzedAt: json['analyzed_at'] ?? '',
        periodDays: json['period_days'] ?? 0,
        totalAnalyzed: json['total_analyzed'] ?? 0,
        proposedPatterns: ((json['proposed_patterns'] ?? []) as List)
            .map((e) => ProposedPattern.fromJson(Map<String, dynamic>.from(e)))
            .toList(),
      );
}

class PatternFeedback {
  final int thumbsUp;
  final int thumbsDown;
  final int noFeedback;

  PatternFeedback({
    required this.thumbsUp,
    required this.thumbsDown,
    required this.noFeedback,
  });

  int get rated => thumbsUp + thumbsDown;

  factory PatternFeedback.fromJson(Map<String, dynamic> json) =>
      PatternFeedback(
        thumbsUp: json['thumbs_up'] ?? 0,
        thumbsDown: json['thumbs_down'] ?? 0,
        noFeedback: json['no_feedback'] ?? 0,
      );
}

/// An override the chatbot is matching right now (or, once revoked, the frozen
/// record of one it used to match).
class PatternOverride {
  final String id;
  final String category;
  final String phrase;
  final String originalProposedPhrase;
  final bool edited;
  final String status; // active | revoked
  final String? appliedAt;
  final int evidenceCount;
  final int hitCount;
  final String? lastHit;
  final PatternFeedback feedback;
  final double satisfactionRate;
  final String verdict;

  // Revoked-only fields.
  final String? revokedAt;
  final String? revokeReason;
  final String? retentionUntil;
  final int? daysRemaining;
  final PatternPerformance? performanceAtRevoke;

  PatternOverride({
    required this.id,
    required this.category,
    required this.phrase,
    required this.originalProposedPhrase,
    required this.edited,
    required this.status,
    required this.appliedAt,
    required this.evidenceCount,
    required this.hitCount,
    required this.lastHit,
    required this.feedback,
    required this.satisfactionRate,
    required this.verdict,
    this.revokedAt,
    this.revokeReason,
    this.retentionUntil,
    this.daysRemaining,
    this.performanceAtRevoke,
  });

  bool get isRevoked => status == 'revoked';

  factory PatternOverride.fromJson(Map<String, dynamic> json) {
    final performance = json['performance_at_revoke'];
    return PatternOverride(
      id: json['id'] ?? '',
      category: json['category'] ?? '',
      phrase: json['phrase'] ?? '',
      originalProposedPhrase:
          json['original_proposed_phrase'] ?? json['phrase'] ?? '',
      edited: json['edited'] ?? false,
      status: json['status'] ?? 'active',
      appliedAt: json['applied_at'],
      evidenceCount: json['evidence_count'] ?? 0,
      hitCount: json['hit_count'] ?? 0,
      lastHit: json['last_hit'],
      feedback: PatternFeedback.fromJson(
        Map<String, dynamic>.from(json['feedback'] ?? {}),
      ),
      satisfactionRate: (json['satisfaction_rate'] as num? ?? 0).toDouble(),
      // Revoked items come straight from the file and carry no computed
      // verdict — they are judged by their frozen snapshot instead.
      verdict: json['verdict'] ?? 'insufficient_data',
      revokedAt: json['revoked_at'],
      revokeReason: json['revoke_reason'],
      retentionUntil: json['retention_until'],
      daysRemaining: json['days_remaining'],
      performanceAtRevoke: performance is Map
          ? PatternPerformance.fromJson(Map<String, dynamic>.from(performance))
          : null,
    );
  }
}

/// The frozen counters captured the moment a pattern was revoked.
class PatternPerformance {
  final int hitCount;
  final int thumbsUp;
  final int thumbsDown;
  final double satisfaction;

  PatternPerformance({
    required this.hitCount,
    required this.thumbsUp,
    required this.thumbsDown,
    required this.satisfaction,
  });

  factory PatternPerformance.fromJson(Map<String, dynamic> json) =>
      PatternPerformance(
        hitCount: json['hit_count'] ?? 0,
        thumbsUp: json['thumbs_up'] ?? 0,
        thumbsDown: json['thumbs_down'] ?? 0,
        satisfaction: (json['satisfaction'] as num? ?? 0).toDouble(),
      );
}

class ActivePatterns {
  final List<PatternOverride> active;
  final Map<String, List<PatternOverride>> byCategory;
  final int revokedCount;
  final String? lastAnalysisAt;

  ActivePatterns({
    required this.active,
    required this.byCategory,
    required this.revokedCount,
    required this.lastAnalysisAt,
  });

  factory ActivePatterns.fromJson(Map<String, dynamic> json) {
    final grouped = <String, List<PatternOverride>>{};
    final raw = json['by_category'];
    if (raw is Map) {
      raw.forEach((key, value) {
        grouped['$key'] = ((value ?? []) as List)
            .map((e) => PatternOverride.fromJson(Map<String, dynamic>.from(e)))
            .toList();
      });
    }
    return ActivePatterns(
      active: ((json['active'] ?? []) as List)
          .map((e) => PatternOverride.fromJson(Map<String, dynamic>.from(e)))
          .toList(),
      byCategory: grouped,
      revokedCount: json['revoked_count'] ?? 0,
      lastAnalysisAt: json['last_analysis_at'],
    );
  }
}

/// One recorded match of an override, with the vote it later attracted.
class PatternHit {
  final String message;
  final String? matchedPhrase;
  final String? timestamp;
  final String? feedback; // up | down | null

  PatternHit({
    required this.message,
    required this.matchedPhrase,
    required this.timestamp,
    required this.feedback,
  });

  factory PatternHit.fromJson(Map<String, dynamic> json) => PatternHit(
    message: json['message'] ?? '',
    matchedPhrase: json['matched_phrase'],
    timestamp: json['timestamp'],
    feedback: json['feedback'],
  );
}

class PatternAuditEntry {
  final String action;
  final String performedBy;
  final String timestamp;
  final Map<String, dynamic> details;

  PatternAuditEntry({
    required this.action,
    required this.performedBy,
    required this.timestamp,
    required this.details,
  });

  factory PatternAuditEntry.fromJson(Map<String, dynamic> json) =>
      PatternAuditEntry(
        action: json['action'] ?? '',
        performedBy: json['performed_by'] ?? '',
        timestamp: json['timestamp'] ?? '',
        details: Map<String, dynamic>.from(json['details'] ?? {}),
      );
}

class PatternAnalytics {
  final PatternOverride pattern;
  final int hitCount;
  final String? lastHit;
  final PatternFeedback feedback;
  final double satisfactionRate;
  final double hitRatePerDay;
  final List<PatternHit> exampleHits;
  final List<PatternHit> falsePositiveCandidates;
  final String verdict;
  final List<PatternAuditEntry> history;

  PatternAnalytics({
    required this.pattern,
    required this.hitCount,
    required this.lastHit,
    required this.feedback,
    required this.satisfactionRate,
    required this.hitRatePerDay,
    required this.exampleHits,
    required this.falsePositiveCandidates,
    required this.verdict,
    required this.history,
  });

  factory PatternAnalytics.fromJson(
    Map<String, dynamic> json,
  ) => PatternAnalytics(
    pattern: PatternOverride.fromJson(
      Map<String, dynamic>.from(json['pattern'] ?? {}),
    ),
    hitCount: json['hit_count'] ?? 0,
    lastHit: json['last_hit'],
    feedback: PatternFeedback.fromJson(
      Map<String, dynamic>.from(json['feedback'] ?? {}),
    ),
    satisfactionRate: (json['satisfaction_rate'] as num? ?? 0).toDouble(),
    hitRatePerDay: (json['hit_rate_per_day'] as num? ?? 0).toDouble(),
    exampleHits: ((json['example_hits'] ?? []) as List)
        .map((e) => PatternHit.fromJson(Map<String, dynamic>.from(e)))
        .toList(),
    falsePositiveCandidates: ((json['false_positive_candidates'] ?? []) as List)
        .map((e) => PatternHit.fromJson(Map<String, dynamic>.from(e)))
        .toList(),
    verdict: json['verdict'] ?? 'insufficient_data',
    history: ((json['history'] ?? []) as List)
        .map((e) => PatternAuditEntry.fromJson(Map<String, dynamic>.from(e)))
        .toList(),
  );
}

/// Pattern Health block inside the gap report.
class PatternHealth {
  final int activeCount;
  final int revokedCount;
  final int totalHits;
  final int hitsThisPeriod;
  final double avgSatisfaction;
  final int needsReviewCount;
  final String? lastAnalysisAt;

  PatternHealth({
    required this.activeCount,
    required this.revokedCount,
    required this.totalHits,
    required this.hitsThisPeriod,
    required this.avgSatisfaction,
    required this.needsReviewCount,
    required this.lastAnalysisAt,
  });

  factory PatternHealth.fromJson(Map<String, dynamic> json) => PatternHealth(
    activeCount: json['active_count'] ?? 0,
    revokedCount: json['revoked_count'] ?? 0,
    totalHits: json['total_hits'] ?? 0,
    hitsThisPeriod: json['hits_this_period'] ?? 0,
    avgSatisfaction: (json['avg_satisfaction'] as num? ?? 0).toDouble(),
    needsReviewCount: json['needs_review_count'] ?? 0,
    lastAnalysisAt: json['last_analysis_at'],
  );
}

/// One rejected selection from an apply call, with the server's reason.
class SkippedPattern {
  final String id;
  final String reason;

  SkippedPattern({required this.id, required this.reason});

  factory SkippedPattern.fromJson(Map<String, dynamic> json) =>
      SkippedPattern(id: json['id'] ?? '', reason: json['reason'] ?? '');
}

class ApplyPatternsResult {
  final int appliedCount;
  final List<String> appliedIds;
  final List<SkippedPattern> skipped;

  ApplyPatternsResult({
    required this.appliedCount,
    required this.appliedIds,
    required this.skipped,
  });

  factory ApplyPatternsResult.fromJson(Map<String, dynamic> json) =>
      ApplyPatternsResult(
        appliedCount: json['applied_count'] ?? 0,
        appliedIds: List<String>.from(json['applied_ids'] ?? const []),
        skipped: ((json['skipped'] ?? []) as List)
            .map((e) => SkippedPattern.fromJson(Map<String, dynamic>.from(e)))
            .toList(),
      );
}
