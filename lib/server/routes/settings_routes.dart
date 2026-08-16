// lib/server/routes/settings_routes.dart
import 'dart:convert';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import '../../db/database_helper.dart';

class SettingsRoutes {
  final DatabaseHelper _db = DatabaseHelper();

  Router get router {
    final router = Router();

    router.get('/<key>', (Request request, String key) async {
      try {
        final value = await _db.getSetting(key);
        return Response.ok(jsonEncode({'value': value}), headers: {'Content-Type': 'application/json'});
      } catch (e) {
        return Response.internalServerError(body: jsonEncode({'error': '$e'}), headers: {'Content-Type': 'application/json'});
      }
    });

    router.put('/<key>', (Request request, String key) async {
      try {
        final data = jsonDecode(await request.readAsString()) as Map<String, dynamic>;
        await _db.setSetting(key, data['value'] as String);
        return Response.ok(jsonEncode({'success': true}), headers: {'Content-Type': 'application/json'});
      } catch (e) {
        return Response.internalServerError(body: jsonEncode({'error': '$e'}), headers: {'Content-Type': 'application/json'});
      }
    });

    router.post('/sms-log', (Request request) async {
      try {
        final data = jsonDecode(await request.readAsString()) as Map<String, dynamic>;
        final id = await _db.insertSmsLog(
          studentId: data['studentId'] as int?,
          phone: data['phone'] as String,
          message: data['message'] as String,
          context: data['context'] as String?,
          status: data['status'] as String,
          errorMessage: data['errorMessage'] as String?,
        );
        return Response.ok(jsonEncode({'success': true, 'id': id}), headers: {'Content-Type': 'application/json'});
      } catch (e) {
        return Response.internalServerError(body: jsonEncode({'error': '$e'}), headers: {'Content-Type': 'application/json'});
      }
    });

    return router;
  }
}
