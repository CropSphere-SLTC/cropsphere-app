// test/error_handler_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/foundation.dart';
import 'package:cropsphere_app/utils/error_handler.dart';

void main() {
  group('ErrorHandler Tests', () {
    test('Invalid credentials returns friendly message', () {
      final msg = ErrorHandler.getErrorMessage('user-not-found');
      expect(msg, 'Invalid email or password. Please try again.');
      debugPrint('✅ Test 1 Passed — Auth error handled');
    });

    test('Network error returns friendly message', () {
      final msg = ErrorHandler.getErrorMessage('network-request-failed');
      expect(msg, 'Network error. Please check your connection.');
      debugPrint('✅ Test 2 Passed — Network error handled');
    });

    test('401 error returns friendly message', () {
      final msg = ErrorHandler.getErrorMessage('401 unauthorized');
      expect(msg, 'Session expired. Please login again.');
      debugPrint('✅ Test 3 Passed — 401 error handled');
    });

    test('429 error returns friendly message', () {
      final msg = ErrorHandler.getErrorMessage('429 too many requests');
      expect(msg, 'Too many requests. Please wait a moment.');
      debugPrint('✅ Test 4 Passed — 429 error handled');
    });

    test('500 error returns friendly message', () {
      final msg = ErrorHandler.getErrorMessage('500 server error');
      expect(msg, 'Server error. Please try again later.');
      debugPrint('✅ Test 5 Passed — 500 error handled');
    });

    test('Unknown error returns default message', () {
      final msg = ErrorHandler.getErrorMessage(
        'some random technical error xyz',
      );
      expect(msg, 'Something went wrong. Please try again.');
      debugPrint('✅ Test 6 Passed — Unknown error handled');
    });

    test('Auth error detection works', () {
      expect(ErrorHandler.isAuthError('401 unauthorized'), true);
      debugPrint('✅ Test 7 Passed — Auth error detected');
    });

    test('Network error detection works', () {
      expect(ErrorHandler.isNetworkError('network timeout'), true);
      debugPrint('✅ Test 8 Passed — Network error detected');
    });
  });
}
