// lib/services/service_factory.dart
// THE ONE FILE to edit when Shifan deploys.
// Change AppConfig.useMockServices to false in app_config.dart
// and update API_BASE_URL — that's it. Every screen switches automatically.

import '../config/app_config.dart';
import '../models/api_models.dart';
import 'api_service.dart';
import 'mock_service.dart';

class ServiceFactory {
  static final ServiceFactory _instance = ServiceFactory._internal();
  factory ServiceFactory() => _instance;
  ServiceFactory._internal();
  // Static accessor so screens can call ServiceFactory.getService()
  static ServiceFactory getService() => ServiceFactory();

  final ApiService _real = ApiService();
  final MockService _mock = MockService();

  bool get _useMock => AppConfig.useMockServices;

  Future<YieldResponse> predictYield(YieldRequest request) =>
      _useMock ? _mock.predictYield(request) : _real.predictYield(request);

  Future<WeatherResponse> forecastWeather(WeatherRequest request) => _useMock
      ? _mock.forecastWeather(request)
      : _real.forecastWeather(request);

  Future<PriceResponse> predictPrice(PriceRequest request) =>
      _useMock ? _mock.predictPrice(request) : _real.predictPrice(request);

  Future<DemandResponse> predictDemand(DemandRequest request) =>
      _useMock ? _mock.predictDemand(request) : _real.predictDemand(request);

  Future<RecommendResponse> recommendCrop(RecommendRequest request) =>
      _useMock ? _mock.recommendCrop(request) : _real.recommendCrop(request);

  Future<ChatResponse> sendChat(ChatRequest request) =>
      _useMock ? _mock.sendChat(request) : _real.sendChat(request);
}
