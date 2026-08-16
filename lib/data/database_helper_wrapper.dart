// lib/data/database_helper_wrapper.dart
// Drop-in replacement for DatabaseHelper singleton
// Maintains exact same API but routes calls through repository layer
// This allows gradual migration of screens without breaking existing code

import 'package:sqflite/sqflite.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'repository_factory.dart';
import 'repository.dart';
import '../db/database_helper.dart';

class DatabaseHelperWrapper {
  // Singleton pattern - matches DatabaseHelper
  static final DatabaseHelperWrapper _instance = DatabaseHelperWrapper._internal();
  factory DatabaseHelperWrapper() => _instance;
  DatabaseHelperWrapper._internal();

  /// Returns a chronological sort key for a term+session pair (year×3 + termIndex).
  /// Use this to filter "prior terms only" without including future terms.
  static int termSortKey(String term, String session) =>
      DatabaseHelper.termSortKey(term, session);

  /// Returns the SQL CASE expression that computes the sort key for a row
  /// using columns prefixed by [alias] (e.g. 'b2' → b2.session, b2.term).
  /// Pass empty string for bare column names.
  static String sqlTermKeyExpr([String alias = '']) {
    final p = alias.isEmpty ? '' : '$alias.';
    return "(CAST(SUBSTR(${p}session, 1, 4) AS INTEGER) * 3 + "
           "CASE LOWER(TRIM(${p}term)) "
           "WHEN '1st term' THEN 0 WHEN '1st' THEN 0 WHEN 'first term' THEN 0 WHEN 'first' THEN 0 "
           "WHEN '2nd term' THEN 1 WHEN '2nd' THEN 1 WHEN 'second term' THEN 1 WHEN 'second' THEN 1 "
           "WHEN '3rd term' THEN 2 WHEN '3rd' THEN 2 WHEN 'third term' THEN 2 WHEN 'third' THEN 2 "
           "ELSE 1 END)";
  }

  /// Returns the previous term and session for carry-over balance calculation.
  /// e.g. "2nd Term" / "2025/2026" → {"term": "1st Term", "session": "2025/2026"}
  /// Returns null when the term format is unrecognised.
  static Map<String, String>? previousTermSession({
    required String term,
    required String session,
  }) {
    final t = term.trim().toLowerCase();
    if (t == '1st term' || t == '1st' || t == 'first term') {
      final parts = session.split('/');
      if (parts.length == 2) {
        final a = int.tryParse(parts[0]);
        if (a != null) return {'term': '3rd Term', 'session': '${a - 1}/$a'};
      }
      return null;
    } else if (t == '2nd term' || t == '2nd' || t == 'second term') {
      return {'term': '1st Term', 'session': session};
    } else if (t == '3rd term' || t == '3rd' || t == 'third term') {
      return {'term': '2nd Term', 'session': session};
    }
    return null;
  }

  DataRepository? _repo;

  // Get repository instance (lazily initialized)
  Future<DataRepository> get _repository async {
    if (_repo == null) {
      print('🔄 DatabaseHelperWrapper: Repository is null, fetching from factory...');
      _repo = await RepositoryFactory.getInstance();
      print('✅ DatabaseHelperWrapper: Got repository instance: ${_repo.runtimeType}');
    } else {
      print('📦 DatabaseHelperWrapper: Using cached repository: ${_repo.runtimeType}');
    }
    return _repo!;
  }

  // Reset repository instance (useful when switching modes)
  void resetRepository() {
    print('🔄 DatabaseHelperWrapper: Resetting repository (was: ${_repo?.runtimeType ?? "null"})');
    _repo = null;
  }

  // ========================================
  // DATABASE GETTER (for direct access if needed)
  // ========================================

  // Note: This is provided for compatibility with existing screens
  // Direct database access only works in standalone/server modes
  // In client mode, this will throw an error since there's no local database
  Future<Database> get database async {
    // Check app mode
    final prefs = await SharedPreferences.getInstance();
    final appMode = prefs.getString('app_mode') ?? 'standalone';

    // Client mode doesn't have local database
    if (appMode == 'client') {
      throw UnsupportedError(
        'Direct database access is not supported in client mode. '
        'The app is connected to a remote server. '
        'Use repository methods instead.',
      );
    }

    // Standalone and Server modes can access local database directly
    // Use the DatabaseHelper singleton
    return DatabaseHelper().database;
  }

  // ========================================
  // AUTHENTICATION & USERS
  // ========================================

  Future<Map<String, dynamic>?> authenticateUser(String username, String password) async {
    final repo = await _repository;
    return repo.authenticateUser(username, password);
  }

  Future<Map<String, dynamic>?> getUserByUsername(String username) async {
    final repo = await _repository;
    return repo.getUserByUsername(username);
  }

  Future<List<Map<String, dynamic>>> getAllUsers() async {
    final repo = await _repository;
    return repo.getAllUsers();
  }

  Future<Map<String, dynamic>?> getUserById(int userId) async {
    final repo = await _repository;
    return repo.getUserById(userId);
  }

