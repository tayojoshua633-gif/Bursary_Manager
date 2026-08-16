// lib/server/routes/sales_routes.dart
// Sales API routes (mirrors payments_routes.dart / expenses_routes.dart)

import 'dart:convert';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import '../../db/database_helper.dart';
import '../auth_middleware.dart';

class SalesRoutes {
  final DatabaseHelper _db = DatabaseHelper();

  Router get router {
    final router = Router();

    router.post('/', _createSale);
    router.get('/totals-by-method', _getSalesTotalsByMethod);
    router.get('/debtors', _getSalesDebtors);
    router.get('/', _getSales);
    router.get('/<id>', _getSaleById);
    router.put('/<id>/payment', _updateSalePayment);
    router.delete('/<id>', _deleteSale);

    return router;
  }

  Response _ok(dynamic body) =>
      Response.ok(jsonEncode(body), headers: {'Content-Type': 'application/json'});

  Response _badRequest(String message) => Response(400,
      body: jsonEncode({'error': message}), headers: {'Content-Type': 'application/json'});

  Response _serverError(String message, Object e) => Response.internalServerError(
      body: jsonEncode({'error': '$message: $e'}), headers: {'Content-Type': 'application/json'});

  Future<void> _writeAuditLog(
    Request request, {
    required int entityId,
    required String action,
    double? amount,
    Map<String, dynamic>? changes,
  }) async {
    final db = await _db.database;
    await db.insert('audit_log', {
      'entityType': 'sale',
      'entityId': entityId,
      'action': action,
      'amount': amount,
      'changes': changes != null ? jsonEncode(changes) : null,
      'userId': getUserIdFromRequest(request),
      'username': getUsernameFromRequest(request) ?? 'Unknown',
      'timestamp': DateTime.now().toIso8601String(),
    });
  }

  Future<Response> _createSale(Request request) async {
    try {
      final data = jsonDecode(await request.readAsString()) as Map<String, dynamic>;
      final createdBy = data['createdBy'] as String?;
      final id = await _db.insertSale(data, createdBy: createdBy);

      final sale = await _db.getSaleById(id);
      if (sale != null) {
        await _writeAuditLog(
          request,
          entityId: id,
          action: 'create',
          amount: (sale['totalAmount'] as num?)?.toDouble(),
          changes: sale,
        );
      }

      return _ok({'success': true, 'id': id});
    } catch (e) {
      return _serverError('Failed to create sale', e);
    }
  }

  Future<Response> _getSales(Request request) async {
    try {
      final params = request.url.queryParameters;
      if (params.containsKey('date')) {
        return _ok(await _db.getSalesByExactDate(params['date']!));
      }
      final studentId = int.tryParse(params['studentId'] ?? '');
      return _ok(await _db.getAllSales(
        term: params['term'],
        session: params['session'],
        startDate: params['startDate'],
        endDate: params['endDate'],
        studentId: studentId,
      ));
    } catch (e) {
      return _serverError('Failed to get sales', e);
    }
  }

  Future<Response> _getSaleById(Request request, String id) async {
    try {
      final saleId = int.tryParse(id);
      if (saleId == null) return _badRequest('Invalid sale ID');
      return _ok(await _db.getSaleById(saleId));
    } catch (e) {
      return _serverError('Failed to get sale', e);
    }
  }

  Future<Response> _updateSalePayment(Request request, String id) async {
    try {
      final saleId = int.tryParse(id);
      if (saleId == null) return _badRequest('Invalid sale ID');

      final data = jsonDecode(await request.readAsString()) as Map<String, dynamic>;
      final amountPaid = (data['amountPaid'] as num).toDouble();
      final outstandingBalance = (data['outstandingBalance'] as num).toDouble();
      final paymentStatus = data['paymentStatus'] as String;
      final additionalPayment = (data['additionalPayment'] as num).toDouble();

      final paymentReceiptId = await _db.updateSalePayment(
        saleId,
        amountPaid: amountPaid,
        outstandingBalance: outstandingBalance,
        paymentStatus: paymentStatus,
        additionalPayment: additionalPayment,
        paymentMethod: data['paymentMethod'] as String?,
        note: data['note'] as String?,
        term: data['term'] as String?,
        session: data['session'] as String?,
        createdBy: data['createdBy'] as String?,
        paymentTimestamp: data['paymentTimestamp'] as String?,
      );

      await _writeAuditLog(
        request,
        entityId: saleId,
        action: 'update',
        amount: additionalPayment,
        changes: {
          'additionalPayment': additionalPayment,
          'paymentStatus': paymentStatus,
          'outstandingBalance': outstandingBalance,
        },
      );

      return _ok(paymentReceiptId > 0 ? {'paymentReceiptId': paymentReceiptId} : {'success': true});
    } catch (e) {
      return _serverError('Failed to update sale payment', e);
    }
  }

  Future<Response> _getSalesTotalsByMethod(Request request) async {
    try {
      final date = request.url.queryParameters['date'] ?? '';
      return _ok(await _db.getSalesTotalsByMethod(date));
    } catch (e) {
      return _serverError('Failed to get sales totals', e);
    }
  }

  Future<Response> _getSalesDebtors(Request request) async {
    try {
      final params = request.url.queryParameters;
      return _ok(await _db.getSalesDebtors(term: params['term'], session: params['session']));
    } catch (e) {
      return _serverError('Failed to get sales debtors', e);
    }
  }

  Future<Response> _deleteSale(Request request, String id) async {
    try {
      final saleId = int.tryParse(id);
      if (saleId == null) return _badRequest('Invalid sale ID');

      final deletedBy = request.url.queryParameters['deletedBy'];
      final row = await _db.getSaleById(saleId);

      await _db.deleteSale(saleId, deletedBy: deletedBy);

      if (row != null) {
        await _writeAuditLog(
          request,
          entityId: saleId,
          action: 'delete',
          amount: (row['totalAmount'] as num?)?.toDouble(),
          changes: row,
        );
      }

      return _ok({'success': true});
    } catch (e) {
      return _serverError('Failed to delete sale', e);
    }
  }
}
