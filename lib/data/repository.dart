// lib/data/repository.dart
// Abstract repository interface for data operations
// This allows switching between local (SQLite) and remote (API) data sources

abstract class DataRepository {
  // ========================================
  // AUTHENTICATION & USERS
  // ========================================

  /// Authenticate user with username and password
  Future<Map<String, dynamic>?> authenticateUser(String username, String password);

  /// Get user by username
  Future<Map<String, dynamic>?> getUserByUsername(String username);

  /// Get all users
  Future<List<Map<String, dynamic>>> getAllUsers();

  /// Get user by ID
  Future<Map<String, dynamic>?> getUserById(int userId);

  /// Update user credentials
  Future<bool> updateUserCredentials({
    required int userId,
    required String newUsername,
    required String newPassword,
  });

  /// Reset bursar credentials
  Future<bool> resetBursarCredentials({
    required String newUsername,
    required String newPassword,
  });

  /// Get bursar account
  Future<Map<String, dynamic>?> getBursarAccount();

  /// Create new user
  Future<int?> createUser({
    required String username,
    required String password,
    required String userType,
    required int canChangeCredentials,
  });

  /// Update user
  Future<bool> updateUser({
    required int userId,
    required String username,
    required String password,
    required String userType,
    required int canChangeCredentials,
  });

  /// Delete user
  Future<Map<String, dynamic>> deleteUser(int userId);

  /// Count super admins
  Future<int> countSuperAdmins();

  // ========================================
  // PERMISSIONS
  // ========================================

  /// Get all permissions for a role
  Future<List<Map<String, dynamic>>> getPermissionsByRole(String role);

  /// Check if role has permission for module
  Future<bool> hasPermission(String role, String module);

  /// Set permission for role and module
  Future<void> setPermission(String role, String module, bool canAccess);

  /// Update all permissions for a role
  Future<void> updateRolePermissions(String role, Map<String, bool> permissions);

  // ========================================
  // SESSIONS & TERMS
  // ========================================

  /// Get active term
  Future<String> getActiveTerm();

  /// Set active term
  Future<void> setActiveTerm(String term);

  /// Get active session
  Future<Map<String, dynamic>?> getActiveSession();

  /// Get all sessions
  Future<List<Map<String, dynamic>>> getAllSessions();

  /// Get sessions (alias for getAllSessions)
  Future<List<Map<String, dynamic>>> getSessions();

  /// Set active session
  Future<void> setActiveSession(int sessionId);

  // ========================================
  // STUDENTS
  // ========================================

  /// Insert new student
  Future<int> insertStudent(Map<String, dynamic> student);

  /// Get all students (optionally include inactive)
  Future<List<Map<String, dynamic>>> getStudents({bool includeInactive = false});

  /// Get only active students
  Future<List<Map<String, dynamic>>> getActiveStudents();

  /// Get active students with class and arm names (for student list display)
  Future<List<Map<String, dynamic>>> getActiveStudentsWithDetails();

  /// Get only inactive students
  Future<List<Map<String, dynamic>>> getInactiveStudents();

  /// Get student by ID
  Future<Map<String, dynamic>?> getStudentById(int id);

  /// Get student by ID with class and arm names (for payment/billing screens)
  Future<Map<String, dynamic>?> getStudentByIdWithDetails(int id);

  /// Update student
  Future<int> updateStudent(int id, Map<String, dynamic> student);

  /// Delete student
  Future<int> deleteStudent(int id);

  /// Deactivate student
  Future<int> deactivateStudent(int studentId, String leftDate, String leftReason);

  /// Restore deactivated student
  Future<int> restoreStudent(int studentId);

  /// Generate new admission number
  Future<String> generateAdmissionNumber();

  // ========================================
  // PARENTS
  // ========================================

  /// Insert new parent
  Future<int> insertParent(Map<String, dynamic> parent);

  /// Get all parents
  Future<List<Map<String, dynamic>>> getAllParents();

  /// Get parent by ID
  Future<Map<String, dynamic>?> getParentById(int id);

  /// Search parents by name, phone, or email
  Future<List<Map<String, dynamic>>> searchParents(String query);

  /// Update parent
  Future<int> updateParent(int id, Map<String, dynamic> parent);

  /// Delete parent
  Future<int> deleteParent(int id);

  // ========================================
  // CLASSES
  // ========================================

  /// Insert new class
  Future<int> insertClass(Map<String, dynamic> cls);

  /// Get all classes
  Future<List<Map<String, dynamic>>> getClasses();

  /// Update class
  Future<int> updateClass(int id, Map<String, dynamic> cls);

