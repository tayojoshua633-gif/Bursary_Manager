// lib/server/routes/bills_routes.dart
import 'dart:convert';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import '../../db/database_helper.dart';

class BillsRoutes {
  final DatabaseHelper _db = DatabaseHelper();

  Router get router {
    final router = Router();
    router.get('/student/<studentId>', (Request request, String studentId) async {
      try {
        final id = int.tryParse(studentId);
        if (id == null) return Response(400, body: jsonEncode({'error': 'Invalid student ID'}), headers: {'Content-Type': 'application/json'});
        final term = request.url.queryParameters['term'] ?? '';
        final session = request.url.queryParameters['session'] ?? '';
        final bill = await _db.getBillForStudent(id, term, session);
        return Response.ok(jsonEncode(bill), headers: {'Content-Type': 'application/json'});
      } catch (e) {
        return Response.internalServerError(body: jsonEncode({'error': '$e'}), headers: {'Content-Type': 'application/json'});
      }
    });

    router.post('/', (Request request) async {
      try {
        final data = jsonDecode(await request.readAsString()) as Map<String, dynamic>;
        final bill = data['bill'] as Map<String, dynamic>;
        final breakdown = (data['breakdown'] as List).cast<Map<String, dynamic>>();
        final id = await _db.insertBill(bill, breakdown);
        return Response.ok(jsonEncode({'success': true, 'id': id}), headers: {'Content-Type': 'application/json'});
      } catch (e) {
        return Response.internalServerError(body: jsonEncode({'error': '$e'}), headers: {'Content-Type': 'application/json'});
      }
    });

    return router;
  }
}
