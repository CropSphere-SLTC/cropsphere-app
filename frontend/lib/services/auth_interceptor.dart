// lib/services/auth_interceptor.dart
// Shared Firebase-JWT Dio interceptor. Attaches the bearer token to every
// outgoing request and, on a 401, forces a token refresh and retries once.
// If the refresh itself fails in a way that means the session is gone, hands
// off to session_recovery to sign the user out.
//
// Every service client (api, admin, superadmin, profile, notification, chat
// history) used to carry its own copy of this block — centralized here so
// the retry/refresh/sign-out behavior lives in exactly one place.
//
// The three callback parameters below default to the real FirebaseAuth
// singleton and exist purely as a testing seam: FirebaseAuth.instance cannot
// run in a plain `flutter_test` VM (no platform channels), so
// test/auth/refresh_flow_test.dart substitutes fakes for these instead of
// testing a hand-copied mirror of this logic.

import 'dart:async';

import 'package:dio/dio.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'session_recovery.dart';

/// Reads the current Firebase ID token without forcing a refresh, or null
/// if nobody is signed in.
typedef TokenReader = Future<String?> Function();

/// Forces a Firebase ID token refresh for the current user. Throws if there
/// is no signed-in user or the refresh itself fails — matching
/// User.getIdToken(true)'s own contract.
typedef TokenRefresher = Future<String?> Function();

/// Invoked when a forced refresh throws. The production default
/// (session_recovery.endSessionIfRevoked) decides whether that means the
/// session is over and signs out if so.
typedef RefreshFailureHandler = Future<void> Function(Object error);

Future<String?> _defaultReadToken() async {
  final user = FirebaseAuth.instance.currentUser;
  if (user == null) return null;
  return user.getIdToken();
}

Future<String?> _defaultRefreshToken() async {
  final user = FirebaseAuth.instance.currentUser;
  if (user == null) {
    throw StateError('No signed-in user to refresh a token for');
  }
  return user.getIdToken(true);
}

// Shared across every Dio client this factory has ever built — all of them
// ultimately refresh the same signed-in user's Firebase ID token, so N
// requests failing with 401 at the same moment (same service or different
// services) should trigger exactly one refresh, not N. Module-level rather
// than per-interceptor because the "one shared login session" it protects is
// itself app-wide, not per-service.
Future<String?>? _inFlightRefresh;

Future<String?> _sharedRefresh(TokenRefresher refreshToken) {
  final existing = _inFlightRefresh;
  if (existing != null) return existing;

  // A Completer, not refreshToken() directly: every caller of _sharedRefresh
  // awaits completer.future, so refreshToken()'s own success/error is fully
  // handled right here (see try/catch below) before being forwarded — no
  // second, un-awaited listener is ever attached to refreshToken()'s Future,
  // which is what an earlier .whenComplete()-based version got wrong: that
  // left a derived Future nobody awaited, and Dart reports an unhandled
  // rejection on it even though the real await elsewhere caught the error
  // just fine.
  final completer = Completer<String?>();
  _inFlightRefresh = completer.future;
  () async {
    try {
      completer.complete(await refreshToken());
    } catch (e, st) {
      completer.completeError(e, st);
    } finally {
      // Clear the slot once this refresh settles (success or failure) so
      // the *next* 401 — a genuinely new expiry, not one of this batch —
      // starts a fresh refresh instead of replaying a stale result forever.
      if (identical(_inFlightRefresh, completer.future)) {
        _inFlightRefresh = null;
      }
    }
  }();
  return completer.future;
}

/// extra[] key marking a request that has already gone through one
/// refresh-and-retry cycle. dio.fetch() below re-enters the full interceptor
/// pipeline, including this same onError — without this guard, a retried
/// request that *also* comes back 401 (stale token propagated by a caller's
/// own fake in a test, or any other cause) recurses through onError with no
/// depth limit. The docstring above already promised "retries once"; this
/// makes that literally true instead of merely typical.
const _retriedKey = '_firebaseAuthInterceptor.retried';

InterceptorsWrapper firebaseAuthInterceptor(
  Dio dio, {
  TokenReader readToken = _defaultReadToken,
  TokenRefresher refreshToken = _defaultRefreshToken,
  RefreshFailureHandler onRefreshFailure = endSessionIfRevoked,
}) {
  return InterceptorsWrapper(
    onRequest: (options, handler) async {
      final token = await readToken();
      if (token != null) {
        options.headers['Authorization'] = 'Bearer $token';
      }
      return handler.next(options);
    },
    onError: (DioException error, ErrorInterceptorHandler handler) async {
      final alreadyRetried = error.requestOptions.extra[_retriedKey] == true;
      if (error.response?.statusCode == 401 && !alreadyRetried) {
        try {
          // Token may have expired — force a refresh (shared with any other
          // request failing at the same moment) and retry once.
          final newToken = await _sharedRefresh(refreshToken);
          final opts = error.requestOptions;
          opts.extra[_retriedKey] = true;
          opts.headers['Authorization'] = 'Bearer $newToken';
          final response = await dio.fetch(opts);
          return handler.resolve(response);
        } catch (e) {
          // Refresh failed. If that means the session is gone — a
          // force-logout revoked the refresh token — sign out so the
          // auth gate routes to login rather than stranding the user
          // in an app where every request 401s.
          await onRefreshFailure(e);
        }
      }
      return handler.next(error);
    },
  );
}
