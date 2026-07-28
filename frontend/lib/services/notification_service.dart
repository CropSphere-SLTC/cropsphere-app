// lib/services/notification_service.dart
// Admin notification API — the bell badge + panel. Same Dio + Firebase JWT
// pattern as admin_service.dart / superadmin_service.dart. All endpoints are
// require_admin server-side, so both admin and superadmin can read.

import 'package:dio/dio.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../config/app_config.dart';
import '../models/admin_models.dart';

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;

  late final Dio _dio;

  NotificationService._internal() {
    _dio = Dio(
      BaseOptions(
        baseUrl: AppConfig.baseUrl,
        connectTimeout: AppConfig.apiTimeout,
        receiveTimeout: AppConfig.apiTimeout,
        headers: {'Content-Type': 'application/json'},
      ),
    );

    // JWT interceptor — Firebase handles token refresh automatically. One
    // retry on 401 with a forced-refresh token, matching AdminService.
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

  Future<List<AdminNotification>> getNotifications({
    int limit = 20,
    bool unreadOnly = false,
  }) async {
    final response = await _dio.get(
      '/api/admin/notifications',
      queryParameters: {'limit': limit, 'unread_only': unreadOnly},
    );
    final items = response.data['notifications'] as List? ?? [];
    return items
        .map((n) => AdminNotification.fromJson(Map<String, dynamic>.from(n)))
        .toList();
  }

  // The badge poll. Returns 0 on any failure rather than throwing, so a blip
  // never surfaces an error on the dashboard — the badge just shows nothing.
  Future<int> getUnreadCount() async {
    try {
      final response = await _dio.get('/api/admin/notifications/unread-count');
      return response.data['count'] ?? 0;
    } catch (_) {
      return 0;
    }
  }

  Future<void> markRead(String id) async {
    await _dio.post('/api/admin/notifications/$id/read');
  }

  Future<void> markAllRead() async {
    await _dio.post('/api/admin/notifications/read-all');
  }
}
