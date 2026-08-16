// lib/server/routes/staff_financial_routes.dart
// Staff financial records API routes (loans, deductions, incentives,
// salary payments, salary increments/history) — mirrors payments_routes.dart
// / expenses_routes.dart, bundled into one file per entity sub-resource.

import 'dart:convert';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import '../../db/database_helper.dart';
import '../auth_middleware.dart';

class StaffFinancialRoutes {
  final DatabaseHelper _db = DatabaseHelper();

  Router get router {
    final router = Router();

    router.get('/staff/<id>', _getStaffById);

    router.get('/loans', _getLoans);
    router.post('/loans', _createLoan);
    router.get('/loans/<id>', _getLoanById);
    router.put('/loans/<id>', _updateLoan);
    router.delete('/loans/<id>', _deleteLoan);

    router.get('/deductions', _getDeductions);
    router.post('/deductions', _createDeduction);
    router.put('/deductions/<id>', _updateDeduction);
    router.delete('/deductions/<id>', _deleteDeduction);

    router.get('/incentives', _getIncentives);
    router.post('/incentives', _createIncentive);
    router.put('/incentives/<id>', _updateIncentive);
    router.delete('/incentives/<id>', _deleteIncentive);

    router.get('/salary-payments/single', _getStaffSalaryPayment);
    router.get('/salary-payments', _getSalaryPaymentsByMonth);
    router.post('/salary-payments/toggle', _toggleSalaryPayment);
    router.post('/salary-payments/loan-deductions', _setLoanDeductionsApplied);

    router.get('/salary-history/staff/<staffId>', _getSalaryHistoryForStaff);
    router.get('/salary-history', _getAllSalaryHistory);
    router.post('/salary-history', _createSalaryHistory);
    router.delete('/salary-history/<id>', _deleteSalaryHistory);

    router.put('/salary/<id>', _updateStaffSalary);

    return router;
  }

  Future<void> _writeAuditLog(
    Request request, {
    required String entityType,
    required int entityId,
    required String action,
    int? staffId,
    double? amount,
    Map<String, dynamic>? changes,
  }) async {
    final db = await _db.database;
    await db.insert('audit_log', {
      'entityType': entityType,
      'entityId': entityId,
      'action': action,
      'studentId': null,
      'staffId': staffId,
      'amount': amount,
      'changes': changes != null ? jsonEncode(changes) : null,
      'userId': getUserIdFromRequest(request),
      'username': getUsernameFromRequest(request) ?? 'Unknown',
      'timestamp': DateTime.now().toIso8601String(),
    });
  }

  Response _ok(dynamic body) =>
      Response.ok(jsonEncode(body), headers: {'Content-Type': 'application/json'});

  Response _badRequest(String message) => Response(400,
      body: jsonEncode({'error': message}), headers: {'Content-Type': 'application/json'});

  Response _serverError(String message, Object e) => Response.internalServerError(
      body: jsonEncode({'error': '$message: $e'}), headers: {'Content-Type': 'application/json'});

  Future<Response> _getStaffById(Request request, String id) async {
    try {
      final staffId = int.tryParse(id);
      if (staffId == null) return _badRequest('Invalid staff ID');
      final staff = await _db.getStaffById(staffId);
      return _ok(staff);
    } catch (e) {
      return _serverError('Failed to get staff', e);
    }
  }

  // -- Staff Loans --

  Future<Response> _getLoans(Request request) async {
    try {
      return _ok(await _db.getAllStaffLoans());
    } catch (e) {
      return _serverError('Failed to get staff loans', e);
    }
  }

  Future<Response> _getLoanById(Request request, String id) async {
    try {
      final loanId = int.tryParse(id);
      if (loanId == null) return _badRequest('Invalid loan ID');
      return _ok(await _db.getStaffLoanById(loanId));
    } catch (e) {
      return _serverError('Failed to get staff loan', e);
    }
  }

  Future<Response> _createLoan(Request request) async {
    try {
      final data = jsonDecode(await request.readAsString()) as Map<String, dynamic>;
      final id = await _db.insertStaffLoan(data);

      final loan = await _db.getStaffLoanById(id);
      if (loan != null) {
        await _writeAuditLog(
          request,
          entityType: 'staff_loan',
          entityId: id,
          action: 'create',
          staffId: loan['staffId'] as int?,
          amount: (loan['amount'] as num?)?.toDouble(),
          changes: loan,
        );
      }

      return _ok({'success': true, 'id': id});
    } catch (e) {
      return _serverError('Failed to create staff loan', e);
    }
  }