  /// Delete class
  Future<int> deleteClass(int id);

  // ========================================
  // ARMS
  // ========================================

  /// Insert new arm
  Future<int> insertArm(Map<String, dynamic> arm);

  /// Get arms for a class
  Future<List<Map<String, dynamic>>> getArmsByClass(int classId);

  /// Get all arms
  Future<List<Map<String, dynamic>>> getArms();

  /// Update arm
  Future<int> updateArm(int id, Map<String, dynamic> arm);

  /// Delete arm
  Future<int> deleteArm(int id);

  // ========================================
  // FEE ITEMS
  // ========================================

  /// Insert fee item
  Future<int> insertFeeItem(Map<String, dynamic> item);

  /// Get fee items (optionally filtered by term and session)
  Future<List<Map<String, dynamic>>> getFeeItems({String? term, String? session});

  /// Update fee item
  Future<int> updateFeeItem(int id, Map<String, dynamic> item);

  /// Delete fee item
  Future<int> deleteFeeItem(int id);

  // ========================================
  // CLASS FEES
  // ========================================

  /// Insert class fee
  Future<int> insertClassFee(Map<String, dynamic> classFee);

  /// Get class fees for a class in specific term/session
  Future<List<Map<String, dynamic>>> getClassFees(int classId, String term, String session, {int? armId});

  /// Delete class fee
  Future<int> deleteClassFee(int id);

  /// Replace all class fees for a class in term/session
  Future<void> replaceClassFeesFor(
    int classId,
    String term,
    String session,
    List<Map<String, dynamic>> fees, {
    int? armId,
  });

  // ========================================
  // SPECIAL FEE ITEMS (for new intake students)
  // ========================================

  /// Insert special fee item
  Future<int> insertSpecialFeeItem(Map<String, dynamic> item);

  /// Get special fee items (optionally filtered by term and session)
  Future<List<Map<String, dynamic>>> getSpecialFeeItems({String? term, String? session, bool? parentsOnly, int? parentId, bool? categoriesOnly, bool? standaloneOnly});

  /// Get parent items (categories) only
  Future<List<Map<String, dynamic>>> getSpecialFeeItemParents({String? term, String? session});

  /// Get categories only (items marked as isCategory = 1)
  Future<List<Map<String, dynamic>>> getSpecialFeeItemCategories({String? term, String? session});

  /// Get standalone items only (parentId IS NULL AND isCategory = 0)
  Future<List<Map<String, dynamic>>> getSpecialFeeItemStandalone({String? term, String? session});

  /// Get child items for a specific parent
  Future<List<Map<String, dynamic>>> getSpecialFeeItemChildren(int parentId, {String? term, String? session});

  /// Check if an item has children
  Future<bool> specialFeeItemHasChildren(int itemId);

  /// Get special fee items with hierarchy
  Future<List<Map<String, dynamic>>> getSpecialFeeItemsHierarchy({String? term, String? session});

  /// Update special fee item
  Future<int> updateSpecialFeeItem(int id, Map<String, dynamic> item);

  /// Delete special fee item
  Future<int> deleteSpecialFeeItem(int id);

  // ========================================
  // SPECIAL CLASS FEES (for new intake students)
  // ========================================

  /// Insert special class fee
  Future<int> insertSpecialClassFee(Map<String, dynamic> classFee);

  /// Get special class fees for a class in specific term/session
  Future<List<Map<String, dynamic>>> getSpecialClassFees(int classId, String term, String session, {int? armId});

  /// Delete special class fee
  Future<int> deleteSpecialClassFee(int id);

  /// Replace all special class fees for a class in term/session
  Future<void> replaceSpecialClassFeesFor(
    int classId,
    String term,
    String session,
    List<Map<String, dynamic>> fees, {
    int? armId,
  });

  /// Get combined new intake bill (regular fees + special fees) for a class
  Future<Map<String, dynamic>> getNewIntakeBillForClass(int classId, String term, String session, {int? armId});

  // ========================================
  // BILLS
  // ========================================

  /// Insert bill with breakdown
  Future<int> insertBill(Map<String, dynamic> bill, List<Map<String, dynamic>> breakdown);

  /// Insert student bill with breakdown (alias)
  Future<int> insertStudentBill(Map<String, dynamic> bill, List<Map<String, dynamic>> breakdown);

  /// Get bill for student in term/session
  Future<Map<String, dynamic>?> getBillForStudent(int studentId, String term, String session);

  /// Get bill breakdown
  Future<List<Map<String, dynamic>>> getBillBreakdown(int billId);