  Future<bool> updateUserCredentials({
    required int userId,
    required String newUsername,
    required String newPassword,
  }) async {
    final repo = await _repository;
    return repo.updateUserCredentials(
      userId: userId,
      newUsername: newUsername,
      newPassword: newPassword,
    );
  }

  Future<bool> resetBursarCredentials({
    required String newUsername,
    required String newPassword,
  }) async {
    final repo = await _repository;
    return repo.resetBursarCredentials(
      newUsername: newUsername,
      newPassword: newPassword,
    );
  }

  Future<Map<String, dynamic>?> getBursarAccount() async {
    final repo = await _repository;
    return repo.getBursarAccount();
  }

  Future<int?> createUser({
    required String username,
    required String password,
    required String userType,
    required int canChangeCredentials,
  }) async {
    final repo = await _repository;
    return repo.createUser(
      username: username,
      password: password,
      userType: userType,
      canChangeCredentials: canChangeCredentials,
    );
  }

  Future<bool> updateUser({
    required int userId,
    required String username,
    required String password,
    required String userType,
    required int canChangeCredentials,
  }) async {
    final repo = await _repository;
    return repo.updateUser(
      userId: userId,
      username: username,
      password: password,
      userType: userType,
      canChangeCredentials: canChangeCredentials,
    );
  }

  Future<Map<String, dynamic>> deleteUser(int userId) async {
    final repo = await _repository;
    return repo.deleteUser(userId);
  }

  Future<int> countSuperAdmins() async {
    final repo = await _repository;
    return repo.countSuperAdmins();
  }

  // ========================================
  // PERMISSIONS
  // ========================================

  Future<List<Map<String, dynamic>>> getPermissionsByRole(String role) async {
    final repo = await _repository;
    return repo.getPermissionsByRole(role);
  }

  Future<bool> hasPermission(String role, String module) async {
    final repo = await _repository;
    return repo.hasPermission(role, module);
  }

  Future<void> setPermission(String role, String module, bool canAccess) async {
    final repo = await _repository;
    return repo.setPermission(role, module, canAccess);
  }

  Future<void> updateRolePermissions(String role, Map<String, bool> permissions) async {
    final repo = await _repository;
    return repo.updateRolePermissions(role, permissions);
  }

  // ========================================
  // SESSIONS & TERMS
  // ========================================

  Future<String> getActiveTerm() async {
    final repo = await _repository;
    return repo.getActiveTerm();
  }

  Future<void> setActiveTerm(String term) async {
    final repo = await _repository;
    return repo.setActiveTerm(term);
  }

  Future<Map<String, dynamic>?> getActiveSession() async {
    final repo = await _repository;
    return repo.getActiveSession();
  }

  Future<List<Map<String, dynamic>>> getAllSessions() async {
    final repo = await _repository;
    return repo.getAllSessions();
  }

  Future<List<Map<String, dynamic>>> getSessions() async {
    final repo = await _repository;
    return repo.getSessions();
  }

  Future<void> setActiveSession(int sessionId) async {
    final repo = await _repository;
    return repo.setActiveSession(sessionId);
  }

  // ========================================
  // STUDENTS
  // ========================================

  Future<int> insertStudent(Map<String, dynamic> student) async {
    final repo = await _repository;
    return repo.insertStudent(student);
  }

  Future<List<Map<String, dynamic>>> getStudents({bool includeInactive = false}) async {
    final repo = await _repository;
    return repo.getStudents(includeInactive: includeInactive);
  }

  Future<List<Map<String, dynamic>>> getActiveStudents() async {
    final repo = await _repository;
    return repo.getActiveStudents();
  }

  Future<List<Map<String, dynamic>>> getActiveStudentsWithDetails() async {
    final repo = await _repository;
    return repo.getActiveStudentsWithDetails();
  }

  Future<List<Map<String, dynamic>>> getInactiveStudents() async {
    final repo = await _repository;
    return repo.getInactiveStudents();
  }

  Future<Map<String, dynamic>?> getStudentById(int id) async {
    final repo = await _repository;
    return repo.getStudentById(id);
  }

  Future<int> updateStudent(int id, Map<String, dynamic> student) async {
    final repo = await _repository;
    return repo.updateStudent(id, student);
  }

  Future<int> deleteStudent(int id) async {
    final repo = await _repository;
    return repo.deleteStudent(id);
  }

  Future<int> deactivateStudent(int studentId, String leftDate, String leftReason) async {
    final repo = await _repository;
    return repo.deactivateStudent(studentId, leftDate, leftReason);
  }

  Future<int> restoreStudent(int studentId) async {
    final repo = await _repository;
    return repo.restoreStudent(studentId);
  }

  Future<String> generateAdmissionNumber() async {
    final repo = await _repository;
    return repo.generateAdmissionNumber();
  }

  // ========================================
  // PARENTS
  // ========================================

  Future<int> insertParent(Map<String, dynamic> parent) async {
    final repo = await _repository;
    return repo.insertParent(parent);
  }