  Future<Response> _updateLoan(Request request, String id) async {
    try {
      final loanId = int.tryParse(id);
      if (loanId == null) return _badRequest('Invalid loan ID');

      final data = jsonDecode(await request.readAsString()) as Map<String, dynamic>;
      final oldRow = await _db.getStaffLoanById(loanId);

      await _db.updateStaffLoan(loanId, data);

      if (oldRow != null) {
        final diff = <String, dynamic>{};
        for (final key in data.keys) {
          if (oldRow[key] != data[key]) diff[key] = {'old': oldRow[key], 'new': data[key]};
        }
        if (diff.isNotEmpty) {
          await _writeAuditLog(
            request,
            entityType: 'staff_loan',
            entityId: loanId,
            action: 'update',
            staffId: oldRow['staffId'] as int?,
            amount: (data['amount'] as num?)?.toDouble() ?? (oldRow['amount'] as num?)?.toDouble(),
            changes: diff,
          );
        }
      }

      return _ok({'success': true});
    } catch (e) {
      return _serverError('Failed to update staff loan', e);
    }
  }

  Future<Response> _deleteLoan(Request request, String id) async {
    try {
      final loanId = int.tryParse(id);
      if (loanId == null) return _badRequest('Invalid loan ID');

      final row = await _db.getStaffLoanById(loanId);
      await _db.deleteStaffLoan(loanId);

      if (row != null) {
        await _writeAuditLog(
          request,
          entityType: 'staff_loan',
          entityId: loanId,
          action: 'delete',
          staffId: row['staffId'] as int?,
          amount: (row['amount'] as num?)?.toDouble(),
          changes: row,
        );
      }

      return _ok({'success': true});
    } catch (e) {
      return _serverError('Failed to delete staff loan', e);
    }
  }

  // -- Staff Deductions --

  Future<Response> _getDeductions(Request request) async {
    try {
      final month = request.url.queryParameters['month'] ?? '';
      return _ok(await _db.getStaffDeductionsByMonth(month));
    } catch (e) {
      return _serverError('Failed to get staff deductions', e);
    }
  }

  Future<Response> _createDeduction(Request request) async {
    try {
      final data = jsonDecode(await request.readAsString()) as Map<String, dynamic>;
      final id = await _db.insertStaffDeduction(data);

      final db = await _db.database;
      final rows = await db.query('staff_deductions', where: 'id = ?', whereArgs: [id]);
      if (rows.isNotEmpty) {
        await _writeAuditLog(
          request,
          entityType: 'staff_deduction',
          entityId: id,
          action: 'create',
          staffId: rows.first['staffId'] as int?,
          amount: (rows.first['amount'] as num?)?.toDouble(),
          changes: rows.first,
        );
      }

      return _ok({'success': true, 'id': id});
    } catch (e) {
      return _serverError('Failed to create staff deduction', e);
    }
  }

  Future<Response> _updateDeduction(Request request, String id) async {
    try {
      final deductionId = int.tryParse(id);
      if (deductionId == null) return _badRequest('Invalid deduction ID');

      final data = jsonDecode(await request.readAsString()) as Map<String, dynamic>;
      final db = await _db.database;
      final existingRows =
          await db.query('staff_deductions', where: 'id = ?', whereArgs: [deductionId]);
      final oldRow = existingRows.isNotEmpty ? existingRows.first : null;

      await _db.updateStaffDeduction(deductionId, data);

      if (oldRow != null) {
        final diff = <String, dynamic>{};
        for (final key in data.keys) {
          if (oldRow[key] != data[key]) diff[key] = {'old': oldRow[key], 'new': data[key]};
        }
        if (diff.isNotEmpty) {
          await _writeAuditLog(
            request,
            entityType: 'staff_deduction',
            entityId: deductionId,
            action: 'update',
            staffId: oldRow['staffId'] as int?,
            amount: (data['amount'] as num?)?.toDouble() ?? (oldRow['amount'] as num?)?.toDouble(),
            changes: diff,
          );
        }
      }

      return _ok({'success': true});
    } catch (e) {
      return _serverError('Failed to update staff deduction', e);
    }
  }

  Future<Response> _deleteDeduction(Request request, String id) async {
    try {
      final deductionId = int.tryParse(id);
      if (deductionId == null) return _badRequest('Invalid deduction ID');

      final db = await _db.database;
      final rows = await db.query('staff_deductions', where: 'id = ?', whereArgs: [deductionId]);
      final row = rows.isNotEmpty ? rows.first : null;

      await _db.deleteStaffDeduction(deductionId);

      if (row != null) {
        await _writeAuditLog(
          request,
          entityType: 'staff_deduction',
          entityId: deductionId,
          action: 'delete',
          staffId: row['staffId'] as int?,
          amount: (row['amount'] as num?)?.toDouble(),
          changes: row,
        );
      }

      return _ok({'success': true});
    } catch (e) {
      return _serverError('Failed to delete staff deduction', e);
    }
  }

