// lib/server/routes/audit_log_routes.dart
// Audit log API routes (financial activity trail)

import 'dart:convert';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import '../../db/database_helper.dart';
import '../auth_middleware.dart';

class AuditLogRoutes {
  final DatabaseHelper _db = DatabaseHelper();

  Router get router {
    final router = Router();

    router.get('/', _getAuditLog);
    router.post('/', _createAuditLog);

    return router;
  }

  Future<Response> _getAuditLog(Request request) async {
    try {
      final params = request.url.queryParameters;
      final conditions = <String>[];
      final args = <dynamic>[];

      final entityType = params['entityType'];
      if (entityType != null) {
        conditions.add('entityType = ?');
        args.add(entityType);
      }
      final entityId = int.tryParse(params['entityId'] ?? '');
      if (entityId != null) {
        conditions.add('entityId = ?');
        args.add(entityId);
      }
      final from = params['from'];
      if (from != null) {
        conditions.add('timestamp >= ?');
        args.add(from);
      }
      final to = params['to'];
      if (to != null) {
        conditions.add('timestamp <= ?');
        args.add(to);
      }
      final userId = int.tryParse(params['userId'] ?? '');
      if (userId != null) {
        conditions.add('userId = ?');
        args.add(userId);
      }

      final db = await _db.database;
      final rows = await db.query(
        'audit_log',
        where: conditions.isEmpty ? null : conditions.join(' AND '),
        whereArgs: args.isEmpty ? null : args,
        orderBy: 'timestamp DESC',
      );

      return Response.ok(jsonEncode(rows),
          headers: {'Content-Type': 'application/json'});
    } catch (e) {
      return Response.internalServerError(
          body: jsonEncode({'error': 'Failed to get audit log: $e'}),
          headers: {'Content-Type': 'application/json'});
    }
  }

  Future<Response> _createAuditLog(Request request) async {
    try {
      final body = await request.readAsString();
      final data = jsonDecode(body) as Map<String, dynamic>;

      final db = await _db.database;
      await db.insert('audit_log', {
        'entityType': data['entityType'],
        'entityId': data['entityId'],
        'action': data['action'],
        'studentId': data['studentId'],
        'amount': data['amount'],
        'changes':
            data['changes'] != null ? jsonEncode(data['changes']) : null,
        'userId': getUserIdFromRequest(request),
        'username': getUsernameFromRequest(request) ?? 'Unknown',
        'timestamp': DateTime.now().toIso8601String(),
      });

      return Response.ok(jsonEncode({'success': true}),
          headers: {'Content-Type': 'application/json'});
    } catch (e) {
      return Response.internalServerError(
          body: jsonEncode({'error': 'Failed to create audit log entry: $e'}),
          headers: {'Content-Type': 'application/json'});
    }
  }
}
