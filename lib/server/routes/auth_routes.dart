// lib/server/routes/auth_routes.dart
// Authentication API routes - login, logout

import 'dart:convert';
import 'dart:io';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import '../../db/database_helper.dart';
import '../auth_middleware.dart';
import '../server.dart';

class AuthRoutes {
  final DatabaseHelper _db = DatabaseHelper();

  Router get router {
    final router = Router();

    router.post('/login', _login);
    router.post('/logout', _logout);
    router.get('/verify', _verifyToken);

    return router;
  }

  /// POST /api/auth/login
  /// Authenticate user and return JWT token
  Future<Response> _login(Request request) async {
    try {
      final body = await request.readAsString();
      final data = jsonDecode(body) as Map<String, dynamic>;

      final username = data['username'] as String?;
      final password = data['password'] as String?;

      if (username == null || password == null) {
        return Response(
          400,
          body: jsonEncode({'error': 'Username and password required'}),
          headers: {'Content-Type': 'application/json'},
        );
      }

      // Authenticate user via database
      final user = await _db.authenticateUser(username, password);

      if (user == null) {
        return Response(
          401,
          body: jsonEncode({'error': 'Invalid credentials'}),
          headers: {'Content-Type': 'application/json'},
        );
      }

      // Generate JWT token
      final token = generateToken(user);

      // Track connected client
      final connectionInfo = request.context['shelf.io.connection_info'] as HttpConnectionInfo?;
      final clientIp = connectionInfo?.remoteAddress.address ?? 'Unknown';
      BursaryServer().addClient(
        clientIp,
        user['username'] as String,
        user['userType'] as String,
      );

      return Response.ok(
        jsonEncode({
          'success': true,
          'token': token,
          'user': {
            'id': user['id'],
            'username': user['username'],
            'userType': user['userType'],
          },
        }),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e) {
      return Response.internalServerError(
        body: jsonEncode({'error': 'Login failed: $e'}),
        headers: {'Content-Type': 'application/json'},
      );
    }
  }

  /// POST /api/auth/logout
  /// Logout user (JWT is stateless, so just return success)
  Future<Response> _logout(Request request) async {
    return Response.ok(
      jsonEncode({'success': true, 'message': 'Logged out successfully'}),
      headers: {'Content-Type': 'application/json'},
    );
  }

  /// GET /api/auth/verify
  /// Verify JWT token validity
  Future<Response> _verifyToken(Request request) async {
    try {
      final authHeader = request.headers['authorization'];

      if (authHeader == null || !authHeader.startsWith('Bearer ')) {
        return Response(
          401,
          body: jsonEncode({'valid': false, 'error': 'No token provided'}),
          headers: {'Content-Type': 'application/json'},
        );
      }

      final token = authHeader.substring(7);
      final payload = verifyToken(token);

      if (payload == null) {
        return Response(
          401,
          body: jsonEncode({'valid': false, 'error': 'Invalid token'}),
          headers: {'Content-Type': 'application/json'},
        );
      }

      return Response.ok(
        jsonEncode({
          'valid': true,
          'user': {
            'userId': payload['userId'],
            'username': payload['username'],
            'userType': payload['userType'],
          },
        }),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e) {
      return Response.internalServerError(
        body: jsonEncode({'valid': false, 'error': 'Verification failed: $e'}),
        headers: {'Content-Type': 'application/json'},
      );
    }
  }
}
