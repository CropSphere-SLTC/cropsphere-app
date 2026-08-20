// test/auth/refresh_flow_test.dart
//
// Scenario 2 from the audit request ("refresh flow"), exercised against the
// REAL firebaseAuthInterceptor from lib/services/auth_interceptor.dart — not
// a hand-copied mirror. That's possible because the interceptor takes
// injectable readToken/refreshToken/onRefreshFailure callbacks (added
// alongside this test suite specifically so it could be tested for real);
// FirebaseAuth.instance itself still cannot run in a plain flutter_test VM,
// so every test below supplies fakes for those three seams instead of
// touching the singleton.
//
// Requests are driven through a real local HttpServer (dart:io), the same
// pattern test/sse_stream_probe_test.dart already established in this repo,
// so this is genuine Dio-transport-level coverage, not a mocked Dio client.
//
// This file originally caught two real gaps in auth_interceptor.dart — a
// refresh stampede on concurrent 401s (no shared in-flight refresh) and
// unbounded retry recursion (a retried request that also 401s would
// recurse through onError with no depth limit). Both are now fixed in the
// interceptor (a module-level shared-refresh guard, and a one-retry-only
// marker on each request's extra[]) — the corresponding tests below assert
// the fixed behavior rather than documenting the gap.

import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cropsphere_app/services/auth_interceptor.dart';
import 'package:cropsphere_app/services/session_recovery.dart';

/// Starts a loopback HTTP server driven by [handler] and returns it plus a
/// ready-to-use Dio baseUrl.
Future<(HttpServer, String)> _startServer(
  void Function(HttpRequest req, int requestIndex) handler,
) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  var i = 0;
  server.listen((req) {
    i++;
    handler(req, i);
  });
  return (server, 'http://127.0.0.1:${server.port}');
}

