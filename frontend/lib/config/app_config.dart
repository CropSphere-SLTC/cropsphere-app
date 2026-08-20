// lib/config/app_config.dart
// The backend URL resolves itself. --dart-define=API_BASE_URL=... still wins
// when supplied, but it is an override for pointing at a staging backend, not
// a step anyone has to remember: a plain `flutter build web --release` served
// from any non-localhost host already targets Railway.

import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kDebugMode, kIsWeb;

class AppConfig {
  static String get baseUrl {
    const envUrl = String.fromEnvironment('API_BASE_URL');
    if (envUrl.isNotEmpty) return envUrl;

    if (kIsWeb) {
      final host = Uri.base.host;
      if (host == 'localhost' || host == '127.0.0.1') {
        return 'http://localhost:8000';
      }
      return 'https://cropsphere.up.railway.app';
    }

    // Only use 10.0.2.2 for Android emulator during local debug testing,
    // and only when explicitly opted in — most debug runs are on a
    // physical device, which can't reach the host machine via 10.0.2.2.
    const useEmulatorLoopback = bool.fromEnvironment(
      'USE_EMULATOR_LOOPBACK',
      defaultValue: false,
    );
    if (kDebugMode && Platform.isAndroid && useEmulatorLoopback) {
      return 'http://10.0.2.2:8000';
    }

    // Everything else (release builds, real devices, iOS, etc.) uses Railway
    return 'https://cropsphere.up.railway.app';
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
