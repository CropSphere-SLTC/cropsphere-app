// lib/services/chat_history_service.dart
// Real API calls to chat conversation history endpoints.
// Same Dio + Firebase JWT pattern as api_service.dart / profile_service.dart.

import 'package:dio/dio.dart';
import 'auth_interceptor.dart';
import '../config/app_config.dart';
import '../models/chat_history_models.dart';

class ChatHistoryService {
  static final ChatHistoryService _instance = ChatHistoryService._internal();
  factory ChatHistoryService() => _instance;

  late final Dio _dio;

  ChatHistoryService._internal() {
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

  Future<List<ConversationSummary>> listConversations() async {
    final response = await _dio.get('/api/chat/conversations');
    // Accept both a bare list and a {conversations: [...]} wrapper.
    final data = response.data;
    final list = data is List ? data : (data['conversations'] as List? ?? []);
    return list.map((c) => ConversationSummary.fromJson(c)).toList();
  }

  Future<ConversationDetail> getConversation(String id) async {
    final response = await _dio.get('/api/chat/conversations/$id');
    return ConversationDetail.fromJson(response.data);
  }

  Future<void> renameConversation(String id, String title) async {
    await _dio.patch('/api/chat/conversations/$id', data: {'title': title});
  }

  Future<void> deleteConversation(String id) async {
    await _dio.delete('/api/chat/conversations/$id');
  }
}
