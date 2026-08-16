// lib/server/auth_middleware.dart
// JWT authentication middleware for protecting API endpoints

import 'package:shelf/shelf.dart';
import 'package:dart_jsonwebtoken/dart_jsonwebtoken.dart';

// JWT secret key
// TODO: In production, this should be generated dynamically and stored securely
// For now, using a static key for simplicity
const String JWT_SECRET = 'bursary_manager_secret_key_change_in_production';

/// JWT middleware - validates JWT tokens on protected routes
Middleware get jwtMiddleware {
  return (Handler innerHandler) {
    return (Request request) async {
      // Get authorization header
      final authHeader = request.headers['authorization'];

      if (authHeader == null || !authHeader.startsWith('Bearer ')) {
        return Response(
          401,
          body: '{"error": "Missing or invalid authorization header"}',
          headers: {'Content-Type': 'application/json'},
        );
      }

      // Extract token
      final token = authHeader.substring(7); // Remove 'Bearer ' prefix

      try {
        // Verify and decode token
        final jwt = JWT.verify(token, SecretKey(JWT_SECRET));
        final payload = jwt.payload as Map<String, dynamic>;

        // Add user info to request context for use in route handlers
        final requestWithUser = request.change(context: {
          'user': payload,
          'userId': payload['userId'],
          'username': payload['username'],
          'userType': payload['userType'],
        });

        // Continue to route handler
        return await innerHandler(requestWithUser);
      } on JWTExpiredException {
        return Response(
          401,
          body: '{"error": "Token expired"}',
          headers: {'Content-Type': 'application/json'},
        );
      } on JWTException catch (e) {
        return Response(
          401,
          body: '{"error": "Invalid token: ${e.message}"}',
          headers: {'Content-Type': 'application/json'},
        );
      } catch (e) {
        return Response(
          500,
          body: '{"error": "Token validation failed: $e"}',
          headers: {'Content-Type': 'application/json'},
        );
      }
    };
  };
}

/// Generate JWT token for authenticated user
String generateToken(Map<String, dynamic> user) {
  // Token expires in 8 hours
  final expiryTime = DateTime.now().add(const Duration(hours: 8));

  final jwt = JWT({
    'userId': user['id'],
    'username': user['username'],
    'userType': user['userType'],
    'iat': DateTime.now().millisecondsSinceEpoch ~/ 1000,
    'exp': expiryTime.millisecondsSinceEpoch ~/ 1000,
  });

  return jwt.sign(SecretKey(JWT_SECRET));
}

/// Verify token without middleware (for testing/validation)
Map<String, dynamic>? verifyToken(String token) {
  try {
    final jwt = JWT.verify(token, SecretKey(JWT_SECRET));
    return jwt.payload as Map<String, dynamic>;
  } catch (e) {
    return null;
  }
}

/// Extract user from request context (set by middleware)
Map<String, dynamic>? getUserFromRequest(Request request) {
  return request.context['user'] as Map<String, dynamic>?;
}

/// Get user ID from request context
int? getUserIdFromRequest(Request request) {
  return request.context['userId'] as int?;
}

/// Get username from request context
String? getUsernameFromRequest(Request request) {
  return request.context['username'] as String?;
}

/// Get user type from request context
String? getUserTypeFromRequest(Request request) {
  return request.context['userType'] as String?;
}
