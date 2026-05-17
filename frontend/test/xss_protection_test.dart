// test/xss_protection_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/foundation.dart';
import 'package:cropsphere_app/utils/xss_protection.dart';

void main() {
  group('XSSProtection Tests', () {
    test('Normal text passes', () {
      expect(XSSProtection.containsXSS('Hello Farmer'), false);
      debugPrint('✅ Test 1 Passed — Normal text accepted');
    });

    test('Script tag detected', () {
      expect(XSSProtection.containsXSS('<script>alert(1)</script>'), true);
      debugPrint('✅ Test 2 Passed — Script tag detected');
    });

    test('JavaScript injection detected', () {
      expect(XSSProtection.containsXSS('javascript:alert(1)'), true);
      debugPrint('✅ Test 3 Passed — JavaScript injection detected');
    });

    test('onerror injection detected', () {
      expect(XSSProtection.containsXSS('onerror=alert(1)'), true);
      debugPrint('✅ Test 4 Passed — onerror injection detected');
    });

    test('Script tag removed from HTML', () {
      final result = XSSProtection.sanitizeHtml('<script>alert(1)</script>Hello');
      expect(result.contains('script'), false);
      debugPrint('✅ Test 5 Passed — Script tag removed');
    });

    test('HTML characters escaped', () {
      final result = XSSProtection.escapeHtml('<b>Hello</b>');
      expect(result, '&lt;b&gt;Hello&lt;/b&gt;');
      debugPrint('✅ Test 6 Passed — HTML escaped');
    });

    test('Safe user input unchanged', () {
      final result = XSSProtection.sanitizeUserInput('Carrot yield prediction');
      expect(result, 'Carrot yield prediction');
      debugPrint('✅ Test 7 Passed — Safe input unchanged');
    });

    test('Malicious input sanitized', () {
      final result = XSSProtection.sanitizeUserInput('<script>hack()</script>');
      expect(XSSProtection.containsXSS(result), false);
      debugPrint('✅ Test 8 Passed — Malicious input sanitized');
    });

    test('Cookie stealing attempt blocked', () {
      expect(XSSProtection.containsXSS('document.cookie'), true);
      debugPrint('✅ Test 9 Passed — Cookie stealing blocked');
    });

    test('iframe injection detected', () {
      expect(XSSProtection.containsXSS('<iframe src="evil.com">'), true);
      debugPrint('✅ Test 10 Passed — iframe injection detected');
    });
  });
}