  Future<List<Map<String, dynamic>>> getAllParents() async {
    final repo = await _repository;
    return repo.getAllParents();
  }

  Future<Map<String, dynamic>?> getParentById(int id) async {
    final repo = await _repository;
    return repo.getParentById(id);
  }

  Future<List<Map<String, dynamic>>> searchParents(String query) async {
    final repo = await _repository;
    return repo.searchParents(query);
  }

  Future<int> updateParent(int id, Map<String, dynamic> parent) async {
    final repo = await _repository;
    return repo.updateParent(id, parent);
  }

  Future<int> deleteParent(int id) async {
    final repo = await _repository;
    return repo.deleteParent(id);
  }

  Future<int> migrateParentDataFromStudents() async {
    // Direct access to DatabaseHelper for migration
    return DatabaseHelper().migrateParentDataFromStudents();
  }

  // ========================================
  // CLASSES
  // ========================================

  Future<int> insertClass(Map<String, dynamic> cls) async {
    final repo = await _repository;
    return repo.insertClass(cls);
  }

  Future<List<Map<String, dynamic>>> getClasses() async {
    final repo = await _repository;
    return repo.getClasses();
  }

  Future<int> updateClass(int id, Map<String, dynamic> cls) async {
    final repo = await _repository;
    return repo.updateClass(id, cls);
  }

  Future<int> deleteClass(int id) async {
    final repo = await _repository;
    return repo.deleteClass(id);
  }

  // ========================================
  // ARMS
  // ========================================

  Future<int> insertArm(Map<String, dynamic> arm) async {
    final repo = await _repository;
    return repo.insertArm(arm);
  }

  Future<List<Map<String, dynamic>>> getArmsByClass(int classId) async {
    final repo = await _repository;
    return repo.getArmsByClass(classId);
  }

  Future<List<Map<String, dynamic>>> getArms() async {
    final repo = await _repository;
    return repo.getArms();
  }

  Future<int> updateArm(int id, Map<String, dynamic> arm) async {
    final repo = await _repository;
    return repo.updateArm(id, arm);
  }

  Future<int> deleteArm(int id) async {
    final repo = await _repository;
    return repo.deleteArm(id);
  }

  // ========================================
  // FEE ITEMS
  // ========================================

  Future<int> insertFeeItem(Map<String, dynamic> item) async {
    final repo = await _repository;
    return repo.insertFeeItem(item);
  }

  Future<List<Map<String, dynamic>>> getFeeItems({String? term, String? session}) async {
    final repo = await _repository;
    return repo.getFeeItems(term: term, session: session);
  }

  Future<int> updateFeeItem(int id, Map<String, dynamic> item) async {
    final repo = await _repository;
    return repo.updateFeeItem(id, item);
  }

  Future<int> deleteFeeItem(int id) async {
    final repo = await _repository;
    return repo.deleteFeeItem(id);
  }

  // ========================================
  // CLASS FEES
  // ========================================

  Future<int> insertClassFee(Map<String, dynamic> classFee) async {
    final repo = await _repository;
    return repo.insertClassFee(classFee);
  }

  Future<List<Map<String, dynamic>>> getClassFees(int classId, String term, String session, {int? armId}) async {
    final repo = await _repository;
    return repo.getClassFees(classId, term, session, armId: armId);
  }

  Future<int> deleteClassFee(int id) async {
    final repo = await _repository;
    return repo.deleteClassFee(id);
  }

  Future<void> replaceClassFeesFor(
    int classId,
    String term,
    String session,
    List<Map<String, dynamic>> fees, {
    int? armId,
  }) async {
    final repo = await _repository;
    return repo.replaceClassFeesFor(classId, term, session, fees, armId: armId);
  }

  // ========================================
  // SPECIAL FEE ITEMS (for new intake students)
  // ========================================

  Future<int> insertSpecialFeeItem(Map<String, dynamic> item) async {
    final repo = await _repository;
    return repo.insertSpecialFeeItem(item);
  }

  Future<List<Map<String, dynamic>>> getSpecialFeeItems({String? term, String? session, bool? parentsOnly, int? parentId, bool? categoriesOnly, bool? standaloneOnly}) async {
    final repo = await _repository;
    return repo.getSpecialFeeItems(term: term, session: session, parentsOnly: parentsOnly, parentId: parentId, categoriesOnly: categoriesOnly, standaloneOnly: standaloneOnly);
  }

  Future<List<Map<String, dynamic>>> getSpecialFeeItemParents({String? term, String? session}) async {
    final repo = await _repository;
    return repo.getSpecialFeeItemParents(term: term, session: session);
  }

  Future<List<Map<String, dynamic>>> getSpecialFeeItemCategories({String? term, String? session}) async {
    final repo = await _repository;
    return repo.getSpecialFeeItemCategories(term: term, session: session);
  }

  Future<List<Map<String, dynamic>>> getSpecialFeeItemStandalone({String? term, String? session}) async {
    final repo = await _repository;
    return repo.getSpecialFeeItemStandalone(term: term, session: session);
  }

