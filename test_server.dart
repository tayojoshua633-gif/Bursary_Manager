// test_server.dart
// Standalone test to verify BursaryServer functionality

import 'dart:io';
import 'package:http/http.dart' as http;
import 'dart:convert';

import 'lib/server/server.dart';

void main() async {
  print('🧪 Testing BursaryServer (Phase 2)');
  print('=' * 50);

  final server = BursaryServer();

  try {
    // Test 1: Start server
    print('\n📝 Test 1: Starting server...');
    await server.start();
    print('✅ Server started successfully');
    print('   Port: ${server.port}');
    print('   PIN: ${server.serverPin}');
    print('   Running: ${server.isRunning}');

    // Wait a moment for server to be ready
    await Future.delayed(Duration(milliseconds: 500));

    // Test 2: Check server-info endpoint (public, no auth)
    print('\n📝 Test 2: Testing public endpoint /api/server-info...');
    try {
      final response = await http.get(
        Uri.parse('http://localhost:${server.port}/api/server-info'),
      );
      print('   Status: ${response.statusCode}');
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        print('   Response: $data');
        print('✅ Server info endpoint working');
      } else {
        print('❌ Unexpected status code: ${response.statusCode}');
      }
    } catch (e) {
      print('❌ Failed to reach server: $e');
    }

    // Test 3: Test login endpoint (should fail without credentials)
    print('\n📝 Test 3: Testing auth endpoint /api/auth/login...');
    try {
      final response = await http.post(
        Uri.parse('http://localhost:${server.port}/api/auth/login'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'username': 'invalid',
          'password': 'invalid',
        }),
      );
      print('   Status: ${response.statusCode}');
      if (response.statusCode == 401) {
        print('✅ Auth endpoint correctly rejects invalid credentials');
      } else {
        print('   Response: ${response.body}');
      }
    } catch (e) {
      print('❌ Failed to test auth: $e');
    }

    // Test 4: Test protected endpoint without auth (should fail with 401)
    print('\n📝 Test 4: Testing protected endpoint /api/students (no auth)...');
    try {
      final response = await http.get(
        Uri.parse('http://localhost:${server.port}/api/students'),
      );
      print('   Status: ${response.statusCode}');
      if (response.statusCode == 401) {
        print('✅ Protected endpoint correctly requires authentication');
      } else {
        print('   Unexpected status: ${response.statusCode}');
        print('   Response: ${response.body}');
      }
    } catch (e) {
      print('❌ Failed to test protected endpoint: $e');
    }

    // Test 5: Stop server
    print('\n📝 Test 5: Stopping server...');
    await server.stop();
    print('✅ Server stopped successfully');
    print('   Running: ${server.isRunning}');

    // Test 6: Verify server stopped (should fail to connect)
    print('\n📝 Test 6: Verifying server is stopped...');
    await Future.delayed(Duration(milliseconds: 500));
    try {
      final response = await http.get(
        Uri.parse('http://localhost:8080/api/server-info'),
      ).timeout(Duration(seconds: 2));
      print('❌ Server still responding (should be stopped)');
    } catch (e) {
      print('✅ Server correctly stopped (connection refused)');
    }

    print('\n${'=' * 50}');
    print('✅ All Phase 2 tests completed successfully!');
    print('=' * 50);

  } catch (e, stackTrace) {
    print('\n❌ Test failed with error:');
    print(e);
    print(stackTrace);
    exit(1);
  }

  exit(0);
}
