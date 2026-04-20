// lib/config/app_config.dart
// ONE LINE CHANGE to connect to real backend:
// Run: flutter run --dart-define=API_BASE_URL=https://your-railway-url.com

class AppConfig {
  static const String baseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://localhost:8000',
  );

  // Set to false when Shifan deploys — switches all services to real API
  static const bool useMockServices = true;

  static const Duration apiTimeout = Duration(seconds: 30);

  // Firebase project
  static const String firebaseProjectId = 'cropsphere';
}
