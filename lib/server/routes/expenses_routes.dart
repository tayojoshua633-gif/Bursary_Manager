// lib/server/routes/expenses_routes.dart
// Expenses API routes (mirrors payments_routes.dart)

import 'dart:convert';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import '../../db/database_helper.dart';
import '../auth_middleware.dart';

class ExpensesRoutes {
  final DatabaseHelper _db = DatabaseHelper();

  Router get router {
    final router = Router();

    router.get('/', _getExpenses);
    router.post('/', _createExpense);
    router.get('/categories', _getCategories);
    router.post('/categories', _createCategory);
    router.put('/categories/<id>', _updateCategory);
    router.delete('/categories/<id>', _deleteCategory);
    router.get('/<id>', _getExpenseById);
    router.put('/<id>', _updateExpense);
    router.delete('/<id>', _deleteExpense);

    return router;
  }

  Future<void> _writeAuditLog(
    Request request, {
    required int entityId,
    required String action,
    double? amount,
    Map<String, dynamic>? changes,
  }) async {
    final db = await _db.database;
    await db.insert('audit_log', {
      'entityType': 'expense',
      'entityId': entityId,
      'action': action,
      'studentId': null,
      'amount': amount,
      'changes': changes != null ? jsonEncode(changes) : null,
      'userId': getUserIdFromRequest(request),
      'username': getUsernameFromRequest(request) ?? 'Unknown',
      'timestamp': DateTime.now().toIso8601String(),
    });
  }

  Future<Response> _getExpenses(Request request) async {
    try {
      final params = request.url.queryParameters;
      final expenses = await _db.getAllExpenses(
        term: params['term'],
        session: params['session'],
        startDate: params['startDate'],
        endDate: params['endDate'],
      );

      return Response.ok(jsonEncode(expenses),
          headers: {'Content-Type': 'application/json'});
    } catch (e) {
      return Response.internalServerError(
          body: jsonEncode({'error': 'Failed to get expenses: $e'}),
          headers: {'Content-Type': 'application/json'});
    }
  }

  Future<Response> _getExpenseById(Request request, String id) async {
    try {
      final expenseId = int.tryParse(id);
      if (expenseId == null) {
        return Response(400, body: jsonEncode({'error': 'Invalid expense ID'}),
            headers: {'Content-Type': 'application/json'});
      }

      final expense = await _db.getExpenseById(expenseId);

      return Response.ok(jsonEncode(expense),
          headers: {'Content-Type': 'application/json'});
    } catch (e) {
      return Response.internalServerError(
          body: jsonEncode({'error': 'Failed to get expense: $e'}),
          headers: {'Content-Type': 'application/json'});
    }
  }

  Future<Response> _createExpense(Request request) async {
    try {
      final body = await request.readAsString();
      final data = jsonDecode(body) as Map<String, dynamic>;

      final id = await _db.insertExpense(data);

      final expense = await _db.getExpenseById(id);
      // Loans auto-post a mirror expense so cash-flow totals stay accurate;
      // the loan's own audit entry already covers this create, so skip a
      // second, redundant "expense created" entry for the same action.
      if (expense != null && expense['category'] != 'Staff Loan') {
        await _writeAuditLog(
          request,
          entityId: id,
          action: 'create',
          amount: (expense['amount'] as num?)?.toDouble(),
          changes: expense,
        );
      }

      return Response.ok(jsonEncode({'success': true, 'id': id}),
          headers: {'Content-Type': 'application/json'});
    } catch (e) {
      return Response.internalServerError(
          body: jsonEncode({'error': 'Failed to create expense: $e'}),
          headers: {'Content-Type': 'application/json'});
    }
  }