  Future<List<Map<String, dynamic>>> getSpecialFeeItemChildren(int parentId, {String? term, String? session}) async {
    final repo = await _repository;
    return repo.getSpecialFeeItemChildren(parentId, term: term, session: session);
  }

  Future<bool> specialFeeItemHasChildren(int itemId) async {
    final repo = await _repository;
    return repo.specialFeeItemHasChildren(itemId);
  }

  Future<List<Map<String, dynamic>>> getSpecialFeeItemsHierarchy({String? term, String? session}) async {
    final repo = await _repository;
    return repo.getSpecialFeeItemsHierarchy(term: term, session: session);
  }

  Future<int> updateSpecialFeeItem(int id, Map<String, dynamic> item) async {
    final repo = await _repository;
    return repo.updateSpecialFeeItem(id, item);
  }

  Future<int> deleteSpecialFeeItem(int id) async {
    final repo = await _repository;
    return repo.deleteSpecialFeeItem(id);
  }

  // ========================================
  // SPECIAL CLASS FEES (for new intake students)
  // ========================================

  Future<int> insertSpecialClassFee(Map<String, dynamic> classFee) async {
    final repo = await _repository;
    return repo.insertSpecialClassFee(classFee);
  }

  Future<List<Map<String, dynamic>>> getSpecialClassFees(int classId, String term, String session, {int? armId}) async {
    final repo = await _repository;
    return repo.getSpecialClassFees(classId, term, session, armId: armId);
  }

  Future<int> deleteSpecialClassFee(int id) async {
    final repo = await _repository;
    return repo.deleteSpecialClassFee(id);
  }

  Future<void> replaceSpecialClassFeesFor(
    int classId,
    String term,
    String session,
    List<Map<String, dynamic>> fees, {
    int? armId,
  }) async {
    final repo = await _repository;
    return repo.replaceSpecialClassFeesFor(classId, term, session, fees, armId: armId);
  }

  Future<Map<String, dynamic>> getNewIntakeBillForClass(int classId, String term, String session, {int? armId}) async {
    final repo = await _repository;
    return repo.getNewIntakeBillForClass(classId, term, session, armId: armId);
  }

  // ========================================
  // BILLS
  // ========================================

  Future<int> insertBill(Map<String, dynamic> bill, List<Map<String, dynamic>> breakdown) async {
    final repo = await _repository;
    return repo.insertBill(bill, breakdown);
  }

  Future<int> insertStudentBill(Map<String, dynamic> bill, List<Map<String, dynamic>> breakdown) async {
    final repo = await _repository;
    return repo.insertStudentBill(bill, breakdown);
  }

  Future<Map<String, dynamic>?> getBillForStudent(int studentId, String term, String session) async {
    final repo = await _repository;
    return repo.getBillForStudent(studentId, term, session);
  }

  Future<List<Map<String, dynamic>>> getBillBreakdown(int billId) async {
    final repo = await _repository;
    return repo.getBillBreakdown(billId);
  }

  Future<double> computeOutstandingForTermSession(
    int studentId, {
    required String term,
    required String session,
  }) async {
    final repo = await _repository;
    return repo.computeOutstandingForTermSession(studentId, term: term, session: session);
  }

  Future<double> computeOutstandingBeforeTerm(
    int studentId, {
    required String term,
    required String session,
  }) async {
    final repo = await _repository;
    return repo.computeOutstandingBeforeTerm(studentId, term: term, session: session);
  }

  Future<int> recalculatePreviousBalances() async {
    final repo = await _repository;
    return repo.recalculatePreviousBalances();
  }

  // ========================================
  // PAYMENTS
  // ========================================

  Future<int> insertPayment(Map<String, dynamic> payment, {String? term, String? session}) async {
    final repo = await _repository;
    return repo.insertPayment(payment, term: term, session: session);
  }

  Future<List<Map<String, dynamic>>> getPaymentsByExactDate(String date) async {
    final repo = await _repository;
    return repo.getPaymentsByExactDate(date);
  }

  Future<List<Map<String, dynamic>>> getPayments(
    int studentId, {
    String? term,
    String? session,
  }) async {
    final repo = await _repository;
    return repo.getPayments(studentId, term: term, session: session);
  }

  Future<double> computeOutstandingBalance(int studentId) async {
    final repo = await _repository;
    return repo.computeOutstandingBalance(studentId);
  }

  Future<int> updatePayment(int paymentId, Map<String, dynamic> updates) async {
    final repo = await _repository;
    return repo.updatePayment(paymentId, updates);
  }

  Future<int> deletePayment(int paymentId) async {
    final repo = await _repository;
    return repo.deletePayment(paymentId);
  }

  // ========================================
  // AUDIT LOG
  // ========================================

  Future<void> insertAuditLog({
    required String entityType,
    required int entityId,
    required String action,
    int? studentId,
    double? amount,
    Map<String, dynamic>? changes,
  }) async {
    final repo = await _repository;
    return repo.insertAuditLog(
      entityType: entityType,
      entityId: entityId,
      action: action,
      studentId: studentId,
      amount: amount,
      changes: changes,
    );
  }

