// test/input_sanitizer_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:cropsphere_app/utils/input_sanitizer.dart';

void main() {
  group('InputSanitizer Tests', () {
    test('Normal string passes sanitization', () {
      final result = InputSanitizer.sanitizeString('Carrot');
      expect(result, 'Carrot');
      print('✅ Test 1 Passed — Normal string accepted');
    });

    test('Script injection blocked', () {
      final result = InputSanitizer.sanitizeString('<script>alert(xss)</script>');
      expect(result, null);
      print('✅ Test 2 Passed — Script injection blocked');
    });

    test('JavaScript injection blocked', () {
      final result = InputSanitizer.sanitizeString('javascript:alert(1)');
      expect(result, null);
      print('✅ Test 3 Passed — JavaScript injection blocked');
    });

    test('NoSQL injection blocked', () {
      final result = InputSanitizer.sanitizeString('\$where: hack');
      expect(result, null);
      print('✅ Test 4 Passed — NoSQL injection blocked');
    });

    test('Valid crop name accepted', () {
      expect(InputSanitizer.isValidCrop('Carrot'), true);
      print('✅ Test 5 Passed — Valid crop accepted');
    });

    test('Invalid crop name rejected', () {
      expect(InputSanitizer.isValidCrop('HACKED'), false);
      print('✅ Test 6 Passed — Invalid crop rejected');
    });

    test('Valid rainfall accepted', () {
      expect(InputSanitizer.isValidRainfall(500), true);
      print('✅ Test 7 Passed — Valid rainfall accepted');
    });

    test('Invalid rainfall rejected', () {
      expect(InputSanitizer.isValidRainfall(-99999), false);
      print('✅ Test 8 Passed — Invalid rainfall rejected');
    });

    test('Valid temperature accepted', () {
      expect(InputSanitizer.isValidTemperature(25), true);
      print('✅ Test 9 Passed — Valid temperature accepted');
    });

    test('Valid month accepted', () {
      expect(InputSanitizer.isValidMonth(6), true);
      print('✅ Test 10 Passed — Valid month accepted');
    });

    test('Invalid month rejected', () {
      expect(InputSanitizer.isValidMonth(99), false);
      print('✅ Test 11 Passed — Invalid month rejected');
    });
  });
}