  /// Compute outstanding for specific term/session
  Future<double> computeOutstandingForTermSession(
    int studentId, {
    required String term,
    required String session,
  });

  /// Compute outstanding before a specific term/session
  Future<double> computeOutstandingBeforeTerm(
    int studentId, {
    required String term,
    required String session,
  });

  /// Fix inflated previousBalance values in all existing bills.
  /// Returns the number of bills that were corrected.
  Future<int> recalculatePreviousBalances();

  // ========================================
  // PAYMENTS
  // ========================================

  /// Insert payment
  Future<int> insertPayment(Map<String, dynamic> payment, {String? term, String? session});

  /// Get payments by exact date
  Future<List<Map<String, dynamic>>> getPaymentsByExactDate(String date);

  /// Get payments for student (optionally filtered by term/session)
  Future<List<Map<String, dynamic>>> getPayments(
    int studentId, {
    String? term,
    String? session,
  });

  /// Compute overall outstanding balance for student
  Future<double> computeOutstandingBalance(int studentId);

  /// Update payment
  Future<int> updatePayment(int paymentId, Map<String, dynamic> updates);

  /// Delete payment
  Future<int> deletePayment(int paymentId);

  // ========================================
  // AUDIT LOG (financial activity trail — create/update/delete)
  // ========================================

  /// Record an audit log entry for a financial mutation
  Future<void> insertAuditLog({
    required String entityType,
    required int entityId,
    required String action,
    int? studentId,
    double? amount,
    Map<String, dynamic>? changes,
  });

  /// Fetch audit log entries, optionally filtered
  Future<List<Map<String, dynamic>>> getAuditLog({
    String? entityType,
    int? entityId,
    DateTime? from,
    DateTime? to,
    int? userId,
  });

  // ========================================
  // EXPENSES
  // ========================================

  /// Insert expense
  Future<int> insertExpense(Map<String, dynamic> expense);

  /// Get all expenses, optionally filtered by term/session/date range
  Future<List<Map<String, dynamic>>> getAllExpenses({
    String? term,
    String? session,
    String? startDate,
    String? endDate,
  });

  /// Get expense by id
  Future<Map<String, dynamic>?> getExpenseById(int id);

  /// Update expense
  Future<int> updateExpense(int id, Map<String, dynamic> expense);

  /// Delete expense
  Future<int> deleteExpense(int id);

  /// Get all expense categories
  Future<List<Map<String, dynamic>>> getAllExpenseCategories();

  /// Insert a new expense category
  Future<int> insertExpenseCategory(String name);

  /// Update an expense category name
  Future<int> updateExpenseCategory(int id, String name);

  /// Delete an expense category
  Future<int> deleteExpenseCategory(int id);

  // ========================================
  // STAFF FINANCIAL RECORDS
  // ========================================

  /// Get staff by id (read-only companion to the staff financial records
  /// below, e.g. for Activity Log name resolution)
  Future<Map<String, dynamic>?> getStaffById(int id);

  // -- Staff Loans --
  Future<int> insertStaffLoan(Map<String, dynamic> loan);
  Future<List<Map<String, dynamic>>> getAllStaffLoans();
  Future<Map<String, dynamic>?> getStaffLoanById(int id);
  Future<int> updateStaffLoan(int id, Map<String, dynamic> loan);
  Future<int> deleteStaffLoan(int id);

  // -- Staff Deductions --
  Future<int> insertStaffDeduction(Map<String, dynamic> deduction);
  Future<List<Map<String, dynamic>>> getStaffDeductionsByMonth(String month);
  Future<int> updateStaffDeduction(int id, Map<String, dynamic> data);
  Future<int> deleteStaffDeduction(int id);

  // -- Staff Incentives --
  Future<int> insertStaffIncentive(Map<String, dynamic> incentive);
  Future<List<Map<String, dynamic>>> getStaffIncentivesByMonth(String month);
  Future<int> updateStaffIncentive(int id, Map<String, dynamic> data);
  Future<int> deleteStaffIncentive(int id);

  // -- Staff Salary Payments --
  Future<void> toggleStaffSalaryPayment(
    int staffId,
    String month,
    bool isPaid, {
    String? paymentMethod,
    String? notes,
  });
  Future<List<Map<String, dynamic>>> getSalaryPaymentsByMonth(String month);
  Future<Map<String, dynamic>?> getStaffSalaryPayment(int staffId, String month);
  Future<void> setLoanDeductionsAppliedForPayment(int staffId, String month, String? json);

