// lib/server/routes/transport_routes.dart
import 'dart:convert';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import '../../db/database_helper.dart';

class TransportRoutes {
  final DatabaseHelper _db = DatabaseHelper();

  Response _json(Object? data) =>
      Response.ok(jsonEncode(data), headers: {'Content-Type': 'application/json'});

  Response _error(Object e) {
    if (e is StateError) {
      return Response(400,
          body: jsonEncode({'error': e.message}),
          headers: {'Content-Type': 'application/json'});
    }
    return Response.internalServerError(
        body: jsonEncode({'error': '$e'}), headers: {'Content-Type': 'application/json'});
  }

  Router get router {
    final router = Router();

    router.get('/routes', (Request request) async {
      try {
        final includeInactive = request.url.queryParameters['includeInactive'] == 'true';
        final routes = await _db.getTransportRoutes(includeInactive: includeInactive);
        return _json(routes);
      } catch (e) {
        return _error(e);
      }
    });

    router.get('/routes/<id>', (Request request, String id) async {
      try {
        final route = await _db.getTransportRouteById(int.parse(id));
        return _json(route);
      } catch (e) {
        return _error(e);
      }
    });

    router.get('/routes/<id>/allocation-count', (Request request, String id) async {
      try {
        final count = await _db.countActiveAllocationsForRoute(int.parse(id));
        return _json({'count': count});
      } catch (e) {
        return _error(e);
      }
    });

    router.post('/routes', (Request request) async {
      try {
        final data = jsonDecode(await request.readAsString()) as Map<String, dynamic>;
        final id = await _db.insertTransportRoute(data);
        return _json({'success': true, 'id': id});
      } catch (e) {
        return _error(e);
      }
    });

    router.put('/routes/<id>', (Request request, String id) async {
      try {
        final data = jsonDecode(await request.readAsString()) as Map<String, dynamic>;
        await _db.updateTransportRoute(int.parse(id), data);
        return _json({'success': true});
      } catch (e) {
        return _error(e);
      }
    });

    router.delete('/routes/<id>', (Request request, String id) async {
      try {
        await _db.deleteTransportRoute(int.parse(id));
        return _json({'success': true});
      } catch (e) {
        return _error(e);
      }
    });

    router.get('/allocations/student/<studentId>', (Request request, String studentId) async {
      try {
        final term = request.url.queryParameters['term'] ?? '';
        final session = request.url.queryParameters['session'] ?? '';
        final alloc = await _db.getStudentTransportAllocation(int.parse(studentId), term, session);
        return _json(alloc);
      } catch (e) {
        return _error(e);
      }
    });

    router.get('/allocations', (Request request) async {
      try {
        final term = request.url.queryParameters['term'] ?? '';
        final session = request.url.queryParameters['session'] ?? '';
        final rows = await _db.getRouteAllocationsWithDetails(term, session);
        return _json(rows);
      } catch (e) {
        return _error(e);
      }
    });

    router.post('/allocations', (Request request) async {
      try {
        final data = jsonDecode(await request.readAsString()) as Map<String, dynamic>;
        final id = await _db.allocateStudentToRoute(
          studentId: data['studentId'],
          routeId: data['routeId'],
          term: data['term'],
          session: data['session'],
        );
        return _json({'success': true, 'id': id});
      } catch (e) {
        return _error(e);
      }
    });

    router.delete('/allocations/student/<studentId>', (Request request, String studentId) async {
      try {
        final term = request.url.queryParameters['term'] ?? '';
        final session = request.url.queryParameters['session'] ?? '';
        final deleted = await _db.removeStudentFromRoute(int.parse(studentId), term, session);
        return _json({'success': true, 'deleted': deleted});
      } catch (e) {
        return _error(e);
      }
    });

    return router;
  }
}
