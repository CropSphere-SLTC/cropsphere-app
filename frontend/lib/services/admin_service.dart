// lib/services/admin_service.dart
// Real API calls to admin-only endpoints — requires admin/superadmin role.
// Same Dio + Firebase JWT pattern as api_service.dart.

import 'package:dio/dio.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../config/app_config.dart';
import '../models/admin_models.dart';

class AdminService {
  static final AdminService _instance = AdminService._internal();
  factory AdminService() => _instance;

  late final Dio _dio;

  AdminService._internal() {
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

  // Gates the Admin nav item — 200 means admin/superadmin, 403 means not.
  Future<bool> checkAdminAccess() async {
    try {
      final response = await _dio.get('/api/admin/stats');
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  Future<AdminStats> getStats() async {
    final response = await _dio.get('/api/admin/stats');
    return AdminStats.fromJson(response.data);
  }

  Future<List<AdminUser>> getUsers() async {
    final response = await _dio.get('/api/admin/users');
    final users = response.data['users'] as List;
    return users.map((u) => AdminUser.fromJson(u)).toList();
  }

  Future<void> updateUserRole(String uid, String role) async {
    await _dio.patch('/api/admin/users/$uid/role', data: {'role': role});
  }

  Future<void> setUserBanned(String uid, bool isBanned) async {
    await _dio.patch(
      '/api/admin/users/$uid/ban',
      data: {'is_banned': isBanned},
    );
  }

  Future<void> deleteUser(String uid) async {
    await _dio.delete('/api/admin/users/$uid');
  }

  Future<List<AuditLog>> getAuditLogs() async {
    final response = await _dio.get('/api/admin/audit-logs');
    final logs = response.data['logs'] as List;
    return logs.map((l) => AuditLog.fromJson(l)).toList();
  }
}