  Future<Response> _updateExpense(Request request, String id) async {
    try {
      final expenseId = int.tryParse(id);
      if (expenseId == null) {
        return Response(400, body: jsonEncode({'error': 'Invalid expense ID'}),
            headers: {'Content-Type': 'application/json'});
      }

      final body = await request.readAsString();
      final data = jsonDecode(body) as Map<String, dynamic>;

      final oldRow = await _db.getExpenseById(expenseId);

      await _db.updateExpense(expenseId, data);

      if (oldRow != null && oldRow['category'] != 'Staff Loan') {
        final diff = <String, dynamic>{};
        for (final key in data.keys) {
          if (oldRow[key] != data[key]) {
            diff[key] = {'old': oldRow[key], 'new': data[key]};
          }
        }
        if (diff.isNotEmpty) {
          await _writeAuditLog(
            request,
            entityId: expenseId,
            action: 'update',
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
          body: jsonEncode({'error': 'Failed to update expense: $e'}),
          headers: {'Content-Type': 'application/json'});
    }
  }

  Future<Response> _deleteExpense(Request request, String id) async {
    try {
      final expenseId = int.tryParse(id);
      if (expenseId == null) {
        return Response(400, body: jsonEncode({'error': 'Invalid expense ID'}),
            headers: {'Content-Type': 'application/json'});
      }

      final row = await _db.getExpenseById(expenseId);

      await _db.deleteExpense(expenseId);

      if (row != null && row['category'] != 'Staff Loan') {
        await _writeAuditLog(
          request,
          entityId: expenseId,
          action: 'delete',
          amount: (row['amount'] as num?)?.toDouble(),
          changes: row,
        );
      }

      return Response.ok(jsonEncode({'success': true}),
          headers: {'Content-Type': 'application/json'});
    } catch (e) {
      return Response.internalServerError(
          body: jsonEncode({'error': 'Failed to delete expense: $e'}),
          headers: {'Content-Type': 'application/json'});
    }
  }

  Future<Response> _getCategories(Request request) async {
    try {
      final categories = await _db.getAllExpenseCategories();

      return Response.ok(jsonEncode(categories),
          headers: {'Content-Type': 'application/json'});
    } catch (e) {
      return Response.internalServerError(
          body: jsonEncode({'error': 'Failed to get expense categories: $e'}),
          headers: {'Content-Type': 'application/json'});
    }
  }

  Future<Response> _createCategory(Request request) async {
    try {
      final body = await request.readAsString();
      final data = jsonDecode(body) as Map<String, dynamic>;
      final name = data['name'] as String? ?? '';

      final id = await _db.insertExpenseCategory(name);

      return Response.ok(jsonEncode({'success': true, 'id': id}),
          headers: {'Content-Type': 'application/json'});
    } catch (e) {
      return Response.internalServerError(
          body: jsonEncode({'error': 'Failed to create expense category: $e'}),
          headers: {'Content-Type': 'application/json'});
    }
  }

  Future<Response> _updateCategory(Request request, String id) async {
    try {
      final categoryId = int.tryParse(id);
      if (categoryId == null) {
        return Response(400, body: jsonEncode({'error': 'Invalid category ID'}),
            headers: {'Content-Type': 'application/json'});
      }

      final body = await request.readAsString();
      final data = jsonDecode(body) as Map<String, dynamic>;
      final name = data['name'] as String? ?? '';

      await _db.updateExpenseCategory(categoryId, name);

      return Response.ok(jsonEncode({'success': true}),
          headers: {'Content-Type': 'application/json'});
    } catch (e) {
      return Response.internalServerError(
          body: jsonEncode({'error': 'Failed to update expense category: $e'}),
          headers: {'Content-Type': 'application/json'});
    }
  }

  Future<Response> _deleteCategory(Request request, String id) async {
    try {
      final categoryId = int.tryParse(id);
      if (categoryId == null) {
        return Response(400, body: jsonEncode({'error': 'Invalid category ID'}),
            headers: {'Content-Type': 'application/json'});
      }

      await _db.deleteExpenseCategory(categoryId);

      return Response.ok(jsonEncode({'success': true}),
          headers: {'Content-Type': 'application/json'});
    } catch (e) {
      return Response.internalServerError(
          body: jsonEncode({'error': 'Failed to delete expense category: $e'}),
          headers: {'Content-Type': 'application/json'});
    }
  }
}
