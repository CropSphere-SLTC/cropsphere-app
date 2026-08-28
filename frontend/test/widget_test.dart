// Smoke test for CropSphere — verifies the login screen renders correctly
// without requiring a real Firebase connection.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cropsphere_app/screens/auth/login_screen.dart';

void main() {
  testWidgets('LoginScreen renders app name and Google button', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: LoginScreen()));

    // App title is visible
    expect(find.text('CropSphere'), findsOneWidget);

    // Google button is present. Must track login_screen.dart's `continueGoogle`
    // string — it was renamed from 'Sign in with Google' and this expectation
    // was left behind.
    expect(find.text('Continue with Google'), findsOneWidget);

    // No error message on initial load
    expect(find.byIcon(Icons.error_outline), findsNothing);
  });
}
