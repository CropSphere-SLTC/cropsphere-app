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
  late final Dio _chatDio; // separate client with longer timeout for chatbot

  ApiService._internal() {
    _dio = Dio(
      BaseOptions(
        baseUrl: AppConfig.baseUrl,
        connectTimeout: AppConfig.apiTimeout,
        receiveTimeout: AppConfig.apiTimeout,
        headers: {'Content-Type': 'application/json'},
      ),
    );

    _chatDio = Dio(
      BaseOptions(
        baseUrl: AppConfig.baseUrl,
        connectTimeout: AppConfig.apiTimeout,
        receiveTimeout: AppConfig.chatTimeout, // 120 seconds for LLaMA 3 + RAG
        headers: {'Content-Type': 'application/json'},
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
          if (error.response?.statusCode == 401) {
            await FirebaseAuth.instance.signOut();
          }
          return handler.next(error);
        },
      ),
    );

    // Add JWT interceptor to both clients
    final interceptor = InterceptorsWrapper(
      onRequest: (options, handler) async {
        final user = FirebaseAuth.instance.currentUser;
        if (user != null) {
          final token = await user.getIdToken();
          options.headers['Authorization'] = 'Bearer $token';
        }
        return handler.next(options);
      },
      onError: (error, handler) async {
        if (error.response?.statusCode == 401) {
          await FirebaseAuth.instance.signOut();
        }
        return handler.next(error);
      },
    );

    _dio.interceptors.add(interceptor);
    _chatDio.interceptors.add(interceptor);
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
    // Use _chatDio with 120s timeout — Groq LLaMA 3 + RAG needs more time
    final response = await _chatDio.post('/api/chat', data: request.toJson());
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