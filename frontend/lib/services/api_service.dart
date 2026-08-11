// lib/services/api_service.dart
// Real API calls — used when AppConfig.useMockServices = false

import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'session_recovery.dart';
import '../config/app_config.dart';
import '../models/api_models.dart';

class ApiService {
  static final ApiService _instance = ApiService._internal();
  factory ApiService() => _instance;

  late final Dio _dio;

  ApiService._internal() {
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
              } catch (e) {
                // Refresh failed. If that means the session is gone — a
                // force-logout revoked the refresh token — sign out so the
                // auth gate routes to login rather than stranding the user
                // in an app where every request 401s.
                await endSessionIfRevoked(e);
              }
            }
          }
          return handler.next(error);
        },
      ),
    );
  }

  Future<YieldResponse> predictYield(YieldRequest request) async {
    final response = await _dio.post(
      '/api/yield/predict',
      data: request.toJson(),
    );
    return YieldResponse.fromJson(response.data);
  }

  Future<WeatherResponse> forecastWeather(WeatherRequest request) async {
    final response = await _dio.post(
      '/api/weather/forecast',
      data: request.toJson(),
    );
    return WeatherResponse.fromJson(response.data);
  }

  Future<PriceResponse> predictPrice(PriceRequest request) async {
    final response = await _dio.post(
      '/api/price/predict',
      data: request.toJson(),
    );
    return PriceResponse.fromJson(response.data);
  }

  Future<DemandResponse> predictDemand(DemandRequest request) async {
    final response = await _dio.post(
      '/api/demand/predict',
      data: request.toJson(),
    );
    return DemandResponse.fromJson(response.data);
  }

  Future<RecommendResponse> recommendCrop(RecommendRequest request) async {
    final response = await _dio.post('/api/recommend', data: request.toJson());
    return RecommendResponse.fromJson(response.data);
  }

  Future<ChatResponse> sendChat(ChatRequest request) async {
    final response = await _dio.post('/api/chat', data: request.toJson());
    return ChatResponse.fromJson(response.data);
  }

  /// Streams SSE events from POST /api/chat/stream as decoded JSON maps:
  /// {'type': 'text'|'metadata'|'error'|'done', ...}. The [DONE] sentinel
  /// becomes {'type': 'done'}. Dio-level failures (timeouts, 4xx/5xx before
  /// the stream opens) are mapped to the same error shape the backend uses,
  /// so the chat screen handles one event vocabulary.
  Stream<Map<String, dynamic>> sendChatStream(ChatRequest request) async* {
    ResponseBody body;
    try {
      final response = await _dio.post<ResponseBody>(
        '/api/chat/stream',
        data: request.toJson(),
        options: Options(
          responseType: ResponseType.stream,
          headers: {'Accept': 'text/event-stream'},
        ),
      );
      body = response.data!;
    } on DioException catch (e) {
      yield {'type': 'error', 'code': _dioErrorCode(e)};
      return;
    }
    var buffer = '';
    var sawDone = false;
    try {
      await for (final chunk in body.stream.cast<List<int>>().transform(
        utf8.decoder,
      )) {
        buffer += chunk;
        // SSE events are \n\n-delimited; one network chunk may carry a
        // partial event, so split on complete events only.
        while (buffer.contains('\n\n')) {
          final idx = buffer.indexOf('\n\n');
          final raw = buffer.substring(0, idx).trim();
          buffer = buffer.substring(idx + 2);
          if (!raw.startsWith('data:')) continue;
          final payload = raw.substring(5).trim();
          if (payload == '[DONE]') {
            sawDone = true;
            yield {'type': 'done'};
            return;
          }
          yield jsonDecode(payload) as Map<String, dynamic>;
        }
      }
    } catch (_) {
      yield {'type': 'error', 'code': 'stream_interrupted'};
      return;
    }
    // Connection closed without the [DONE] sentinel — treat as interrupted.
    if (!sawDone) {
      yield {'type': 'error', 'code': 'stream_interrupted'};
    }
  }

  /// Maps dio transport errors to the backend's streaming error codes.
  String _dioErrorCode(DioException e) {
    final status = e.response?.statusCode ?? 0;
    if (status == 401 || status == 403) return 'auth_error';
    if (status == 429) return 'rate_limit';
    if (status >= 500) return 'server_error';
    return 'network'; // timeout / connection refused / no internet
  }

  /// Records a thumbs up/down on a bot reply. Fire-and-forget — the caller
  /// does not await this in the UI and silently ignores failures.
  Future<void> sendFeedback({
    required String conversationId,
    required int messageIndex,
    required String feedback,
    required String messageText,
  }) async {
    await _dio.post(
      '/api/chat/feedback',
      data: {
        'conversation_id': conversationId,
        'message_index': messageIndex,
        'feedback': feedback,
        'message_text': messageText,
      },
    );
  }

  /// Returns this user's thumbs votes for a conversation as
  /// {messageIndex: 'up'|'down'}, so feedback survives a page reload. JSON
  /// object keys arrive as strings and are parsed back to ints.
  Future<Map<int, String>> getConversationFeedback(
    String conversationId,
  ) async {
    final response = await _dio.get('/api/chat/feedback/$conversationId');
    final votes = (response.data['votes'] as Map?) ?? {};
    return votes.map((k, v) => MapEntry(int.parse(k.toString()), v.toString()));
  }

  Future<bool> checkHealth() async {
    try {
      final response = await _dio.get('/api/health');
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }
}
