// test/session_service_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/foundation.dart';
import 'package:cropsphere_app/services/session_service.dart';

void main() {
  group('SessionService Tests', () {
    tearDown(() {
      SessionService.stopTimer();
    });

    test('Timer starts successfully', () {
      SessionService.startTimer();
      expect(SessionService.isTimerActive(), true);
      debugPrint('✅ Test 1 Passed — Timer started');
    });

    test('Timer resets successfully', () {
      SessionService.startTimer();
      SessionService.resetTimer();
      expect(SessionService.isTimerActive(), true);
      debugPrint('✅ Test 2 Passed — Timer reset');
    });

    test('Timer stops successfully', () {
      SessionService.startTimer();
      SessionService.stopTimer();
      expect(SessionService.isTimerActive(), false);
      debugPrint('✅ Test 3 Passed — Timer stopped');
    });

    test('Timer is inactive initially', () {
      expect(SessionService.isTimerActive(), false);
      debugPrint('✅ Test 4 Passed — Timer inactive initially');
    });
  });
}
