// lib/utils/error_handler.dart

class ErrorHandler {
  // Convert technical errors to user friendly messages
  static String getErrorMessage(dynamic error) {
    final errorStr = error.toString().toLowerCase();

    // Firebase Auth errors
    if (errorStr.contains('user-not-found') ||
        errorStr.contains('wrong-password') ||
        errorStr.contains('invalid-credential')) {
      return 'Invalid email or password. Please try again.';
    }

    if (errorStr.contains('too-many-requests')) {
      return 'Too many attempts. Please try again later.';
    }

    if (errorStr.contains('network-request-failed') ||
        errorStr.contains('network')) {
      return 'Network error. Please check your connection.';
    }

    if (errorStr.contains('unauthorized') || errorStr.contains('401')) {
      return 'Session expired. Please login again.';
    }

    if (errorStr.contains('429')) {
      return 'Too many requests. Please wait a moment.';
    }

    if (errorStr.contains('500') || errorStr.contains('server')) {
      return 'Server error. Please try again later.';
    }

    if (errorStr.contains('timeout')) {
      return 'Request timed out. Please try again.';
    }

    // Default message — no technical details
    return 'Something went wrong. Please try again.';
  }

  // Check if error is auth related
  static bool isAuthError(dynamic error) {
    final errorStr = error.toString().toLowerCase();
    return errorStr.contains('unauthorized') ||
        errorStr.contains('401') ||
        errorStr.contains('user-not-found') ||
        errorStr.contains('wrong-password');
  }

  // Check if error is network related
  static bool isNetworkError(dynamic error) {
    final errorStr = error.toString().toLowerCase();
    return errorStr.contains('network') ||
        errorStr.contains('timeout') ||
        errorStr.contains('connection');
  }
}
