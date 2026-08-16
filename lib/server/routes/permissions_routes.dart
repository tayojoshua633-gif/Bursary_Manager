// lib/server/routes/permissions_routes.dart
import 'dart:convert';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import '../../db/database_helper.dart';

class PermissionsRoutes {
  final DatabaseHelper _db = DatabaseHelper();

  Router get router {
    final router = Router();
    router.get('/role/<role>', (Request request, String role) async {
      try {
        final permissions = await _db.getPermissionsByRole(role);
        return Response.ok(jsonEncode(permissions), headers: {'Content-Type': 'application/json'});
      } catch (e) {
        return Response.internalServerError(body: jsonEncode({'error': '$e'}), headers: {'Content-Type': 'application/json'});
      }
    });

    router.get('/check/<role>/<module>', (Request request, String role, String module) async {
      try {
        final hasAccess = await _db.hasPermission(role, module);
        return Response.ok(jsonEncode({'hasPermission': hasAccess}), headers: {'Content-Type': 'application/json'});
      } catch (e) {
        return Response.internalServerError(body: jsonEncode({'error': '$e'}), headers: {'Content-Type': 'application/json'});
      }
    });

    return router;
  }
}
