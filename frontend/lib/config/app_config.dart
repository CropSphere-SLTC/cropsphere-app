// lib/config/app_config.dart
// ONE LINE CHANGE to connect to real backend:
// Run: flutter run --dart-define=API_BASE_URL=https://your-railway-url.com

import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;

class AppConfig {
  static String get baseUrl {
    if (kIsWeb) {
      // Check if running on localhost (development) or deployed
      final host = Uri.base.host;
      if (host == 'localhost' || host == '127.0.0.1') {
        return 'http://localhost:8000';
      }
      // Production — use Railway backend
      return 'https://cropsphere-app.up.railway.app';
    }
    if (Platform.isAndroid) return 'http://10.0.2.2:8000';
    return 'http://localhost:8000';
  }

  // Set to false when Shifan deploys — switches all services to real API
  static const bool useMockServices = false;

  // Streaming chat (SSE via POST /api/chat/stream). Set false to fall back
  // to the non-streaming POST /api/chat for every message.
  static const bool useStreamingChat = true;

  static const Duration apiTimeout = Duration(seconds: 30);

  // Firebase project
  static const String firebaseProjectId = 'cropsphere';
}
