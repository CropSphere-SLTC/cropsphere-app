// lib/utils/xss_protection.dart

class XSSProtection {
  // Dangerous XSS patterns
  static const List<String> _xssPatterns = [
    '<script',
    '</script>',
    'javascript:',
    'onerror=',
    'onload=',
    'onclick=',
    'onmouseover=',
    '<iframe',
    '</iframe>',
    '<img',
    'alert\\(',
    'document.cookie',
    'document.write',
    'window.location',
    'eval\\(',
  ];

  // Sanitize HTML — remove dangerous tags
  static String sanitizeHtml(String input) {
    String sanitized = input;

    for (final pattern in _xssPatterns) {
      sanitized = sanitized.replaceAll(
        RegExp(pattern, caseSensitive: false),
        '',
      );
    }

    return sanitized.trim();
  }

  // Escape HTML special characters
  static String escapeHtml(String input) {
    return input
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;')
        .replaceAll("'", '&#x27;');
  }

  // Check if input contains XSS
  static bool containsXSS(String input) {
    final lowercaseInput = input.toLowerCase();
    return _xssPatterns.any(
      (pattern) => lowercaseInput.contains(pattern.toLowerCase()),
    );
  }

  // Sanitize user input for display
  static String sanitizeUserInput(String input) {
    if (containsXSS(input)) {
      return escapeHtml(sanitizeHtml(input));
    }
    return input.trim();
  }
}