  // -- Staff Salary Increments/History --
  Future<int> insertSalaryHistory(
    int staffId,
    double salary,
    String effectiveMonth, {
    String? reason,
  });
  Future<List<Map<String, dynamic>>> getSalaryHistory(int staffId);
  Future<List<Map<String, dynamic>>> getAllSalaryHistory();
  Future<int> deleteSalaryHistory(int id);
  Future<int> updateStaffSalary(int id, double salary);

  // ========================================
  // FINANCIAL AGGREGATES (for Dashboard & Reports)
  // ========================================

  /// Get total bills amount for specific term/session
  Future<double> getTotalBillsForTermSession({
    required String term,
    required String session,
  });

  /// Get total payments amount for specific term/session
  Future<double> getTotalPaymentsForTermSession({
    required String term,
    required String session,
  });

  // ========================================
  // REPORTS
  // ========================================

  /// Get debtors list with detailed breakdown
  Future<List<Map<String, dynamic>>> getDebtorsList({
    required int classId,
    required String term,
    required String session,
    double minPercentagePaid = 0.0,
  });

  /// Get debtors summary statistics
  Future<Map<String, dynamic>> getDebtorsSummary({
    required int classId,
    required String term,
    required String session,
  });

  /// Get students with a carry-over previous balance on their current-term bill
  Future<List<Map<String, dynamic>>> getLastTermDebtors({
    required String term,
    required String session,
    int classId = 0,
    int armId = 0,
  });

  /// Get counts/totals of balanced vs owing students for a term/session
  Future<Map<String, dynamic>> getFeesBalanceSummary({
    required String term,
    required String session,
    int classId = 0,
  });

  /// Get students who have fully paid off their bill for a term/session
  Future<List<Map<String, dynamic>>> getBalancedStudentsList({
    required int classId,
    required String term,
    required String session,
  });

  // ========================================
  // SCHOOL PROFILE
  // ========================================

  /// Get school profile
  Future<Map<String, dynamic>?> getSchoolProfile();

  /// Save school profile
  Future<int> saveSchoolProfile(Map<String, dynamic> data);

  // ========================================
  // GENERIC SETTINGS (SMS gateway config, etc.)
  // ========================================

  /// Get a generic key/value setting
  Future<String?> getSetting(String key);

  /// Set a generic key/value setting
  Future<void> setSetting(String key, String value);

  // ========================================
  // SMS LOG
  // ========================================

  /// Record an SMS send attempt (success or failure)
  Future<int> insertSmsLog({
    int? studentId,
    required String phone,
    required String message,
    String? context,
    required String status,
    String? errorMessage,
  });

  // ========================================
  // LICENSES
  // ========================================

  /// Get active license
  Future<Map<String, dynamic>?> getActiveLicense();

  /// Activate license
  Future<int> activateLicense({
    required String licenseKey,
    required String schoolName,
    required String schoolCode,
    required String deviceId,
    required DateTime expiryDate,
    int? maxStudents,
  });

  /// Deactivate license
  Future<int> deactivateLicense(int licenseId);

  /// Get all licenses
  Future<List<Map<String, dynamic>>> getAllLicenses();

  /// Check if license key exists
  Future<bool> licenseKeyExists(String licenseKey);

  /// Get license by key
  Future<Map<String, dynamic>?> getLicenseByKey(String licenseKey);

  /// Reactivate license
  Future<void> reactivateLicense(int licenseId);

  // ========================================
  // STOCK ITEMS
  // ========================================

  /// Insert new stock item
  Future<int> insertStockItem(Map<String, dynamic> item);

  /// Get all stock items
  Future<List<Map<String, dynamic>>> getStockItems({bool includeInactive = false});

  /// Get stock item by ID
  Future<Map<String, dynamic>?> getStockItemById(int id);

  /// Update stock item
  Future<int> updateStockItem(int id, Map<String, dynamic> item);

  /// Deactivate stock item (soft delete)
  Future<int> deactivateStockItem(int id);

  /// Delete stock item (only if not used in any sales)
  Future<void> deleteStockItem(int stockItemId);

  /// Adjust stock quantity manually (with audit trail)
  Future<void> adjustStockQuantity(
    int stockItemId,
    int newQuantity,
    String note, {
    String? createdBy,
  });

  /// Restock an item (add inventory with purchase tracking)
  Future<void> restockItem(
    int stockItemId, {
    required int quantityAdded,
    required String supplier,
    String? invoiceNumber,
    double? newCostPrice,
    String? notes,
    String? createdBy,
  });

  /// Get low stock items (below reorder level)
  Future<List<Map<String, dynamic>>> getLowStockItems();

  /// Get all parent items (categories)
  Future<List<Map<String, dynamic>>> getParentItems();

