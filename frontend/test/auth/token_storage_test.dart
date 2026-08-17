// test/auth/token_storage_test.dart
//
// Scenario 1 from the audit request ("token storage") assumed a manual
// access-token + refresh-token write to flutter_secure_storage on login, and
// a delete-all on logout. That isn't this app's architecture: auth is
// Firebase Auth, which owns its own token persistence internally — nothing
// in lib/ ever writes a Firebase ID/refresh token to SharedPreferences or to
// flutter_secure_storage (see the Phase-1 audit; SecureStorageService/
// flutter_secure_storage were removed as unused dead code in Phase 2).
//
// So instead of testing a login flow that doesn't exist, these are
// regression guards over source: they fail loudly if someone reintroduces
// the insecure pattern (a token in SharedPreferences) or the removed unused
// dependency, and they confirm logout has exactly one code path so nothing
// can bypass it and leave residual session state.
//
// Pure source-scanning — no Flutter widgets, no Firebase — so these run in
// a plain VM `dart test`/`flutter test` with no platform setup required.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Joins path segments with the platform separator — avoids taking a direct
/// dependency on package:path (only a transitive dep here) for something
/// this small.
String _join(List<String> segments) => segments.join(Platform.pathSeparator);

/// Repo-relative frontend root, regardless of which directory `flutter test`
/// was invoked from.
final _frontendRoot = _findFrontendRoot();

Directory _findFrontendRoot() {
  var dir = Directory.current;
  while (true) {
    if (File(_join([dir.path, 'pubspec.yaml'])).existsSync()) return dir;
    final parent = dir.parent;
    if (parent.path == dir.path) {
      throw StateError(
        'Could not locate frontend/pubspec.yaml from ${Directory.current.path}',
      );
    }
    dir = parent;
  }
}

List<File> _dartFilesUnder(String relativeDir) {
  final dir = Directory(_join([_frontendRoot.path, relativeDir]));
  if (!dir.existsSync()) return [];
  return dir
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.dart'))
      .toList();
}

void main() {
  group('Token storage — regression guards', () {
    test(
      'no lib/ file writes a token-shaped value to SharedPreferences',
      () {
        final offenders = <String>[];
        for (final file in _dartFilesUnder('lib')) {
          final text = file.readAsStringSync();
          if (!text.contains('SharedPreferences')) continue;
          // Any line that both touches SharedPreferences' write API and
          // mentions "token" (case-insensitive) is the insecure pattern
          // this guard exists to catch — SharedPreferences is unencrypted
          // on-disk storage.
          for (final line in text.split('\n')) {
            final lower = line.toLowerCase();
            final looksLikeWrite =
                lower.contains('.setstring(') || lower.contains('.set(');
            if (looksLikeWrite && lower.contains('token')) {
              offenders.add('${file.path}: ${line.trim()}');
            }
          }
        }
        expect(
          offenders,
          isEmpty,
          reason:
              'Found SharedPreferences write(s) that look like they persist '
              'a token — SharedPreferences is unencrypted, tokens must not '
              'be written there:\n${offenders.join('\n')}',
        );
      },
    );

    test(
      'flutter_secure_storage is not a dependency (removed as unused dead code)',
      () {
        final pubspec = File(
          _join([_frontendRoot.path, 'pubspec.yaml']),
        ).readAsStringSync();
        expect(
          pubspec.contains('flutter_secure_storage'),
          isFalse,
          reason:
              'flutter_secure_storage was removed because nothing wired a '
              'token through it (Firebase Auth owns token persistence). If '
              'it has been reintroduced, either it is dead code again or a '
              'real manual token-storage path was added and these tests '
              'need to be rewritten to cover it for real.',
        );
      },
    );

    test(
      'no production file constructs a SecureStorageService-style token store',
      () {
        final offenders = <String>[];
        for (final file in _dartFilesUnder('lib')) {
          final text = file.readAsStringSync();
          if (text.contains('SecureStorageService')) {
            offenders.add(file.path);
          }
        }
        expect(
          offenders,
          isEmpty,
          reason:
              'SecureStorageService was deleted (Phase 2) as unused dead '
              'code. A reference to it here means either the class was '
              'reintroduced without being wired to anything (dead code '
              'again), or it is now genuinely used to store tokens — in '
              'which case this whole test file needs rewriting to test '
              'that flow for real: ${offenders.join(', ')}',
        );
      },
    );

    test('logout has exactly two deliberate code paths, no others', () {
      // FirebaseAuth.instance.signOut() is called from exactly two places by
      // design:
      //  - session_service.dart (normal manual/inactivity logout — also
      //    stops the 15-minute timer)
      //  - session_recovery.dart (endSessionIfRevoked — signs out when a
      //    forced token refresh proves the session is dead; see
      //    auth_interceptor.dart's onRefreshFailure)
      // Any OTHER call site would bypass SessionService.stopTimer(), leaving
      // the inactivity timer running against a signed-out session.
      const allowed = {'session_service.dart', 'session_recovery.dart'};
      final offenders = <String>[];
      for (final file in _dartFilesUnder('lib')) {
        final basename = file.path.split(Platform.pathSeparator).last;
        if (allowed.contains(basename)) continue;
        final text = file.readAsStringSync();
        if (text.contains('FirebaseAuth.instance.signOut()')) {
          offenders.add(file.path);
        }
      }
      expect(
        offenders,
        isEmpty,
        reason:
            'Found a direct FirebaseAuth.instance.signOut() call outside '
            'the two deliberate sign-out paths — every other caller should '
            'go through SessionService.logout() so the inactivity timer is '
            'always stopped too: ${offenders.join(', ')}',
      );
    });

    test(
      'SessionService.logout stops the inactivity timer and signs out',
      () {
        final text = File(
          _join([_frontendRoot.path, 'lib/services/session_service.dart']),
        ).readAsStringSync();
        final logoutBody = RegExp(
          r'static Future<void> logout\(\) async \{([\s\S]*?)\n  \}',
        ).firstMatch(text)?.group(1);
        expect(
          logoutBody,
          isNotNull,
          reason: 'Could not find SessionService.logout() — has it moved?',
        );
        expect(
          logoutBody!.contains('stopTimer()'),
          isTrue,
          reason: 'logout() must stop the inactivity timer.',
        );
        expect(
          logoutBody.contains('FirebaseAuth.instance.signOut()'),
          isTrue,
          reason: 'logout() must sign out of Firebase.',
        );
      },
    );
  });
}
