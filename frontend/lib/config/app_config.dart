// lib/config/app_config.dart
// ONE LINE CHANGE to connect to real backend:
// Run: flutter run --dart-define=API_BASE_URL=https://your-railway-url.com

import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;

class AppConfig {
  static String get baseUrl {
    const envUrl = String.fromEnvironment('API_BASE_URL');
    if (envUrl.isNotEmpty) return envUrl;
    // Android emulator routes host machine via 10.0.2.2, not localhost
    if (!kIsWeb && Platform.isAndroid) return 'http://10.0.2.2:8000';
    return 'http://localhost:8000';
  }

  // Set to false when Shifan deploys — switches all services to real API
  static const bool useMockServices = false;

  static const Duration apiTimeout = Duration(seconds: 30);

  // Firebase project
  static const String firebaseProjectId = 'cropsphere';
}
