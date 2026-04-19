// lib/services/api_service.dart
// Real API calls — used when AppConfig.useMockServices = false

import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../config/app_config.dart';
import '../models/api_models.dart';

class ApiService {
  static final ApiService _instance = ApiService._internal();
  factory ApiService() => _instance;

  late final Dio _dio;
  final FlutterSecureStorage _storage = const FlutterSecureStorage();

  ApiService._internal() {
    _dio = Dio(
      BaseOptions(
        baseUrl: AppConfig.baseUrl,
        connectTimeout: AppConfig.apiTimeout,
        receiveTimeout: AppConfig.apiTimeout,
        headers: {'Content-Type': 'application/json'},
      ),
    );

    // JWT interceptor — adds Bearer token to every request
    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          final token = await _storage.read(key: 'jwt_token');
          if (token != null) {
            options.headers['Authorization'] = 'Bearer $token';
          }
          return handler.next(options);
        },
        onError: (error, handler) {
          // 401 = token expired, trigger re-login
          if (error.response?.statusCode == 401) {
            // TODO: Navigate to login screen
          }
          return handler.next(error);
        },
      ),
    );
  }

  Future<void> saveToken(String token) async {
    await _storage.write(key: 'jwt_token', value: token);
  }

  Future<void> clearToken() async {
    await _storage.delete(key: 'jwt_token');
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

  Future<bool> checkHealth() async {
    try {
      final response = await _dio.get('/api/health');
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }
}