  Future<List<Map<String, dynamic>>> getAuditLog({
    String? entityType,
    int? entityId,
    DateTime? from,
    DateTime? to,
    int? userId,
  }) async {
    final repo = await _repository;
    return repo.getAuditLog(
      entityType: entityType,
      entityId: entityId,
      from: from,
      to: to,
      userId: userId,
    );
  }

  // ========================================
  // EXPENSES
  // ========================================

  Future<int> insertExpense(Map<String, dynamic> expense) async {
    final repo = await _repository;
    return repo.insertExpense(expense);
  }

  Future<List<Map<String, dynamic>>> getAllExpenses({
    String? term,
    String? session,
    String? startDate,
    String? endDate,
  }) async {
    final repo = await _repository;
    return repo.getAllExpenses(
      term: term,
      session: session,
      startDate: startDate,
      endDate: endDate,
    );
  }

  Future<Map<String, dynamic>?> getExpenseById(int id) async {
    final repo = await _repository;
    return repo.getExpenseById(id);
  }

  Future<int> updateExpense(int id, Map<String, dynamic> expense) async {
    final repo = await _repository;
    return repo.updateExpense(id, expense);
  }

  Future<int> deleteExpense(int id) async {
    final repo = await _repository;
    return repo.deleteExpense(id);
  }

  Future<List<Map<String, dynamic>>> getAllExpenseCategories() async {
    final repo = await _repository;
    return repo.getAllExpenseCategories();
  }

  Future<int> insertExpenseCategory(String name) async {
    final repo = await _repository;
    return repo.insertExpenseCategory(name);
  }

  Future<int> updateExpenseCategory(int id, String name) async {
    final repo = await _repository;
    return repo.updateExpenseCategory(id, name);
  }

  Future<int> deleteExpenseCategory(int id) async {
    final repo = await _repository;
    return repo.deleteExpenseCategory(id);
  }

  // ========================================
  // STAFF FINANCIAL RECORDS
  // ========================================

  Future<Map<String, dynamic>?> getStaffById(int id) async {
    final repo = await _repository;
    return repo.getStaffById(id);
  }

  // -- Staff Loans --

  Future<int> insertStaffLoan(Map<String, dynamic> loan) async {
    final repo = await _repository;
    return repo.insertStaffLoan(loan);
  }

  Future<List<Map<String, dynamic>>> getAllStaffLoans() async {
    final repo = await _repository;
    return repo.getAllStaffLoans();
  }

  Future<Map<String, dynamic>?> getStaffLoanById(int id) async {
    final repo = await _repository;
    return repo.getStaffLoanById(id);
  }

  Future<int> updateStaffLoan(int id, Map<String, dynamic> loan) async {
    final repo = await _repository;
    return repo.updateStaffLoan(id, loan);
  }

  Future<int> deleteStaffLoan(int id) async {
    final repo = await _repository;
    return repo.deleteStaffLoan(id);
  }

  // -- Staff Deductions --

  Future<int> insertStaffDeduction(Map<String, dynamic> deduction) async {
    final repo = await _repository;
    return repo.insertStaffDeduction(deduction);
  }

  Future<List<Map<String, dynamic>>> getStaffDeductionsByMonth(String month) async {
    final repo = await _repository;
    return repo.getStaffDeductionsByMonth(month);
  }

  Future<int> updateStaffDeduction(int id, Map<String, dynamic> data) async {
    final repo = await _repository;
    return repo.updateStaffDeduction(id, data);
  }

  Future<int> deleteStaffDeduction(int id) async {
    final repo = await _repository;
    return repo.deleteStaffDeduction(id);
  }

  // -- Staff Incentives --

  Future<int> insertStaffIncentive(Map<String, dynamic> incentive) async {
    final repo = await _repository;
    return repo.insertStaffIncentive(incentive);
  }

  Future<List<Map<String, dynamic>>> getStaffIncentivesByMonth(String month) async {
    final repo = await _repository;
    return repo.getStaffIncentivesByMonth(month);
  }

  Future<int> updateStaffIncentive(int id, Map<String, dynamic> data) async {
    final repo = await _repository;
    return repo.updateStaffIncentive(id, data);
  }

  Future<int> deleteStaffIncentive(int id) async {
    final repo = await _repository;
    return repo.deleteStaffIncentive(id);
  }

  // -- Staff Salary Payments --

  Future<void> toggleStaffSalaryPayment(
    int staffId,
    String month,
    bool isPaid, {
    String? paymentMethod,
    String? notes,
  }) async {
    final repo = await _repository;
    return repo.toggleStaffSalaryPayment(
      staffId,
      month,
      isPaid,
      paymentMethod: paymentMethod,
      notes: notes,
    );
  }

  Future<List<Map<String, dynamic>>> getSalaryPaymentsByMonth(String month) async {
    final repo = await _repository;
    return repo.getSalaryPaymentsByMonth(month);
  }

  Future<Map<String, dynamic>?> getStaffSalaryPayment(int staffId, String month) async {
    final repo = await _repository;
    return repo.getStaffSalaryPayment(staffId, month);
  }

