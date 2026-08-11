// lib/config/app_config.dart
// The backend URL resolves itself. --dart-define=API_BASE_URL=... still wins
// when supplied, but it is an override for pointing at a staging backend, not
// a step anyone has to remember: a plain `flutter build web --release` served
// from any non-localhost host already targets Railway.

import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;

class AppConfig {
  static String get baseUrl {
    const envUrl = String.fromEnvironment('API_BASE_URL');
    if (envUrl.isNotEmpty) return envUrl;

    if (kIsWeb) {
      final host = Uri.base.host;
      if (host == 'localhost' || host == '127.0.0.1') {
        return 'http://localhost:8000';
      }
      // Any other host (Firebase Hosting, custom domain, etc.)
      // defaults to production Railway backend
      return 'https://cropsphere.up.railway.app';
    }
    // Android emulator routes host machine via 10.0.2.2, not localhost
    if (!kIsWeb && Platform.isAndroid) return 'http://10.0.2.2:8000';
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
