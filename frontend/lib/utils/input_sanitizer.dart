// lib/utils/input_sanitizer.dart

class InputSanitizer {
  // Dangerous patterns
  static const List<String> _dangerousPatterns = [
    '<script',
    '</script>',
    'javascript:',
    '\$where',
    '\$gt',
    '\$lt',
    '\$ne',
    'DROP TABLE',
    'SELECT *',
    '--',
    '/*',
    '*/',
  ];

  // Valid crop names
  static const List<String> _validCrops = [
    'Carrot',
    'Maize',
    'Greengram',
    'Cowpea',
    'Fingermillet',
    'Groundnut',
  ];

  // Sanitize string input
  static String? sanitizeString(String? value) {
    if (value == null || value.isEmpty) return null;

    for (final pattern in _dangerousPatterns) {
      if (value.toLowerCase().contains(pattern.toLowerCase())) {
        return null; // Malicious input detected
      }
    }
    return value.trim();
  }

  // Validate crop name
  static bool isValidCrop(String? crop) {
    if (crop == null || crop.isEmpty) return false;
    return _validCrops.contains(crop);
  }

  // Validate numeric range
  static bool isValidRainfall(double? value) {
    if (value == null) return false;
    return value >= 0 && value <= 5000;
  }

  static bool isValidTemperature(double? value) {
    if (value == null) return false;
    return value >= -10 && value <= 50;
  }

  static bool isValidHumidity(double? value) {
    if (value == null) return false;
    return value >= 0 && value <= 100;
  }

  static bool isValidMonth(int? value) {
    if (value == null) return false;
    return value >= 1 && value <= 12;
  }
}