  Future<void> setLoanDeductionsAppliedForPayment(int staffId, String month, String? json) async {
    final repo = await _repository;
    return repo.setLoanDeductionsAppliedForPayment(staffId, month, json);
  }

  // -- Staff Salary Increments/History --

  Future<int> insertSalaryHistory(
    int staffId,
    double salary,
    String effectiveMonth, {
    String? reason,
  }) async {
    final repo = await _repository;
    return repo.insertSalaryHistory(staffId, salary, effectiveMonth, reason: reason);
  }

  Future<List<Map<String, dynamic>>> getSalaryHistory(int staffId) async {
    final repo = await _repository;
    return repo.getSalaryHistory(staffId);
  }

  Future<List<Map<String, dynamic>>> getAllSalaryHistory() async {
    final repo = await _repository;
    return repo.getAllSalaryHistory();
  }

  Future<int> deleteSalaryHistory(int id) async {
    final repo = await _repository;
    return repo.deleteSalaryHistory(id);
  }

  Future<int> updateStaffSalary(int id, double salary) async {
    final repo = await _repository;
    return repo.updateStaffSalary(id, salary);
  }

  // ========================================
  // FINANCIAL AGGREGATES
  // ========================================

  Future<double> getTotalBillsForTermSession({
    required String term,
    required String session,
  }) async {
    final repo = await _repository;
    return repo.getTotalBillsForTermSession(term: term, session: session);
  }

  Future<double> getTotalPaymentsForTermSession({
    required String term,
    required String session,
  }) async {
    final repo = await _repository;
    return repo.getTotalPaymentsForTermSession(term: term, session: session);
  }

  // ========================================
  // REPORTS
  // ========================================

  Future<List<Map<String, dynamic>>> getDebtorsList({
    required int classId,
    required String term,
    required String session,
    double minPercentagePaid = 0.0,
  }) async {
    final repo = await _repository;
    return repo.getDebtorsList(
      classId: classId,
      term: term,
      session: session,
      minPercentagePaid: minPercentagePaid,
    );
  }

  Future<Map<String, dynamic>> getDebtorsSummary({
    required int classId,
    required String term,
    required String session,
  }) async {
    final repo = await _repository;
    return repo.getDebtorsSummary(classId: classId, term: term, session: session);
  }

  Future<List<Map<String, dynamic>>> getLastTermDebtors({
    required String term,
    required String session,
    int classId = 0,
    int armId = 0,
  }) async {
    final repo = await _repository;
    return repo.getLastTermDebtors(
      term: term,
      session: session,
      classId: classId,
      armId: armId,
    );
  }

  Future<Map<String, dynamic>> getFeesBalanceSummary({
    required String term,
    required String session,
    int classId = 0,
  }) async {
    final repo = await _repository;
    return repo.getFeesBalanceSummary(
      term: term,
      session: session,
      classId: classId,
    );
  }

  Future<List<Map<String, dynamic>>> getBalancedStudentsList({
    required int classId,
    required String term,
    required String session,
  }) async {
    final repo = await _repository;
    return repo.getBalancedStudentsList(
      classId: classId,
      term: term,
      session: session,
    );
  }

  // ========================================
  // SCHOOL PROFILE
  // ========================================

  Future<Map<String, dynamic>?> getSchoolProfile() async {
    final repo = await _repository;
    return repo.getSchoolProfile();
  }

  Future<int> saveSchoolProfile(Map<String, dynamic> data) async {
    final repo = await _repository;
    return repo.saveSchoolProfile(data);
  }

  // ========================================
  // GENERIC SETTINGS
  // ========================================

  Future<String?> getSetting(String key) async {
    final repo = await _repository;
    return repo.getSetting(key);
  }

  Future<void> setSetting(String key, String value) async {
    final repo = await _repository;
    return repo.setSetting(key, value);
  }

  // ========================================
  // SMS LOG
  // ========================================

  Future<int> insertSmsLog({
    int? studentId,
    required String phone,
    required String message,
    String? context,
    required String status,
    String? errorMessage,
  }) async {
    final repo = await _repository;
    return repo.insertSmsLog(
      studentId: studentId,
      phone: phone,
      message: message,
      context: context,
      status: status,
      errorMessage: errorMessage,
    );
  }

  // ========================================
  // STOCK ITEMS
  // ========================================

  Future<int> insertStockItem(Map<String, dynamic> item) async {
    final repo = await _repository;
    return repo.insertStockItem(item);
  }

  Future<List<Map<String, dynamic>>> getStockItems({bool includeInactive = false}) async {
    final repo = await _repository;
    return repo.getStockItems(includeInactive: includeInactive);
  }

  Future<Map<String, dynamic>?> getStockItemById(int id) async {
    final repo = await _repository;
    return repo.getStockItemById(id);
  }

  Future<int> updateStockItem(int id, Map<String, dynamic> item) async {
    final repo = await _repository;
    return repo.updateStockItem(id, item);
  }