  /// Get child items for a specific parent
  Future<List<Map<String, dynamic>>> getChildItems(int parentId);

  /// Check if item has children (prevent deletion)
  Future<bool> hasChildItems(int itemId);

  /// Validate parent-child relationship (prevent circular references)
  Future<bool> canSetAsParent(int itemId, int? proposedParentId);

  // ========================================
  // SUPPLIERS
  // ========================================

  /// Insert a new supplier
  Future<int> insertSupplier(Map<String, dynamic> supplier);

  /// Get all suppliers
  Future<List<Map<String, dynamic>>> getSuppliers({bool includeInactive = false});

  /// Get a supplier by ID
  Future<Map<String, dynamic>?> getSupplierById(int id);

  /// Update a supplier
  Future<int> updateSupplier(int id, Map<String, dynamic> supplier);

  /// Deactivate a supplier (soft delete)
  Future<int> deactivateSupplier(int id);

  /// Permanently delete a supplier
  Future<void> deleteSupplier(int id);

  // ========================================
  // SALES
  // ========================================

  /// Record a new sale (with automatic stock deduction and movement log)
  Future<int> insertSale(Map<String, dynamic> sale, {String? createdBy});

  /// Update an existing sale with additional payment (for debt repayment)
  /// Returns the payment receipt ID (if a payment was made) or 0 (if no payment)
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
  });

  /// Get sales by exact date
  Future<List<Map<String, dynamic>>> getSalesByExactDate(String date);

  /// Get all sales with optional filters
  Future<List<Map<String, dynamic>>> getAllSales({
    String? term,
    String? session,
    String? startDate,
    String? endDate,
    int? studentId,
  });

  /// Get sale by ID
  Future<Map<String, dynamic>?> getSaleById(int id);

  /// Get sales totals by payment method for a date
  Future<Map<String, double>> getSalesTotalsByMethod(String date);

  /// Delete sale and restore stock quantity
  Future<void> deleteSale(int saleId, {String? deletedBy});

  /// Get all sales debtors
  Future<List<Map<String, dynamic>>> getSalesDebtors({
    String? term,
    String? session,
  });

  // ========================================
  // STOCK MOVEMENTS
  // ========================================

  /// Get stock movements for an item
  Future<List<Map<String, dynamic>>> getStockMovements(
    int stockItemId, {
    String? startDate,
    String? endDate,
  });

  // ========================================
  // FEE PRIORITY (Fee Tracker)
  // ========================================

  Future<List<Map<String, dynamic>>> getFeePriorities({
    required String scope,
    int? classId,
    int? armId,
    required String term,
    required String session,
  });

  Future<void> saveFeePriorities({
    required String scope,
    int? classId,
    int? armId,
    required String term,
    required String session,
    required List<Map<String, dynamic>> priorities,
  });

  Future<List<Map<String, dynamic>>> getEffectiveFeePriorities({
    required int classId,
    int? armId,
    required String term,
    required String session,
  });

  Future<List<Map<String, dynamic>>> getStudentsWithFeeItem({
    required int feeItemId,
    required String term,
    required String session,
    int? classId,
    int? armId,
  });

  Future<List<Map<String, dynamic>>> getPaymentProgressionData({
    required String term,
    required String session,
    int? classId,
    int? armId,
  });

  /// Get fee items in student bills for a class/arm that are NOT class-default fees
  Future<List<Map<String, dynamic>>> getExtraFeeItemsForClassArm({
    required int classId,
    int? armId,
    required String term,
    required String session,
  });

  // ========================================
  // TRANSPORTATION
  // ========================================

  Future<List<Map<String, dynamic>>> getTransportRoutes({bool includeInactive = false});

  Future<Map<String, dynamic>?> getTransportRouteById(int id);

  Future<int> insertTransportRoute(Map<String, dynamic> data);

  Future<int> updateTransportRoute(int id, Map<String, dynamic> data);

  Future<int> deleteTransportRoute(int id);

  Future<int> countActiveAllocationsForRoute(int routeId);

  Future<Map<String, dynamic>?> getStudentTransportAllocation(int studentId, String term, String session);

  Future<List<Map<String, dynamic>>> getRouteAllocationsWithDetails(String term, String session);

  Future<int> allocateStudentToRoute({
    required int studentId,
    required int routeId,
    required String term,
    required String session,
  });

  Future<int> removeStudentFromRoute(int studentId, String term, String session);

  // ========================================
  // DATABASE MANAGEMENT
  // ========================================

  /// Close database connection and reset
  Future<void> closeAndReset();

  /// Close database connection
  Future<void> close();
}
