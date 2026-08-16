// lib/server/routes/school_routes.dart
import 'dart:convert';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import '../../db/database_helper.dart';

class SchoolRoutes {
  final DatabaseHelper _db = DatabaseHelper();

  Router get router {
    final router = Router();
    router.get('/profile', (Request request) async {
      try {
        final profile = await _db.getSchoolProfile();
        return Response.ok(jsonEncode(profile), headers: {'Content-Type': 'application/json'});
      } catch (e) {
        return Response.internalServerError(body: jsonEncode({'error': '$e'}), headers: {'Content-Type': 'application/json'});
      }
    });

    router.post('/profile', (Request request) async {
      try {
        final data = jsonDecode(await request.readAsString()) as Map<String, dynamic>;
        final id = await _db.saveSchoolProfile(data);
        return Response.ok(jsonEncode({'success': true, 'id': id}), headers: {'Content-Type': 'application/json'});
      } catch (e) {
        return Response.internalServerError(body: jsonEncode({'error': '$e'}), headers: {'Content-Type': 'application/json'});
      }
    });

    return router;
  }
}
