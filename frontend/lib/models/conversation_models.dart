// lib/models/conversation_models.dart
// Conversation analytics models — the Conversation Health block of the gap
// report. Mirrors backend conversation_miner_service.conversation_health().
//
// Follow-up chips are generated per reply by the LLM and validated against RAG,
// so there is no chip configuration to model any more. What survives here is
// purely descriptive: how long conversations run, where farmers abandon them,
// which flows are common, and whether chips are still being tapped.

/// One response state's drop-off rates. `secondaryRate` is the useful
/// alternative to leaving — rephrasing, continuing, or getting an answer.
class ConversationDropOffBucket {
  final int sampleSize;
  final double leaveRate;
  final double secondaryRate;
  final String secondaryLabel;

  ConversationDropOffBucket({
    required this.sampleSize,
    required this.leaveRate,
    required this.secondaryRate,
    required this.secondaryLabel,
  });

  factory ConversationDropOffBucket.fromJson(
    Map<String, dynamic> json,
    String secondaryKey,
    String secondaryLabel,
  ) => ConversationDropOffBucket(
    sampleSize: json['sample_size'] ?? 0,
    leaveRate: (json['leave_rate'] as num? ?? 0).toDouble(),
    secondaryRate: (json[secondaryKey] as num? ?? 0).toDouble(),
    secondaryLabel: secondaryLabel,
  );
}

class ConversationDropOff {
  final ConversationDropOffBucket afterRefusal;
  final ConversationDropOffBucket afterLowConfidence;
  final ConversationDropOffBucket afterClarification;

  ConversationDropOff({
    required this.afterRefusal,
    required this.afterLowConfidence,
    required this.afterClarification,
  });

  factory ConversationDropOff.fromJson(Map<String, dynamic> json) =>
      ConversationDropOff(
        afterRefusal: ConversationDropOffBucket.fromJson(
          Map<String, dynamic>.from(json['after_refusal'] ?? {}),
          'rephrase_rate',
          'rephrased',
        ),
        afterLowConfidence: ConversationDropOffBucket.fromJson(
          Map<String, dynamic>.from(json['after_low_confidence'] ?? {}),
          'continue_rate',
          'continued',
        ),
        afterClarification: ConversationDropOffBucket.fromJson(
          Map<String, dynamic>.from(json['after_clarification'] ?? {}),
          'answer_rate',
          'answered',
        ),
      );

  Map<String, ConversationDropOffBucket> get all => {
    'After refusal': afterRefusal,
    'After low confidence': afterLowConfidence,
    'After clarification': afterClarification,
  };
}

/// One question-type sequence farmers followed, e.g. "yield → price".
class ConversationFlow {
  final String flow;
  final int count;

  ConversationFlow({required this.flow, required this.count});

  factory ConversationFlow.fromJson(Map<String, dynamic> json) =>
      ConversationFlow(flow: json['flow'] ?? '', count: json['count'] ?? 0);
}

class QuestionTypeDropOff {
  final String questionType;
  final int turns;
  final double leaveRate;

  QuestionTypeDropOff({
    required this.questionType,
    required this.turns,
    required this.leaveRate,
  });

  factory QuestionTypeDropOff.fromJson(Map<String, dynamic> json) =>
      QuestionTypeDropOff(
        questionType: json['question_type'] ?? '',
        turns: json['turns'] ?? 0,
        leaveRate: (json['leave_rate'] as num? ?? 0).toDouble(),
      );
}

/// Chip tap rate this week vs last — now measuring LLM-generated chips.
class ChipTapTrend {
  final double thisWeek;
  final double lastWeek;
  final double change;

  ChipTapTrend({
    required this.thisWeek,
    required this.lastWeek,
    required this.change,
  });

  factory ChipTapTrend.fromJson(Map<String, dynamic> json) => ChipTapTrend(
    thisWeek: (json['this_week'] as num? ?? 0).toDouble(),
    lastWeek: (json['last_week'] as num? ?? 0).toDouble(),
    change: (json['change'] as num? ?? 0).toDouble(),
  );
}

/// Conversation Health block inside the gap report.
class ConversationHealth {
  final int totalConversations;
  final double avgConversationLength;
  final double singleTurnRate;
  final ConversationDropOff dropOffByResponse;
  final List<QuestionTypeDropOff> dropOffByQuestionType;
  final List<ConversationFlow> topFlows;
  final List<ConversationFlow> problemFlows;
  final ChipTapTrend chipTapTrend;

  ConversationHealth({
    required this.totalConversations,
    required this.avgConversationLength,
    required this.singleTurnRate,
    required this.dropOffByResponse,
    required this.dropOffByQuestionType,
    required this.topFlows,
    required this.problemFlows,
    required this.chipTapTrend,
  });

  factory ConversationHealth.fromJson(
    Map<String, dynamic> json,
  ) => ConversationHealth(
    totalConversations: json['total_conversations'] ?? 0,
    avgConversationLength: (json['avg_conversation_length'] as num? ?? 0)
        .toDouble(),
    singleTurnRate: (json['single_turn_rate'] as num? ?? 0).toDouble(),
    dropOffByResponse: ConversationDropOff.fromJson(
      Map<String, dynamic>.from(json['drop_off_by_response'] ?? {}),
    ),
    dropOffByQuestionType: ((json['drop_off_by_question_type'] ?? []) as List)
        .map((d) => QuestionTypeDropOff.fromJson(Map<String, dynamic>.from(d)))
        .toList(),
    topFlows: ((json['top_flows'] ?? []) as List)
        .map((f) => ConversationFlow.fromJson(Map<String, dynamic>.from(f)))
        .toList(),
    problemFlows: ((json['problem_flows'] ?? []) as List)
        .map((f) => ConversationFlow.fromJson(Map<String, dynamic>.from(f)))
        .toList(),
    chipTapTrend: ChipTapTrend.fromJson(
      Map<String, dynamic>.from(json['chip_tap_trend'] ?? {}),
    ),
  );
}
