// lib/models/chat_history_models.dart
// Models for the chat conversation history endpoints.

class ConversationSummary {
  final String id;
  final String title;
  final DateTime? updatedAt;
  final int messageCount;

  ConversationSummary({
    required this.id,
    required this.title,
    this.updatedAt,
    required this.messageCount,
  });

  factory ConversationSummary.fromJson(Map<String, dynamic> json) =>
      ConversationSummary(
        id: json['id'] ?? '',
        title: json['title'] ?? '',
        updatedAt: json['updated_at'] != null
            ? DateTime.tryParse(json['updated_at'])
            : null,
        messageCount: json['message_count'] ?? 0,
      );
}

class ConversationMessage {
  final String role;
  final String content;
  // Backend sends this per-message (schemas.ConversationMessage.timestamp)
  // but the frontend was never parsing it, which silently disabled the
  // chat screen's tap/hover-to-reveal timestamp for every message loaded
  // from history (it only had a value for messages created this session).
  final DateTime? timestamp;

  ConversationMessage({
    required this.role,
    required this.content,
    this.timestamp,
  });

  factory ConversationMessage.fromJson(Map<String, dynamic> json) =>
      ConversationMessage(
        role: json['role'] ?? 'user',
        content: json['content'] ?? '',
        timestamp: json['timestamp'] != null
            ? DateTime.tryParse(json['timestamp'])
            : null,
      );
}

class ConversationDetail {
  final String id;
  final String title;
  final List<ConversationMessage> messages;

  ConversationDetail({
    required this.id,
    required this.title,
    required this.messages,
  });

  factory ConversationDetail.fromJson(Map<String, dynamic> json) =>
      ConversationDetail(
        id: json['id'] ?? '',
        title: json['title'] ?? '',
        messages: (json['messages'] as List? ?? [])
            .map((m) => ConversationMessage.fromJson(m))
            .toList(),
      );
}
