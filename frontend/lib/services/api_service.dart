// lib/services/api_service.dart
// Real API calls — used when AppConfig.useMockServices = false

import 'package:dio/dio.dart';
import 'package:firebase_auth/firebase_auth.dart';
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
        onError: (error, handler) async {
          // Never auto-signout on 401 — this would redirect the user to
          // LoginScreen instead of showing the error on the prediction screen.
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

  Future<bool> checkHealth() async {
    try {
      final response = await _dio.get('/api/health');
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }
}