  Future<int> deactivateStockItem(int id) async {
    final repo = await _repository;
    return repo.deactivateStockItem(id);
  }

  Future<void> deleteStockItem(int stockItemId) async {
    final repo = await _repository;
    return repo.deleteStockItem(stockItemId);
  }

  Future<void> adjustStockQuantity(
    int stockItemId,
    int newQuantity,
    String note, {
    String? createdBy,
  }) async {
    final repo = await _repository;
    return repo.adjustStockQuantity(stockItemId, newQuantity, note, createdBy: createdBy);
  }

  Future<void> restockItem(
    int stockItemId, {
    required int quantityAdded,
    required String supplier,
    String? invoiceNumber,
    double? newCostPrice,
    String? notes,
    String? createdBy,
  }) async {
    final repo = await _repository;
    return repo.restockItem(
      stockItemId,
      quantityAdded: quantityAdded,
      supplier: supplier,
      invoiceNumber: invoiceNumber,
      newCostPrice: newCostPrice,
      notes: notes,
      createdBy: createdBy,
    );
  }

  Future<List<Map<String, dynamic>>> getLowStockItems() async {
    final repo = await _repository;
    return repo.getLowStockItems();
  }

  Future<List<Map<String, dynamic>>> getParentItems() async {
    final repo = await _repository;
    return repo.getParentItems();
  }

  Future<List<Map<String, dynamic>>> getChildItems(int parentId) async {
    final repo = await _repository;
    return repo.getChildItems(parentId);
  }

  Future<bool> hasChildItems(int itemId) async {
    final repo = await _repository;
    return repo.hasChildItems(itemId);
  }

  Future<bool> canSetAsParent(int itemId, int? proposedParentId) async {
    final repo = await _repository;
    return repo.canSetAsParent(itemId, proposedParentId);
  }

  // ========================================
  // SUPPLIERS
  // ========================================

  Future<int> insertSupplier(Map<String, dynamic> supplier) async {
    final repo = await _repository;
    return repo.insertSupplier(supplier);
  }

  Future<List<Map<String, dynamic>>> getSuppliers({bool includeInactive = false}) async {
    final repo = await _repository;
    return repo.getSuppliers(includeInactive: includeInactive);
  }

  Future<Map<String, dynamic>?> getSupplierById(int id) async {
    final repo = await _repository;
    return repo.getSupplierById(id);
  }

  Future<int> updateSupplier(int id, Map<String, dynamic> supplier) async {
    final repo = await _repository;
    return repo.updateSupplier(id, supplier);
  }

  Future<int> deactivateSupplier(int id) async {
    final repo = await _repository;
    return repo.deactivateSupplier(id);
  }

  Future<void> deleteSupplier(int id) async {
    final repo = await _repository;
    return repo.deleteSupplier(id);
  }

  // ========================================
  // SALES
  // ========================================

  Future<int> insertSale(Map<String, dynamic> sale, {String? createdBy}) async {
    final repo = await _repository;
    return repo.insertSale(sale, createdBy: createdBy);
  }

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
    final repo = await _repository;
    return repo.updateSalePayment(
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
  }

  Future<List<Map<String, dynamic>>> getSalesByExactDate(String date) async {
    final repo = await _repository;
    return repo.getSalesByExactDate(date);
  }

  Future<List<Map<String, dynamic>>> getAllSales({
    String? term,
    String? session,
    String? startDate,
    String? endDate,
    int? studentId,
  }) async {
    final repo = await _repository;
    return repo.getAllSales(
      term: term,
      session: session,
      startDate: startDate,
      endDate: endDate,
      studentId: studentId,
    );
  }

  Future<Map<String, dynamic>?> getSaleById(int id) async {
    final repo = await _repository;
    return repo.getSaleById(id);
  }

  Future<Map<String, double>> getSalesTotalsByMethod(String date) async {
    final repo = await _repository;
    return repo.getSalesTotalsByMethod(date);
  }

  Future<void> deleteSale(int saleId, {String? deletedBy}) async {
    final repo = await _repository;
    return repo.deleteSale(saleId, deletedBy: deletedBy);
  }

  Future<List<Map<String, dynamic>>> getSalesDebtors({
    String? term,
    String? session,
  }) async {
    final repo = await _repository;
    return repo.getSalesDebtors(term: term, session: session);
  }

  // ========================================
  // STOCK MOVEMENTS
  // ========================================

  Future<List<Map<String, dynamic>>> getStockMovements(
    int stockItemId, {
    String? startDate,
    String? endDate,
  }) async {
    final repo = await _repository;
    return repo.getStockMovements(stockItemId, startDate: startDate, endDate: endDate);
  }

  // ========================================
  // LICENSES
  // ========================================

  Future<Map<String, dynamic>?> getActiveLicense() async {
    final repo = await _repository;
    return repo.getActiveLicense();
  }

  Future<int> activateLicense({
    required String licenseKey,
    required String schoolName,
    required String schoolCode,
    required String deviceId,
    required DateTime expiryDate,
    int? maxStudents,
  }) async {
    final repo = await _repository;
    return repo.activateLicense(
      licenseKey: licenseKey,
      schoolName: schoolName,
      schoolCode: schoolCode,
      deviceId: deviceId,
      expiryDate: expiryDate,
      maxStudents: maxStudents,
    );
  }

