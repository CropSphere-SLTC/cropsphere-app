// lib/services/chat_history_service.dart
// Real API calls to chat conversation history endpoints.
// Same Dio + Firebase JWT pattern as api_service.dart / profile_service.dart.

import 'package:dio/dio.dart';
import 'package:firebase_auth/firebase_auth.dart';
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
