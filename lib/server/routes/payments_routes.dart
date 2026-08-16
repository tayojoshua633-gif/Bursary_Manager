// lib/server/routes/payments_routes.dart
// Payments API routes

import 'dart:convert';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import '../../db/database_helper.dart';
import '../auth_middleware.dart';

class PaymentsRoutes {
  final DatabaseHelper _db = DatabaseHelper();

  Router get router {
    final router = Router();

    router.get('/student/<studentId>', _getPayments);
    router.post('/', _createPayment);
    router.put('/<id>', _updatePayment);
    router.delete('/<id>', _deletePayment);
    router.get('/date/<date>', _getPaymentsByDate);
    router.get('/balance/<studentId>', _getOutstandingBalance);

    return router;
  }

  Future<void> _writeAuditLog(
    Request request, {
    required int entityId,
    required String action,
    int? studentId,
    double? amount,
    Map<String, dynamic>? changes,
  }) async {
    final db = await _db.database;
    await db.insert('audit_log', {
      'entityType': 'payment',
      'entityId': entityId,
      'action': action,
      'studentId': studentId,
      'amount': amount,
      'changes': changes != null ? jsonEncode(changes) : null,
      'userId': getUserIdFromRequest(request),
      'username': getUsernameFromRequest(request) ?? 'Unknown',
      'timestamp': DateTime.now().toIso8601String(),
    });
  }

  Future<Response> _getPayments(Request request, String studentId) async {
    try {
      final id = int.tryParse(studentId);
      if (id == null) {
        return Response(400, body: jsonEncode({'error': 'Invalid student ID'}),
            headers: {'Content-Type': 'application/json'});
      }

      final term = request.url.queryParameters['term'];
      final session = request.url.queryParameters['session'];
      final payments = await _db.getPayments(id, term: term, session: session);

      return Response.ok(jsonEncode(payments),
          headers: {'Content-Type': 'application/json'});
    } catch (e) {
      return Response.internalServerError(
          body: jsonEncode({'error': 'Failed to get payments: $e'}),
          headers: {'Content-Type': 'application/json'});
    }
  }

  Future<Response> _createPayment(Request request) async {
    try {
      final body = await request.readAsString();
      final data = jsonDecode(body) as Map<String, dynamic>;
      final term = data['term'] as String?;
      final session = data['session'] as String?;

      final id = await _db.insertPayment(data, term: term, session: session);

      final db = await _db.database;
      final rows = await db.query('payments', where: 'id = ?', whereArgs: [id]);
      if (rows.isNotEmpty) {
        final row = rows.first;
        await _writeAuditLog(
          request,
          entityId: id,
          action: 'create',
          studentId: row['studentId'] as int?,
          amount: (row['amount'] as num?)?.toDouble(),
          changes: Map<String, dynamic>.from(row),
        );
      }

      return Response.ok(jsonEncode({'success': true, 'id': id}),
          headers: {'Content-Type': 'application/json'});
    } catch (e) {
      return Response.internalServerError(
          body: jsonEncode({'error': 'Failed to create payment: $e'}),
          headers: {'Content-Type': 'application/json'});
    }
  }

  Future<Response> _updatePayment(Request request, String id) async {
    try {
      final paymentId = int.tryParse(id);
      if (paymentId == null) {
        return Response(400, body: jsonEncode({'error': 'Invalid payment ID'}),
            headers: {'Content-Type': 'application/json'});
      }

      final body = await request.readAsString();
      final data = jsonDecode(body) as Map<String, dynamic>;

      final db = await _db.database;

      final existingRows =
          await db.query('payments', where: 'id = ?', whereArgs: [paymentId]);
      final oldRow = existingRows.isNotEmpty ? existingRows.first : null;

      await db.update('payments', data, where: 'id = ?', whereArgs: [paymentId]);

      if (oldRow != null) {
        final diff = <String, dynamic>{};
        for (final key in data.keys) {
          if (oldRow[key] != data[key]) {
            diff[key] = {'old': oldRow[key], 'new': data[key]};
          }
        }
        if (diff.isNotEmpty) {
          await _writeAuditLog(
            request,
            entityId: paymentId,
            action: 'update',
            studentId: oldRow['studentId'] as int?,
            amount: (data['amount'] as num?)?.toDouble() ??
                (oldRow['amount'] as num?)?.toDouble(),
            changes: diff,
          );
        }
      }

      return Response.ok(jsonEncode({'success': true}),
          headers: {'Content-Type': 'application/json'});
    } catch (e) {
      return Response.internalServerError(
          body: jsonEncode({'error': 'Failed to update payment: $e'}),
          headers: {'Content-Type': 'application/json'});
    }
  }

  Future<Response> _deletePayment(Request request, String id) async {
    try {
      final paymentId = int.tryParse(id);
      if (paymentId == null) {
        return Response(400, body: jsonEncode({'error': 'Invalid payment ID'}),
            headers: {'Content-Type': 'application/json'});
      }

      final db = await _db.database;

      final rows = await db.query('payments', where: 'id = ?', whereArgs: [paymentId]);
      final row = rows.isNotEmpty ? rows.first : null;

      await db.delete('payments', where: 'id = ?', whereArgs: [paymentId]);

      if (row != null) {
        await _writeAuditLog(
          request,
          entityId: paymentId,
          action: 'delete',
          studentId: row['studentId'] as int?,
          amount: (row['amount'] as num?)?.toDouble(),
          changes: Map<String, dynamic>.from(row),
        );
      }

      return Response.ok(jsonEncode({'success': true}),
          headers: {'Content-Type': 'application/json'});
    } catch (e) {
      return Response.internalServerError(
          body: jsonEncode({'error': 'Failed to delete payment: $e'}),
          headers: {'Content-Type': 'application/json'});
    }
  }

  Future<Response> _getPaymentsByDate(Request request, String date) async {
    try {
      final payments = await _db.getPaymentsByExactDate(date);

      return Response.ok(jsonEncode(payments),
          headers: {'Content-Type': 'application/json'});
    } catch (e) {
      return Response.internalServerError(
          body: jsonEncode({'error': 'Failed to get payments by date: $e'}),
          headers: {'Content-Type': 'application/json'});
    }
  }

  Future<Response> _getOutstandingBalance(Request request, String studentId) async {
    try {
      final id = int.tryParse(studentId);
      if (id == null) {
        return Response(400, body: jsonEncode({'error': 'Invalid student ID'}),
            headers: {'Content-Type': 'application/json'});
      }

      final balance = await _db.computeOutstandingBalance(id);

      return Response.ok(jsonEncode({'balance': balance}),
          headers: {'Content-Type': 'application/json'});
    } catch (e) {
      return Response.internalServerError(
          body: jsonEncode({'error': 'Failed to compute balance: $e'}),
          headers: {'Content-Type': 'application/json'});
    }
  }
}
