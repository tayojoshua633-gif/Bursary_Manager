// lib/server/routes/classes_routes.dart
import 'dart:convert';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import '../../db/database_helper.dart';

class ClassesRoutes {
  final DatabaseHelper _db = DatabaseHelper();

  Router get router {
    final router = Router();
    router.get('/', (Request request) async {
      try {
        final classes = await _db.getClasses();
        return Response.ok(jsonEncode(classes), headers: {'Content-Type': 'application/json'});
      } catch (e) {
        return Response.internalServerError(body: jsonEncode({'error': '$e'}), headers: {'Content-Type': 'application/json'});
      }
    });

    router.post('/', (Request request) async {
      try {
        final data = jsonDecode(await request.readAsString()) as Map<String, dynamic>;
        final id = await _db.insertClass(data);
        return Response.ok(jsonEncode({'success': true, 'id': id}), headers: {'Content-Type': 'application/json'});
      } catch (e) {
        return Response.internalServerError(body: jsonEncode({'error': '$e'}), headers: {'Content-Type': 'application/json'});
      }
    });

    router.get('/arms', (Request request) async {
      try {
        final arms = await _db.getArms();
        return Response.ok(jsonEncode(arms), headers: {'Content-Type': 'application/json'});
      } catch (e) {
        return Response.internalServerError(body: jsonEncode({'error': '$e'}), headers: {'Content-Type': 'application/json'});
      }
    });

    router.get('/<classId>/arms', (Request request, String classId) async {
      try {
        final id = int.tryParse(classId);
        if (id == null) return Response(400, body: jsonEncode({'error': 'Invalid class ID'}), headers: {'Content-Type': 'application/json'});
        final arms = await _db.getArmsByClass(id);
        return Response.ok(jsonEncode(arms), headers: {'Content-Type': 'application/json'});
      } catch (e) {
        return Response.internalServerError(body: jsonEncode({'error': '$e'}), headers: {'Content-Type': 'application/json'});
      }
    });

    return router;
  }
}
