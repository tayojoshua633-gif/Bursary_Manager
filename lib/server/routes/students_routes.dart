// lib/server/routes/students_routes.dart
// Students API routes - CRUD operations for students

import 'dart:convert';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import '../../db/database_helper.dart';

class StudentsRoutes {
  final DatabaseHelper _db = DatabaseHelper();

  Router get router {
    final router = Router();

    // Student CRUD operations
    router.get('/', _getStudents);
    router.get('/active', _getActiveStudents);
    router.get('/with-details', _getActiveStudentsWithDetails);
    router.get('/inactive', _getInactiveStudents);
    router.get('/<id>', _getStudent);
    router.post('/', _createStudent);
    router.put('/<id>', _updateStudent);
    router.delete('/<id>', _deleteStudent);

    // Student operations
    router.post('/<id>/deactivate', _deactivateStudent);
    router.post('/<id>/restore', _restoreStudent);
    router.get('/generate-admission-number', _generateAdmissionNumber);

    return router;
  }

  /// GET /api/students?includeInactive=true/false
  /// Get all students (optionally include inactive)
  Future<Response> _getStudents(Request request) async {
    try {
      final includeInactive = request.url.queryParameters['includeInactive'] == 'true';
      final students = await _db.getStudents(includeInactive: includeInactive);

      return Response.ok(
        jsonEncode(students),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e) {
      return Response.internalServerError(
        body: jsonEncode({'error': 'Failed to get students: $e'}),
        headers: {'Content-Type': 'application/json'},
      );
    }
  }

  /// GET /api/students/active
  /// Get only active students
  Future<Response> _getActiveStudents(Request request) async {
    try {
      final students = await _db.getActiveStudents();

      return Response.ok(
        jsonEncode(students),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e) {
      return Response.internalServerError(
        body: jsonEncode({'error': 'Failed to get active students: $e'}),
        headers: {'Content-Type': 'application/json'},
      );
    }
  }

  /// GET /api/students/with-details
  /// Get active students with class and arm names (for student list display)
  Future<Response> _getActiveStudentsWithDetails(Request request) async {
    try {
      final db = await _db.database;
      final students = await db.rawQuery('''
        SELECT
          s.*,
          c.name as className,
          a.name as armName
        FROM students s
        LEFT JOIN classes c ON s.classId = c.id
        LEFT JOIN arms a ON s.armId = a.id
        WHERE s.isActive = 1
        ORDER BY s.surname ASC, s.firstName ASC
      ''');

      return Response.ok(
        jsonEncode(students),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e) {
      return Response.internalServerError(
        body: jsonEncode({'error': 'Failed to get students with details: $e'}),
        headers: {'Content-Type': 'application/json'},
      );
    }
  }

  /// GET /api/students/inactive
  /// Get only inactive students
  Future<Response> _getInactiveStudents(Request request) async {
    try {
      final students = await _db.getInactiveStudents();

      return Response.ok(
        jsonEncode(students),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e) {
      return Response.internalServerError(
        body: jsonEncode({'error': 'Failed to get inactive students: $e'}),
        headers: {'Content-Type': 'application/json'},
      );
    }
  }

  /// GET /api/students/:id
  /// Get student by ID
  Future<Response> _getStudent(Request request, String id) async {
    try {
      final studentId = int.tryParse(id);
      if (studentId == null) {
        return Response(
          400,
          body: jsonEncode({'error': 'Invalid student ID'}),
          headers: {'Content-Type': 'application/json'},
        );
      }

      final student = await _db.getStudentById(studentId);

      if (student == null) {
        return Response.notFound(
          jsonEncode({'error': 'Student not found'}),
          headers: {'Content-Type': 'application/json'},
        );
      }

      return Response.ok(
        jsonEncode(student),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e) {
      return Response.internalServerError(
        body: jsonEncode({'error': 'Failed to get student: $e'}),
        headers: {'Content-Type': 'application/json'},
      );
    }
  }

  /// POST /api/students
  /// Create new student
  Future<Response> _createStudent(Request request) async {
    try {
      final body = await request.readAsString();
      final data = jsonDecode(body) as Map<String, dynamic>;

      final id = await _db.insertStudent(data);

      return Response.ok(
        jsonEncode({'success': true, 'id': id}),
        headers: {'Content-Type': 'application/json'},
      );
    } on StudentLimitExceededException catch (e) {
      return Response(
        403,
        body: jsonEncode({'error': e.message}),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e) {
      return Response.internalServerError(
        body: jsonEncode({'error': 'Failed to create student: $e'}),
        headers: {'Content-Type': 'application/json'},
      );
    }
  }

  /// PUT /api/students/:id
  /// Update student
  Future<Response> _updateStudent(Request request, String id) async {
    try {
      final studentId = int.tryParse(id);
      if (studentId == null) {
        return Response(
          400,
          body: jsonEncode({'error': 'Invalid student ID'}),
          headers: {'Content-Type': 'application/json'},
        );
      }

      final body = await request.readAsString();
      final data = jsonDecode(body) as Map<String, dynamic>;

      await _db.updateStudent(studentId, data);

      return Response.ok(
        jsonEncode({'success': true}),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e) {
      return Response.internalServerError(
        body: jsonEncode({'error': 'Failed to update student: $e'}),
        headers: {'Content-Type': 'application/json'},
      );
    }
  }

  /// DELETE /api/students/:id
  /// Delete student
  Future<Response> _deleteStudent(Request request, String id) async {
    try {
      final studentId = int.tryParse(id);
      if (studentId == null) {
        return Response(
          400,
          body: jsonEncode({'error': 'Invalid student ID'}),
          headers: {'Content-Type': 'application/json'},
        );
      }

      await _db.deleteStudent(studentId);

      return Response.ok(
        jsonEncode({'success': true}),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e) {
      return Response.internalServerError(
        body: jsonEncode({'error': 'Failed to delete student: $e'}),
        headers: {'Content-Type': 'application/json'},
      );
    }
  }

  /// POST /api/students/:id/deactivate
  /// Deactivate student
  Future<Response> _deactivateStudent(Request request, String id) async {
    try {
      final studentId = int.tryParse(id);
      if (studentId == null) {
        return Response(
          400,
          body: jsonEncode({'error': 'Invalid student ID'}),
          headers: {'Content-Type': 'application/json'},
        );
      }

      final body = await request.readAsString();
      final data = jsonDecode(body) as Map<String, dynamic>;

      final leftDate = data['leftDate'] as String?;
      final leftReason = data['leftReason'] as String?;

      if (leftDate == null || leftReason == null) {
        return Response(
          400,
          body: jsonEncode({'error': 'leftDate and leftReason required'}),
          headers: {'Content-Type': 'application/json'},
        );
      }

      await _db.deactivateStudent(studentId, leftDate, leftReason);

      return Response.ok(
        jsonEncode({'success': true}),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e) {
      return Response.internalServerError(
        body: jsonEncode({'error': 'Failed to deactivate student: $e'}),
        headers: {'Content-Type': 'application/json'},
      );
    }
  }

  /// POST /api/students/:id/restore
  /// Restore deactivated student
  Future<Response> _restoreStudent(Request request, String id) async {
    try {
      final studentId = int.tryParse(id);
      if (studentId == null) {
        return Response(
          400,
          body: jsonEncode({'error': 'Invalid student ID'}),
          headers: {'Content-Type': 'application/json'},
        );
      }

      await _db.restoreStudent(studentId);

      return Response.ok(
        jsonEncode({'success': true}),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e) {
      return Response.internalServerError(
        body: jsonEncode({'error': 'Failed to restore student: $e'}),
        headers: {'Content-Type': 'application/json'},
      );
    }
  }

  /// GET /api/students/generate-admission-number
  /// Generate new admission number
  Future<Response> _generateAdmissionNumber(Request request) async {
    try {
      final admissionNo = await _db.generateAdmissionNumber();

      return Response.ok(
        jsonEncode({'admissionNo': admissionNo}),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e) {
      return Response.internalServerError(
        body: jsonEncode({'error': 'Failed to generate admission number: $e'}),
        headers: {'Content-Type': 'application/json'},
      );
    }
  }
}
