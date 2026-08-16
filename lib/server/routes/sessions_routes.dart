// lib/server/routes/sessions_routes.dart
import 'dart:convert';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import '../../db/database_helper.dart';

class SessionsRoutes {
  final DatabaseHelper _db = DatabaseHelper();

  Router get router {
    final router = Router();
    router.get('/', (Request request) async {
      try {
        final sessions = await _db.getAllSessions();
        return Response.ok(jsonEncode(sessions), headers: {'Content-Type': 'application/json'});
      } catch (e) {
        return Response.internalServerError(body: jsonEncode({'error': '$e'}), headers: {'Content-Type': 'application/json'});
      }
    });

    router.get('/active', (Request request) async {
      try {
        final session = await _db.getActiveSession();
        return Response.ok(jsonEncode(session), headers: {'Content-Type': 'application/json'});
      } catch (e) {
        return Response.internalServerError(body: jsonEncode({'error': '$e'}), headers: {'Content-Type': 'application/json'});
      }
    });

    router.get('/term', (Request request) async {
      try {
        final term = await _db.getActiveTerm();
        return Response.ok(jsonEncode({'term': term}), headers: {'Content-Type': 'application/json'});
      } catch (e) {
        return Response.internalServerError(body: jsonEncode({'error': '$e'}), headers: {'Content-Type': 'application/json'});
      }
    });

    return router;
  }
}
