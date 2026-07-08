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

  ConversationMessage({required this.role, required this.content});

  factory ConversationMessage.fromJson(Map<String, dynamic> json) =>
      ConversationMessage(
        role: json['role'] ?? 'user',
        content: json['content'] ?? '',
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