  // -- Staff Incentives --

  Future<Response> _getIncentives(Request request) async {
    try {
      final month = request.url.queryParameters['month'] ?? '';
      return _ok(await _db.getStaffIncentivesByMonth(month));
    } catch (e) {
      return _serverError('Failed to get staff incentives', e);
    }
  }

  Future<Response> _createIncentive(Request request) async {
    try {
      final data = jsonDecode(await request.readAsString()) as Map<String, dynamic>;
      final id = await _db.insertStaffIncentive(data);

      final db = await _db.database;
      final rows = await db.query('staff_incentives', where: 'id = ?', whereArgs: [id]);
      if (rows.isNotEmpty) {
        await _writeAuditLog(
          request,
          entityType: 'staff_incentive',
          entityId: id,
          action: 'create',
          staffId: rows.first['staffId'] as int?,
          amount: (rows.first['amount'] as num?)?.toDouble(),
          changes: rows.first,
        );
      }

      return _ok({'success': true, 'id': id});
    } catch (e) {
      return _serverError('Failed to create staff incentive', e);
    }
  }

  Future<Response> _updateIncentive(Request request, String id) async {
    try {
      final incentiveId = int.tryParse(id);
      if (incentiveId == null) return _badRequest('Invalid incentive ID');

      final data = jsonDecode(await request.readAsString()) as Map<String, dynamic>;
      final db = await _db.database;
      final existingRows =
          await db.query('staff_incentives', where: 'id = ?', whereArgs: [incentiveId]);
      final oldRow = existingRows.isNotEmpty ? existingRows.first : null;

      await _db.updateStaffIncentive(incentiveId, data);

      if (oldRow != null) {
        final diff = <String, dynamic>{};
        for (final key in data.keys) {
          if (oldRow[key] != data[key]) diff[key] = {'old': oldRow[key], 'new': data[key]};
        }
        if (diff.isNotEmpty) {
          await _writeAuditLog(
            request,
            entityType: 'staff_incentive',
            entityId: incentiveId,
            action: 'update',
            staffId: oldRow['staffId'] as int?,
            amount: (data['amount'] as num?)?.toDouble() ?? (oldRow['amount'] as num?)?.toDouble(),
            changes: diff,
          );
        }
      }

      return _ok({'success': true});
    } catch (e) {
      return _serverError('Failed to update staff incentive', e);
    }
  }

  Future<Response> _deleteIncentive(Request request, String id) async {
    try {
      final incentiveId = int.tryParse(id);
      if (incentiveId == null) return _badRequest('Invalid incentive ID');

      final db = await _db.database;
      final rows = await db.query('staff_incentives', where: 'id = ?', whereArgs: [incentiveId]);
      final row = rows.isNotEmpty ? rows.first : null;

      await _db.deleteStaffIncentive(incentiveId);

      if (row != null) {
        await _writeAuditLog(
          request,
          entityType: 'staff_incentive',
          entityId: incentiveId,
          action: 'delete',
          staffId: row['staffId'] as int?,
          amount: (row['amount'] as num?)?.toDouble(),
          changes: row,
        );
      }

      return _ok({'success': true});
    } catch (e) {
      return _serverError('Failed to delete staff incentive', e);
    }
  }

  // -- Staff Salary Payments --

  Future<Response> _getSalaryPaymentsByMonth(Request request) async {
    try {
      final month = request.url.queryParameters['month'] ?? '';
      return _ok(await _db.getSalaryPaymentsByMonth(month));
    } catch (e) {
      return _serverError('Failed to get salary payments', e);
    }
  }

  Future<Response> _getStaffSalaryPayment(Request request) async {
    try {
      final staffId = int.tryParse(request.url.queryParameters['staffId'] ?? '');
      final month = request.url.queryParameters['month'];
      if (staffId == null || month == null) return _badRequest('Missing staffId/month');
      return _ok(await _db.getStaffSalaryPayment(staffId, month));
    } catch (e) {
      return _serverError('Failed to get staff salary payment', e);
    }
  }

