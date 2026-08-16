// test/server_test.dart
// Flutter integration test for BursaryServer

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:bursary_manager/server/server.dart';

void main() {
  // Initialize sqflite_common_ffi for testing
  setUpAll(() {
    // Initialize FFI
    sqfliteFfiInit();
    // Set the database factory for tests
    databaseFactory = databaseFactoryFfi;
  });

  group('BursaryServer Phase 2 Tests', () {
    late BursaryServer server;

    setUp(() {
      server = BursaryServer();
    });

    tearDown(() async {
      if (server.isRunning) {
        await server.stop();
      }
    });

    test('Server starts and generates PIN', () async {
      expect(server.isRunning, false);

      await server.start();

      expect(server.isRunning, true);
      expect(server.serverPin, isNotNull);
      expect(server.serverPin!.length, 6);
      expect(int.tryParse(server.serverPin!), isNotNull);
      expect(server.port, 8080);

      print('✅ Server started with PIN: ${server.serverPin}');
    });

    test('Server info endpoint responds', () async {
      await server.start();
      await Future.delayed(Duration(milliseconds: 500));

      final response = await http.get(
        Uri.parse('http://localhost:${server.port}/api/server-info'),
      );

      expect(response.statusCode, 200);

      final data = jsonDecode(response.body);
      expect(data['pin'], server.serverPin);
      expect(data['port'], 8080);

      print('✅ Server info endpoint working');
    });

    test('Auth endpoint rejects invalid credentials', () async {
      await server.start();
      await Future.delayed(Duration(milliseconds: 500));

      final response = await http.post(
        Uri.parse('http://localhost:${server.port}/api/auth/login'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'username': 'invalid',
          'password': 'invalid',
        }),
      );

      if (response.statusCode != 401) {
        print('❌ Unexpected status: ${response.statusCode}');
        print('Response body: ${response.body}');
      }

      expect(response.statusCode, 401);
      print('✅ Auth endpoint rejects invalid credentials');
    });

    test('Protected endpoints require authentication', () async {
      await server.start();
      await Future.delayed(Duration(milliseconds: 500));

      final response = await http.get(
        Uri.parse('http://localhost:${server.port}/api/students'),
      );

      expect(response.statusCode, 401);
      print('✅ Protected endpoint requires authentication');
    });

    test('Server stops correctly', () async {
      await server.start();
      expect(server.isRunning, true);

      await server.stop();

      expect(server.isRunning, false);
      expect(server.serverPin, isNull);

      print('✅ Server stopped correctly');
    });
  });
}
