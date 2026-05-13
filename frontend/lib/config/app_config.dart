// lib/config/app_config.dart

class AppConfig {
  static const String baseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://localhost:8000',
  );

  // Real ML models — never use mock
  static const bool useMockServices = false;

  // General API timeout (yield, price, weather, demand, recommend)
  static const Duration apiTimeout = Duration(seconds: 60);

  // Chatbot timeout — Groq LLaMA 3 + RAG needs more time
  static const Duration chatTimeout = Duration(seconds: 120);

  // Firebase project
  static const String firebaseProjectId = 'cropsphere-2e87c';
}
