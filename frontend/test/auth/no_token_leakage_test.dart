// test/auth/no_token_leakage_test.dart
//
// Scenario 5 from the audit request ("no token leakage"). This app has no
// dedicated logging wrapper around requests/responses to unit-test — Dio is
// used with no logging interceptor (see every *_service.dart), and the only
// logging is scattered debugPrint() calls. So instead of asserting against a
// captured log string from a wrapper that doesn't exist, this is a source
// regression guard: it fails if any debugPrint/print call anywhere in lib/
// interpolates a variable that plausibly holds a raw token, or logs the
// literal "Bearer " prefix a token would follow.
//
// This is deliberately a static check, not a runtime one — there's nothing
// to instrument at runtime here without inventing a logging layer the app
// doesn't have.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _join(List<String> segments) => segments.join(Platform.pathSeparator);

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

List<File> _dartFilesUnderLib() {
  final dir = Directory(_join([_frontendRoot.path, 'lib']));
  return dir
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.dart'))
      .toList();
}

/// Variable-name fragments that plausibly hold a raw bearer/JWT/refresh
/// token value, based on the names actually used in this codebase's auth
/// code (token, newToken, idToken, refreshToken, accessToken, ...).
final _tokenLikeNamePattern = RegExp(
  r'\b(token|idToken|newToken|refreshToken|accessToken|bearerToken)\b',
  caseSensitive: false,
);

final _printCallPattern = RegExp(r'\b(print|debugPrint)\s*\(');

void main() {
  group('No token leakage — static log-source guard', () {
    test(
      'no print()/debugPrint() call interpolates a token-shaped variable',
      () {
        final offenders = <String>[];
        for (final file in _dartFilesUnderLib()) {
          final lines = file.readAsStringSync().split('\n');
          for (var i = 0; i < lines.length; i++) {
            final line = lines[i];
            if (!_printCallPattern.hasMatch(line)) continue;
            if (_tokenLikeNamePattern.hasMatch(line)) {
              offenders.add('${file.path}:${i + 1}: ${line.trim()}');
            }
          }
        }
        expect(
          offenders,
          isEmpty,
          reason:
              'Found a print()/debugPrint() call that looks like it logs a '
              'token value:\n${offenders.join('\n')}',
        );
      },
    );

    test(
      'no print()/debugPrint() call logs a literal "Bearer " value',
      () {
        // Catches the shape 'Bearer $x' even if x isn't named anything
        // token-like — the "Bearer " prefix itself is the tell.
        final offenders = <String>[];
        for (final file in _dartFilesUnderLib()) {
          final lines = file.readAsStringSync().split('\n');
          for (var i = 0; i < lines.length; i++) {
            final line = lines[i];
            if (!_printCallPattern.hasMatch(line)) continue;
            if (line.contains('Bearer')) {
              offenders.add('${file.path}:${i + 1}: ${line.trim()}');
            }
          }
        }
        expect(
          offenders,
          isEmpty,
          reason:
              'Found a print()/debugPrint() call that logs something '
              'containing "Bearer":\n${offenders.join('\n')}',
        );
      },
    );

    test(
      'the Authorization header is only ever set, never logged',
      () {
        // A regression guard specifically on auth_interceptor.dart, the one
        // place every request's Authorization header is assembled — the
        // highest-value place a leak could be introduced.
        final text = File(
          _join([
            _frontendRoot.path,
            'lib/services/auth_interceptor.dart',
          ]),
        ).readAsStringSync();
        final loggingLines = text
            .split('\n')
            .where((l) => _printCallPattern.hasMatch(l))
            .toList();
        expect(
          loggingLines,
          isEmpty,
          reason:
              'auth_interceptor.dart should have no logging calls at all — '
              'found: ${loggingLines.join(' | ')}',
        );
      },
    );
  });
}
