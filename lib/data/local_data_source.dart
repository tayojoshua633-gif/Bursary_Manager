// lib/data/local_data_source.dart
// Local data source that wraps DatabaseHelper
// Used in Standalone and Server modes

import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';
import '../db/database_helper.dart';
import 'repository.dart';

class LocalDataSource implements DataRepository {
  final DatabaseHelper _db = DatabaseHelper();

  // ========================================
  // AUDIT LOG (internal helper — used by payments create/update/delete below)
  // ========================================

  Future<void> _writeAuditLog(
    Database db, {
    required String entityType,
    required int entityId,
    required String action,
    int? studentId,
    int? staffId,
    double? amount,
    Map<String, dynamic>? changes,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await db.insert('audit_log', {
      'entityType': entityType,
      'entityId': entityId,
      'action': action,
      'studentId': studentId,
      'staffId': staffId,
      'amount': amount,
      'changes': changes != null ? jsonEncode(changes) : null,
      'userId': prefs.getInt('userId'),
      'username': prefs.getString('username') ?? 'Unknown',
      'timestamp': DateTime.now().toIso8601String(),
    });
  }

  // ========================================
  // AUTHENTICATION & USERS
  // ========================================

  @override
  Future<Map<String, dynamic>?> authenticateUser(String username, String password) {
    return _db.authenticateUser(username, password);
  }

  @override
  Future<Map<String, dynamic>?> getUserByUsername(String username) {
    return _db.getUserByUsername(username);
  }

  @override
  Future<List<Map<String, dynamic>>> getAllUsers() {
    return _db.getAllUsers();
  }

  @override
  Future<Map<String, dynamic>?> getUserById(int userId) {
    return _db.getUserById(userId);
  }

  @override
  Future<bool> updateUserCredentials({
    required int userId,
    required String newUsername,
    required String newPassword,
  }) {
    return _db.updateUserCredentials(
      userId: userId,
      newUsername: newUsername,
      newPassword: newPassword,
    );
  }

  @override
  Future<bool> resetBursarCredentials({
    required String newUsername,
    required String newPassword,
  }) {
    return _db.resetBursarCredentials(
      newUsername: newUsername,
      newPassword: newPassword,
    );
  }

  @override
  Future<Map<String, dynamic>?> getBursarAccount() {
    return _db.getBursarAccount();
  }

  @override
  Future<int?> createUser({
    required String username,
    required String password,
    required String userType,
    required int canChangeCredentials,
  }) {
    return _db.createUser(
      username: username,
      password: password,
      userType: userType,
      canChangeCredentials: canChangeCredentials,
    );
  }

  @override
  Future<bool> updateUser({
    required int userId,
    required String username,
    required String password,
    required String userType,
    required int canChangeCredentials,
  }) {
    return _db.updateUser(
      userId: userId,
      username: username,
      password: password,
      userType: userType,
      canChangeCredentials: canChangeCredentials,
    );
  }

  @override
  Future<Map<String, dynamic>> deleteUser(int userId) {
    return _db.deleteUser(userId);
  }

  @override
  Future<int> countSuperAdmins() {
    return _db.countSuperAdmins();
  }

  // ========================================
  // PERMISSIONS
  // ========================================

  @override
  Future<List<Map<String, dynamic>>> getPermissionsByRole(String role) {
    return _db.getPermissionsByRole(role);
  }

  @override
  Future<bool> hasPermission(String role, String module) {
    return _db.hasPermission(role, module);
  }

  @override
  Future<void> setPermission(String role, String module, bool canAccess) {
    return _db.setPermission(role, module, canAccess);
  }

  @override
  Future<void> updateRolePermissions(String role, Map<String, bool> permissions) {
    return _db.updateRolePermissions(role, permissions);
  }

  // ========================================
  // SESSIONS & TERMS
  // ========================================

  @override
  Future<String> getActiveTerm() {
    return _db.getActiveTerm();
  }

  @override
  Future<void> setActiveTerm(String term) {
    return _db.setActiveTerm(term);
  }

  @override
  Future<Map<String, dynamic>?> getActiveSession() {
    return _db.getActiveSession();
  }

  @override
  Future<List<Map<String, dynamic>>> getAllSessions() {
    return _db.getAllSessions();
  }

  @override
  Future<List<Map<String, dynamic>>> getSessions() {
    return _db.getSessions();
  }

  @override
  Future<void> setActiveSession(int sessionId) {
    return _db.setActiveSession(sessionId);
  }

  // ========================================
  // STUDENTS
  // ========================================

  @override
  Future<int> insertStudent(Map<String, dynamic> student) {
    return _db.insertStudent(student);
  }

  @override
  Future<List<Map<String, dynamic>>> getStudents({bool includeInactive = false}) {
    return _db.getStudents(includeInactive: includeInactive);
  }

  @override
  Future<List<Map<String, dynamic>>> getActiveStudents() {
    return _db.getActiveStudents();
  }

  @override
  Future<List<Map<String, dynamic>>> getActiveStudentsWithDetails() async {
    final db = await _db.database;
    return await db.rawQuery('''
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
  }

  @override
  Future<List<Map<String, dynamic>>> getInactiveStudents() {
    return _db.getInactiveStudents();
  }

  @override
  Future<Map<String, dynamic>?> getStudentById(int id) {
    return _db.getStudentById(id);
  }

  @override
  Future<Map<String, dynamic>?> getStudentByIdWithDetails(int id) async {
    final db = await _db.database;
    final result = await db.rawQuery('''
      SELECT
        s.*,
        c.name as className,
        a.name as armName
      FROM students s
      LEFT JOIN classes c ON s.classId = c.id
      LEFT JOIN arms a ON s.armId = a.id
      WHERE s.id = ?
    ''', [id]);

    return result.isNotEmpty ? result.first : null;
  }

  @override
  Future<int> updateStudent(int id, Map<String, dynamic> student) {
    return _db.updateStudent(id, student);
  }

  @override
  Future<int> deleteStudent(int id) {
    return _db.deleteStudent(id);
  }

  @override
  Future<int> deactivateStudent(int studentId, String leftDate, String leftReason) {
    return _db.deactivateStudent(studentId, leftDate, leftReason);
  }

  @override
  Future<int> restoreStudent(int studentId) {
    return _db.restoreStudent(studentId);
  }

  @override
  Future<String> generateAdmissionNumber() {
    return _db.generateAdmissionNumber();
  }

  // ========================================
  // PARENTS
  // ========================================

  @override
  Future<int> insertParent(Map<String, dynamic> parent) {
    return _db.insertParent(parent);
  }

  @override
  Future<List<Map<String, dynamic>>> getAllParents() {
    return _db.getAllParents();
  }

  @override
  Future<Map<String, dynamic>?> getParentById(int id) {
    return _db.getParentById(id);
  }

  @override
  Future<List<Map<String, dynamic>>> searchParents(String query) {
    return _db.searchParents(query);
  }

  @override
  Future<int> updateParent(int id, Map<String, dynamic> parent) {
    return _db.updateParent(id, parent);
  }

  @override
  Future<int> deleteParent(int id) {
    return _db.deleteParent(id);
  }

  // ========================================
  // CLASSES
  // ========================================

  @override
  Future<int> insertClass(Map<String, dynamic> cls) {
    return _db.insertClass(cls);
  }

  @override
  Future<List<Map<String, dynamic>>> getClasses() {
    return _db.getClasses();
  }

  @override
  Future<int> updateClass(int id, Map<String, dynamic> cls) {
    return _db.updateClass(id, cls);
  }

  @override
  Future<int> deleteClass(int id) {
    return _db.deleteClass(id);
  }

  // ========================================
  // ARMS
  // ========================================

  @override
  Future<int> insertArm(Map<String, dynamic> arm) {
    return _db.insertArm(arm);
  }

  @override
  Future<List<Map<String, dynamic>>> getArmsByClass(int classId) {
    return _db.getArmsByClass(classId);
  }

  @override
  Future<List<Map<String, dynamic>>> getArms() {
    return _db.getArms();
  }

  @override
  Future<int> updateArm(int id, Map<String, dynamic> arm) {
    return _db.updateArm(id, arm);
  }

  @override
  Future<int> deleteArm(int id) {
    return _db.deleteArm(id);
  }

  // ========================================
  // FEE ITEMS
  // ========================================

  @override
  Future<int> insertFeeItem(Map<String, dynamic> item) {
    return _db.insertFeeItem(item);
  }

  @override
  Future<List<Map<String, dynamic>>> getFeeItems({String? term, String? session}) {
    return _db.getFeeItems(term: term, session: session);
  }

  @override
  Future<int> updateFeeItem(int id, Map<String, dynamic> item) {
    return _db.updateFeeItem(id, item);
  }

  @override
  Future<int> deleteFeeItem(int id) {
    return _db.deleteFeeItem(id);
  }

  // ========================================
  // CLASS FEES
  // ========================================

  @override
  Future<int> insertClassFee(Map<String, dynamic> classFee) {
    return _db.insertClassFee(classFee);
  }

  @override
  Future<List<Map<String, dynamic>>> getClassFees(int classId, String term, String session, {int? armId}) {
    return _db.getClassFees(classId, term, session, armId: armId);
  }

  @override
  Future<int> deleteClassFee(int id) {
    return _db.deleteClassFee(id);
  }

  @override
  Future<void> replaceClassFeesFor(
    int classId,
    String term,
    String session,
    List<Map<String, dynamic>> fees, {
    int? armId,
  }) {
    return _db.replaceClassFeesFor(classId, term, session, fees, armId: armId);
  }

  // ========================================
  // SPECIAL FEE ITEMS (for new intake students)
  // ========================================

  @override
  Future<int> insertSpecialFeeItem(Map<String, dynamic> item) {
    return _db.insertSpecialFeeItem(item);
  }

  @override
  Future<List<Map<String, dynamic>>> getSpecialFeeItems({String? term, String? session, bool? parentsOnly, int? parentId, bool? categoriesOnly, bool? standaloneOnly}) {
    return _db.getSpecialFeeItems(term: term, session: session, parentsOnly: parentsOnly, parentId: parentId, categoriesOnly: categoriesOnly, standaloneOnly: standaloneOnly);
  }

  @override
  Future<List<Map<String, dynamic>>> getSpecialFeeItemParents({String? term, String? session}) {
    return _db.getSpecialFeeItemParents(term: term, session: session);
  }

  @override
  Future<List<Map<String, dynamic>>> getSpecialFeeItemCategories({String? term, String? session}) {
    return _db.getSpecialFeeItemCategories(term: term, session: session);
  }

  @override
  Future<List<Map<String, dynamic>>> getSpecialFeeItemStandalone({String? term, String? session}) {
    return _db.getSpecialFeeItemStandalone(term: term, session: session);
  }

  @override
  Future<List<Map<String, dynamic>>> getSpecialFeeItemChildren(int parentId, {String? term, String? session}) {
    return _db.getSpecialFeeItemChildren(parentId, term: term, session: session);
  }

  @override
  Future<bool> specialFeeItemHasChildren(int itemId) {
    return _db.specialFeeItemHasChildren(itemId);
  }

  @override
  Future<List<Map<String, dynamic>>> getSpecialFeeItemsHierarchy({String? term, String? session}) {
    return _db.getSpecialFeeItemsHierarchy(term: term, session: session);
  }

  @override
  Future<int> updateSpecialFeeItem(int id, Map<String, dynamic> item) {
    return _db.updateSpecialFeeItem(id, item);
  }

  @override
  Future<int> deleteSpecialFeeItem(int id) {
    return _db.deleteSpecialFeeItem(id);
  }

  // ========================================
  // SPECIAL CLASS FEES (for new intake students)
  // ========================================

  @override
  Future<int> insertSpecialClassFee(Map<String, dynamic> classFee) {
    return _db.insertSpecialClassFee(classFee);
  }

  @override
  Future<List<Map<String, dynamic>>> getSpecialClassFees(int classId, String term, String session, {int? armId}) {
    return _db.getSpecialClassFees(classId, term, session, armId: armId);
  }

  @override
  Future<int> deleteSpecialClassFee(int id) {
    return _db.deleteSpecialClassFee(id);
  }

  @override
  Future<void> replaceSpecialClassFeesFor(
    int classId,
    String term,
    String session,
    List<Map<String, dynamic>> fees, {
    int? armId,
  }) {
    return _db.replaceSpecialClassFeesFor(classId, term, session, fees, armId: armId);
  }

  @override
  Future<Map<String, dynamic>> getNewIntakeBillForClass(int classId, String term, String session, {int? armId}) {
    return _db.getNewIntakeBillForClass(classId, term, session, armId: armId);
  }

  // ========================================
  // BILLS
  // ========================================

  @override
  Future<int> insertBill(Map<String, dynamic> bill, List<Map<String, dynamic>> breakdown) {
    return _db.insertBill(bill, breakdown);
  }

  @override
  Future<int> insertStudentBill(Map<String, dynamic> bill, List<Map<String, dynamic>> breakdown) {
    return _db.insertStudentBill(bill, breakdown);
  }

  @override
  Future<Map<String, dynamic>?> getBillForStudent(int studentId, String term, String session) {
    return _db.getBillForStudent(studentId, term, session);
  }

  @override
  Future<List<Map<String, dynamic>>> getBillBreakdown(int billId) {
    return _db.getBillBreakdown(billId);
  }

  @override
  Future<double> computeOutstandingForTermSession(
    int studentId, {
    required String term,
    required String session,
  }) {
    return _db.computeOutstandingForTermSession(
      studentId,
      term: term,
      session: session,
    );
  }

  @override
  Future<double> computeOutstandingBeforeTerm(
    int studentId, {
    required String term,
    required String session,
  }) {
    return _db.computeOutstandingBeforeTerm(
      studentId,
      term: term,
      session: session,
    );
  }

  @override
  Future<int> recalculatePreviousBalances() {
    return _db.recalculatePreviousBalances();
  }

  // ========================================
  // PAYMENTS
  // ========================================

  @override
  Future<int> insertPayment(Map<String, dynamic> payment, {String? term, String? session}) async {
    final id = await _db.insertPayment(payment, term: term, session: session);

    final db = await _db.database;
    final rows = await db.query('payments', where: 'id = ?', whereArgs: [id]);
    if (rows.isNotEmpty) {
      final row = rows.first;
      await _writeAuditLog(
        db,
        entityType: 'payment',
        entityId: id,
        action: 'create',
        studentId: row['studentId'] as int?,
        amount: (row['amount'] as num?)?.toDouble(),
        changes: Map<String, dynamic>.from(row),
      );
    }

    return id;
  }

  @override
  Future<List<Map<String, dynamic>>> getPaymentsByExactDate(String date) {
    return _db.getPaymentsByExactDate(date);
  }

  @override
  Future<List<Map<String, dynamic>>> getPayments(
    int studentId, {
    String? term,
    String? session,
  }) {
    return _db.getPayments(studentId, term: term, session: session);
  }

  @override
  Future<double> computeOutstandingBalance(int studentId) {
    return _db.computeOutstandingBalance(studentId);
  }

  @override
  Future<int> updatePayment(int paymentId, Map<String, dynamic> updates) async {
    final db = await _db.database;

    final existingRows =
        await db.query('payments', where: 'id = ?', whereArgs: [paymentId]);
    final oldRow = existingRows.isNotEmpty ? existingRows.first : null;

    final result = await db.update(
      'payments',
      updates,
      where: 'id = ?',
      whereArgs: [paymentId],
    );

    if (oldRow != null) {
      final diff = <String, dynamic>{};
      for (final key in updates.keys) {
        if (oldRow[key] != updates[key]) {
          diff[key] = {'old': oldRow[key], 'new': updates[key]};
        }
      }
      if (diff.isNotEmpty) {
        await _writeAuditLog(
          db,
          entityType: 'payment',
          entityId: paymentId,
          action: 'update',
          studentId: oldRow['studentId'] as int?,
          amount: (updates['amount'] as num?)?.toDouble() ??
              (oldRow['amount'] as num?)?.toDouble(),
          changes: diff,
        );
      }
    }

    return result;
  }

  @override
  Future<int> deletePayment(int paymentId) async {
    final db = await _db.database;

    final rows = await db.query('payments', where: 'id = ?', whereArgs: [paymentId]);
    final row = rows.isNotEmpty ? rows.first : null;

    final result = await db.delete('payments', where: 'id = ?', whereArgs: [paymentId]);

    if (row != null) {
      await _writeAuditLog(
        db,
        entityType: 'payment',
        entityId: paymentId,
        action: 'delete',
        studentId: row['studentId'] as int?,
        amount: (row['amount'] as num?)?.toDouble(),
        changes: Map<String, dynamic>.from(row),
      );
    }

    return result;
  }

  @override
  Future<void> insertAuditLog({
    required String entityType,
    required int entityId,
    required String action,
    int? studentId,
    double? amount,
    Map<String, dynamic>? changes,
  }) async {
    final db = await _db.database;
    await _writeAuditLog(
      db,
      entityType: entityType,
      entityId: entityId,
      action: action,
      studentId: studentId,
      amount: amount,
      changes: changes,
    );
  }

  @override
  Future<List<Map<String, dynamic>>> getAuditLog({
    String? entityType,
    int? entityId,
    DateTime? from,
    DateTime? to,
    int? userId,
  }) async {
    final db = await _db.database;

    final conditions = <String>[];
    final args = <dynamic>[];

    if (entityType != null) {
      conditions.add('entityType = ?');
      args.add(entityType);
    }
    if (entityId != null) {
      conditions.add('entityId = ?');
      args.add(entityId);
    }
    if (from != null) {
      conditions.add('timestamp >= ?');
      args.add(from.toIso8601String());
    }
    if (to != null) {
      conditions.add('timestamp <= ?');
      args.add(to.toIso8601String());
    }
    if (userId != null) {
      conditions.add('userId = ?');
      args.add(userId);
    }

    return db.query(
      'audit_log',
      where: conditions.isEmpty ? null : conditions.join(' AND '),
      whereArgs: args.isEmpty ? null : args,
      orderBy: 'timestamp DESC',
    );
  }

  // ========================================
  // EXPENSES
  // ========================================

  @override
  Future<int> insertExpense(Map<String, dynamic> expense) async {
    final id = await _db.insertExpense(expense);

    final db = await _db.database;
    final rows = await db.query('expenses', where: 'id = ?', whereArgs: [id]);
    // Loans auto-post a mirror expense so cash-flow totals stay accurate;
    // the loan's own audit entry already covers this create, so skip a
    // second, redundant "expense created" entry for the same action.
    if (rows.isNotEmpty && rows.first['category'] != 'Staff Loan') {
      await _writeAuditLog(
        db,
        entityType: 'expense',
        entityId: id,
        action: 'create',
        amount: (rows.first['amount'] as num?)?.toDouble(),
        changes: Map<String, dynamic>.from(rows.first),
      );
    }

    return id;
  }

  @override
  Future<List<Map<String, dynamic>>> getAllExpenses({
    String? term,
    String? session,
    String? startDate,
    String? endDate,
  }) {
    return _db.getAllExpenses(
      term: term,
      session: session,
      startDate: startDate,
      endDate: endDate,
    );
  }

  @override
  Future<Map<String, dynamic>?> getExpenseById(int id) {
    return _db.getExpenseById(id);
  }

  @override
  Future<int> updateExpense(int id, Map<String, dynamic> expense) async {
    final db = await _db.database;

    final existingRows = await db.query('expenses', where: 'id = ?', whereArgs: [id]);
    final oldRow = existingRows.isNotEmpty ? existingRows.first : null;

    final result = await _db.updateExpense(id, expense);

    if (oldRow != null && oldRow['category'] != 'Staff Loan') {
      final diff = <String, dynamic>{};
      for (final key in expense.keys) {
        if (oldRow[key] != expense[key]) {
          diff[key] = {'old': oldRow[key], 'new': expense[key]};
        }
      }
      if (diff.isNotEmpty) {
        await _writeAuditLog(
          db,
          entityType: 'expense',
          entityId: id,
          action: 'update',
          amount: (expense['amount'] as num?)?.toDouble() ??
              (oldRow['amount'] as num?)?.toDouble(),
          changes: diff,
        );
      }
    }

    return result;
  }

  @override
  Future<int> deleteExpense(int id) async {
    final db = await _db.database;

    final rows = await db.query('expenses', where: 'id = ?', whereArgs: [id]);
    final row = rows.isNotEmpty ? rows.first : null;

    final result = await _db.deleteExpense(id);

    if (row != null && row['category'] != 'Staff Loan') {
      await _writeAuditLog(
        db,
        entityType: 'expense',
        entityId: id,
        action: 'delete',
        amount: (row['amount'] as num?)?.toDouble(),
        changes: Map<String, dynamic>.from(row),
      );
    }

    return result;
  }

  @override
  Future<List<Map<String, dynamic>>> getAllExpenseCategories() {
    return _db.getAllExpenseCategories();
  }

  @override
  Future<int> insertExpenseCategory(String name) {
    return _db.insertExpenseCategory(name);
  }

  @override
  Future<int> updateExpenseCategory(int id, String name) {
    return _db.updateExpenseCategory(id, name);
  }

  @override
  Future<int> deleteExpenseCategory(int id) {
    return _db.deleteExpenseCategory(id);
  }

  // ========================================
  // STAFF FINANCIAL RECORDS
  // ========================================

  @override
  Future<Map<String, dynamic>?> getStaffById(int id) {
    return _db.getStaffById(id);
  }

  // -- Staff Loans --

  @override
  Future<int> insertStaffLoan(Map<String, dynamic> loan) async {
    final id = await _db.insertStaffLoan(loan);

    final db = await _db.database;
    final rows = await db.query('staff_loans', where: 'id = ?', whereArgs: [id]);
    if (rows.isNotEmpty) {
      await _writeAuditLog(
        db,
        entityType: 'staff_loan',
        entityId: id,
        action: 'create',
        staffId: rows.first['staffId'] as int?,
        amount: (rows.first['amount'] as num?)?.toDouble(),
        changes: Map<String, dynamic>.from(rows.first),
      );
    }

    return id;
  }

  @override
  Future<List<Map<String, dynamic>>> getAllStaffLoans() {
    return _db.getAllStaffLoans();
  }

  @override
  Future<Map<String, dynamic>?> getStaffLoanById(int id) {
    return _db.getStaffLoanById(id);
  }

  @override
  Future<int> updateStaffLoan(int id, Map<String, dynamic> loan) async {
    final db = await _db.database;

    final existingRows = await db.query('staff_loans', where: 'id = ?', whereArgs: [id]);
    final oldRow = existingRows.isNotEmpty ? existingRows.first : null;

    final result = await _db.updateStaffLoan(id, loan);

    if (oldRow != null) {
      final diff = <String, dynamic>{};
      for (final key in loan.keys) {
        if (oldRow[key] != loan[key]) {
          diff[key] = {'old': oldRow[key], 'new': loan[key]};
        }
      }
      if (diff.isNotEmpty) {
        await _writeAuditLog(
          db,
          entityType: 'staff_loan',
          entityId: id,
          action: 'update',
          staffId: oldRow['staffId'] as int?,
          amount: (loan['amount'] as num?)?.toDouble() ??
              (oldRow['amount'] as num?)?.toDouble(),
          changes: diff,
        );
      }
    }

    return result;
  }

  @override
  Future<int> deleteStaffLoan(int id) async {
    final db = await _db.database;

    final rows = await db.query('staff_loans', where: 'id = ?', whereArgs: [id]);
    final row = rows.isNotEmpty ? rows.first : null;

    final result = await _db.deleteStaffLoan(id);

    if (row != null) {
      await _writeAuditLog(
        db,
        entityType: 'staff_loan',
        entityId: id,
        action: 'delete',
        staffId: row['staffId'] as int?,
        amount: (row['amount'] as num?)?.toDouble(),
        changes: Map<String, dynamic>.from(row),
      );
    }

    return result;
  }

  // -- Staff Deductions --

  @override
  Future<int> insertStaffDeduction(Map<String, dynamic> deduction) async {
    final id = await _db.insertStaffDeduction(deduction);

    final db = await _db.database;
    final rows = await db.query('staff_deductions', where: 'id = ?', whereArgs: [id]);
    if (rows.isNotEmpty) {
      await _writeAuditLog(
        db,
        entityType: 'staff_deduction',
        entityId: id,
        action: 'create',
        staffId: rows.first['staffId'] as int?,
        amount: (rows.first['amount'] as num?)?.toDouble(),
        changes: Map<String, dynamic>.from(rows.first),
      );
    }

    return id;
  }

  @override
  Future<List<Map<String, dynamic>>> getStaffDeductionsByMonth(String month) {
    return _db.getStaffDeductionsByMonth(month);
  }

  @override
  Future<int> updateStaffDeduction(int id, Map<String, dynamic> data) async {
    final db = await _db.database;

    final existingRows = await db.query('staff_deductions', where: 'id = ?', whereArgs: [id]);
    final oldRow = existingRows.isNotEmpty ? existingRows.first : null;

    final result = await _db.updateStaffDeduction(id, data);

    if (oldRow != null) {
      final diff = <String, dynamic>{};
      for (final key in data.keys) {
        if (oldRow[key] != data[key]) {
          diff[key] = {'old': oldRow[key], 'new': data[key]};
        }
      }
      if (diff.isNotEmpty) {
        await _writeAuditLog(
          db,
          entityType: 'staff_deduction',
          entityId: id,
          action: 'update',
          staffId: oldRow['staffId'] as int?,
          amount: (data['amount'] as num?)?.toDouble() ??
              (oldRow['amount'] as num?)?.toDouble(),
          changes: diff,
        );
      }
    }

    return result;
  }

  @override
  Future<int> deleteStaffDeduction(int id) async {
    final db = await _db.database;

    final rows = await db.query('staff_deductions', where: 'id = ?', whereArgs: [id]);
    final row = rows.isNotEmpty ? rows.first : null;

    final result = await _db.deleteStaffDeduction(id);

    if (row != null) {
      await _writeAuditLog(
        db,
        entityType: 'staff_deduction',
        entityId: id,
        action: 'delete',
        staffId: row['staffId'] as int?,
        amount: (row['amount'] as num?)?.toDouble(),
        changes: Map<String, dynamic>.from(row),
      );
    }

    return result;
  }

  // -- Staff Incentives --

  @override
  Future<int> insertStaffIncentive(Map<String, dynamic> incentive) async {
    final id = await _db.insertStaffIncentive(incentive);

    final db = await _db.database;
    final rows = await db.query('staff_incentives', where: 'id = ?', whereArgs: [id]);
    if (rows.isNotEmpty) {
      await _writeAuditLog(
        db,
        entityType: 'staff_incentive',
        entityId: id,
        action: 'create',
        staffId: rows.first['staffId'] as int?,
        amount: (rows.first['amount'] as num?)?.toDouble(),
        changes: Map<String, dynamic>.from(rows.first),
      );
    }

    return id;
  }

  @override
  Future<List<Map<String, dynamic>>> getStaffIncentivesByMonth(String month) {
    return _db.getStaffIncentivesByMonth(month);
  }

  @override
  Future<int> updateStaffIncentive(int id, Map<String, dynamic> data) async {
    final db = await _db.database;

    final existingRows = await db.query('staff_incentives', where: 'id = ?', whereArgs: [id]);
    final oldRow = existingRows.isNotEmpty ? existingRows.first : null;

    final result = await _db.updateStaffIncentive(id, data);

    if (oldRow != null) {
      final diff = <String, dynamic>{};
      for (final key in data.keys) {
        if (oldRow[key] != data[key]) {
          diff[key] = {'old': oldRow[key], 'new': data[key]};
        }
      }
      if (diff.isNotEmpty) {
        await _writeAuditLog(
          db,
          entityType: 'staff_incentive',
          entityId: id,
          action: 'update',
          staffId: oldRow['staffId'] as int?,
          amount: (data['amount'] as num?)?.toDouble() ??
              (oldRow['amount'] as num?)?.toDouble(),
          changes: diff,
        );
      }
    }

    return result;
  }

  @override
  Future<int> deleteStaffIncentive(int id) async {
    final db = await _db.database;

    final rows = await db.query('staff_incentives', where: 'id = ?', whereArgs: [id]);
    final row = rows.isNotEmpty ? rows.first : null;

    final result = await _db.deleteStaffIncentive(id);

    if (row != null) {
      await _writeAuditLog(
        db,
        entityType: 'staff_incentive',
        entityId: id,
        action: 'delete',
        staffId: row['staffId'] as int?,
        amount: (row['amount'] as num?)?.toDouble(),
        changes: Map<String, dynamic>.from(row),
      );
    }

    return result;
  }

  // -- Staff Salary Payments --

  @override
  Future<void> toggleStaffSalaryPayment(
    int staffId,
    String month,
    bool isPaid, {
    String? paymentMethod,
    String? notes,
  }) async {
    final oldRow = await _db.getStaffSalaryPayment(staffId, month);

    await _db.toggleStaffSalaryPayment(
      staffId,
      month,
      isPaid,
      paymentMethod: paymentMethod,
      notes: notes,
    );

    final db = await _db.database;
    final newValues = {
      'isPaid': isPaid,
      'paymentMethod': paymentMethod,
      'notes': notes,
    };

    if (oldRow == null) {
      await _writeAuditLog(
        db,
        entityType: 'staff_salary_payment',
        entityId: staffId,
        action: 'create',
        staffId: staffId,
        changes: newValues,
      );
    } else {
      final diff = <String, dynamic>{};
      final oldValues = {
        'isPaid': oldRow['isPaid'] == 1,
        'paymentMethod': oldRow['paymentMethod'],
        'notes': oldRow['notes'],
      };
      for (final key in newValues.keys) {
        if (oldValues[key] != newValues[key]) {
          diff[key] = {'old': oldValues[key], 'new': newValues[key]};
        }
      }
      if (diff.isNotEmpty) {
        await _writeAuditLog(
          db,
          entityType: 'staff_salary_payment',
          entityId: oldRow['id'] as int,
          action: 'update',
          staffId: staffId,
          changes: diff,
        );
      }
    }
  }

  @override
  Future<List<Map<String, dynamic>>> getSalaryPaymentsByMonth(String month) {
    return _db.getSalaryPaymentsByMonth(month);
  }

  @override
  Future<Map<String, dynamic>?> getStaffSalaryPayment(int staffId, String month) {
    return _db.getStaffSalaryPayment(staffId, month);
  }

  @override
  Future<void> setLoanDeductionsAppliedForPayment(int staffId, String month, String? json) {
    return _db.setLoanDeductionsAppliedForPayment(staffId, month, json);
  }

  // -- Staff Salary Increments/History --

  @override
  Future<int> insertSalaryHistory(
    int staffId,
    double salary,
    String effectiveMonth, {
    String? reason,
  }) async {
    final id = await _db.insertSalaryHistory(staffId, salary, effectiveMonth, reason: reason);

    final db = await _db.database;
    final rows = await db.query('staff_salary_history', where: 'id = ?', whereArgs: [id]);
    if (rows.isNotEmpty) {
      await _writeAuditLog(
        db,
        entityType: 'staff_salary_history',
        entityId: id,
        action: 'create',
        staffId: staffId,
        amount: salary,
        changes: Map<String, dynamic>.from(rows.first),
      );
    }

    return id;
  }

  @override
  Future<List<Map<String, dynamic>>> getSalaryHistory(int staffId) {
    return _db.getSalaryHistory(staffId);
  }

  @override
  Future<List<Map<String, dynamic>>> getAllSalaryHistory() {
    return _db.getAllSalaryHistory();
  }

  @override
  Future<int> deleteSalaryHistory(int id) async {
    final db = await _db.database;

    final rows = await db.query('staff_salary_history', where: 'id = ?', whereArgs: [id]);
    final row = rows.isNotEmpty ? rows.first : null;

    final result = await _db.deleteSalaryHistory(id);

    if (row != null) {
      await _writeAuditLog(
        db,
        entityType: 'staff_salary_history',
        entityId: id,
        action: 'delete',
        staffId: row['staffId'] as int?,
        amount: (row['salary'] as num?)?.toDouble(),
        changes: Map<String, dynamic>.from(row),
      );
    }

    return result;
  }

  @override
  Future<int> updateStaffSalary(int id, double salary) {
    return _db.updateStaffSalary(id, salary);
  }

  // ========================================
  // FINANCIAL AGGREGATES
  // ========================================

  @override
  Future<double> getTotalBillsForTermSession({
    required String term,
    required String session,
  }) async {
    final db = await _db.database;

    final targetKey = DatabaseHelper.termSortKey(term, session);
    final result = await db.rawQuery('''
      SELECT COALESCE(SUM(
        (COALESCE(b.totalAmount, 0) - COALESCE(b.previousBalance, 0))
        + COALESCE((
            SELECT SUM(COALESCE(b2.totalAmount, 0) - COALESCE(b2.previousBalance, 0))
            FROM student_bills b2
            WHERE b2.studentId = s.id
              AND (CAST(SUBSTR(b2.session, 1, 4) AS INTEGER) * 3 +
                   CASE LOWER(TRIM(b2.term))
                     WHEN '1st term' THEN 0 WHEN '1st' THEN 0 WHEN 'first term' THEN 0 WHEN 'first' THEN 0
                     WHEN '2nd term' THEN 1 WHEN '2nd' THEN 1 WHEN 'second term' THEN 1 WHEN 'second' THEN 1
                     WHEN '3rd term' THEN 2 WHEN '3rd' THEN 2 WHEN 'third term' THEN 2 WHEN 'third' THEN 2
                     ELSE 1
                   END) < ?
          ), 0)
        - COALESCE((
            SELECT SUM(p2.amount)
            FROM payments p2
            WHERE p2.studentId = s.id
              AND (CAST(SUBSTR(p2.session, 1, 4) AS INTEGER) * 3 +
                   CASE LOWER(TRIM(p2.term))
                     WHEN '1st term' THEN 0 WHEN '1st' THEN 0 WHEN 'first term' THEN 0 WHEN 'first' THEN 0
                     WHEN '2nd term' THEN 1 WHEN '2nd' THEN 1 WHEN 'second term' THEN 1 WHEN 'second' THEN 1
                     WHEN '3rd term' THEN 2 WHEN '3rd' THEN 2 WHEN 'third term' THEN 2 WHEN 'third' THEN 2
                     ELSE 1
                   END) < ?
          ), 0)
      ), 0) AS total
      FROM student_bills b
      INNER JOIN students s ON b.studentId = s.id
      WHERE b.term = ? AND b.session = ? AND s.isActive = 1
    ''', [targetKey, targetKey, term, session]);
    return (result.first['total'] as num?)?.toDouble() ?? 0.0;
  }

  @override
  Future<double> getTotalPaymentsForTermSession({
    required String term,
    required String session,
  }) async {
    final db = await _db.database;
    // Include ALL students' payments (active and inactive) for accurate reporting
    // Payments received should be counted regardless of student status
    final result = await db.rawQuery('''
      SELECT COALESCE(SUM(amount), 0) AS total
      FROM payments
      WHERE term = ? AND session = ?
    ''', [term, session]);
    return (result.first['total'] as num?)?.toDouble() ?? 0.0;
  }

  // ========================================
  // REPORTS
  // ========================================

  @override
  Future<List<Map<String, dynamic>>> getDebtorsList({
    required int classId,
    required String term,
    required String session,
    double minPercentagePaid = 0.0,
  }) {
    return _db.getDebtorsList(
      classId: classId,
      term: term,
      session: session,
      minPercentagePaid: minPercentagePaid,
    );
  }

  @override
  Future<Map<String, dynamic>> getDebtorsSummary({
    required int classId,
    required String term,
    required String session,
  }) {
    return _db.getDebtorsSummary(
      classId: classId,
      term: term,
      session: session,
    );
  }

  @override
  Future<List<Map<String, dynamic>>> getLastTermDebtors({
    required String term,
    required String session,
    int classId = 0,
    int armId = 0,
  }) {
    return _db.getLastTermDebtors(
      term: term,
      session: session,
      classId: classId,
      armId: armId,
    );
  }

  @override
  Future<Map<String, dynamic>> getFeesBalanceSummary({
    required String term,
    required String session,
    int classId = 0,
  }) {
    return _db.getFeesBalanceSummary(
      term: term,
      session: session,
      classId: classId,
    );
  }

  @override
  Future<List<Map<String, dynamic>>> getBalancedStudentsList({
    required int classId,
    required String term,
    required String session,
  }) {
    return _db.getBalancedStudentsList(
      classId: classId,
      term: term,
      session: session,
    );
  }

  // ========================================
  // SCHOOL PROFILE
  // ========================================

  @override
  Future<Map<String, dynamic>?> getSchoolProfile() {
    return _db.getSchoolProfile();
  }

  @override
  Future<int> saveSchoolProfile(Map<String, dynamic> data) {
    return _db.saveSchoolProfile(data);
  }

  // ========================================
  // GENERIC SETTINGS
  // ========================================

  @override
  Future<String?> getSetting(String key) {
    return _db.getSetting(key);
  }

  @override
  Future<void> setSetting(String key, String value) {
    return _db.setSetting(key, value);
  }

  // ========================================
  // SMS LOG
  // ========================================

  @override
  Future<int> insertSmsLog({
    int? studentId,
    required String phone,
    required String message,
    String? context,
    required String status,
    String? errorMessage,
  }) {
    return _db.insertSmsLog(
      studentId: studentId,
      phone: phone,
      message: message,
      context: context,
      status: status,
      errorMessage: errorMessage,
    );
  }

  // ========================================
  // LICENSES
  // ========================================

  @override
  Future<Map<String, dynamic>?> getActiveLicense() {
    return _db.getActiveLicense();
  }

  @override
  Future<int> activateLicense({
    required String licenseKey,
    required String schoolName,
    required String schoolCode,
    required String deviceId,
    required DateTime expiryDate,
    int? maxStudents,
  }) {
    return _db.activateLicense(
      licenseKey: licenseKey,
      schoolName: schoolName,
      schoolCode: schoolCode,
      deviceId: deviceId,
      expiryDate: expiryDate,
      maxStudents: maxStudents,
    );
  }

  @override
  Future<int> deactivateLicense(int licenseId) {
    return _db.deactivateLicense(licenseId);
  }

  @override
  Future<List<Map<String, dynamic>>> getAllLicenses() {
    return _db.getAllLicenses();
  }

  @override
  Future<bool> licenseKeyExists(String licenseKey) {
    return _db.licenseKeyExists(licenseKey);
  }

  @override
  Future<Map<String, dynamic>?> getLicenseByKey(String licenseKey) {
    return _db.getLicenseByKey(licenseKey);
  }

  @override
  Future<void> reactivateLicense(int licenseId) {
    return _db.reactivateLicense(licenseId);
  }

  // ========================================
  // STOCK ITEMS
  // ========================================

  @override
  Future<int> insertStockItem(Map<String, dynamic> item) async {
    final id = await _db.insertStockItem(item);

    final db = await _db.database;
    final rows = await db.query('stock_items', where: 'id = ?', whereArgs: [id]);
    if (rows.isNotEmpty) {
      await _writeAuditLog(
        db,
        entityType: 'stock_item',
        entityId: id,
        action: 'create',
        changes: Map<String, dynamic>.from(rows.first),
      );
    }

    return id;
  }

  @override
  Future<List<Map<String, dynamic>>> getStockItems({bool includeInactive = false}) {
    return _db.getStockItems(includeInactive: includeInactive);
  }

  @override
  Future<Map<String, dynamic>?> getStockItemById(int id) {
    return _db.getStockItemById(id);
  }

  @override
  Future<int> updateStockItem(int id, Map<String, dynamic> item) async {
    final db = await _db.database;

    final existingRows = await db.query('stock_items', where: 'id = ?', whereArgs: [id]);
    final oldRow = existingRows.isNotEmpty ? existingRows.first : null;

    final result = await _db.updateStockItem(id, item);

    if (oldRow != null) {
      final diff = <String, dynamic>{};
      for (final key in item.keys) {
        if (oldRow[key] != item[key]) {
          diff[key] = {'old': oldRow[key], 'new': item[key]};
        }
      }
      if (diff.isNotEmpty) {
        await _writeAuditLog(
          db,
          entityType: 'stock_item',
          entityId: id,
          action: 'update',
          changes: diff,
        );
      }
    }

    return result;
  }

  @override
  Future<int> deactivateStockItem(int id) async {
    final db = await _db.database;

    final existingRows = await db.query('stock_items', where: 'id = ?', whereArgs: [id]);
    final oldRow = existingRows.isNotEmpty ? existingRows.first : null;

    final result = await _db.deactivateStockItem(id);

    if (oldRow != null && oldRow['isActive'] != 0) {
      await _writeAuditLog(
        db,
        entityType: 'stock_item',
        entityId: id,
        action: 'update',
        changes: {
          'isActive': {'old': oldRow['isActive'], 'new': 0},
        },
      );
    }

    return result;
  }

  @override
  Future<void> deleteStockItem(int stockItemId) async {
    final db = await _db.database;

    final rows = await db.query('stock_items', where: 'id = ?', whereArgs: [stockItemId]);
    final row = rows.isNotEmpty ? rows.first : null;

    await _db.deleteStockItem(stockItemId);

    if (row != null) {
      await _writeAuditLog(
        db,
        entityType: 'stock_item',
        entityId: stockItemId,
        action: 'delete',
        changes: Map<String, dynamic>.from(row),
      );
    }
  }

  @override
  Future<void> adjustStockQuantity(
    int stockItemId,
    int newQuantity,
    String note, {
    String? createdBy,
  }) {
    return _db.adjustStockQuantity(stockItemId, newQuantity, note, createdBy: createdBy);
  }

  @override
  Future<void> restockItem(
    int stockItemId, {
    required int quantityAdded,
    required String supplier,
    String? invoiceNumber,
    double? newCostPrice,
    String? notes,
    String? createdBy,
  }) {
    return _db.restockItem(
      stockItemId,
      quantityAdded: quantityAdded,
      supplier: supplier,
      invoiceNumber: invoiceNumber,
      newCostPrice: newCostPrice,
      notes: notes,
      createdBy: createdBy,
    );
  }

  @override
  Future<List<Map<String, dynamic>>> getLowStockItems() {
    return _db.getLowStockItems();
  }

  @override
  Future<List<Map<String, dynamic>>> getParentItems() {
    return _db.getParentItems();
  }

  @override
  Future<List<Map<String, dynamic>>> getChildItems(int parentId) {
    return _db.getChildItems(parentId);
  }

  @override
  Future<bool> hasChildItems(int itemId) {
    return _db.hasChildItems(itemId);
  }

  @override
  Future<bool> canSetAsParent(int itemId, int? proposedParentId) {
    return _db.canSetAsParent(itemId, proposedParentId);
  }

  // ========================================
  // SUPPLIERS
  // ========================================

  @override
  Future<int> insertSupplier(Map<String, dynamic> supplier) async {
    final id = await _db.insertSupplier(supplier);

    final db = await _db.database;
    final rows = await db.query('suppliers', where: 'id = ?', whereArgs: [id]);
    if (rows.isNotEmpty) {
      await _writeAuditLog(
        db,
        entityType: 'supplier',
        entityId: id,
        action: 'create',
        changes: Map<String, dynamic>.from(rows.first),
      );
    }

    return id;
  }

  @override
  Future<List<Map<String, dynamic>>> getSuppliers({bool includeInactive = false}) {
    return _db.getSuppliers(includeInactive: includeInactive);
  }

  @override
  Future<Map<String, dynamic>?> getSupplierById(int id) {
    return _db.getSupplierById(id);
  }

  @override
  Future<int> updateSupplier(int id, Map<String, dynamic> supplier) async {
    final db = await _db.database;

    final existingRows = await db.query('suppliers', where: 'id = ?', whereArgs: [id]);
    final oldRow = existingRows.isNotEmpty ? existingRows.first : null;

    final result = await _db.updateSupplier(id, supplier);

    if (oldRow != null) {
      final diff = <String, dynamic>{};
      for (final key in supplier.keys) {
        if (oldRow[key] != supplier[key]) {
          diff[key] = {'old': oldRow[key], 'new': supplier[key]};
        }
      }
      if (diff.isNotEmpty) {
        await _writeAuditLog(
          db,
          entityType: 'supplier',
          entityId: id,
          action: 'update',
          changes: diff,
        );
      }
    }

    return result;
  }

  @override
  Future<int> deactivateSupplier(int id) async {
    final db = await _db.database;

    final existingRows = await db.query('suppliers', where: 'id = ?', whereArgs: [id]);
    final oldRow = existingRows.isNotEmpty ? existingRows.first : null;

    final result = await _db.deactivateSupplier(id);

    if (oldRow != null && oldRow['isActive'] != 0) {
      await _writeAuditLog(
        db,
        entityType: 'supplier',
        entityId: id,
        action: 'update',
        changes: {
          'isActive': {'old': oldRow['isActive'], 'new': 0},
        },
      );
    }

    return result;
  }

  @override
  Future<void> deleteSupplier(int id) async {
    final db = await _db.database;

    final rows = await db.query('suppliers', where: 'id = ?', whereArgs: [id]);
    final row = rows.isNotEmpty ? rows.first : null;

    await _db.deleteSupplier(id);

    if (row != null) {
      await _writeAuditLog(
        db,
        entityType: 'supplier',
        entityId: id,
        action: 'delete',
        changes: Map<String, dynamic>.from(row),
      );
    }
  }

  // ========================================
  // SALES
  // ========================================

  @override
  Future<int> insertSale(Map<String, dynamic> sale, {String? createdBy}) async {
    final id = await _db.insertSale(sale, createdBy: createdBy);

    final db = await _db.database;
    final rows = await db.query('sales', where: 'id = ?', whereArgs: [id]);
    if (rows.isNotEmpty) {
      await _writeAuditLog(
        db,
        entityType: 'sale',
        entityId: id,
        action: 'create',
        amount: (rows.first['totalAmount'] as num?)?.toDouble(),
        changes: Map<String, dynamic>.from(rows.first),
      );
    }

    return id;
  }

  @override
  Future<int> updateSalePayment(
    int saleId, {
    required double amountPaid,
    required double outstandingBalance,
    required String paymentStatus,
    required double additionalPayment,
    String? paymentMethod,
    String? note,
    String? term,
    String? session,
    String? createdBy,
    String? paymentTimestamp,
  }) async {
    final result = await _db.updateSalePayment(
      saleId,
      amountPaid: amountPaid,
      outstandingBalance: outstandingBalance,
      paymentStatus: paymentStatus,
      additionalPayment: additionalPayment,
      paymentMethod: paymentMethod,
      note: note,
      term: term,
      session: session,
      createdBy: createdBy,
      paymentTimestamp: paymentTimestamp,
    );

    final db = await _db.database;
    await _writeAuditLog(
      db,
      entityType: 'sale',
      entityId: saleId,
      action: 'update',
      amount: additionalPayment,
      changes: {
        'additionalPayment': additionalPayment,
        'paymentStatus': paymentStatus,
        'outstandingBalance': outstandingBalance,
      },
    );

    return result;
  }

  @override
  Future<List<Map<String, dynamic>>> getSalesByExactDate(String date) {
    return _db.getSalesByExactDate(date);
  }

  @override
  Future<List<Map<String, dynamic>>> getAllSales({
    String? term,
    String? session,
    String? startDate,
    String? endDate,
    int? studentId,
  }) {
    return _db.getAllSales(
      term: term,
      session: session,
      startDate: startDate,
      endDate: endDate,
      studentId: studentId,
    );
  }

  @override
  Future<Map<String, dynamic>?> getSaleById(int id) {
    return _db.getSaleById(id);
  }

  @override
  Future<Map<String, double>> getSalesTotalsByMethod(String date) {
    return _db.getSalesTotalsByMethod(date);
  }

  @override
  Future<void> deleteSale(int saleId, {String? deletedBy}) async {
    final db = await _db.database;

    final rows = await db.query('sales', where: 'id = ?', whereArgs: [saleId]);
    final row = rows.isNotEmpty ? rows.first : null;

    await _db.deleteSale(saleId, deletedBy: deletedBy);

    if (row != null) {
      await _writeAuditLog(
        db,
        entityType: 'sale',
        entityId: saleId,
        action: 'delete',
        amount: (row['totalAmount'] as num?)?.toDouble(),
        changes: Map<String, dynamic>.from(row),
      );
    }
  }

  @override
  Future<List<Map<String, dynamic>>> getSalesDebtors({
    String? term,
    String? session,
  }) {
    return _db.getSalesDebtors(term: term, session: session);
  }

  // ========================================
  // STOCK MOVEMENTS
  // ========================================

  @override
  Future<List<Map<String, dynamic>>> getStockMovements(
    int stockItemId, {
    String? startDate,
    String? endDate,
  }) {
    return _db.getStockMovements(stockItemId, startDate: startDate, endDate: endDate);
  }

  // ========================================
  // DATABASE MANAGEMENT
  // ========================================
  // FEE PRIORITY (Fee Tracker)
  // ========================================

  @override
  Future<List<Map<String, dynamic>>> getFeePriorities({
    required String scope, int? classId, int? armId,
    required String term, required String session,
  }) => _db.getFeePriorities(scope: scope, classId: classId, armId: armId, term: term, session: session);

  @override
  Future<void> saveFeePriorities({
    required String scope, int? classId, int? armId,
    required String term, required String session,
    required List<Map<String, dynamic>> priorities,
  }) => _db.saveFeePriorities(scope: scope, classId: classId, armId: armId, term: term, session: session, priorities: priorities);

  @override
  Future<List<Map<String, dynamic>>> getEffectiveFeePriorities({
    required int classId, int? armId,
    required String term, required String session,
  }) => _db.getEffectiveFeePriorities(classId: classId, armId: armId, term: term, session: session);

  @override
  Future<List<Map<String, dynamic>>> getStudentsWithFeeItem({
    required int feeItemId, required String term, required String session,
    int? classId, int? armId,
  }) => _db.getStudentsWithFeeItem(feeItemId: feeItemId, term: term, session: session, classId: classId, armId: armId);

  @override
  Future<List<Map<String, dynamic>>> getPaymentProgressionData({
    required String term, required String session,
    int? classId, int? armId,
  }) => _db.getPaymentProgressionData(term: term, session: session, classId: classId, armId: armId);

  @override
  Future<List<Map<String, dynamic>>> getExtraFeeItemsForClassArm({
    required int classId, int? armId,
    required String term, required String session,
  }) => _db.getExtraFeeItemsForClassArm(classId: classId, armId: armId, term: term, session: session);

  // ========================================
  // TRANSPORTATION
  // ========================================

  @override
  Future<List<Map<String, dynamic>>> getTransportRoutes({bool includeInactive = false}) =>
      _db.getTransportRoutes(includeInactive: includeInactive);

  @override
  Future<Map<String, dynamic>?> getTransportRouteById(int id) => _db.getTransportRouteById(id);

  @override
  Future<int> insertTransportRoute(Map<String, dynamic> data) => _db.insertTransportRoute(data);

  @override
  Future<int> updateTransportRoute(int id, Map<String, dynamic> data) => _db.updateTransportRoute(id, data);

  @override
  Future<int> deleteTransportRoute(int id) => _db.deleteTransportRoute(id);

  @override
  Future<int> countActiveAllocationsForRoute(int routeId) => _db.countActiveAllocationsForRoute(routeId);

  @override
  Future<Map<String, dynamic>?> getStudentTransportAllocation(int studentId, String term, String session) =>
      _db.getStudentTransportAllocation(studentId, term, session);

  @override
  Future<List<Map<String, dynamic>>> getRouteAllocationsWithDetails(String term, String session) =>
      _db.getRouteAllocationsWithDetails(term, session);

  @override
  Future<int> allocateStudentToRoute({
    required int studentId,
    required int routeId,
    required String term,
    required String session,
  }) =>
      _db.allocateStudentToRoute(studentId: studentId, routeId: routeId, term: term, session: session);

  @override
  Future<int> removeStudentFromRoute(int studentId, String term, String session) =>
      _db.removeStudentFromRoute(studentId, term, session);

  // ========================================

  @override
  Future<void> closeAndReset() {
    return _db.closeAndReset();
  }

  @override
  Future<void> close() {
    return _db.close();
  }
}
