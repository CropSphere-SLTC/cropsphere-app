// test/secure_storage_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Mock storage for testing
  const storage = FlutterSecureStorage();

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
  });

  group('SecureStorageService Tests', () {
    test('Save and retrieve token', () async {
      await storage.write(key: 'firebase_token', value: 'test_token_123');
      final token = await storage.read(key: 'firebase_token');
      expect(token, 'test_token_123');
      debugPrint('✅ Test 1 Passed — Token saved and retrieved');
    });

    test('Delete token', () async {
      await storage.write(key: 'firebase_token', value: 'test_token_123');
      await storage.delete(key: 'firebase_token');
      final token = await storage.read(key: 'firebase_token');
      expect(token, null);
      debugPrint('✅ Test 2 Passed — Token deleted');
    });

    test('Has token returns true when token exists', () async {
      await storage.write(key: 'firebase_token', value: 'test_token_123');
      final token = await storage.read(key: 'firebase_token');
      expect(token != null && token.isNotEmpty, true);
      debugPrint('✅ Test 3 Passed — Token exists');
    });

    test('Has token returns false when no token', () async {
      await storage.deleteAll();
      final token = await storage.read(key: 'firebase_token');
      expect(token == null, true);
      debugPrint('✅ Test 4 Passed — No token exists');
    });
  });
}