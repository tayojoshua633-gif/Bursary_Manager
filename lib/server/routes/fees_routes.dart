// lib/server/routes/fees_routes.dart
import 'dart:convert';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import '../../db/database_helper.dart';

class FeesRoutes {
  final DatabaseHelper _db = DatabaseHelper();

  Router get router {
    final router = Router();
    router.get('/', (Request request) async {
      try {
        final term = request.url.queryParameters['term'];
        final session = request.url.queryParameters['session'];
        final fees = await _db.getFeeItems(term: term, session: session);
        return Response.ok(jsonEncode(fees), headers: {'Content-Type': 'application/json'});
      } catch (e) {
        return Response.internalServerError(body: jsonEncode({'error': '$e'}), headers: {'Content-Type': 'application/json'});
      }
    });

    router.post('/', (Request request) async {
      try {
        final data = jsonDecode(await request.readAsString()) as Map<String, dynamic>;
        final id = await _db.insertFeeItem(data);
        return Response.ok(jsonEncode({'success': true, 'id': id}), headers: {'Content-Type': 'application/json'});
      } catch (e) {
        return Response.internalServerError(body: jsonEncode({'error': '$e'}), headers: {'Content-Type': 'application/json'});
      }
    });

    return router;
  }
}