void main() {
  group('Refresh flow — 401 triggers exactly one retry', () {
    test('a 401 forces a refresh, then retries with the new token', () async {
      final authHeadersSeen = <String?>[];
      final (server, baseUrl) = await _startServer((req, index) async {
        authHeadersSeen.add(req.headers.value('authorization'));
        if (index == 1) {
          req.response.statusCode = 401;
        } else {
          req.response
            ..statusCode = 200
            ..write('{"ok":true}');
        }
        await req.response.close();
      });
      addTearDown(() => server.close(force: true));

      final dio = Dio(BaseOptions(baseUrl: baseUrl));
      var refreshCalls = 0;
      // Mirrors real Firebase behavior: getIdToken() (no force) returns
      // whatever is currently cached, and a forced refresh updates that
      // cache — readToken() must reflect refreshToken()'s result, because
      // Dio's retry (dio.fetch) re-runs onRequest and would otherwise
      // clobber the just-refreshed header with a stale one.
      var currentToken = 'initial-token';
      dio.interceptors.add(
        firebaseAuthInterceptor(
          dio,
          readToken: () async => currentToken,
          refreshToken: () async {
            refreshCalls++;
            currentToken = 'refreshed-token';
            return currentToken;
          },
          onRefreshFailure: (_) async {},
        ),
      );

      final response = await dio.get('/resource');

      expect(response.statusCode, 200);
      expect(refreshCalls, 1);
      expect(authHeadersSeen, [
        'Bearer initial-token',
        'Bearer refreshed-token',
      ]);
    });

    test(
      'refresh failure clears the retry loop — one attempt, no crash, original error surfaces',
      () async {
        final (server, baseUrl) = await _startServer((req, index) async {
          req.response.statusCode = 401;
          await req.response.close();
        });
        addTearDown(() => server.close(force: true));

        final dio = Dio(BaseOptions(baseUrl: baseUrl));
        var refreshCalls = 0;
        var failureHandlerCalls = 0;
        dio.interceptors.add(
          firebaseAuthInterceptor(
            dio,
            readToken: () async => 'initial-token',
            refreshToken: () async {
              refreshCalls++;
              throw Exception('refresh token expired/invalid');
            },
            onRefreshFailure: (_) async {
              failureHandlerCalls++;
            },
          ),
        );

        await expectLater(
          () => dio.get('/resource'),
          throwsA(isA<DioException>()),
        );

        // Exactly one refresh attempt, exactly one failure handoff — not an
        // infinite retry loop, and the interceptor didn't hang or crash.
        expect(refreshCalls, 1);
        expect(failureHandlerCalls, 1);
      },
    );

    test('concurrent requests failing with 401 at the same time', () async {
      final (server, baseUrl) = await _startServer((req, index) async {
        final auth = req.headers.value('authorization');
        if (auth == 'Bearer refreshed-token') {
          req.response
            ..statusCode = 200
            ..write('{"ok":true}');
        } else {
          req.response.statusCode = 401;
        }
        await req.response.close();
      });
      addTearDown(() => server.close(force: true));

      final dio = Dio(BaseOptions(baseUrl: baseUrl));
      var refreshCalls = 0;
      // See the happy-path test above for why readToken must track
      // refreshToken's result — without it, Dio's retry re-runs
      // onRequest, clobbers the header back to a token the server will
      // 401 again, and each retry recurses back into onError with no
      // depth limit (empirically: a 30s hang, not a clean failure).
      var currentToken = 'initial-token';
      dio.interceptors.add(
        firebaseAuthInterceptor(
          dio,
          readToken: () async => currentToken,
          refreshToken: () async {
            refreshCalls++;
            // A real getIdToken(true) is a network round-trip, not
            // instantaneous — without some delay here, this fake resolves
            // before the other concurrently-failing requests even reach
            // onError, so there's no real "stampede window" for the
            // shared-refresh guard to prove it closes.
            await Future.delayed(const Duration(milliseconds: 20));
            currentToken = 'refreshed-token';
            return currentToken;
          },
          onRefreshFailure: (_) async {},
        ),
      );

      const concurrentRequests = 5;
      final results =
          await Future.wait([
            for (var i = 0; i < concurrentRequests; i++) dio.get('/resource'),
          ]).timeout(
            const Duration(seconds: 5),
            onTimeout: () => throw TimeoutException(
              'Concurrent requests did not settle within 5s — possible '
              'unbounded retry recursion in the interceptor '
              '(onError -> dio.fetch -> onError -> ...).',
            ),
          );

      // All requests still succeed either way — this is about efficiency,
      // not correctness of the end result.
      expect(results.every((r) => r.statusCode == 200), isTrue);

      // auth_interceptor.dart shares one in-flight refresh across every
      // concurrently-failing request (module-level _inFlightRefresh) —
      // N requests hitting 401 at once trigger exactly one refresh, not N.
      expect(
        refreshCalls,
        1,
        reason:
            'Expected $concurrentRequests concurrently-failing requests to '
            'share a single refresh; got $refreshCalls refreshToken() '
            'calls instead — the shared in-flight guard may have '
            'regressed.',
      );
    });

    test(
      'a retried request that also comes back 401 does not recurse indefinitely',
      () async {
        // dio.fetch(opts) inside onError re-enters the full interceptor
        // pipeline, including onError itself. Without a retry cap, a
        // retried request that ALSO 401s would recurse through onError with
        // no depth limit. The server here always returns 401 regardless of
        // the header, so every retry is guaranteed to fail — this is
        // specifically exercising the cap, not the happy path.
        final (server, baseUrl) = await _startServer((req, index) async {
          req.response.statusCode = 401;
          await req.response.close();
        });
        addTearDown(() => server.close(force: true));

        final dio = Dio(BaseOptions(baseUrl: baseUrl));
        var refreshCalls = 0;
        dio.interceptors.add(
          firebaseAuthInterceptor(
            dio,
            readToken: () async => 'initial-token',
            refreshToken: () async {
              refreshCalls++;
              return 'refreshed-token'; // still gets 401 — see above.
            },
            onRefreshFailure: (_) async {},
          ),
        );

        await expectLater(
          () => dio.get('/resource'),
          throwsA(isA<DioException>()),
        ).timeout(
          const Duration(seconds: 5),
          onTimeout: () => throw TimeoutException(
            'Did not settle within 5s — the retry cap did not stop '
            'recursion.',
          ),
        );

        // Exactly one refresh, exactly one retry — not one per recursive
        // bounce through onError.
        expect(refreshCalls, 1);
      },
    );
  });

  group(
    'Auto-logout — session_recovery.endSessionIfRevoked as the real onRefreshFailure',
    () {
      test(
        'a refresh failure NOT caused by a dead session does not sign out (and does not crash)',
        () async {
          final (server, baseUrl) = await _startServer((req, index) async {
            req.response.statusCode = 401;
            await req.response.close();
          });
          addTearDown(() => server.close(force: true));

          final dio = Dio(BaseOptions(baseUrl: baseUrl));
          dio.interceptors.add(
            firebaseAuthInterceptor(
              dio,
              readToken: () async => 'initial-token',
              refreshToken: () async => throw FirebaseAuthException(
                code: 'network-request-failed',
                message: 'transient network blip',
              ),
              // The REAL production function, not a fake.
              onRefreshFailure: endSessionIfRevoked,
            ),
          );

          // A transient error must not be treated as "session over": the
          // request still fails (401 stands), but nothing should throw out of
          // endSessionIfRevoked itself.
          await expectLater(
            () => dio.get('/resource'),
            throwsA(isA<DioException>()),
          );
        },
      );

      test(
        'a dead-session refresh failure is handled gracefully (does not crash the request)',
        () async {
          // NOTE — coverage limitation: endSessionIfRevoked's "true" branch
          // calls FirebaseAuth.instance.signOut(), and FirebaseAuth.instance
          // cannot be constructed in a plain flutter_test VM (no Firebase app
          // registered, no platform channels) — it throws synchronously.
          // endSessionIfRevoked catches that internally and returns false, so
          // this test can only prove the request pipeline survives a
          // dead-session code without crashing — NOT that a real dead session
          // actually signs the user out. Proving that needs Firebase test
          // scaffolding (e.g. the firebase_auth_mocks package) that isn't a
          // project dependency; flagged in the final report rather than added
          // here without asking.
          final (server, baseUrl) = await _startServer((req, index) async {
            req.response.statusCode = 401;
            await req.response.close();
          });
          addTearDown(() => server.close(force: true));

          final dio = Dio(BaseOptions(baseUrl: baseUrl));
          dio.interceptors.add(
            firebaseAuthInterceptor(
              dio,
              readToken: () async => 'initial-token',
              refreshToken: () async => throw FirebaseAuthException(
                code: 'user-token-expired',
                message: 'refresh token revoked by a force-logout',
              ),
              onRefreshFailure: endSessionIfRevoked,
            ),
          );

          await expectLater(
            () => dio.get('/resource'),
            throwsA(isA<DioException>()),
          );
        },
      );
    },
  );
}
