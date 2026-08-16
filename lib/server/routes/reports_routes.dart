// lib/server/routes/reports_routes.dart
import 'dart:convert';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import '../../db/database_helper.dart';

class ReportsRoutes {
  final DatabaseHelper _db = DatabaseHelper();

  Router get router {
    final router = Router();

    // Get debtors list
    router.get('/debtors', (Request request) async {
      try {
        final classId = int.tryParse(request.url.queryParameters['classId'] ?? '0') ?? 0;
        final term = request.url.queryParameters['term'] ?? '';
        final session = request.url.queryParameters['session'] ?? '';
        final minPaid = double.tryParse(request.url.queryParameters['minPercentagePaid'] ?? '0') ?? 0.0;

        final debtors = await _db.getDebtorsList(
          classId: classId,
          term: term,
          session: session,
          minPercentagePaid: minPaid,
        );

        return Response.ok(jsonEncode(debtors), headers: {'Content-Type': 'application/json'});
      } catch (e) {
        return Response.internalServerError(body: jsonEncode({'error': '$e'}), headers: {'Content-Type': 'application/json'});
      }
    });

    // Get total bills for term/session (for dashboard)
    router.get('/total-bills', (Request request) async {
      try {
        final term = request.url.queryParameters['term'] ?? '';
        final session = request.url.queryParameters['session'] ?? '';

        final db = await _db.database;
        final result = await db.rawQuery(
          'SELECT COALESCE(SUM(totalAmount), 0) AS total FROM student_bills WHERE term = ? AND session = ?',
          [term, session],
        );

        final total = (result.first['total'] as num?)?.toDouble() ?? 0.0;
        return Response.ok(jsonEncode({'total': total}), headers: {'Content-Type': 'application/json'});
      } catch (e) {
        return Response.internalServerError(body: jsonEncode({'error': '$e'}), headers: {'Content-Type': 'application/json'});
      }
    });

    // Get total payments for term/session (for dashboard)
    router.get('/total-payments', (Request request) async {
      try {
        final term = request.url.queryParameters['term'] ?? '';
        final session = request.url.queryParameters['session'] ?? '';

        final db = await _db.database;
        final result = await db.rawQuery(
          'SELECT COALESCE(SUM(amount), 0) AS total FROM payments WHERE term = ? AND session = ?',
          [term, session],
        );

        final total = (result.first['total'] as num?)?.toDouble() ?? 0.0;
        return Response.ok(jsonEncode({'total': total}), headers: {'Content-Type': 'application/json'});
      } catch (e) {
        return Response.internalServerError(body: jsonEncode({'error': '$e'}), headers: {'Content-Type': 'application/json'});
      }
    });

    return router;
  }
}