  Future<int> deactivateLicense(int licenseId) async {
    final repo = await _repository;
    return repo.deactivateLicense(licenseId);
  }

  Future<List<Map<String, dynamic>>> getAllLicenses() async {
    final repo = await _repository;
    return repo.getAllLicenses();
  }

  Future<bool> licenseKeyExists(String licenseKey) async {
    final repo = await _repository;
    return repo.licenseKeyExists(licenseKey);
  }

  Future<Map<String, dynamic>?> getLicenseByKey(String licenseKey) async {
    final repo = await _repository;
    return repo.getLicenseByKey(licenseKey);
  }

  Future<void> reactivateLicense(int licenseId) async {
    final repo = await _repository;
    return repo.reactivateLicense(licenseId);
  }

  // ========================================
  // DATABASE MANAGEMENT
  // ========================================

  // ========================================
  // FEE PRIORITY (Fee Tracker)
  // ========================================

  Future<List<Map<String, dynamic>>> getFeePriorities({
    required String scope, int? classId, int? armId,
    required String term, required String session,
  }) async {
    final repo = await _repository;
    return repo.getFeePriorities(scope: scope, classId: classId, armId: armId, term: term, session: session);
  }

  Future<void> saveFeePriorities({
    required String scope, int? classId, int? armId,
    required String term, required String session,
    required List<Map<String, dynamic>> priorities,
  }) async {
    final repo = await _repository;
    return repo.saveFeePriorities(scope: scope, classId: classId, armId: armId, term: term, session: session, priorities: priorities);
  }

  Future<List<Map<String, dynamic>>> getEffectiveFeePriorities({
    required int classId, int? armId,
    required String term, required String session,
  }) async {
    final repo = await _repository;
    return repo.getEffectiveFeePriorities(classId: classId, armId: armId, term: term, session: session);
  }

  Future<List<Map<String, dynamic>>> getStudentsWithFeeItem({
    required int feeItemId, required String term, required String session,
    int? classId, int? armId,
  }) async {
    final repo = await _repository;
    return repo.getStudentsWithFeeItem(feeItemId: feeItemId, term: term, session: session, classId: classId, armId: armId);
  }

  Future<List<Map<String, dynamic>>> getPaymentProgressionData({
    required String term, required String session,
    int? classId, int? armId,
  }) async {
    final repo = await _repository;
    return repo.getPaymentProgressionData(term: term, session: session, classId: classId, armId: armId);
  }

  Future<List<Map<String, dynamic>>> getExtraFeeItemsForClassArm({
    required int classId, int? armId,
    required String term, required String session,
  }) async {
    final repo = await _repository;
    return repo.getExtraFeeItemsForClassArm(classId: classId, armId: armId, term: term, session: session);
  }

  // ========================================
  // TRANSPORTATION
  // ========================================

  Future<List<Map<String, dynamic>>> getTransportRoutes({bool includeInactive = false}) async {
    final repo = await _repository;
    return repo.getTransportRoutes(includeInactive: includeInactive);
  }

  Future<Map<String, dynamic>?> getTransportRouteById(int id) async {
    final repo = await _repository;
    return repo.getTransportRouteById(id);
  }

  Future<int> insertTransportRoute(Map<String, dynamic> data) async {
    final repo = await _repository;
    return repo.insertTransportRoute(data);
  }

  Future<int> updateTransportRoute(int id, Map<String, dynamic> data) async {
    final repo = await _repository;
    return repo.updateTransportRoute(id, data);
  }

  Future<int> deleteTransportRoute(int id) async {
    final repo = await _repository;
    return repo.deleteTransportRoute(id);
  }

  Future<int> countActiveAllocationsForRoute(int routeId) async {
    final repo = await _repository;
    return repo.countActiveAllocationsForRoute(routeId);
  }

  Future<Map<String, dynamic>?> getStudentTransportAllocation(int studentId, String term, String session) async {
    final repo = await _repository;
    return repo.getStudentTransportAllocation(studentId, term, session);
  }

  Future<List<Map<String, dynamic>>> getRouteAllocationsWithDetails(String term, String session) async {
    final repo = await _repository;
    return repo.getRouteAllocationsWithDetails(term, session);
  }

  Future<int> allocateStudentToRoute({
    required int studentId,
    required int routeId,
    required String term,
    required String session,
  }) async {
    final repo = await _repository;
    return repo.allocateStudentToRoute(studentId: studentId, routeId: routeId, term: term, session: session);
  }

  Future<int> removeStudentFromRoute(int studentId, String term, String session) async {
    final repo = await _repository;
    return repo.removeStudentFromRoute(studentId, term, session);
  }

  Future<void> closeAndReset() async {
    final repo = await _repository;
    return repo.closeAndReset();
  }

  Future<void> close() async {
    final repo = await _repository;
    return repo.close();
  }
}