  Future<Response> _toggleSalaryPayment(Request request) async {
    try {
      final data = jsonDecode(await request.readAsString()) as Map<String, dynamic>;
      final staffId = data['staffId'] as int;
      final month = data['month'] as String;
      final isPaid = data['isPaid'] as bool;
      final paymentMethod = data['paymentMethod'] as String?;
      final notes = data['notes'] as String?;

      final oldRow = await _db.getStaffSalaryPayment(staffId, month);

      await _db.toggleStaffSalaryPayment(staffId, month, isPaid,
          paymentMethod: paymentMethod, notes: notes);

      final newValues = {'isPaid': isPaid, 'paymentMethod': paymentMethod, 'notes': notes};

      if (oldRow == null) {
        await _writeAuditLog(
          request,
          entityType: 'staff_salary_payment',
          entityId: staffId,
          action: 'create',
          staffId: staffId,
          changes: newValues,
        );
      } else {
        final oldValues = {
          'isPaid': oldRow['isPaid'] == 1,
          'paymentMethod': oldRow['paymentMethod'],
          'notes': oldRow['notes'],
        };
        final diff = <String, dynamic>{};
        for (final key in newValues.keys) {
          if (oldValues[key] != newValues[key]) {
            diff[key] = {'old': oldValues[key], 'new': newValues[key]};
          }
        }
        if (diff.isNotEmpty) {
          await _writeAuditLog(
            request,
            entityType: 'staff_salary_payment',
            entityId: oldRow['id'] as int,
            action: 'update',
            staffId: staffId,
            changes: diff,
          );
        }
      }

      return _ok({'success': true});
    } catch (e) {
      return _serverError('Failed to toggle staff salary payment', e);
    }
  }

  Future<Response> _setLoanDeductionsApplied(Request request) async {
    try {
      final data = jsonDecode(await request.readAsString()) as Map<String, dynamic>;
      await _db.setLoanDeductionsAppliedForPayment(
        data['staffId'] as int,
        data['month'] as String,
        data['json'] as String?,
      );
      return _ok({'success': true});
    } catch (e) {
      return _serverError('Failed to set loan deductions applied', e);
    }
  }

  // -- Staff Salary Increments/History --

  Future<Response> _getAllSalaryHistory(Request request) async {
    try {
      return _ok(await _db.getAllSalaryHistory());
    } catch (e) {
      return _serverError('Failed to get salary history', e);
    }
  }

  Future<Response> _getSalaryHistoryForStaff(Request request, String staffId) async {
    try {
      final id = int.tryParse(staffId);
      if (id == null) return _badRequest('Invalid staff ID');
      return _ok(await _db.getSalaryHistory(id));
    } catch (e) {
      return _serverError('Failed to get salary history for staff', e);
    }
  }

  Future<Response> _createSalaryHistory(Request request) async {
    try {
      final data = jsonDecode(await request.readAsString()) as Map<String, dynamic>;
      final staffId = data['staffId'] as int;
      final salary = (data['salary'] as num).toDouble();
      final effectiveMonth = data['effectiveMonth'] as String;
      final reason = data['reason'] as String?;

      final id = await _db.insertSalaryHistory(staffId, salary, effectiveMonth, reason: reason);

      final db = await _db.database;
      final rows = await db.query('staff_salary_history', where: 'id = ?', whereArgs: [id]);
      if (rows.isNotEmpty) {
        await _writeAuditLog(
          request,
          entityType: 'staff_salary_history',
          entityId: id,
          action: 'create',
          staffId: staffId,
          amount: salary,
          changes: rows.first,
        );
      }

      return _ok({'success': true, 'id': id});
    } catch (e) {
      return _serverError('Failed to create salary history', e);
    }
  }

  Future<Response> _deleteSalaryHistory(Request request, String id) async {
    try {
      final historyId = int.tryParse(id);
      if (historyId == null) return _badRequest('Invalid history ID');

      final db = await _db.database;
      final rows =
          await db.query('staff_salary_history', where: 'id = ?', whereArgs: [historyId]);
      final row = rows.isNotEmpty ? rows.first : null;

      await _db.deleteSalaryHistory(historyId);

      if (row != null) {
        await _writeAuditLog(
          request,
          entityType: 'staff_salary_history',
          entityId: historyId,
          action: 'delete',
          staffId: row['staffId'] as int?,
          amount: (row['salary'] as num?)?.toDouble(),
          changes: row,
        );
      }

      return _ok({'success': true});
    } catch (e) {
      return _serverError('Failed to delete salary history', e);
    }
  }

  Future<Response> _updateStaffSalary(Request request, String id) async {
    try {
      final staffId = int.tryParse(id);
      if (staffId == null) return _badRequest('Invalid staff ID');

      final data = jsonDecode(await request.readAsString()) as Map<String, dynamic>;
      final salary = (data['salary'] as num).toDouble();

      await _db.updateStaffSalary(staffId, salary);

      return _ok({'success': true});
    } catch (e) {
      return _serverError('Failed to update staff salary', e);
    }
  }
}
