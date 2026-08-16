// lib/db/database_helper.dart
import 'dart:async';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';
import '../utils/password_helper.dart';
import '../utils/admission_settings_helper.dart';

/// Thrown when adding a student would exceed the active license's
/// maxStudents cap.
class StudentLimitExceededException implements Exception {
  final int currentCount;
  final int maxStudents;

  StudentLimitExceededException({
    required this.currentCount,
    required this.maxStudents,
  });

  String get message =>
      'Student limit reached: your license allows a maximum of '
      '$maxStudents active students (currently $currentCount). '
      'Please contact support to upgrade your license.';

  @override
  String toString() => message;
}

class DatabaseHelper {
  // Singleton
  static final DatabaseHelper _instance = DatabaseHelper._internal();
  factory DatabaseHelper() => _instance;
  DatabaseHelper._internal();

  static Database? _database;
  // bumped DB version to add deactivation columns + users table + license table + permissions table
  // v10: Expanded permission modules from 16 to 27 for granular page-level control
  // v11: Added payments_edit module for editing recorded payments
  // v12: Implemented bcrypt password hashing for enhanced security
  // v13: Added expenses table for expense tracking
  // v14: Updated default user accounts (developeradmin, superadmin, admin, bursar)
  // v15: Separated daily_print_count from thermal_printer, added thermal_printer to bursar
  // v16: Added Sales Management tables (stock_items, sales, stock_movements)
  // v17: Added credit/part payment support to sales (paymentStatus, amountPaid, outstandingBalance)
  // v18: Added sales_debtors table for dedicated debt tracking
  // v19: Added parents table for parent management
  // v20: Added parent-child hierarchy for stock items (parentItemId, isParent fields)
  // v21: Added suppliers table for supplier management
  // v22: Added dateOfAdmission field to students table
  // v23: Added Staff Management tables (staff, staff_offices, staff_class_allocations, staff_office_allocations)
  // v24: Added Next of Kin fields to staff table
  // v25: Added bank details to staff, staff_incentives, staff_loans, staff_deductions tables
  // v26: Added staff_salary_payments table for tracking staff payment status
  // v27: Added collectionDate field to staff_loans table
  // v28: Added nationality, stateOfOrigin, lga fields to students table
  // v29: Added special_fee_items and special_class_fees tables for new intake bills
  // v30: Added excluded_default_fees table to exclude default fees from new intake bills
  // v31: Added parentId column to special_fee_items for category hierarchy
  // v32: Added isCategory column to special_fee_items to distinguish categories from standalone items
  // v33: Added armId column to class_fees and special_class_fees for arm-specific fee assignments
  // v34: Added custom item support to sales (itemName, isCustomItem columns, nullable stockItemId)
  // v35: Added Continuous Assessment Portal tables (school_divisions, subjects, activities, exams, grading, scores, psychomotor, affective, result_computations)
  // v36: Added bank account fields to school_profile (3 bank accounts: bankName1/2/3, accountNumber1/2/3, accountName1/2/3)
  // v37: Added fee_priority table for payment allocation ordering (Fee Tracker feature)
  // v38: Added staff_salary_history table for tracking salary increments per month
  // v39: Added expense_categories table for managing expense categories
  // v40: Guard — ensure sales.itemName / isCustomItem exist on every device
  // v41: Added external_examinations and examination_registrations tables
  // v42: Added snapshot columns to examination_registrations (preserve data when student deleted/deactivated)
  // v43: Added session column to examination_registrations; UNIQUE now (examinationId, studentId, session)
  // v45: Added paymentFor column to payments table
  // v46: Migrated daily print counters from SharedPreferences into print_counters table
  // v47: Added lastKnownDate column to licenses table (clock rollback detection)
  // v48: Added payroll basis support (Full/Percentage/Working Days/Working Weeks
  //      pro-rated salary) — payroll_month_settings table + basis columns on
  //      staff_salary_payments for per-staff overrides
  // v49: Added salary_expense_postings table to track how much of a month's
  //      paid salary has already been posted to Expenses (prevents
  //      accidental duplicate posting; detects top-up amounts when staff are
  //      marked paid after an earlier post)
  // v50: Added deactivationDate column to staff table — lets admins back-date
  //      a deactivation so the staff stops appearing in payroll/payment
  //      records for months after that date, without losing prior history
  // v55: Added paymentMethod column to staff_loans table (Cash/Transfer/POS),
  //      so a loan's disbursement method carries through to its linked
  //      Expense record instead of always being hardcoded to Cash
  // v56: Added audit_log table for financial audit trail (tracks create/
  //      update/delete on payments — who, when, what changed) + audit_log_view
  //      permission module
  // v57: Added staffId column to audit_log — same role as studentId but for
  //      staff financial records (loans, deductions, incentives, salary
  //      payments/increments)
  // v59: Added reports_fees_balance permission module for the School Fees
  //      Balance Report (students who have fully cleared their fees, with
  //      term-over-term and session-over-session comparison)
  // v60: Added Transportation feature — transport_routes and
  //      student_transport_allocations tables, wired to student_bills /
  //      student_fee_breakdown so assigning/removing a route automatically
  //      adds/removes a "Transportation" line on the student's bill for the
  //      active term/session. Added transportation_manage and
  //      transportation_allocate permission modules.
  static const int _dbVersion = 60;
  static const String _dbName = 'bursary_manager.db';
  static const String _kActiveTerm = 'activeTerm';

  // Permission modules - Comprehensive list covering all app screens (30 modules)
  static const List<String> PERMISSION_MODULES = [
    'dashboard',
    'session_term',
    'students_view',           // View student list and details
    'students_add',            // Register new students
    'students_edit',           // Edit student information
    'students_batch_upload',   // Batch upload students
    'students_promote',        // Promote students to next class
    'students_deactivate',     // Deactivate students
    'students_inactive',       // View inactive students
    'students_statement',      // View student account statement
    'classes_arms',            // View/manage classes and arms
    'fee_items_view',          // View fee items
    'fee_items_manage',        // Add/edit fee items
    'fee_class_assignment',    // Assign fees to classes
    'billing_generate',        // Generate student bills
    'billing_print',           // Print bills
    'payments_record',         // Record payments
    'payments_edit',           // Edit recorded payments
    'payments_receipt',        // Print payment receipts
    'payments_history',        // View payment history
    'reports_daily',           // Daily financial reports
    'reports_debtors',         // Debtors list report
    'reports_termly',          // Termly financial report
    'reports_overpayment',     // Overpayment tracker report
    'reports_fees_balance',    // School fees balance report
    'expenses',                // Track and manage expenses
    'school_profile',          // View/edit school profile
    'license_management',      // Manage license
    'thermal_printer',         // Thermal printer connection (bursar and admin)
    'daily_print_count',       // Daily print counter (admin only)
    'server_hosting',          // Server/hosting management
    'backup',                  // Backup and restore
    'data_management',         // Data clearing tools
    'user_management',         // User management (super_admin only - always restricted)
    'stock_manage',            // Manage stock items and inventory
    'sales_record',            // Record sales transactions
    'sales_report',            // View sales reports and analytics
    'staff_view',              // View staff list and details
    'staff_add',               // Register new staff
    'staff_edit',              // Edit staff information
    'staff_offices',           // Manage staff offices
    'staff_class_allocation',  // Allocate teachers to classes
    'staff_office_allocation', // Allocate staff to offices
    'staff_salary',            // Manage staff salaries
    'staff_listing',           // View staff table listing
    'staff_incentive',         // Manage staff incentives/grants
    'staff_loan',              // Manage staff loans
    'staff_deduction',         // Manage staff deductions/penalties
    'staff_payroll',           // View staff payroll/salary details
    'fee_tracker',             // Fee tracker - priority, tracking, progression
    'external_examinations',   // External examination management and registration
    'audit_log_view',          // View financial activity/audit log
    'transportation_manage',   // Manage transport routes and fares
    'transportation_allocate', // Allocate/remove students from transport routes
  ];

  // ------------------------------------------------------------------
  // Database getter / init
  // ------------------------------------------------------------------
  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDb();
    return _database!;
  }

  Future<Database> _initDb() async {
    final dbPath = await getDatabasesPath();
    final fullPath = join(dbPath, _dbName);

    return await openDatabase(
      fullPath,
      version: _dbVersion,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  // Close and reset database (for restore operations)
  Future<void> closeAndReset() async {
    if (_database != null) {
      await _database!.close();
      _database = null;
    }
  }

  // ------------------------------------------------------------------
  // onCreate
  // ------------------------------------------------------------------
  Future _onCreate(Database db, int version) async {
    // STUDENTS (note isActive + leftDate + leftReason)
    await db.execute('''
      CREATE TABLE students (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        admissionNo TEXT NOT NULL,
        surname TEXT NOT NULL,
        firstName TEXT NOT NULL,
        otherName TEXT,
        gender TEXT NOT NULL,
        dob TEXT NOT NULL,
        classId INTEGER NOT NULL,
        armId INTEGER NOT NULL,
        address TEXT NOT NULL,
        nationality TEXT,
        stateOfOrigin TEXT,
        lga TEXT,
        parentName TEXT NOT NULL,
        parentPhone TEXT NOT NULL,
        parentEmail TEXT,
        parentAddress TEXT,
        photoPath TEXT,
        isActive INTEGER NOT NULL DEFAULT 1,
        leftDate TEXT,
        leftReason TEXT,
        dateOfAdmission TEXT
      )
    ''');

    // CLASSES
    await db.execute('''
      CREATE TABLE classes (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL
      )
    ''');

    // ARMS
    await db.execute('''
      CREATE TABLE arms (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        classId INTEGER NOT NULL,
        name TEXT NOT NULL
      )
    ''');

    // FEE ITEMS
    await db.execute('''
      CREATE TABLE fee_items (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        defaultAmount REAL NOT NULL,
        description TEXT,
        term TEXT,
        session TEXT
      )
    ''');

    // CLASS–FEE ASSIGNMENTS
    await db.execute('''
      CREATE TABLE class_fees (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        classId INTEGER NOT NULL,
        armId INTEGER,
        feeItemId INTEGER NOT NULL,
        amount REAL NOT NULL,
        term TEXT NOT NULL,
        session TEXT NOT NULL
      )
    ''');

    // SPECIAL FEE ITEMS (for new intake students)
    await db.execute('''
      CREATE TABLE special_fee_items (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        defaultAmount REAL NOT NULL,
        description TEXT,
        term TEXT,
        session TEXT,
        createdAt TEXT NOT NULL,
        parentId INTEGER,
        isCategory INTEGER DEFAULT 0,
        FOREIGN KEY (parentId) REFERENCES special_fee_items(id) ON DELETE CASCADE
      )
    ''');

    // SPECIAL CLASS FEES (special fee assignments for new intake)
    await db.execute('''
      CREATE TABLE special_class_fees (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        classId INTEGER NOT NULL,
        armId INTEGER,
        specialFeeItemId INTEGER NOT NULL,
        amount REAL NOT NULL,
        term TEXT NOT NULL,
        session TEXT NOT NULL
      )
    ''');

    // EXCLUDED DEFAULT FEES (fees to exclude from new intake bills)
    await db.execute('''
      CREATE TABLE excluded_default_fees (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        classId INTEGER NOT NULL,
        classFeeId INTEGER NOT NULL,
        term TEXT NOT NULL,
        session TEXT NOT NULL,
        UNIQUE(classId, classFeeId, term, session)
      )
    ''');

    // PRINT COUNTERS (daily thermal printer usage statistics)
    await db.execute('''
      CREATE TABLE print_counters (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        date TEXT NOT NULL UNIQUE,
        bills INTEGER NOT NULL DEFAULT 0,
        receipts INTEGER NOT NULL DEFAULT 0,
        paymentHistory INTEGER NOT NULL DEFAULT 0,
        receiptReprint INTEGER NOT NULL DEFAULT 0
      )
    ''');

    // FEE PRIORITY (payment allocation order for Fee Tracker)
    await db.execute('''
      CREATE TABLE fee_priority (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        scope TEXT NOT NULL DEFAULT 'global',
        classId INTEGER,
        armId INTEGER,
        feeItemId INTEGER NOT NULL,
        priority INTEGER NOT NULL,
        term TEXT NOT NULL,
        session TEXT NOT NULL,
        UNIQUE(scope, classId, armId, feeItemId, term, session)
      )
    ''');

    // EXTERNAL EXAMINATIONS
    await db.execute('''
      CREATE TABLE external_examinations (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        code TEXT NOT NULL,
        isDefault INTEGER NOT NULL DEFAULT 0,
        isActive INTEGER NOT NULL DEFAULT 1,
        createdAt TEXT NOT NULL
      )
    ''');

    // EXAMINATION REGISTRATIONS
    await db.execute('''
      CREATE TABLE examination_registrations (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        examinationId INTEGER NOT NULL,
        studentId INTEGER,
        registrationDate TEXT NOT NULL,
        createdAt TEXT NOT NULL,
        session TEXT NOT NULL DEFAULT '',
        snapshotName TEXT,
        snapshotAdmNo TEXT,
        snapshotGender TEXT,
        snapshotClass TEXT,
        snapshotArm TEXT,
        FOREIGN KEY (examinationId) REFERENCES external_examinations(id) ON DELETE CASCADE,
        FOREIGN KEY (studentId) REFERENCES students(id) ON DELETE SET NULL,
        UNIQUE(examinationId, studentId, session)
      )
    ''');

    // SESSIONS
    await db.execute('''
      CREATE TABLE sessions (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        sessionName TEXT NOT NULL,
        isActive INTEGER NOT NULL DEFAULT 0
      )
    ''');

    // STUDENT BILLS
    await db.execute('''
      CREATE TABLE student_bills (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        studentId INTEGER NOT NULL,
        totalAmount REAL NOT NULL,
        previousBalance REAL NOT NULL DEFAULT 0,
        term TEXT,
        session TEXT,
        billDate TEXT NOT NULL
      )
    ''');

    // FEE BREAKDOWN
    await db.execute('''
      CREATE TABLE student_fee_breakdown (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        billId INTEGER NOT NULL,
        feeItemId INTEGER NOT NULL,
        amount REAL NOT NULL,
        label TEXT
      )
    ''');

    // TRANSPORTATION
    await db.execute('''
      CREATE TABLE IF NOT EXISTS transport_routes (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        description TEXT,
        fare REAL NOT NULL DEFAULT 0,
        isActive INTEGER NOT NULL DEFAULT 1,
        createdAt TEXT,
        updatedAt TEXT
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS student_transport_allocations (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        studentId INTEGER NOT NULL,
        routeId INTEGER NOT NULL,
        billId INTEGER NOT NULL,
        fareCharged REAL NOT NULL DEFAULT 0,
        term TEXT NOT NULL,
        session TEXT NOT NULL,
        createdAt TEXT,
        UNIQUE(studentId, term, session),
        FOREIGN KEY (studentId) REFERENCES students(id) ON DELETE CASCADE,
        FOREIGN KEY (routeId) REFERENCES transport_routes(id) ON DELETE CASCADE
      )
    ''');

    // PAYMENTS
    await db.execute('''
      CREATE TABLE payments (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        studentId INTEGER NOT NULL,
        amount REAL NOT NULL,
        method TEXT NOT NULL,
        note TEXT,
        paymentDate TEXT NOT NULL,
        term TEXT,
        session TEXT,
        paymentFor TEXT DEFAULT 'Tuition Fee'
      )
    ''');

    // AUDIT LOG - tracks create/update/delete on financial records (starting
    // with payments) so edits and deletions are never silent
    await db.execute('''
      CREATE TABLE audit_log (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        entityType TEXT NOT NULL,
        entityId INTEGER NOT NULL,
        action TEXT NOT NULL,
        studentId INTEGER,
        staffId INTEGER,
        amount REAL,
        changes TEXT,
        userId INTEGER,
        username TEXT,
        timestamp TEXT NOT NULL
      )
    ''');

    // SCHOOL PROFILE
    await db.execute('''
      CREATE TABLE school_profile (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        motto TEXT,
        address TEXT,
        phone TEXT,
        email TEXT,
        logoPath TEXT,
        shortName TEXT,
        bankName1 TEXT,
        accountNumber1 TEXT,
        accountName1 TEXT,
        bankName2 TEXT,
        accountNumber2 TEXT,
        accountName2 TEXT,
        bankName3 TEXT,
        accountNumber3 TEXT,
        accountName3 TEXT
      )
    ''');

    // SETTINGS
    await db.execute('''
      CREATE TABLE settings (
        key TEXT PRIMARY KEY,
        value TEXT
      )
    ''');

    // SMS LOG - audit trail of SMS notifications sent to parents
    await db.execute('''
      CREATE TABLE sms_log (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        studentId INTEGER,
        phone TEXT NOT NULL,
        message TEXT NOT NULL,
        context TEXT,
        status TEXT NOT NULL,
        errorMessage TEXT,
        sentAt TEXT NOT NULL
      )
    ''');

    // USERS TABLE (NEW FOR AUTHENTICATION)
    await db.execute('''
      CREATE TABLE users (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        username TEXT NOT NULL UNIQUE,
        password TEXT NOT NULL,
        userType TEXT NOT NULL,
        canChangeCredentials INTEGER NOT NULL DEFAULT 0,
        createdAt TEXT NOT NULL
      )
    ''');

    // PROMOTION HISTORY TABLE (NEW FOR STUDENT PROMOTION)
    await db.execute('''
      CREATE TABLE promotion_history (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        studentId INTEGER NOT NULL,
        fromClassId INTEGER,
        fromArmId INTEGER,
        toClassId INTEGER NOT NULL,
        toArmId INTEGER,
        promotionDate TEXT NOT NULL,
        FOREIGN KEY (studentId) REFERENCES students (id),
        FOREIGN KEY (fromClassId) REFERENCES classes (id),
        FOREIGN KEY (fromArmId) REFERENCES arms (id),
        FOREIGN KEY (toClassId) REFERENCES classes (id),
        FOREIGN KEY (toArmId) REFERENCES arms (id)
      )
    ''');

    // LICENSE TABLE (NEW FOR APP LICENSING)
    await db.execute('''
      CREATE TABLE licenses (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        licenseKey TEXT NOT NULL UNIQUE,
        schoolName TEXT NOT NULL,
        schoolCode TEXT,
        deviceId TEXT,
        activationDate TEXT NOT NULL,
        expiryDate TEXT NOT NULL,
        maxStudents INTEGER DEFAULT 0,
        isActive INTEGER NOT NULL DEFAULT 1,
        createdAt TEXT NOT NULL,
        lastKnownDate TEXT
      )
    ''');

    // PERMISSIONS TABLE (NEW FOR ROLE-BASED ACCESS CONTROL)
    await db.execute('''
      CREATE TABLE permissions (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        role TEXT NOT NULL,
        module TEXT NOT NULL,
        canAccess INTEGER NOT NULL DEFAULT 1,
        UNIQUE(role, module)
      )
    ''');

    // EXPENSES TABLE
    await db.execute('''
      CREATE TABLE expenses (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        amount REAL NOT NULL,
        category TEXT NOT NULL,
        customCategory TEXT,
        description TEXT NOT NULL,
        expenseDate TEXT NOT NULL,
        paymentMethod TEXT NOT NULL,
        recipient TEXT NOT NULL,
        term TEXT,
        session TEXT,
        createdAt TEXT NOT NULL,
        createdBy TEXT
      )
    ''');

    // EXPENSE CATEGORIES TABLE
    await db.execute('''
      CREATE TABLE expense_categories (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL UNIQUE,
        isPreset INTEGER NOT NULL DEFAULT 0,
        createdAt TEXT NOT NULL
      )
    ''');

    // Seed default expense categories
    final now = DateTime.now().toIso8601String();
    for (final cat in [
      'Staff Loan',
      'Paid Salary',
      'Utilities',
      'Maintenance & Repairs',
      'Office Supplies',
      'Other',
    ]) {
      await db.insert('expense_categories', {
        'name': cat,
        'isPreset': 1,
        'createdAt': now,
      });
    }

    // STOCK ITEMS TABLE
    await db.execute('''
      CREATE TABLE stock_items (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        itemName TEXT NOT NULL,
        itemDescription TEXT,
        supplierName TEXT,
        supplierContact TEXT,
        currentQuantity INTEGER NOT NULL DEFAULT 0,
        costPrice REAL NOT NULL,
        sellingPrice REAL NOT NULL,
        reorderLevel INTEGER DEFAULT 0,
        parentItemId INTEGER DEFAULT NULL,
        isParent INTEGER NOT NULL DEFAULT 0,
        isActive INTEGER NOT NULL DEFAULT 1,
        createdAt TEXT NOT NULL,
        updatedAt TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_stock_items_parent
      ON stock_items(parentItemId)
    ''');

    // SUPPLIERS TABLE
    await db.execute('''
      CREATE TABLE suppliers (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        supplierName TEXT NOT NULL UNIQUE,
        contactPerson TEXT,
        phoneNumber TEXT,
        email TEXT,
        address TEXT,
        notes TEXT,
        isActive INTEGER NOT NULL DEFAULT 1,
        createdAt TEXT NOT NULL,
        updatedAt TEXT NOT NULL
      )
    ''');

    // SALES TABLE
    await db.execute('''
      CREATE TABLE sales (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        studentId INTEGER,
        buyerName TEXT NOT NULL,
        buyerType TEXT NOT NULL,
        stockItemId INTEGER NOT NULL,
        itemName TEXT,
        isCustomItem INTEGER DEFAULT 0,
        quantity INTEGER NOT NULL,
        unitPrice REAL NOT NULL,
        totalAmount REAL NOT NULL,
        paymentMethod TEXT NOT NULL,
        paymentStatus TEXT NOT NULL DEFAULT 'Paid',
        amountPaid REAL,
        outstandingBalance REAL,
        note TEXT,
        saleDate TEXT NOT NULL,
        term TEXT NOT NULL,
        session TEXT NOT NULL,
        createdBy TEXT,
        createdAt TEXT NOT NULL,
        FOREIGN KEY (stockItemId) REFERENCES stock_items (id)
      )
    ''');

    // STOCK MOVEMENTS TABLE
    await db.execute('''
      CREATE TABLE stock_movements (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        stockItemId INTEGER NOT NULL,
        movementType TEXT NOT NULL,
        quantity INTEGER NOT NULL,
        balanceAfter INTEGER NOT NULL,
        referenceType TEXT NOT NULL,
        referenceId INTEGER,
        note TEXT,
        movementDate TEXT NOT NULL,
        createdBy TEXT,
        FOREIGN KEY (stockItemId) REFERENCES stock_items (id)
      )
    ''');

    // SALES DEBTORS TABLE
    await db.execute('''
      CREATE TABLE sales_debtors (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        buyerName TEXT NOT NULL,
        buyerType TEXT NOT NULL,
        studentId INTEGER,
        totalAmount REAL NOT NULL DEFAULT 0.0,
        amountPaid REAL NOT NULL DEFAULT 0.0,
        outstandingBalance REAL NOT NULL DEFAULT 0.0,
        lastPaymentDate TEXT,
        term TEXT,
        session TEXT,
        createdAt TEXT NOT NULL,
        updatedAt TEXT NOT NULL,
        UNIQUE(buyerName, buyerType, term, session)
      )
    ''');

    // PARENTS TABLE
    await db.execute('''
      CREATE TABLE parents (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        parentName TEXT NOT NULL,
        phoneNumber TEXT NOT NULL,
        phoneNumber2 TEXT,
        homeAddress TEXT NOT NULL,
        occupation TEXT,
        officeAddress TEXT,
        emailAddress TEXT,
        createdAt TEXT NOT NULL,
        updatedAt TEXT NOT NULL
      )
    ''');

    // STAFF TABLE
    await db.execute('''
      CREATE TABLE staff (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        staffId TEXT UNIQUE NOT NULL,
        staffType TEXT NOT NULL,
        title TEXT,
        surname TEXT NOT NULL,
        firstName TEXT NOT NULL,
        otherName TEXT,
        gender TEXT NOT NULL,
        dateOfBirth TEXT,
        maritalStatus TEXT,
        stateOfOrigin TEXT,
        lga TEXT,
        nationality TEXT,
        religion TEXT,
        address TEXT,
        phone TEXT,
        phone2 TEXT,
        email TEXT,
        nextOfKinName TEXT,
        nextOfKinPhone TEXT,
        nextOfKinRelationship TEXT,
        nextOfKinAddress TEXT,
        academicInfo TEXT,
        jobExperience TEXT,
        skills TEXT,
        hobbies TEXT,
        referee1Name TEXT,
        referee1Phone TEXT,
        referee1Relationship TEXT,
        referee1Address TEXT,
        referee2Name TEXT,
        referee2Phone TEXT,
        referee2Relationship TEXT,
        referee2Address TEXT,
        dateOfEmployment TEXT,
        salary REAL DEFAULT 0,
        bankName TEXT,
        accountName TEXT,
        accountNumber TEXT,
        photoPath TEXT,
        isActive INTEGER DEFAULT 1,
        deactivationDate TEXT,
        createdAt TEXT,
        updatedAt TEXT
      )
    ''');

    // STAFF OFFICES TABLE
    await db.execute('''
      CREATE TABLE staff_offices (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL UNIQUE,
        description TEXT,
        createdAt TEXT
      )
    ''');

    // STAFF CLASS ALLOCATIONS TABLE
    await db.execute('''
      CREATE TABLE staff_class_allocations (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        staffId INTEGER NOT NULL,
        classId INTEGER NOT NULL,
        armId INTEGER NOT NULL,
        subjectsTaught TEXT,
        createdAt TEXT,
        FOREIGN KEY (staffId) REFERENCES staff(id),
        FOREIGN KEY (classId) REFERENCES classes(id),
        FOREIGN KEY (armId) REFERENCES arms(id)
      )
    ''');

    // STAFF OFFICE ALLOCATIONS TABLE
    await db.execute('''
      CREATE TABLE staff_office_allocations (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        staffId INTEGER NOT NULL,
        officeId INTEGER NOT NULL,
        createdAt TEXT,
        FOREIGN KEY (staffId) REFERENCES staff(id),
        FOREIGN KEY (officeId) REFERENCES staff_offices(id)
      )
    ''');

    // STAFF INCENTIVES TABLE
    await db.execute('''
      CREATE TABLE IF NOT EXISTS staff_incentives (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        staffId INTEGER NOT NULL,
        staffName TEXT NOT NULL,
        month TEXT NOT NULL,
        amount REAL NOT NULL,
        description TEXT,
        createdAt TEXT,
        FOREIGN KEY (staffId) REFERENCES staff(id)
      )
    ''');

    // STAFF LOANS TABLE
    await db.execute('''
      CREATE TABLE IF NOT EXISTS staff_loans (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        staffId INTEGER NOT NULL,
        staffName TEXT NOT NULL,
        month TEXT NOT NULL,
        amount REAL NOT NULL,
        deductionPerMonth REAL NOT NULL,
        monthsRemaining INTEGER DEFAULT 0,
        reason TEXT,
        status TEXT DEFAULT 'Active',
        collectionDate TEXT,
        createdAt TEXT,
        linkedExpenseId INTEGER,
        paymentMethod TEXT,
        FOREIGN KEY (staffId) REFERENCES staff(id)
      )
    ''');

    // STAFF DEDUCTIONS TABLE
    await db.execute('''
      CREATE TABLE IF NOT EXISTS staff_deductions (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        staffId INTEGER NOT NULL,
        staffName TEXT NOT NULL,
        month TEXT NOT NULL,
        amount REAL NOT NULL,
        reason TEXT NOT NULL,
        description TEXT,
        date TEXT NOT NULL,
        createdAt TEXT,
        FOREIGN KEY (staffId) REFERENCES staff(id)
      )
    ''');

    // STAFF SALARY PAYMENTS TABLE
    // basisType/percentageValue/totalUnits/workedUnits: per-staff pro-ration
    // override for this month (null = use the month-wide default in
    // payroll_month_settings, or Full Payment if no default is set either)
    await db.execute('''
      CREATE TABLE IF NOT EXISTS staff_salary_payments (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        staffId INTEGER NOT NULL,
        month TEXT NOT NULL,
        isPaid INTEGER DEFAULT 0,
        paymentDate TEXT,
        paymentMethod TEXT,
        notes TEXT,
        basisType TEXT,
        percentageValue REAL,
        totalUnits REAL,
        workedUnits REAL,
        loanDeductionsApplied TEXT,
        createdAt TEXT,
        updatedAt TEXT,
        FOREIGN KEY (staffId) REFERENCES staff(id),
        UNIQUE(staffId, month)
      )
    ''');

    // STAFF SALARY HISTORY TABLE (for tracking salary increments)
    await db.execute('''
      CREATE TABLE IF NOT EXISTS staff_salary_history (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        staffId INTEGER NOT NULL,
        salary REAL NOT NULL,
        effectiveMonth TEXT NOT NULL,
        reason TEXT,
        createdAt TEXT,
        FOREIGN KEY (staffId) REFERENCES staff(id)
      )
    ''');

    // PAYROLL MONTH SETTINGS TABLE
    // Month-wide default pro-ration basis (basisType: 'full' | 'percentage' |
    // 'days' | 'weeks'), used for staff who don't have a per-staff override
    // in staff_salary_payments. Lets a school pay by working days/weeks/
    // percentage for a month a term resumed partway through, defaulting to
    // Full Payment (100%).
    await db.execute('''
      CREATE TABLE IF NOT EXISTS payroll_month_settings (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        month TEXT NOT NULL UNIQUE,
        basisType TEXT NOT NULL DEFAULT 'full',
        percentageValue REAL,
        totalUnits REAL,
        workedUnits REAL,
        createdAt TEXT,
        updatedAt TEXT
      )
    ''');

    // SALARY EXPENSE POSTINGS TABLE
    // Tracks how much of a month's paid salary has already been posted to
    // Expenses (via the "Post to Expenses" button on the Salary Payment
    // Record screen), so the app can warn about duplicate posting and detect
    // top-up amounts when staff are marked paid after an earlier post.
    await db.execute('''
      CREATE TABLE IF NOT EXISTS salary_expense_postings (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        month TEXT NOT NULL,
        amount REAL NOT NULL,
        postedAt TEXT NOT NULL,
        postedBy TEXT
      )
    ''');

    // Continuous Assessment Portal tables
    await _createCATables(db);

    // Seed default data
    await db.insert('sessions', {'sessionName': '2025/2026', 'isActive': 1});
    await db.insert('settings', {'key': _kActiveTerm, 'value': '1st Term'});

    // Seed default users with hashed passwords

    // Developer - Fixed and uneditable (Superior to all roles)
    await db.insert('users', {
      'username': 'developer',
      'password': PasswordHelper.hashPassword('dev2024bursarymanager@master'),
      'userType': 'developer',
      'canChangeCredentials': 0,
      'createdAt': DateTime.now().toIso8601String(),
    });

    // Super Admin - Default account (editable)
    await db.insert('users', {
      'username': 'superadmin',
      'password': PasswordHelper.hashPassword('12345'),
      'userType': 'super_admin',
      'canChangeCredentials': 1,
      'createdAt': DateTime.now().toIso8601String(),
    });

    // Admin - Default account (editable)
    await db.insert('users', {
      'username': 'admin',
      'password': PasswordHelper.hashPassword('12345'),
      'userType': 'admin',
      'canChangeCredentials': 1,
      'createdAt': DateTime.now().toIso8601String(),
    });

    // Bursar - Default account (editable)
    await db.insert('users', {
      'username': 'bursar',
      'password': PasswordHelper.hashPassword('12345'),
      'userType': 'bursar',
      'canChangeCredentials': 1,
      'createdAt': DateTime.now().toIso8601String(),
    });

    // Seed default examinations
    await _seedDefaultExaminations(db);

    // Seed default permissions for roles
    await _seedDefaultPermissions(db);
  }

  // ------------------------------------------------------------------
  // onUpgrade
  // ------------------------------------------------------------------
  Future _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await _safeExec(db, "ALTER TABLE students ADD COLUMN photoPath TEXT");
    }

    if (oldVersion < 3) {
      await _safeExec(db, '''
        CREATE TABLE IF NOT EXISTS settings (
          key TEXT PRIMARY KEY,
          value TEXT
        )
      ''');
    }

    if (oldVersion < 4) {
      await _safeExec(db, "ALTER TABLE fee_items ADD COLUMN term TEXT");
      await _safeExec(db, "ALTER TABLE fee_items ADD COLUMN session TEXT");
      await _safeExec(db, "ALTER TABLE payments ADD COLUMN term TEXT");
      await _safeExec(db, "ALTER TABLE payments ADD COLUMN session TEXT");
    }

    // NEW in v5: student deactivation columns
    if (oldVersion < 5) {
      // add columns safely if they don't already exist
      await _safeExec(db, "ALTER TABLE students ADD COLUMN isActive INTEGER NOT NULL DEFAULT 1");
      await _safeExec(db, "ALTER TABLE students ADD COLUMN leftDate TEXT");
      await _safeExec(db, "ALTER TABLE students ADD COLUMN leftReason TEXT");
    }

    // NEW in v6: users table for authentication
    if (oldVersion < 6) {
      await _safeExec(db, '''
        CREATE TABLE IF NOT EXISTS users (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          username TEXT NOT NULL UNIQUE,
          password TEXT NOT NULL,
          userType TEXT NOT NULL,
          canChangeCredentials INTEGER NOT NULL DEFAULT 0,
          createdAt TEXT NOT NULL
        )
      ''');

      // Check if users exist, if not add them
      final userCount = await db.rawQuery('SELECT COUNT(*) as count FROM users');
      final count = (userCount.first['count'] as int?) ?? 0;

      if (count == 0) {
        // Developer - Fixed and uneditable (Superior to all roles)
        await db.insert('users', {
          'username': 'developer',
          'password': PasswordHelper.hashPassword('dev2024bursarymanager@master'),
          'userType': 'developer',
          'canChangeCredentials': 0,
          'createdAt': DateTime.now().toIso8601String(),
        });

        // Super Admin - Default account (editable)
        await db.insert('users', {
          'username': 'superadmin',
          'password': PasswordHelper.hashPassword('12345'),
          'userType': 'super_admin',
          'canChangeCredentials': 1,
          'createdAt': DateTime.now().toIso8601String(),
        });

        // Admin - Default account (editable)
        await db.insert('users', {
          'username': 'admin',
          'password': PasswordHelper.hashPassword('12345'),
          'userType': 'admin',
          'canChangeCredentials': 1,
          'createdAt': DateTime.now().toIso8601String(),
        });

        // Bursar - Default account (editable)
        await db.insert('users', {
          'username': 'bursar',
          'password': PasswordHelper.hashPassword('12345'),
          'userType': 'bursar',
          'canChangeCredentials': 1,
          'createdAt': DateTime.now().toIso8601String(),
        });
      }
    }

    // NEW in v7: promotion_history table for student promotion tracking
    if (oldVersion < 7) {
      await _safeExec(db, '''
        CREATE TABLE IF NOT EXISTS promotion_history (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          studentId INTEGER NOT NULL,
          fromClassId INTEGER,
          fromArmId INTEGER,
          toClassId INTEGER NOT NULL,
          toArmId INTEGER,
          promotionDate TEXT NOT NULL,
          FOREIGN KEY (studentId) REFERENCES students (id),
          FOREIGN KEY (fromClassId) REFERENCES classes (id),
          FOREIGN KEY (fromArmId) REFERENCES arms (id),
          FOREIGN KEY (toClassId) REFERENCES classes (id),
          FOREIGN KEY (toArmId) REFERENCES arms (id)
        )
      ''');
    }

    // NEW in v8: licenses table for app licensing
    if (oldVersion < 8) {
      await _safeExec(db, '''
        CREATE TABLE IF NOT EXISTS licenses (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          licenseKey TEXT NOT NULL UNIQUE,
          schoolName TEXT NOT NULL,
          schoolCode TEXT,
          deviceId TEXT,
          activationDate TEXT NOT NULL,
          expiryDate TEXT NOT NULL,
          maxStudents INTEGER DEFAULT 0,
          isActive INTEGER NOT NULL DEFAULT 1,
          createdAt TEXT NOT NULL
        )
      ''');
    }

    // NEW in v9: permissions table for role-based access control
    if (oldVersion < 9) {
      await _safeExec(db, '''
        CREATE TABLE IF NOT EXISTS permissions (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          role TEXT NOT NULL,
          module TEXT NOT NULL,
          canAccess INTEGER NOT NULL DEFAULT 1,
          UNIQUE(role, module)
        )
      ''');

      // Seed default permissions for existing roles
      await _seedDefaultPermissions(db);
    }

    // NEW in v10: Expanded permission modules from 16 to 27
    if (oldVersion < 10) {
      // Add new granular permission modules for admin and bursar roles
      // This migration adds new modules while preserving any custom permissions

      // New modules for admin role (default enabled)
      final newAdminModules = [
        'students_add',
        'students_edit',
        'students_batch_upload',
        'students_promote',
        'students_deactivate',
        'students_inactive',
        'students_statement',
        'fee_items_view',
        'fee_items_manage',
        'fee_class_assignment',
        'billing_generate',
        'billing_print',
        'payments_record',
        'payments_receipt',
        'payments_history',
        'data_management',
      ];

      for (var module in newAdminModules) {
        try {
          await db.insert('permissions', {
            'role': 'admin',
            'module': module,
            'canAccess': module == 'data_management' ? 0 : 1, // data_management off by default
          });
        } catch (_) {
          // Skip if already exists
        }
      }

      // New modules for bursar role (most disabled by default)
      final newBursarModules = [
        'students_statement',   // Enabled - needed for billing
        'billing_generate',     // Enabled - core bursar function
        'billing_print',        // Enabled - core bursar function
        'payments_record',      // Enabled - core bursar function
        'payments_receipt',     // Enabled - core bursar function
        'payments_history',     // Enabled - core bursar function
        'students_add',         // Disabled by default
        'students_edit',        // Disabled by default
        'students_batch_upload', // Disabled by default
        'students_promote',     // Disabled by default
        'students_deactivate',  // Disabled by default
        'students_inactive',    // Disabled by default
        'fee_items_view',       // Disabled by default
        'fee_items_manage',     // Disabled by default
        'fee_class_assignment', // Disabled by default
        'data_management',      // Disabled by default
      ];

      final bursarEnabledModules = {
        'students_statement',
        'billing_generate',
        'billing_print',
        'payments_record',
        'payments_receipt',
        'payments_history',
      };

      for (var module in newBursarModules) {
        try {
          await db.insert('permissions', {
            'role': 'bursar',
            'module': module,
            'canAccess': bursarEnabledModules.contains(module) ? 1 : 0,
          });
        } catch (_) {
          // Skip if already exists
        }
      }

      // Migrate old combined modules to new granular modules
      // If user had 'students_manage', enable all student management sub-modules
      final hadStudentsManage = await db.query(
        'permissions',
        where: 'module = ? AND canAccess = ?',
        whereArgs: ['students_manage', 1],
      );

      if (hadStudentsManage.isNotEmpty) {
        for (var perm in hadStudentsManage) {
          final role = perm['role'] as String;
          final studentModules = [
            'students_add',
            'students_edit',
            'students_batch_upload',
            'students_promote',
          ];
          for (var module in studentModules) {
            try {
              await db.update(
                'permissions',
                {'canAccess': 1},
                where: 'role = ? AND module = ?',
                whereArgs: [role, module],
              );
            } catch (_) {}
          }
        }
      }

      // If user had 'student_deactivation', enable deactivation sub-modules
      final hadStudentDeactivation = await db.query(
        'permissions',
        where: 'module = ? AND canAccess = ?',
        whereArgs: ['student_deactivation', 1],
      );

      if (hadStudentDeactivation.isNotEmpty) {
        for (var perm in hadStudentDeactivation) {
          final role = perm['role'] as String;
          final deactivationModules = ['students_deactivate', 'students_inactive'];
          for (var module in deactivationModules) {
            try {
              await db.update(
                'permissions',
                {'canAccess': 1},
                where: 'role = ? AND module = ?',
                whereArgs: [role, module],
              );
            } catch (_) {}
          }
        }
      }

      // If user had 'fee_items', enable fee_items_view and fee_items_manage
      final hadFeeItems = await db.query(
        'permissions',
        where: 'module = ? AND canAccess = ?',
        whereArgs: ['fee_items', 1],
      );

      if (hadFeeItems.isNotEmpty) {
        for (var perm in hadFeeItems) {
          final role = perm['role'] as String;
          final feeModules = ['fee_items_view', 'fee_items_manage', 'fee_class_assignment'];
          for (var module in feeModules) {
            try {
              await db.update(
                'permissions',
                {'canAccess': 1},
                where: 'role = ? AND module = ?',
                whereArgs: [role, module],
              );
            } catch (_) {}
          }
        }
      }

      // If user had 'billing', enable billing sub-modules
      final hadBilling = await db.query(
        'permissions',
        where: 'module = ? AND canAccess = ?',
        whereArgs: ['billing', 1],
      );

      if (hadBilling.isNotEmpty) {
        for (var perm in hadBilling) {
          final role = perm['role'] as String;
          final billingModules = ['billing_generate', 'billing_print'];
          for (var module in billingModules) {
            try {
              await db.update(
                'permissions',
                {'canAccess': 1},
                where: 'role = ? AND module = ?',
                whereArgs: [role, module],
              );
            } catch (_) {}
          }
        }
      }

      // If user had 'payments', enable payment sub-modules
      final hadPayments = await db.query(
        'permissions',
        where: 'module = ? AND canAccess = ?',
        whereArgs: ['payments', 1],
      );

      if (hadPayments.isNotEmpty) {
        for (var perm in hadPayments) {
          final role = perm['role'] as String;
          final paymentModules = ['payments_record', 'payments_receipt', 'payments_history'];
          for (var module in paymentModules) {
            try {
              await db.update(
                'permissions',
                {'canAccess': 1},
                where: 'role = ? AND module = ?',
                whereArgs: [role, module],
              );
            } catch (_) {}
          }
        }
      }

      // If user had 'backup', enable data_management (only for admin, not bursar)
      final hadBackup = await db.query(
        'permissions',
        where: 'module = ? AND canAccess = ? AND role = ?',
        whereArgs: ['backup', 1, 'admin'],
      );

      if (hadBackup.isNotEmpty) {
        try {
          await db.update(
            'permissions',
            {'canAccess': 0}, // Keep disabled by default even for admin
            where: 'role = ? AND module = ?',
            whereArgs: ['admin', 'data_management'],
          );
        } catch (_) {}
      }
    }

    // NEW in v11: Added payments_edit permission module
    if (oldVersion < 11) {
      // Add payments_edit permission for admin (enabled by default)
      try {
        await db.insert('permissions', {
          'role': 'admin',
          'module': 'payments_edit',
          'canAccess': 1,
        });
      } catch (_) {
        // Skip if already exists
      }

      // Add payments_edit permission for bursar (disabled by default)
      try {
        await db.insert('permissions', {
          'role': 'bursar',
          'module': 'payments_edit',
          'canAccess': 0,
        });
      } catch (_) {
        // Skip if already exists
      }
    }

    // v12: Hash existing plain text passwords
    if (oldVersion < 12) {
      print('🔐 Migrating passwords to bcrypt hashing...');

      // Get all users
      final users = await db.query('users');

      for (var user in users) {
        final userId = user['id'] as int;
        final password = user['password'] as String;

        // Check if password is already hashed
        if (!PasswordHelper.isPasswordHashed(password)) {
          // Hash the plain text password
          final hashedPassword = PasswordHelper.hashPassword(password);

          // Update user with hashed password
          await db.update(
            'users',
            {'password': hashedPassword},
            where: 'id = ?',
            whereArgs: [userId],
          );

          print('✅ Hashed password for user: ${user['username']}');
        }
      }

      print('🔐 Password migration complete');
    }

    // NEW in v13: expenses table for expense tracking
    if (oldVersion < 13) {
      print('💰 Adding expenses table...');

      await _safeExec(db, '''
        CREATE TABLE IF NOT EXISTS expenses (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          amount REAL NOT NULL,
          category TEXT NOT NULL,
          customCategory TEXT,
          description TEXT NOT NULL,
          expenseDate TEXT NOT NULL,
          paymentMethod TEXT NOT NULL,
          recipient TEXT NOT NULL,
          term TEXT,
          session TEXT,
          createdAt TEXT NOT NULL,
          createdBy TEXT
        )
      ''');

      // Add expenses permission for admin (enabled by default)
      try {
        await db.insert('permissions', {
          'role': 'admin',
          'module': 'expenses',
          'canAccess': 1,
        });
      } catch (_) {}

      // Add expenses permission for bursar (enabled by default)
      try {
        await db.insert('permissions', {
          'role': 'bursar',
          'module': 'expenses',
          'canAccess': 1,
        });
      } catch (_) {}

      print('✅ Expenses table and permissions added');
    }

    // NEW in v14: Update default user accounts
    if (oldVersion < 14) {
      print('👥 Updating default user accounts...');

      // Check for old developeradmin account and remove it
      final oldDevAdminExists = await db.query(
        'users',
        where: 'username = ?',
        whereArgs: ['developeradmin'],
      );

      if (oldDevAdminExists.isNotEmpty) {
        await db.delete(
          'users',
          where: 'username = ?',
          whereArgs: ['developeradmin'],
        );
        print('🗑️ Removed old developeradmin account');
      }

      // Add developer account if it doesn't exist
      final developerExists = await db.query(
        'users',
        where: 'username = ?',
        whereArgs: ['developer'],
      );

      if (developerExists.isEmpty) {
        await db.insert('users', {
          'username': 'developer',
          'password': PasswordHelper.hashPassword('dev2024bursarymanager@master'),
          'userType': 'developer',
          'canChangeCredentials': 0,
          'createdAt': DateTime.now().toIso8601String(),
        });
        print('✅ Developer account created');
      }

      // Add admin user if it doesn't exist
      final adminExists = await db.query(
        'users',
        where: 'username = ?',
        whereArgs: ['admin'],
      );

      if (adminExists.isEmpty) {
        await db.insert('users', {
          'username': 'admin',
          'password': PasswordHelper.hashPassword('12345'),
          'userType': 'admin',
          'canChangeCredentials': 1,
          'createdAt': DateTime.now().toIso8601String(),
        });
        print('✅ Admin account created');
      }

      // Update existing superadmin account
      final superadminExists = await db.query(
        'users',
        where: 'username = ?',
        whereArgs: ['superadmin'],
      );

      if (superadminExists.isNotEmpty) {
        await db.update(
          'users',
          {
            'password': PasswordHelper.hashPassword('12345'),
            'canChangeCredentials': 1,
          },
          where: 'username = ?',
          whereArgs: ['superadmin'],
        );
        print('✅ Superadmin account updated');
      }

      // Update existing bursar account
      final bursarExists = await db.query(
        'users',
        where: 'username = ?',
        whereArgs: ['bursar'],
      );

      if (bursarExists.isNotEmpty) {
        await db.update(
          'users',
          {
            'password': PasswordHelper.hashPassword('12345'),
          },
          where: 'username = ?',
          whereArgs: ['bursar'],
        );
        print('✅ Bursar account updated');
      }

      print('✅ User accounts migration complete');
    }

    // NEW in v15: Separate daily_print_count from thermal_printer
    if (oldVersion < 15) {
      print('🖨️ Updating thermal printer permissions...');

      // Add thermal_printer permission to bursar if it doesn't exist
      final bursarThermalExists = await db.query(
        'permissions',
        where: 'role = ? AND module = ?',
        whereArgs: ['bursar', 'thermal_printer'],
      );

      if (bursarThermalExists.isEmpty) {
        try {
          await db.insert('permissions', {
            'role': 'bursar',
            'module': 'thermal_printer',
            'canAccess': 1,
          });
          print('✅ Added thermal_printer permission to bursar');
        } catch (e) {
          print('⚠️ Error adding thermal_printer to bursar: $e');
        }
      }

      // Add daily_print_count permission to admin if it doesn't exist
      final adminDailyPrintExists = await db.query(
        'permissions',
        where: 'role = ? AND module = ?',
        whereArgs: ['admin', 'daily_print_count'],
      );

      if (adminDailyPrintExists.isEmpty) {
        try {
          await db.insert('permissions', {
            'role': 'admin',
            'module': 'daily_print_count',
            'canAccess': 1,
          });
          print('✅ Added daily_print_count permission to admin');
        } catch (e) {
          print('⚠️ Error adding daily_print_count to admin: $e');
        }
      }

      print('✅ Thermal printer permissions migration complete');
    }

    // NEW in v16: Sales Management tables
    if (oldVersion < 16) {
      print('🛒 Adding Sales Management tables...');

      // Stock Items table
      await _safeExec(db, '''
        CREATE TABLE IF NOT EXISTS stock_items (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          itemName TEXT NOT NULL,
          itemDescription TEXT,
          supplierName TEXT NOT NULL,
          supplierContact TEXT,
          currentQuantity INTEGER NOT NULL DEFAULT 0,
          costPrice REAL NOT NULL,
          sellingPrice REAL NOT NULL,
          reorderLevel INTEGER DEFAULT 0,
          isActive INTEGER NOT NULL DEFAULT 1,
          createdAt TEXT NOT NULL,
          updatedAt TEXT NOT NULL
        )
      ''');

      // Sales table
      await _safeExec(db, '''
        CREATE TABLE IF NOT EXISTS sales (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          studentId INTEGER,
          buyerName TEXT NOT NULL,
          buyerType TEXT NOT NULL,
          stockItemId INTEGER NOT NULL,
          quantity INTEGER NOT NULL,
          unitPrice REAL NOT NULL,
          totalAmount REAL NOT NULL,
          paymentMethod TEXT NOT NULL,
          paymentStatus TEXT NOT NULL DEFAULT 'Paid',
          amountPaid REAL,
          outstandingBalance REAL,
          note TEXT,
          saleDate TEXT NOT NULL,
          term TEXT NOT NULL,
          session TEXT NOT NULL,
          createdBy TEXT,
          createdAt TEXT NOT NULL,
          FOREIGN KEY (stockItemId) REFERENCES stock_items (id)
        )
      ''');

      // Stock Movements table (audit trail)
      await _safeExec(db, '''
        CREATE TABLE IF NOT EXISTS stock_movements (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          stockItemId INTEGER NOT NULL,
          movementType TEXT NOT NULL,
          quantity INTEGER NOT NULL,
          balanceAfter INTEGER NOT NULL,
          referenceType TEXT NOT NULL,
          referenceId INTEGER,
          note TEXT,
          movementDate TEXT NOT NULL,
          createdBy TEXT,
          FOREIGN KEY (stockItemId) REFERENCES stock_items (id)
        )
      ''');

      // Add sales permissions for admin (enabled by default)
      try {
        await db.insert('permissions', {
          'role': 'admin',
          'module': 'stock_manage',
          'canAccess': 1,
        });
        await db.insert('permissions', {
          'role': 'admin',
          'module': 'sales_record',
          'canAccess': 1,
        });
        await db.insert('permissions', {
          'role': 'admin',
          'module': 'sales_report',
          'canAccess': 1,
        });
      } catch (_) {}

      // Add sales permissions for bursar (enabled by default)
      try {
        await db.insert('permissions', {
          'role': 'bursar',
          'module': 'stock_manage',
          'canAccess': 1,
        });
        await db.insert('permissions', {
          'role': 'bursar',
          'module': 'sales_record',
          'canAccess': 1,
        });
        await db.insert('permissions', {
          'role': 'bursar',
          'module': 'sales_report',
          'canAccess': 1,
        });
      } catch (_) {}

      print('✅ Sales Management tables and permissions added');
    }

    // NEW in v17: Credit/part payment support for sales
    if (oldVersion < 17) {
      print('💳 Adding credit/part payment support to sales...');

      // Add new columns to sales table
      await _safeExec(db, "ALTER TABLE sales ADD COLUMN paymentStatus TEXT NOT NULL DEFAULT 'Paid'");
      await _safeExec(db, "ALTER TABLE sales ADD COLUMN amountPaid REAL");
      await _safeExec(db, "ALTER TABLE sales ADD COLUMN outstandingBalance REAL");

      // Update existing sales to have default values
      await _safeExec(db, '''
        UPDATE sales
        SET paymentStatus = 'Paid',
            amountPaid = totalAmount,
            outstandingBalance = 0
        WHERE paymentStatus IS NULL OR paymentStatus = ''
      ''');

      print('✅ Credit/part payment support added to sales');
    }

    // NEW in v18: Dedicated sales debtors table
    if (oldVersion < 18) {
      print('🗂️ Creating sales_debtors table for dedicated debt tracking...');

      // Create sales_debtors table
      await _safeExec(db, '''
        CREATE TABLE IF NOT EXISTS sales_debtors (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          buyerName TEXT NOT NULL,
          buyerType TEXT NOT NULL,
          studentId INTEGER,
          totalAmount REAL NOT NULL DEFAULT 0.0,
          amountPaid REAL NOT NULL DEFAULT 0.0,
          outstandingBalance REAL NOT NULL DEFAULT 0.0,
          lastPaymentDate TEXT,
          term TEXT,
          session TEXT,
          createdAt TEXT NOT NULL,
          updatedAt TEXT NOT NULL,
          UNIQUE(buyerName, buyerType, term, session)
        )
      ''');

      // Migrate existing debtors from sales table
      print('📦 Migrating existing debtors to new table...');

      final sales = await db.rawQuery('''
        SELECT
          buyerName,
          buyerType,
          studentId,
          term,
          session,
          SUM(totalAmount) as totalAmount,
          SUM(COALESCE(amountPaid, 0)) as amountPaid,
          SUM(COALESCE(outstandingBalance, 0)) as outstandingBalance
        FROM sales
        WHERE COALESCE(outstandingBalance, 0) > 0
        GROUP BY buyerName, buyerType, term, session
      ''');

      final now = DateTime.now().toIso8601String();

      for (final debtor in sales) {
        if ((debtor['outstandingBalance'] as num) > 0) {
          await db.insert('sales_debtors', {
            'buyerName': debtor['buyerName'],
            'buyerType': debtor['buyerType'],
            'studentId': debtor['studentId'],
            'totalAmount': debtor['totalAmount'],
            'amountPaid': debtor['amountPaid'],
            'outstandingBalance': debtor['outstandingBalance'],
            'term': debtor['term'],
            'session': debtor['session'],
            'createdAt': now,
            'updatedAt': now,
          });
        }
      }

      print('✅ Sales debtors table created and migrated (${sales.length} debtors)');
    }

    // NEW in v19: Parents table for parent management
    if (oldVersion < 19) {
      print('👨‍👩‍👧‍👦 Creating parents table for parent management...');

      await _safeExec(db, '''
        CREATE TABLE IF NOT EXISTS parents (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          parentName TEXT NOT NULL,
          phoneNumber TEXT NOT NULL,
          phoneNumber2 TEXT,
          homeAddress TEXT NOT NULL,
          occupation TEXT,
          officeAddress TEXT,
          emailAddress TEXT,
          createdAt TEXT NOT NULL,
          updatedAt TEXT NOT NULL
        )
      ''');

      print('✅ Parents table created successfully');

      // Migrate existing parent data from students table
      print('📦 Migrating existing parent data from students table...');
      await _migrateParentDataFromStudents(db);
    }

    // NEW in v20: Parent-Child hierarchy for stock items + Schema migration
    if (oldVersion < 20) {
      print('🏗️ Migrating stock_items table to new schema...');

      // Check if old schema exists by checking for 'description' column
      final tableInfo = await db.rawQuery('PRAGMA table_info(stock_items)');
      final hasOldSchema = tableInfo.any((col) => col['name'] == 'description');

      if (hasOldSchema) {
        print('📦 Old schema detected - migrating to new schema...');

        // Create new table with correct schema
        await _safeExec(db, '''
          CREATE TABLE stock_items_new (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            itemName TEXT NOT NULL,
            itemDescription TEXT,
            supplierName TEXT NOT NULL,
            supplierContact TEXT,
            currentQuantity INTEGER NOT NULL DEFAULT 0,
            costPrice REAL NOT NULL,
            sellingPrice REAL NOT NULL,
            reorderLevel INTEGER DEFAULT 0,
            parentItemId INTEGER DEFAULT NULL,
            isParent INTEGER NOT NULL DEFAULT 0,
            isActive INTEGER NOT NULL DEFAULT 1,
            createdAt TEXT NOT NULL,
            updatedAt TEXT NOT NULL
          )
        ''');

        // Migrate data from old table to new table
        await _safeExec(db, '''
          INSERT INTO stock_items_new (
            id, itemName, itemDescription, supplierName, supplierContact,
            currentQuantity, costPrice, sellingPrice, reorderLevel,
            isActive, createdAt, updatedAt
          )
          SELECT
            id, itemName, description, supplier, '',
            currentQuantity, costPrice, sellingPrice, reorderLevel,
            isActive, createdAt, updatedAt
          FROM stock_items
        ''');

        // Drop old table
        await _safeExec(db, 'DROP TABLE stock_items');

        // Rename new table to stock_items
        await _safeExec(db, 'ALTER TABLE stock_items_new RENAME TO stock_items');

        print('✅ Schema migrated successfully');
      } else {
        print('📦 New schema detected - adding parent-child columns...');

        // Add parentItemId column if it doesn't exist
        try {
          await _safeExec(db, '''
            ALTER TABLE stock_items
            ADD COLUMN parentItemId INTEGER DEFAULT NULL
          ''');
        } catch (e) {
          print('⚠️ parentItemId column may already exist: $e');
        }

        // Add isParent flag if it doesn't exist
        try {
          await _safeExec(db, '''
            ALTER TABLE stock_items
            ADD COLUMN isParent INTEGER NOT NULL DEFAULT 0
          ''');
        } catch (e) {
          print('⚠️ isParent column may already exist: $e');
        }
      }

      // Create index for faster parent lookups
      await _safeExec(db, '''
        CREATE INDEX IF NOT EXISTS idx_stock_items_parent
        ON stock_items(parentItemId)
      ''');

      print('✅ Parent-child hierarchy added successfully');
    }

    // V21: Add suppliers table
    if (oldVersion < 21) {
      print('🏢 Adding suppliers table...');

      await _safeExec(db, '''
        CREATE TABLE IF NOT EXISTS suppliers (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          supplierName TEXT NOT NULL UNIQUE,
          contactPerson TEXT,
          phoneNumber TEXT,
          email TEXT,
          address TEXT,
          notes TEXT,
          isActive INTEGER NOT NULL DEFAULT 1,
          createdAt TEXT NOT NULL,
          updatedAt TEXT NOT NULL
        )
      ''');

      print('✅ Suppliers table created successfully');
    }

    // NEW in v22: Add dateOfAdmission field to students table
    if (oldVersion < 22) {
      print('📅 Adding dateOfAdmission field to students table...');
      await _safeExec(db, "ALTER TABLE students ADD COLUMN dateOfAdmission TEXT");
      print('✅ dateOfAdmission field added successfully');
    }

    // NEW in v23: Staff Management tables
    if (oldVersion < 23) {
      print('👥 Adding Staff Management tables...');

      // STAFF TABLE
      await _safeExec(db, '''
        CREATE TABLE IF NOT EXISTS staff (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          staffId TEXT UNIQUE NOT NULL,
          staffType TEXT NOT NULL,
          surname TEXT NOT NULL,
          firstName TEXT NOT NULL,
          otherName TEXT,
          gender TEXT NOT NULL,
          dateOfBirth TEXT,
          maritalStatus TEXT,
          stateOfOrigin TEXT,
          lga TEXT,
          nationality TEXT,
          religion TEXT,
          address TEXT,
          phone TEXT,
          phone2 TEXT,
          email TEXT,
          academicInfo TEXT,
          jobExperience TEXT,
          skills TEXT,
          hobbies TEXT,
          referee1Name TEXT,
          referee1Phone TEXT,
          referee1Relationship TEXT,
          referee1Address TEXT,
          referee2Name TEXT,
          referee2Phone TEXT,
          referee2Relationship TEXT,
          referee2Address TEXT,
          dateOfEmployment TEXT,
          salary REAL DEFAULT 0,
          bankName TEXT,
          accountName TEXT,
          accountNumber TEXT,
          photoPath TEXT,
          isActive INTEGER DEFAULT 1,
          createdAt TEXT,
          updatedAt TEXT
        )
      ''');

      // STAFF INCENTIVES TABLE
      await _safeExec(db, '''
        CREATE TABLE IF NOT EXISTS staff_incentives (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          staffId INTEGER NOT NULL,
          staffName TEXT NOT NULL,
          month TEXT NOT NULL,
          amount REAL NOT NULL,
          description TEXT,
          createdAt TEXT,
          FOREIGN KEY (staffId) REFERENCES staff(id)
        )
      ''');

      // STAFF LOANS TABLE
      await _safeExec(db, '''
        CREATE TABLE IF NOT EXISTS staff_loans (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          staffId INTEGER NOT NULL,
          staffName TEXT NOT NULL,
          month TEXT NOT NULL,
          amount REAL NOT NULL,
          deductionPerMonth REAL NOT NULL,
          monthsRemaining INTEGER DEFAULT 0,
          reason TEXT,
          status TEXT DEFAULT 'Active',
          collectionDate TEXT,
          createdAt TEXT,
          FOREIGN KEY (staffId) REFERENCES staff(id)
        )
      ''');

      // STAFF DEDUCTIONS TABLE
      await _safeExec(db, '''
        CREATE TABLE IF NOT EXISTS staff_deductions (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          staffId INTEGER NOT NULL,
          staffName TEXT NOT NULL,
          month TEXT NOT NULL,
          amount REAL NOT NULL,
          reason TEXT NOT NULL,
          description TEXT,
          date TEXT NOT NULL,
          createdAt TEXT,
          FOREIGN KEY (staffId) REFERENCES staff(id)
        )
      ''');

      // STAFF OFFICES TABLE
      await _safeExec(db, '''
        CREATE TABLE IF NOT EXISTS staff_offices (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          name TEXT NOT NULL UNIQUE,
          description TEXT,
          createdAt TEXT
        )
      ''');

      // STAFF CLASS ALLOCATIONS TABLE
      await _safeExec(db, '''
        CREATE TABLE IF NOT EXISTS staff_class_allocations (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          staffId INTEGER NOT NULL,
          classId INTEGER NOT NULL,
          armId INTEGER NOT NULL,
          subjectsTaught TEXT,
          createdAt TEXT,
          FOREIGN KEY (staffId) REFERENCES staff(id),
          FOREIGN KEY (classId) REFERENCES classes(id),
          FOREIGN KEY (armId) REFERENCES arms(id)
        )
      ''');

      // STAFF OFFICE ALLOCATIONS TABLE
      await _safeExec(db, '''
        CREATE TABLE IF NOT EXISTS staff_office_allocations (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          staffId INTEGER NOT NULL,
          officeId INTEGER NOT NULL,
          createdAt TEXT,
          FOREIGN KEY (staffId) REFERENCES staff(id),
          FOREIGN KEY (officeId) REFERENCES staff_offices(id)
        )
      ''');

      // Add staff permissions for admin (enabled by default)
      final staffModules = [
        'staff_view',
        'staff_add',
        'staff_edit',
        'staff_offices',
        'staff_class_allocation',
        'staff_office_allocation',
        'staff_salary',
        'staff_listing',
      ];

      for (var module in staffModules) {
        try {
          await db.insert('permissions', {
            'role': 'admin',
            'module': module,
            'canAccess': 1,
          });
        } catch (_) {}
      }

      // Add staff permissions for bursar (view and listing only by default)
      for (var module in staffModules) {
        try {
          await db.insert('permissions', {
            'role': 'bursar',
            'module': module,
            'canAccess': (module == 'staff_view' || module == 'staff_listing') ? 1 : 0,
          });
        } catch (_) {}
      }

      print('✅ Staff Management tables and permissions added');
    }

    // NEW in v24: Add Next of Kin fields to staff table
    if (oldVersion < 24) {
      print('👥 Adding Next of Kin fields to staff table...');
      await _safeExec(db, "ALTER TABLE staff ADD COLUMN nextOfKinName TEXT");
      await _safeExec(db, "ALTER TABLE staff ADD COLUMN nextOfKinPhone TEXT");
      await _safeExec(db, "ALTER TABLE staff ADD COLUMN nextOfKinRelationship TEXT");
      await _safeExec(db, "ALTER TABLE staff ADD COLUMN nextOfKinAddress TEXT");
      print('✅ Next of Kin fields added to staff table');
    }

    // NEW in v25: Add bank details and payroll tables
    if (oldVersion < 25) {
      print('💰 Adding bank details and payroll tables...');

      // Add bank columns to staff table
      await _safeExec(db, "ALTER TABLE staff ADD COLUMN bankName TEXT");
      await _safeExec(db, "ALTER TABLE staff ADD COLUMN accountName TEXT");
      await _safeExec(db, "ALTER TABLE staff ADD COLUMN accountNumber TEXT");

      // Create staff incentives table
      await _safeExec(db, '''
        CREATE TABLE IF NOT EXISTS staff_incentives (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          staffId INTEGER NOT NULL,
          staffName TEXT NOT NULL,
          month TEXT NOT NULL,
          amount REAL NOT NULL,
          description TEXT,
          createdAt TEXT,
          FOREIGN KEY (staffId) REFERENCES staff(id)
        )
      ''');

      // Create staff loans table
      await _safeExec(db, '''
        CREATE TABLE IF NOT EXISTS staff_loans (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          staffId INTEGER NOT NULL,
          staffName TEXT NOT NULL,
          month TEXT NOT NULL,
          amount REAL NOT NULL,
          deductionPerMonth REAL NOT NULL,
          monthsRemaining INTEGER DEFAULT 0,
          reason TEXT,
          status TEXT DEFAULT 'Active',
          collectionDate TEXT,
          createdAt TEXT,
          FOREIGN KEY (staffId) REFERENCES staff(id)
        )
      ''');

      // Create staff deductions table
      await _safeExec(db, '''
        CREATE TABLE IF NOT EXISTS staff_deductions (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          staffId INTEGER NOT NULL,
          staffName TEXT NOT NULL,
          month TEXT NOT NULL,
          amount REAL NOT NULL,
          reason TEXT NOT NULL,
          description TEXT,
          date TEXT NOT NULL,
          createdAt TEXT,
          FOREIGN KEY (staffId) REFERENCES staff(id)
        )
      ''');

      // Add new payroll permissions for admin
      final payrollModules = ['staff_incentive', 'staff_loan', 'staff_deduction', 'staff_payroll'];
      for (var module in payrollModules) {
        try {
          await db.insert('permissions', {'role': 'admin', 'module': module, 'canAccess': 1});
        } catch (_) {}
      }

      print('✅ Bank details and payroll tables added');
    }

    // NEW in v26: Add staff_salary_payments table
    if (oldVersion < 26) {
      print('💵 Adding staff_salary_payments table...');

      await _safeExec(db, '''
        CREATE TABLE IF NOT EXISTS staff_salary_payments (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          staffId INTEGER NOT NULL,
          month TEXT NOT NULL,
          isPaid INTEGER DEFAULT 0,
          paymentDate TEXT,
          paymentMethod TEXT,
          notes TEXT,
          createdAt TEXT,
          updatedAt TEXT,
          FOREIGN KEY (staffId) REFERENCES staff(id),
          UNIQUE(staffId, month)
        )
      ''');

      print('✅ staff_salary_payments table added');
    }

    // NEW in v27: Add collectionDate field to staff_loans table
    if (oldVersion < 27) {
      print('📅 Adding collectionDate field to staff_loans table...');
      await _safeExec(db, "ALTER TABLE staff_loans ADD COLUMN collectionDate TEXT");
      print('✅ collectionDate field added to staff_loans table');
    }

    // NEW in v28: Add nationality, stateOfOrigin, lga fields to students table
    if (oldVersion < 28) {
      print('🌍 Adding nationality, stateOfOrigin, lga fields to students table...');
      await _safeExec(db, "ALTER TABLE students ADD COLUMN nationality TEXT");
      await _safeExec(db, "ALTER TABLE students ADD COLUMN stateOfOrigin TEXT");
      await _safeExec(db, "ALTER TABLE students ADD COLUMN lga TEXT");
      print('✅ nationality, stateOfOrigin, lga fields added to students table');
    }

    // NEW in v29: Special fee items and special class fees tables for new intake bills
    if (oldVersion < 29) {
      print('📋 Adding special_fee_items and special_class_fees tables...');
      await _safeExec(db, '''
        CREATE TABLE IF NOT EXISTS special_fee_items (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          name TEXT NOT NULL,
          defaultAmount REAL NOT NULL,
          description TEXT,
          term TEXT,
          session TEXT,
          createdAt TEXT NOT NULL
        )
      ''');
      await _safeExec(db, '''
        CREATE TABLE IF NOT EXISTS special_class_fees (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          classId INTEGER NOT NULL,
          specialFeeItemId INTEGER NOT NULL,
          amount REAL NOT NULL,
          term TEXT NOT NULL,
          session TEXT NOT NULL
        )
      ''');
      print('✅ special_fee_items and special_class_fees tables added');
    }

    // NEW in v30: Excluded default fees table for new intake bills
    if (oldVersion < 30) {
      print('📋 Adding excluded_default_fees table...');
      await _safeExec(db, '''
        CREATE TABLE IF NOT EXISTS excluded_default_fees (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          classId INTEGER NOT NULL,
          classFeeId INTEGER NOT NULL,
          term TEXT NOT NULL,
          session TEXT NOT NULL,
          UNIQUE(classId, classFeeId, term, session)
        )
      ''');
      print('✅ excluded_default_fees table added');
    }

    // NEW in v31: Add parentId column to special_fee_items for category hierarchy
    if (oldVersion < 31) {
      print('📋 Adding parentId column to special_fee_items table...');
      await _safeExec(db, "ALTER TABLE special_fee_items ADD COLUMN parentId INTEGER");
      print('✅ parentId column added to special_fee_items');
    }

    // NEW in v32: Add isCategory column to special_fee_items to distinguish categories from standalone items
    if (oldVersion < 32) {
      print('📋 Adding isCategory column to special_fee_items table...');
      await _safeExec(db, "ALTER TABLE special_fee_items ADD COLUMN isCategory INTEGER DEFAULT 0");
      print('✅ isCategory column added to special_fee_items');
    }

    // NEW in v33: Add armId column to class_fees and special_class_fees for arm-specific fee assignments
    if (oldVersion < 33) {
      print('📋 Adding armId column to class_fees and special_class_fees tables...');
      await _safeExec(db, "ALTER TABLE class_fees ADD COLUMN armId INTEGER");
      await _safeExec(db, "ALTER TABLE special_class_fees ADD COLUMN armId INTEGER");
      print('✅ armId column added to class_fees and special_class_fees');

      // Migrate existing fees to the first arm of each class
      print('📋 Migrating existing fee assignments to class arms...');

      try {
        // Get all classes
        final classes = await db.query('classes');

        for (var cls in classes) {
          final classId = cls['id'] as int;

          // Get the first arm for this class
          final arms = await db.query(
            'arms',
            where: 'classId = ?',
            whereArgs: [classId],
            orderBy: 'name ASC',
            limit: 1,
          );

          if (arms.isNotEmpty) {
            final firstArmId = arms.first['id'] as int;

            // Update class_fees with NULL armId to use the first arm
            await db.update(
              'class_fees',
              {'armId': firstArmId},
              where: 'classId = ? AND (armId IS NULL OR armId = 0)',
              whereArgs: [classId],
            );

            // Update special_class_fees with NULL armId to use the first arm
            await db.update(
              'special_class_fees',
              {'armId': firstArmId},
              where: 'classId = ? AND (armId IS NULL OR armId = 0)',
              whereArgs: [classId],
            );

            print('   ✓ Migrated fees for class $classId to arm $firstArmId');
          }
        }

        print('✅ Fee migration completed successfully');
      } catch (e) {
        print('⚠️  Warning: Fee migration encountered an error: $e');
        print('   Existing fees may need manual assignment to arms');
      }
    }

    // NEW in v34: Custom item support for sales
    if (oldVersion < 34) {
      print('🛒 Adding custom item support to sales table...');

      // Add itemName column for custom items (and as fallback for stock items)
      await _safeExec(db, "ALTER TABLE sales ADD COLUMN itemName TEXT");

      // Add isCustomItem flag to identify custom items
      await _safeExec(db, "ALTER TABLE sales ADD COLUMN isCustomItem INTEGER DEFAULT 0");

      // SQLite doesn't support altering columns to nullable, but we can work around this
      // by storing NULL stockItemId as 0 for custom items. The app code will handle this.

      // Backfill itemName from stock_items for existing sales
      print('📦 Backfilling item names from stock_items...');
      try {
        await db.execute('''
          UPDATE sales
          SET itemName = (
            SELECT itemName FROM stock_items WHERE stock_items.id = sales.stockItemId
          )
          WHERE itemName IS NULL AND stockItemId IS NOT NULL
        ''');
        print('✅ Item names backfilled successfully');
      } catch (e) {
        print('⚠️ Warning: Could not backfill item names: $e');
      }

      print('✅ Custom item support added to sales');
    }

    // NEW in v35: Continuous Assessment Portal tables
    if (oldVersion < 35) {
      print('📋 Adding Continuous Assessment Portal tables...');
      await _createCATables(db);
      print('✅ CA tables added (school_divisions, subjects, exams, grading, scores, etc.)');
    }

    // NEW in v36: Bank account fields for school_profile
    if (oldVersion < 36) {
      print('🏦 Adding bank account fields to school_profile...');
      await _safeExec(db, "ALTER TABLE school_profile ADD COLUMN bankName1 TEXT");
      await _safeExec(db, "ALTER TABLE school_profile ADD COLUMN accountNumber1 TEXT");
      await _safeExec(db, "ALTER TABLE school_profile ADD COLUMN accountName1 TEXT");
      await _safeExec(db, "ALTER TABLE school_profile ADD COLUMN bankName2 TEXT");
      await _safeExec(db, "ALTER TABLE school_profile ADD COLUMN accountNumber2 TEXT");
      await _safeExec(db, "ALTER TABLE school_profile ADD COLUMN accountName2 TEXT");
      await _safeExec(db, "ALTER TABLE school_profile ADD COLUMN bankName3 TEXT");
      await _safeExec(db, "ALTER TABLE school_profile ADD COLUMN accountNumber3 TEXT");
      await _safeExec(db, "ALTER TABLE school_profile ADD COLUMN accountName3 TEXT");
      print('✅ Bank account fields added to school_profile');
    }

    // NEW in v37: Fee priority table for payment allocation ordering
    if (oldVersion < 37) {
      print('📊 Adding fee_priority table for Fee Tracker...');
      await _safeExec(db, '''
        CREATE TABLE IF NOT EXISTS fee_priority (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          scope TEXT NOT NULL DEFAULT 'global',
          classId INTEGER,
          armId INTEGER,
          feeItemId INTEGER NOT NULL,
          priority INTEGER NOT NULL,
          term TEXT NOT NULL,
          session TEXT NOT NULL,
          UNIQUE(scope, classId, armId, feeItemId, term, session)
        )
      ''');
      print('✅ fee_priority table added');
    }

    // NEW in v38: Staff salary history table for tracking salary increments
    if (oldVersion < 38) {
      print('💼 Adding staff_salary_history table...');
      await _safeExec(db, '''
        CREATE TABLE IF NOT EXISTS staff_salary_history (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          staffId INTEGER NOT NULL,
          salary REAL NOT NULL,
          effectiveMonth TEXT NOT NULL,
          reason TEXT,
          createdAt TEXT,
          FOREIGN KEY (staffId) REFERENCES staff(id)
        )
      ''');
      print('✅ staff_salary_history table added');
    }

    // NEW in v39: expense_categories table
    if (oldVersion < 39) {
      print('🗂️ Adding expense_categories table...');
      await _safeExec(db, '''
        CREATE TABLE IF NOT EXISTS expense_categories (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          name TEXT NOT NULL UNIQUE,
          isPreset INTEGER NOT NULL DEFAULT 0,
          createdAt TEXT NOT NULL
        )
      ''');

      // Seed preset categories (skip duplicates)
      final now = DateTime.now().toIso8601String();
      for (final cat in [
        'Staff Loan',
        'Paid Salary',
        'Utilities',
        'Maintenance & Repairs',
        'Office Supplies',
        'Other',
      ]) {
        try {
          await db.insert('expense_categories', {
            'name': cat,
            'isPreset': 1,
            'createdAt': now,
          });
        } catch (_) {}
      }
      print('✅ expense_categories table added');
    }

    // v40: Guard — ensure sales.itemName and sales.isCustomItem exist on every device.
    // _safeExec swallows "duplicate column" errors, so this is safe to run unconditionally.
    if (oldVersion < 40) {
      await _safeExec(db, "ALTER TABLE sales ADD COLUMN itemName TEXT");
      await _safeExec(db, "ALTER TABLE sales ADD COLUMN isCustomItem INTEGER DEFAULT 0");
      // Backfill itemName from stock_items for rows that have a linked stock item
      await _safeExec(db, '''
        UPDATE sales
        SET itemName = (SELECT itemName FROM stock_items WHERE stock_items.id = sales.stockItemId)
        WHERE (itemName IS NULL OR itemName = '') AND stockItemId IS NOT NULL AND stockItemId > 0
      ''');
      print('✅ v40 guard: sales.itemName / isCustomItem ensured');
    }

    // v41: External examinations and registrations tables
    if (oldVersion < 41) {
      await _safeExec(db, '''
        CREATE TABLE IF NOT EXISTS external_examinations (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          name TEXT NOT NULL,
          code TEXT NOT NULL,
          isDefault INTEGER NOT NULL DEFAULT 0,
          isActive INTEGER NOT NULL DEFAULT 1,
          createdAt TEXT NOT NULL
        )
      ''');

      await _safeExec(db, '''
        CREATE TABLE IF NOT EXISTS examination_registrations (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          examinationId INTEGER NOT NULL,
          studentId INTEGER NOT NULL,
          registrationDate TEXT NOT NULL,
          createdAt TEXT NOT NULL,
          FOREIGN KEY (examinationId) REFERENCES external_examinations(id) ON DELETE CASCADE,
          FOREIGN KEY (studentId) REFERENCES students(id) ON DELETE CASCADE,
          UNIQUE(examinationId, studentId)
        )
      ''');

      final existingExams = await db.query('external_examinations', limit: 1);
      if (existingExams.isEmpty) {
        await _seedDefaultExaminations(db);
      }

      for (final role in ['admin', 'bursar']) {
        try {
          await db.insert('permissions', {
            'role': role,
            'module': 'external_examinations',
            'canAccess': 1,
          });
        } catch (_) {}
      }

      print('✅ v41: External examinations tables added');
    }

    // v42: Add snapshot columns so student data survives deactivation / deletion
    if (oldVersion < 42) {
      await _safeExec(db, 'ALTER TABLE examination_registrations ADD COLUMN snapshotName TEXT');
      await _safeExec(db, 'ALTER TABLE examination_registrations ADD COLUMN snapshotAdmNo TEXT');
      await _safeExec(db, 'ALTER TABLE examination_registrations ADD COLUMN snapshotGender TEXT');
      await _safeExec(db, 'ALTER TABLE examination_registrations ADD COLUMN snapshotClass TEXT');
      await _safeExec(db, 'ALTER TABLE examination_registrations ADD COLUMN snapshotArm TEXT');
      // Backfill snapshot from live student data for existing rows
      await _safeExec(db, '''
        UPDATE examination_registrations
        SET snapshotName  = (SELECT s.surname || ' ' || s.firstName
                             FROM students s WHERE s.id = examination_registrations.studentId),
            snapshotAdmNo = (SELECT s.admissionNo FROM students s WHERE s.id = examination_registrations.studentId),
            snapshotGender= (SELECT s.gender     FROM students s WHERE s.id = examination_registrations.studentId),
            snapshotClass = (SELECT c.name FROM students s JOIN classes c ON c.id = s.classId
                             WHERE s.id = examination_registrations.studentId),
            snapshotArm   = (SELECT a.name FROM students s LEFT JOIN arms a ON a.id = s.armId
                             WHERE s.id = examination_registrations.studentId)
        WHERE snapshotName IS NULL
      ''');
      print('✅ v42: examination_registrations snapshot columns added');
    }

    // v43: Add session column; rebuild table with UNIQUE(examinationId, studentId, session)
    if (oldVersion < 43) {
      await _safeExec(db, '''
        CREATE TABLE examination_registrations_new (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          examinationId INTEGER NOT NULL,
          studentId INTEGER,
          registrationDate TEXT NOT NULL,
          createdAt TEXT NOT NULL,
          session TEXT NOT NULL DEFAULT '',
          snapshotName TEXT,
          snapshotAdmNo TEXT,
          snapshotGender TEXT,
          snapshotClass TEXT,
          snapshotArm TEXT,
          FOREIGN KEY (examinationId) REFERENCES external_examinations(id) ON DELETE CASCADE,
          FOREIGN KEY (studentId) REFERENCES students(id) ON DELETE SET NULL,
          UNIQUE(examinationId, studentId, session)
        )
      ''');
      await _safeExec(db, '''
        INSERT INTO examination_registrations_new
          (id, examinationId, studentId, registrationDate, createdAt, session,
           snapshotName, snapshotAdmNo, snapshotGender, snapshotClass, snapshotArm)
        SELECT id, examinationId, studentId, registrationDate, createdAt,
               COALESCE((SELECT sessionName FROM sessions WHERE isActive = 1 LIMIT 1), ''),
               snapshotName, snapshotAdmNo, snapshotGender, snapshotClass, snapshotArm
        FROM examination_registrations
      ''');
      await _safeExec(db, 'DROP TABLE examination_registrations');
      await _safeExec(db, 'ALTER TABLE examination_registrations_new RENAME TO examination_registrations');
      print('✅ v43: examination_registrations rebuilt with session column');
    }

    if (oldVersion < 44) {
      await _safeExec(db, 'ALTER TABLE staff ADD COLUMN title TEXT');
      print('✅ v44: title column added to staff table');
    }

    if (oldVersion < 45) {
      await _safeExec(db, "ALTER TABLE payments ADD COLUMN paymentFor TEXT DEFAULT 'Tuition Fee'");
      print('✅ v45: paymentFor column added to payments table');
    }

    if (oldVersion < 46) {
      await _safeExec(db, '''
        CREATE TABLE IF NOT EXISTS print_counters (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          date TEXT NOT NULL UNIQUE,
          bills INTEGER NOT NULL DEFAULT 0,
          receipts INTEGER NOT NULL DEFAULT 0,
          paymentHistory INTEGER NOT NULL DEFAULT 0,
          receiptReprint INTEGER NOT NULL DEFAULT 0
        )
      ''');
      print('✅ v46: print_counters table added');
    }

    if (oldVersion < 47) {
      await _safeExec(db, 'ALTER TABLE licenses ADD COLUMN lastKnownDate TEXT');
      print('✅ v47: lastKnownDate column added to licenses table');
    }

    if (oldVersion < 48) {
      await _safeExec(db, 'ALTER TABLE staff_salary_payments ADD COLUMN basisType TEXT');
      await _safeExec(db, 'ALTER TABLE staff_salary_payments ADD COLUMN percentageValue REAL');
      await _safeExec(db, 'ALTER TABLE staff_salary_payments ADD COLUMN totalUnits REAL');
      await _safeExec(db, 'ALTER TABLE staff_salary_payments ADD COLUMN workedUnits REAL');
      await _safeExec(db, '''
        CREATE TABLE IF NOT EXISTS payroll_month_settings (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          month TEXT NOT NULL UNIQUE,
          basisType TEXT NOT NULL DEFAULT 'full',
          percentageValue REAL,
          totalUnits REAL,
          workedUnits REAL,
          createdAt TEXT,
          updatedAt TEXT
        )
      ''');
      print('✅ v48: payroll basis (Full/Percentage/Days/Weeks) support added');
    }

    if (oldVersion < 49) {
      await _safeExec(db, '''
        CREATE TABLE IF NOT EXISTS salary_expense_postings (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          month TEXT NOT NULL,
          amount REAL NOT NULL,
          postedAt TEXT NOT NULL,
          postedBy TEXT
        )
      ''');
      print('✅ v49: salary_expense_postings table added');
    }

    if (oldVersion < 50) {
      await _safeExec(db, 'ALTER TABLE staff ADD COLUMN deactivationDate TEXT');
      print('✅ v50: deactivationDate column added to staff table');
    }

    if (oldVersion < 51) {
      try {
        await db.insert('expense_categories', {
          'name': 'Paid Salary',
          'isPreset': 1,
          'createdAt': DateTime.now().toIso8601String(),
        });
      } catch (_) {}
      print('✅ v51: Paid Salary expense category added');
    }

    if (oldVersion < 52) {
      try {
        await db.update(
          'expense_categories',
          {'name': 'Staff Loan'},
          where: 'name = ?',
          whereArgs: ['Staff Salaries'],
        );
      } catch (_) {}
      print('✅ v52: Staff Salaries preset category renamed to Staff Loan');
    }

    if (oldVersion < 53) {
      await _safeExec(db, 'ALTER TABLE staff_loans ADD COLUMN linkedExpenseId INTEGER');
      print('✅ v53: linkedExpenseId column added to staff_loans table');
    }

    if (oldVersion < 54) {
      await _safeExec(db, 'ALTER TABLE staff_salary_payments ADD COLUMN loanDeductionsApplied TEXT');
      print('✅ v54: loanDeductionsApplied column added to staff_salary_payments table');
    }

    if (oldVersion < 55) {
      await _safeExec(db, 'ALTER TABLE staff_loans ADD COLUMN paymentMethod TEXT');
      print('✅ v55: paymentMethod column added to staff_loans table');
    }

    if (oldVersion < 56) {
      await _safeExec(db, '''
        CREATE TABLE IF NOT EXISTS audit_log (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          entityType TEXT NOT NULL,
          entityId INTEGER NOT NULL,
          action TEXT NOT NULL,
          studentId INTEGER,
          amount REAL,
          changes TEXT,
          userId INTEGER,
          username TEXT,
          timestamp TEXT NOT NULL
        )
      ''');
      print('✅ v56: audit_log table added');

      // audit_log_view permission — admin enabled, bursar disabled by default
      try {
        await db.insert('permissions', {
          'role': 'admin',
          'module': 'audit_log_view',
          'canAccess': 1,
        });
      } catch (_) {}
      try {
        await db.insert('permissions', {
          'role': 'bursar',
          'module': 'audit_log_view',
          'canAccess': 0,
        });
      } catch (_) {}
      print('✅ v56: audit_log_view permission seeded');
    }

    if (oldVersion < 57) {
      await _safeExec(db, 'ALTER TABLE audit_log ADD COLUMN staffId INTEGER');
      print('✅ v57: staffId column added to audit_log table');
    }

    if (oldVersion < 58) {
      await _safeExec(db, '''
        CREATE TABLE IF NOT EXISTS sms_log (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          studentId INTEGER,
          phone TEXT NOT NULL,
          message TEXT NOT NULL,
          context TEXT,
          status TEXT NOT NULL,
          errorMessage TEXT,
          sentAt TEXT NOT NULL
        )
      ''');
      print('✅ v58: sms_log table added');
    }

    if (oldVersion < 59) {
      // reports_fees_balance permission — enabled by default for admin and bursar
      try {
        await db.insert('permissions', {
          'role': 'admin',
          'module': 'reports_fees_balance',
          'canAccess': 1,
        });
      } catch (_) {}
      try {
        await db.insert('permissions', {
          'role': 'bursar',
          'module': 'reports_fees_balance',
          'canAccess': 1,
        });
      } catch (_) {}
      print('✅ v59: reports_fees_balance permission seeded');
    }

    if (oldVersion < 60) {
      await _safeExec(db, '''
        CREATE TABLE IF NOT EXISTS transport_routes (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          name TEXT NOT NULL,
          description TEXT,
          fare REAL NOT NULL DEFAULT 0,
          isActive INTEGER NOT NULL DEFAULT 1,
          createdAt TEXT,
          updatedAt TEXT
        )
      ''');
      await _safeExec(db, '''
        CREATE TABLE IF NOT EXISTS student_transport_allocations (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          studentId INTEGER NOT NULL,
          routeId INTEGER NOT NULL,
          billId INTEGER NOT NULL,
          fareCharged REAL NOT NULL DEFAULT 0,
          term TEXT NOT NULL,
          session TEXT NOT NULL,
          createdAt TEXT,
          UNIQUE(studentId, term, session),
          FOREIGN KEY (studentId) REFERENCES students(id) ON DELETE CASCADE,
          FOREIGN KEY (routeId) REFERENCES transport_routes(id) ON DELETE CASCADE
        )
      ''');
      for (final module in ['transportation_manage', 'transportation_allocate']) {
        try {
          await db.insert('permissions', {'role': 'admin', 'module': module, 'canAccess': 1});
        } catch (_) {}
      }
      try {
        await db.insert('permissions', {'role': 'bursar', 'module': 'transportation_allocate', 'canAccess': 1});
      } catch (_) {}
      print('✅ v60: Transportation tables + permissions added');
    }

    // ensure session/term exists
    final sess = await db.query('sessions', limit: 1);
    if (sess.isEmpty) {
      await db.insert('sessions', {'sessionName': '2025/2026', 'isActive': 1});
    }

    final term = await db.query('settings',
        where: 'key = ?', whereArgs: [_kActiveTerm], limit: 1);
    if (term.isEmpty) {
      await db.insert('settings', {'key': _kActiveTerm, 'value': '1st Term'});
    }
  }

  Future<void> _safeExec(Database db, String sql) async {
    try {
      await db.execute(sql);
    } catch (_) {}
  }

  // ------------------------------------------------------------------
  // Continuous Assessment Portal tables
  // ------------------------------------------------------------------
  Future<void> _createCATables(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS school_divisions (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        description TEXT,
        sortOrder INTEGER DEFAULT 0,
        createdAt TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS division_class_allocations (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        divisionId INTEGER NOT NULL,
        classId INTEGER NOT NULL,
        createdAt TEXT NOT NULL,
        FOREIGN KEY (divisionId) REFERENCES school_divisions(id) ON DELETE CASCADE,
        FOREIGN KEY (classId) REFERENCES classes(id) ON DELETE CASCADE,
        UNIQUE(classId)
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS subjects (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        shortName TEXT,
        description TEXT,
        isActive INTEGER NOT NULL DEFAULT 1,
        createdAt TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS activities (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        description TEXT,
        isActive INTEGER NOT NULL DEFAULT 1,
        createdAt TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS class_subject_allocations (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        classId INTEGER NOT NULL,
        armId INTEGER NOT NULL,
        subjectId INTEGER NOT NULL,
        createdAt TEXT NOT NULL,
        FOREIGN KEY (classId) REFERENCES classes(id) ON DELETE CASCADE,
        FOREIGN KEY (armId) REFERENCES arms(id) ON DELETE CASCADE,
        FOREIGN KEY (subjectId) REFERENCES subjects(id) ON DELETE CASCADE,
        UNIQUE(classId, armId, subjectId)
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS class_activity_allocations (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        classId INTEGER NOT NULL,
        armId INTEGER NOT NULL,
        activityId INTEGER NOT NULL,
        createdAt TEXT NOT NULL,
        FOREIGN KEY (classId) REFERENCES classes(id) ON DELETE CASCADE,
        FOREIGN KEY (armId) REFERENCES arms(id) ON DELETE CASCADE,
        FOREIGN KEY (activityId) REFERENCES activities(id) ON DELETE CASCADE,
        UNIQUE(classId, armId, activityId)
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS class_teacher_allocations (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        classId INTEGER NOT NULL,
        armId INTEGER NOT NULL,
        staffId INTEGER NOT NULL,
        session TEXT NOT NULL,
        createdAt TEXT NOT NULL,
        FOREIGN KEY (classId) REFERENCES classes(id) ON DELETE CASCADE,
        FOREIGN KEY (armId) REFERENCES arms(id) ON DELETE CASCADE,
        FOREIGN KEY (staffId) REFERENCES staff(id) ON DELETE CASCADE,
        UNIQUE(classId, armId, session)
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS subject_teacher_allocations (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        staffId INTEGER NOT NULL,
        subjectId INTEGER NOT NULL,
        classId INTEGER NOT NULL,
        armId INTEGER NOT NULL,
        session TEXT NOT NULL,
        createdAt TEXT NOT NULL,
        FOREIGN KEY (staffId) REFERENCES staff(id) ON DELETE CASCADE,
        FOREIGN KEY (subjectId) REFERENCES subjects(id) ON DELETE CASCADE,
        FOREIGN KEY (classId) REFERENCES classes(id) ON DELETE CASCADE,
        FOREIGN KEY (armId) REFERENCES arms(id) ON DELETE CASCADE,
        UNIQUE(staffId, subjectId, classId, armId, session)
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS exams (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        shortName TEXT,
        maxScore REAL NOT NULL,
        sortOrder INTEGER NOT NULL,
        session TEXT NOT NULL,
        term TEXT NOT NULL,
        isActive INTEGER NOT NULL DEFAULT 1,
        createdAt TEXT NOT NULL,
        UNIQUE(name, session, term)
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS grading_definitions (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        divisionId INTEGER NOT NULL,
        minScore REAL NOT NULL,
        maxScore REAL NOT NULL,
        grade TEXT NOT NULL,
        remark TEXT NOT NULL,
        sortOrder INTEGER DEFAULT 0,
        session TEXT NOT NULL,
        createdAt TEXT NOT NULL,
        FOREIGN KEY (divisionId) REFERENCES school_divisions(id) ON DELETE CASCADE
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS student_scores (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        studentId INTEGER NOT NULL,
        subjectId INTEGER NOT NULL,
        examId INTEGER NOT NULL,
        classId INTEGER NOT NULL,
        armId INTEGER NOT NULL,
        score REAL,
        session TEXT NOT NULL,
        term TEXT NOT NULL,
        enteredBy TEXT,
        enteredAt TEXT,
        updatedAt TEXT,
        FOREIGN KEY (studentId) REFERENCES students(id) ON DELETE CASCADE,
        FOREIGN KEY (subjectId) REFERENCES subjects(id) ON DELETE CASCADE,
        FOREIGN KEY (examId) REFERENCES exams(id) ON DELETE CASCADE,
        FOREIGN KEY (classId) REFERENCES classes(id) ON DELETE CASCADE,
        FOREIGN KEY (armId) REFERENCES arms(id) ON DELETE CASCADE,
        UNIQUE(studentId, subjectId, examId, session, term)
      )
    ''');

    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_student_scores_lookup
        ON student_scores(classId, armId, subjectId, session, term)
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS psychomotor_skills (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        description TEXT,
        isActive INTEGER NOT NULL DEFAULT 1,
        sortOrder INTEGER DEFAULT 0,
        createdAt TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS affective_traits (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        description TEXT,
        isActive INTEGER NOT NULL DEFAULT 1,
        sortOrder INTEGER DEFAULT 0,
        createdAt TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS student_psychomotor_scores (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        studentId INTEGER NOT NULL,
        psychomotorSkillId INTEGER NOT NULL,
        rating INTEGER NOT NULL,
        classId INTEGER NOT NULL,
        armId INTEGER NOT NULL,
        session TEXT NOT NULL,
        term TEXT NOT NULL,
        createdAt TEXT,
        FOREIGN KEY (studentId) REFERENCES students(id) ON DELETE CASCADE,
        FOREIGN KEY (psychomotorSkillId) REFERENCES psychomotor_skills(id) ON DELETE CASCADE,
        UNIQUE(studentId, psychomotorSkillId, session, term)
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS student_affective_scores (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        studentId INTEGER NOT NULL,
        affectiveTraitId INTEGER NOT NULL,
        rating INTEGER NOT NULL,
        classId INTEGER NOT NULL,
        armId INTEGER NOT NULL,
        session TEXT NOT NULL,
        term TEXT NOT NULL,
        createdAt TEXT,
        FOREIGN KEY (studentId) REFERENCES students(id) ON DELETE CASCADE,
        FOREIGN KEY (affectiveTraitId) REFERENCES affective_traits(id) ON DELETE CASCADE,
        UNIQUE(studentId, affectiveTraitId, session, term)
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS result_computations (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        studentId INTEGER NOT NULL,
        classId INTEGER NOT NULL,
        armId INTEGER NOT NULL,
        session TEXT NOT NULL,
        term TEXT NOT NULL,
        totalScore REAL,
        averageScore REAL,
        subjectCount INTEGER,
        positionInClass INTEGER,
        positionInArm INTEGER,
        grade TEXT,
        remark TEXT,
        classTeacherComment TEXT,
        headTeacherComment TEXT,
        computedAt TEXT NOT NULL,
        FOREIGN KEY (studentId) REFERENCES students(id) ON DELETE CASCADE,
        UNIQUE(studentId, classId, armId, session, term)
      )
    ''');

    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_result_computations_lookup
        ON result_computations(classId, armId, session, term)
    ''');
  }

  // ------------------------------------------------------------------
  // SEED DEFAULT PERMISSIONS
  // ------------------------------------------------------------------
  Future<void> _seedDefaultPermissions(Database db) async {
    // Default Admin permissions (all features except data_management and user_management)
    final adminPermissions = [
      'dashboard',
      'session_term',
      'students_view',
      'students_add',
      'students_edit',
      'students_batch_upload',
      'students_promote',
      'students_deactivate',
      'students_inactive',
      'students_statement',
      'classes_arms',
      'fee_items_view',
      'fee_items_manage',
      'fee_class_assignment',
      'billing_generate',
      'billing_print',
      'payments_record',
      'payments_edit',           // Edit recorded payments (admin only)
      'payments_receipt',
      'payments_history',
      'reports_daily',
      'reports_debtors',
      'reports_termly',          // Termly financial report
      'reports_overpayment',     // Overpayment tracker report
      'reports_fees_balance',    // School fees balance report
      'expenses',                // Track and manage expenses
      'school_profile',
      'license_management',
      'thermal_printer',         // Connect to thermal printer
      'daily_print_count',       // Daily print counter (admin only)
      'backup',
      'stock_manage',            // Manage stock items and inventory
      'sales_record',            // Record sales transactions
      'sales_report',            // View sales reports and analytics
      'audit_log_view',          // View financial activity/audit log (admin only)
      'transportation_manage',   // Manage transport routes and fares
      'transportation_allocate', // Allocate/remove students from transport routes
      // data_management excluded (super_admin only - too destructive)
      // user_management excluded (super_admin only)
    ];

    for (var module in adminPermissions) {
      try {
        await db.insert('permissions', {
          'role': 'admin',
          'module': module,
          'canAccess': 1,
        });
      } catch (_) {
        // Skip if already exists (UNIQUE constraint)
      }
    }

    // Default Bursar permissions (billing, payments, view students, reports)
    final bursarPermissions = [
      'dashboard',
      'students_view',       // View student list/details only
      'students_statement',  // View student account statements
      'billing_generate',    // Generate bills
      'billing_print',       // Print bills
      'payments_record',     // Record payments
      'payments_receipt',    // Print payment receipts
      'payments_history',    // View payment history
      'reports_daily',       // Daily financial reports
      'reports_debtors',     // Debtors list
      'reports_termly',      // Termly financial report
      'reports_overpayment', // Overpayment tracker report
      'reports_fees_balance', // School fees balance report
      'expenses',            // Track and manage expenses
      'thermal_printer',     // Connect to thermal printer (for receipt printing)
      'stock_manage',        // Manage stock items and inventory
      'sales_record',        // Record sales transactions
      'sales_report',        // View sales reports and analytics
      'transportation_allocate', // Allocate/remove students from transport routes
    ];

    for (var module in bursarPermissions) {
      try {
        await db.insert('permissions', {
          'role': 'bursar',
          'module': module,
          'canAccess': 1,
        });
      } catch (_) {
        // Skip if already exists (UNIQUE constraint)
      }
    }
  }

  // ------------------------------------------------------------------
  // SEED DEFAULT EXAMINATIONS
  // ------------------------------------------------------------------
  Future<void> _seedDefaultExaminations(Database db) async {
    final now = DateTime.now().toIso8601String();
    final defaults = [
      {'name': 'Primary School Leaving Certificate', 'code': 'PSLC'},
      {'name': 'Basic Education Certificate Examination', 'code': 'BECE'},
      {'name': 'SSS Two Joint Examination', 'code': 'SSS 2 JOINT'},
      {'name': 'West African Examination Council', 'code': 'WAEC'},
      {'name': 'National Examination Council', 'code': 'NECO'},
    ];
    for (final exam in defaults) {
      await db.insert('external_examinations', {
        'name': exam['name'],
        'code': exam['code'],
        'isDefault': 1,
        'isActive': 1,
        'createdAt': now,
      });
    }
  }

  // ------------------------------------------------------------------
  // EXTERNAL EXAMINATIONS CRUD
  // ------------------------------------------------------------------

  Future<List<Map<String, dynamic>>> getExternalExaminations({bool activeOnly = false}) async {
    final db = await database;
    if (activeOnly) {
      return db.query('external_examinations', where: 'isActive = ?', whereArgs: [1], orderBy: 'name ASC');
    }
    return db.query('external_examinations', orderBy: 'name ASC');
  }

  Future<int> insertExternalExamination(Map<String, dynamic> data) async {
    final db = await database;
    return db.insert('external_examinations', data);
  }

  Future<int> updateExternalExamination(int id, Map<String, dynamic> data) async {
    final db = await database;
    return db.update('external_examinations', data, where: 'id = ?', whereArgs: [id]);
  }

  Future<int> deleteExternalExamination(int id) async {
    final db = await database;
    return db.delete('external_examinations', where: 'id = ?', whereArgs: [id]);
  }

  // ------------------------------------------------------------------
  // EXAMINATION REGISTRATIONS CRUD
  // ------------------------------------------------------------------

  Future<List<Map<String, dynamic>>> getExaminationRegistrations({int? examinationId, String? session}) async {
    final db = await database;
    final conditions = <String>[];
    final args = <dynamic>[];
    if (examinationId != null) { conditions.add('er.examinationId = ?'); args.add(examinationId); }
    if (session != null) { conditions.add('er.session = ?'); args.add(session); }
    final whereClause = conditions.isEmpty ? '' : 'AND ${conditions.join(' AND ')}';
    return db.rawQuery('''
      SELECT er.id, er.examinationId, er.studentId, er.registrationDate, er.createdAt, er.session,
             er.snapshotName, er.snapshotAdmNo, er.snapshotGender, er.snapshotClass, er.snapshotArm,
             s.surname, s.firstName, s.otherName, s.parentPhone,
             COALESCE(s.admissionNo, er.snapshotAdmNo) AS admissionNo,
             COALESCE(s.gender,      er.snapshotGender) AS gender,
             COALESCE(c.name,        er.snapshotClass)  AS className,
             COALESCE(a.name,        er.snapshotArm)    AS armName,
             s.isActive AS studentIsActive,
             ee.name AS examinationName, ee.code AS examinationCode
      FROM examination_registrations er
      LEFT JOIN students s ON s.id = er.studentId
      LEFT JOIN classes c ON c.id = s.classId
      LEFT JOIN arms a ON a.id = s.armId
      JOIN external_examinations ee ON ee.id = er.examinationId
      WHERE 1=1 $whereClause
      ORDER BY ee.name ASC, className ASC, armName ASC, er.snapshotName ASC
    ''', args);
  }

  Future<List<String>> getExamRegistrationSessions() async {
    final db = await database;
    final rows = await db.rawQuery(
        'SELECT DISTINCT session FROM examination_registrations WHERE session != \'\' ORDER BY session DESC');
    return rows.map((r) => r['session'] as String).toList();
  }

  Future<int> insertExaminationRegistration(Map<String, dynamic> data) async {
    final db = await database;
    return db.insert('examination_registrations', data);
  }

  Future<int> deleteExaminationRegistration(int id) async {
    final db = await database;
    return db.delete('examination_registrations', where: 'id = ?', whereArgs: [id]);
  }

  Future<int> deleteExaminationRegistrationByKeys(int studentId, int examinationId, String session) async {
    final db = await database;
    return db.delete('examination_registrations',
        where: 'studentId = ? AND examinationId = ? AND session = ?',
        whereArgs: [studentId, examinationId, session]);
  }

  /// Returns the list of external examinations a student is registered for.
  /// Used to block deletion when the student has exam records.
  Future<List<Map<String, dynamic>>> getStudentExamRegistrations(int studentId) async {
    final db = await database;
    return db.rawQuery('''
      SELECT ee.name, ee.code
      FROM examination_registrations er
      JOIN external_examinations ee ON ee.id = er.examinationId
      WHERE er.studentId = ?
      ORDER BY ee.name ASC
    ''', [studentId]);
  }

  Future<bool> isStudentRegisteredForExam(int studentId, int examinationId) async {
    final db = await database;
    final result = await db.query(
      'examination_registrations',
      where: 'studentId = ? AND examinationId = ?',
      whereArgs: [studentId, examinationId],
      limit: 1,
    );
    return result.isNotEmpty;
  }

  // ------------------------------------------------------------------
  // PERMISSION MANAGEMENT
  // ------------------------------------------------------------------

  /// Get all permissions for a specific role
  Future<List<Map<String, dynamic>>> getPermissionsByRole(String role) async {
    final db = await database;
    return await db.query(
      'permissions',
      where: 'role = ?',
      whereArgs: [role],
      orderBy: 'module ASC',
    );
  }

  /// Check if a role has permission to access a specific module
  Future<bool> hasPermission(String role, String module) async {
    final db = await database;
    final result = await db.query(
      'permissions',
      where: 'role = ? AND module = ? AND canAccess = ?',
      whereArgs: [role, module, 1],
      limit: 1,
    );
    return result.isNotEmpty;
  }

  /// Set permission for a role and module
  Future<void> setPermission(String role, String module, bool canAccess) async {
    final db = await database;

    // Check if permission entry exists
    final existing = await db.query(
      'permissions',
      where: 'role = ? AND module = ?',
      whereArgs: [role, module],
      limit: 1,
    );

    if (existing.isNotEmpty) {
      // Update existing permission
      await db.update(
        'permissions',
        {'canAccess': canAccess ? 1 : 0},
        where: 'role = ? AND module = ?',
        whereArgs: [role, module],
      );
    } else {
      // Insert new permission
      await db.insert('permissions', {
        'role': role,
        'module': module,
        'canAccess': canAccess ? 1 : 0,
      });
    }
  }

  /// Bulk update permissions for a role
  Future<void> updateRolePermissions(String role, Map<String, bool> permissions) async {
    final db = await database;

    await db.transaction((txn) async {
      for (var entry in permissions.entries) {
        final module = entry.key;
        final canAccess = entry.value;

        // Check if permission entry exists
        final existing = await txn.query(
          'permissions',
          where: 'role = ? AND module = ?',
          whereArgs: [role, module],
          limit: 1,
        );

        if (existing.isNotEmpty) {
          // Update existing permission
          await txn.update(
            'permissions',
            {'canAccess': canAccess ? 1 : 0},
            where: 'role = ? AND module = ?',
            whereArgs: [role, module],
          );
        } else {
          // Insert new permission
          await txn.insert('permissions', {
            'role': role,
            'module': module,
            'canAccess': canAccess ? 1 : 0,
          });
        }
      }
    });
  }

  // ------------------------------------------------------------------
  // TERM & SESSION
  // ------------------------------------------------------------------
  Future<String> getActiveTerm() async {
    final db = await database;
    final rows = await db.query('settings',
        where: 'key = ?', whereArgs: [_kActiveTerm], limit: 1);
    return rows.isNotEmpty ? (rows.first['value'] as String) : '1st Term';
  }

  Future<void> setActiveTerm(String term) async {
    final db = await database;
    await db.update('settings', {'value': term},
        where: 'key = ?', whereArgs: [_kActiveTerm]);
  }

  // ------------------------------------------------------------------
  // GENERIC KEY/VALUE SETTINGS (SMS gateway config, etc.)
  // ------------------------------------------------------------------
  Future<String?> getSetting(String key) async {
    final db = await database;
    final rows = await db.query('settings',
        where: 'key = ?', whereArgs: [key], limit: 1);
    return rows.isNotEmpty ? rows.first['value'] as String? : null;
  }

  Future<void> setSetting(String key, String value) async {
    final db = await database;
    await db.insert('settings', {'key': key, 'value': value},
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  // ------------------------------------------------------------------
  // SMS LOG
  // ------------------------------------------------------------------
  Future<int> insertSmsLog({
    int? studentId,
    required String phone,
    required String message,
    String? context,
    required String status,
    String? errorMessage,
  }) async {
    final db = await database;
    return db.insert('sms_log', {
      'studentId': studentId,
      'phone': phone,
      'message': message,
      'context': context,
      'status': status,
      'errorMessage': errorMessage,
      'sentAt': DateTime.now().toIso8601String(),
    });
  }

  Future<Map<String, dynamic>?> getActiveSession() async {
    final db = await database;
    final rows = await db.query('sessions',
        where: 'isActive = ?', whereArgs: [1], limit: 1);
    return rows.isNotEmpty ? rows.first : null;
  }

  Future<List<Map<String, dynamic>>> getAllSessions() async {
    final db = await database;
    return db.query('sessions', orderBy: 'sessionName DESC');
  }

  // alias
  Future<List<Map<String, dynamic>>> getSessions() async {
    return getAllSessions();
  }

  Future<void> setActiveSession(int sessionId) async {
    final db = await database;
    await db.transaction((txn) async {
      // deactivate all
      await txn.update('sessions', {'isActive': 0});
      // activate chosen
      await txn.update('sessions', {'isActive': 1},
          where: 'id = ?', whereArgs: [sessionId]);
    });
  }

  // ------------------------------------------------------------------
  // STUDENTS
  // ------------------------------------------------------------------

  /// Checks the active license's maxStudents cap against the current count
  /// of active students, mirroring the `isActive = 1` convention used
  /// elsewhere for student counts (see CentralBackupHelper). A missing
  /// license or a maxStudents of null/0 is treated as unlimited.
  Future<void> _enforceStudentLimit(Database db) async {
    final licenseRows = await db.query(
      'licenses',
      where: 'isActive = ?',
      whereArgs: [1],
      orderBy: 'createdAt DESC',
      limit: 1,
    );
    if (licenseRows.isEmpty) return;

    final maxStudents = licenseRows.first['maxStudents'] as int?;
    if (maxStudents == null || maxStudents <= 0) return;

    final countResult = await db.rawQuery(
      'SELECT COUNT(*) AS cnt FROM students WHERE isActive = 1',
    );
    final currentCount = Sqflite.firstIntValue(countResult) ?? 0;

    if (currentCount >= maxStudents) {
      throw StudentLimitExceededException(
        currentCount: currentCount,
        maxStudents: maxStudents,
      );
    }
  }

  Future<int> insertStudent(Map<String, dynamic> student) async {
    final db = await database;
    await _enforceStudentLimit(db);
    return db.insert('students', student);
  }

  Future<List<Map<String, dynamic>>> getStudents({bool includeInactive = false}) async {
    final db = await database;
    if (includeInactive) {
      return db.query('students',
          orderBy: 'surname ASC, firstName ASC');
    } else {
      return db.query('students',
          where: 'isActive = ?',
          whereArgs: [1],
          orderBy: 'surname ASC, firstName ASC');
    }
  }

  // Convenience: only active with class and arm names
  Future<List<Map<String, dynamic>>> getActiveStudents() async {
    final db = await database;
    return db.rawQuery('''
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

  // Convenience: only inactive with class and arm names
  Future<List<Map<String, dynamic>>> getInactiveStudents() async {
    final db = await database;
    return db.rawQuery('''
      SELECT
        s.*,
        c.name as className,
        a.name as armName
      FROM students s
      LEFT JOIN classes c ON s.classId = c.id
      LEFT JOIN arms a ON s.armId = a.id
      WHERE s.isActive = 0
      ORDER BY s.surname ASC, s.firstName ASC
    ''');
  }

  Future<Map<String, dynamic>?> getStudentById(int id) async {
    final db = await database;
    final rows = await db.query('students',
        where: 'id = ?', whereArgs: [id], limit: 1);
    return rows.isNotEmpty ? rows.first : null;
  }

  Future<int> updateStudent(int id, Map<String, dynamic> student) async {
    final db = await database;
    return db.update('students', student,
        where: 'id = ?', whereArgs: [id]);
  }

  Future<int> deleteStudent(int id) async {
    final db = await database;
    return db.delete('students', where: 'id = ?', whereArgs: [id]);
  }

  // deactivateStudent: marks student as inactive
  Future<int> deactivateStudent(int studentId, String leftDate, String leftReason) async {
    final db = await database;
    return db.update(
      'students',
      {
        'isActive': 0,
        'leftDate': leftDate,
        'leftReason': leftReason,
      },
      where: 'id = ?',
      whereArgs: [studentId],
    );
  }

  // restoreStudent: reactivates student
  Future<int> restoreStudent(int studentId) async {
    final db = await database;
    return db.update(
      'students',
      {
        'isActive': 1,
        'leftDate': null,
        'leftReason': null,
      },
      where: 'id = ?',
      whereArgs: [studentId],
    );
  }

  // Generate admission number: FORMAT = SHORTNAME/YEAR/SERIAL
  // Example: DAWOT/2025/0001
  Future<String> generateAdmissionNumber() async {
    final db = await database;
    
    // Get school short name
    final profile = await getSchoolProfile();
    String shortName = profile?['shortName'] as String? ?? 'SCH';
    shortName = shortName.toUpperCase().trim();
    if (shortName.isEmpty) shortName = 'SCH';
    
    // Get active session year (e.g., "2025/2026" -> "2025")
    final session = await getActiveSession();
    String sessionYear = '2025';
    if (session != null) {
      final sessionName = session['sessionName'] as String? ?? '2025/2026';
      final parts = sessionName.split('/');
      if (parts.isNotEmpty) {
        sessionYear = parts[0].trim();
      }
    }
    
    final restartPerSession = await AdmissionSettingsHelper.isRestartSerialPerSession();

    int maxSerial;
    if (restartPerSession) {
      // Serial restarts at 1 whenever the session year in the admission
      // number changes, so only look at numbers from the current prefix.
      final prefix = '$shortName/$sessionYear/';
      // Escape LIKE wildcards that may appear in the school short name.
      final escapedPrefix = prefix.replaceAll('\\', '\\\\').replaceAll('%', '\\%').replaceAll('_', '\\_');
      final result = await db.rawQuery(
        "SELECT MAX(CAST(SUBSTR(admissionNo, LENGTH(?) + 1) AS INTEGER)) as maxSerial FROM students WHERE admissionNo LIKE ? ESCAPE '\\'",
        [prefix, '$escapedPrefix%'],
      );
      maxSerial = (result.first['maxSerial'] as int?) ?? 0;
    } else {
      // Get max serial across ALL admission numbers to avoid collisions on deletion
      final result = await db.rawQuery(
        "SELECT MAX(CAST(SUBSTR(admissionNo, INSTR(SUBSTR(admissionNo, INSTR(admissionNo, '/') + 1), '/') + INSTR(admissionNo, '/') + 1) AS INTEGER)) as maxSerial FROM students"
      );
      maxSerial = (result.first['maxSerial'] as int?) ?? 0;
    }

    final nextNumber = maxSerial + 1;
    final serial = nextNumber.toString().padLeft(4, '0');

    return '$shortName/$sessionYear/$serial';
  }

  // ------------------------------------------------------------------
  // PARENTS
  // ------------------------------------------------------------------
  Future<int> insertParent(Map<String, dynamic> parent) async {
    final db = await database;
    final now = DateTime.now().toIso8601String();
    parent['createdAt'] = now;
    parent['updatedAt'] = now;
    return db.insert('parents', parent);
  }

  Future<List<Map<String, dynamic>>> getAllParents() async {
    final db = await database;
    return db.query('parents', orderBy: 'parentName ASC');
  }

  Future<Map<String, dynamic>?> getParentById(int id) async {
    final db = await database;
    final rows = await db.query('parents',
        where: 'id = ?', whereArgs: [id], limit: 1);
    return rows.isNotEmpty ? rows.first : null;
  }

  Future<List<Map<String, dynamic>>> searchParents(String query) async {
    final db = await database;
    final searchQuery = '%$query%';
    return db.query(
      'parents',
      where: 'parentName LIKE ? OR phoneNumber LIKE ? OR phoneNumber2 LIKE ? OR emailAddress LIKE ?',
      whereArgs: [searchQuery, searchQuery, searchQuery, searchQuery],
      orderBy: 'parentName ASC',
    );
  }

  Future<int> updateParent(int id, Map<String, dynamic> parent) async {
    final db = await database;
    parent['updatedAt'] = DateTime.now().toIso8601String();
    return db.update('parents', parent,
        where: 'id = ?', whereArgs: [id]);
  }

  Future<int> deleteParent(int id) async {
    final db = await database;
    return db.delete('parents', where: 'id = ?', whereArgs: [id]);
  }

  /// PUBLIC: Manually run parent data migration (useful after backup restore)
  /// Call this from the UI to populate parents table from existing student data
  Future<int> migrateParentDataFromStudents() async {
    final db = await database;
    return await _migrateParentDataFromStudents(db);
  }

  /// PRIVATE: Migrate existing parent data from students table to parents table
  /// This extracts unique parent records based on phone number and name
  /// Returns the number of parents migrated
  Future<int> _migrateParentDataFromStudents(Database db) async {
    try {
      final now = DateTime.now().toIso8601String();

      // Get all unique parent data from students table (group by phone number)
      final students = await db.rawQuery('''
        SELECT DISTINCT
          parentName,
          parentPhone,
          parentEmail,
          parentAddress
        FROM students
        WHERE parentName IS NOT NULL
          AND parentName != ''
          AND parentPhone IS NOT NULL
          AND parentPhone != ''
        GROUP BY parentPhone, parentName
        ORDER BY parentName ASC
      ''');

      int migratedCount = 0;
      for (final student in students) {
        final parentName = student['parentName'] as String?;
        final phoneNumber = student['parentPhone'] as String?;
        final emailAddress = student['parentEmail'] as String?;
        final homeAddress = student['parentAddress'] as String?;

        if (parentName == null || parentName.isEmpty ||
            phoneNumber == null || phoneNumber.isEmpty) {
          continue;
        }

        // Check if parent already exists (by phone number and name)
        final existing = await db.query(
          'parents',
          where: 'phoneNumber = ? AND parentName = ?',
          whereArgs: [phoneNumber, parentName],
          limit: 1,
        );

        if (existing.isEmpty) {
          // Insert new parent record
          await db.insert('parents', {
            'parentName': parentName,
            'phoneNumber': phoneNumber,
            'phoneNumber2': null,
            'homeAddress': homeAddress ?? '',
            'occupation': null,
            'officeAddress': null,
            'emailAddress': emailAddress,
            'createdAt': now,
            'updatedAt': now,
          });
          migratedCount++;
        }
      }

      print('✅ Migrated $migratedCount unique parent records from students table');
      return migratedCount;
    } catch (e) {
      print('⚠️ Error migrating parent data: $e');
      // Don't throw - migration failure shouldn't break database upgrade
      return 0;
    }
  }

  // ------------------------------------------------------------------
  // CLASSES
  // ------------------------------------------------------------------
  Future<int> insertClass(Map<String, dynamic> cls) async {
    final db = await database;
    return db.insert('classes', cls);
  }

  Future<List<Map<String, dynamic>>> getClasses() async {
    final db = await database;
    return db.query('classes', orderBy: 'name ASC');
  }

  Future<int> updateClass(int id, Map<String, dynamic> cls) async {
    final db = await database;
    return db.update('classes', cls, where: 'id = ?', whereArgs: [id]);
  }

  Future<int> deleteClass(int id) async {
    final db = await database;
    return db.delete('classes', where: 'id = ?', whereArgs: [id]);
  }

  // ------------------------------------------------------------------
  // ARMS
  // ------------------------------------------------------------------
  Future<int> insertArm(Map<String, dynamic> arm) async {
    final db = await database;
    return db.insert('arms', arm);
  }

  Future<List<Map<String, dynamic>>> getArmsByClass(int classId) async {
    final db = await database;
    return db.query('arms',
        where: 'classId = ?', whereArgs: [classId], orderBy: 'name ASC');
  }

  // Get all arms
  Future<List<Map<String, dynamic>>> getArms() async {
    final db = await database;
    return db.query('arms', orderBy: 'classId ASC, name ASC');
  }

  Future<int> updateArm(int id, Map<String, dynamic> arm) async {
    final db = await database;
    return db.update('arms', arm, where: 'id = ?', whereArgs: [id]);
  }

  Future<int> deleteArm(int id) async {
    final db = await database;
    return db.delete('arms', where: 'id = ?', whereArgs: [id]);
  }

  // ------------------------------------------------------------------
  // FEE ITEMS
  // ------------------------------------------------------------------
  Future<int> insertFeeItem(Map<String, dynamic> item) async {
    final db = await database;
    return db.insert('fee_items', item);
  }

  Future<List<Map<String, dynamic>>> getFeeItems({String? term, String? session}) async {
    final db = await database;

    if (term == null && session == null) {
      return db.query('fee_items', orderBy: 'name ASC');
    }

    String where = '';
    List<dynamic> whereArgs = [];

    if (term != null) {
      where = 'term = ?';
      whereArgs.add(term);
    }

    if (session != null) {
      if (where.isNotEmpty) {
        where += ' AND ';
      }
      where += 'session = ?';
      whereArgs.add(session);
    }

    return db.query(
      'fee_items',
      where: where.isNotEmpty ? where : null,
      whereArgs: whereArgs.isNotEmpty ? whereArgs : null,
      orderBy: 'name ASC',
    );
  }

  Future<int> updateFeeItem(int id, Map<String, dynamic> item) async {
    final db = await database;
    return db.update('fee_items', item,
        where: 'id = ?', whereArgs: [id]);
  }

  Future<int> deleteFeeItem(int id) async {
    final db = await database;
    return db.delete('fee_items', where: 'id = ?', whereArgs: [id]);
  }

  // ------------------------------------------------------------------
  // CLASS FEES
  // ------------------------------------------------------------------
  Future<int> insertClassFee(Map<String, dynamic> classFee) async {
    final db = await database;
    return db.insert('class_fees', classFee);
  }

  Future<List<Map<String, dynamic>>> getClassFees(int classId, String term, String session, {int? armId}) async {
    final db = await database;

    String where;
    List<dynamic> whereArgs;

    if (armId != null) {
      // Get fees for specific arm
      where = 'classId = ? AND term = ? AND session = ? AND armId = ?';
      whereArgs = [classId, term, session, armId];
    } else {
      // Get fees for class without arm or with null armId
      where = 'classId = ? AND term = ? AND session = ? AND (armId IS NULL OR armId = 0)';
      whereArgs = [classId, term, session];
    }

    return db.query('class_fees',
        where: where,
        whereArgs: whereArgs);
  }

  Future<int> deleteClassFee(int id) async {
    final db = await database;
    return db.delete('class_fees', where: 'id = ?', whereArgs: [id]);
  }

  // replaceClassFeesFor: removes old fees and inserts new ones
  Future<void> replaceClassFeesFor(int classId, String term, String session, List<Map<String, dynamic>> fees, {int? armId}) async {
    final db = await database;

    await db.transaction((txn) async {
      // Delete existing fees for this class/term/session/arm
      String deleteWhere;
      List<dynamic> deleteArgs;

      if (armId != null) {
        deleteWhere = 'classId = ? AND term = ? AND session = ? AND armId = ?';
        deleteArgs = [classId, term, session, armId];
      } else {
        deleteWhere = 'classId = ? AND term = ? AND session = ? AND (armId IS NULL OR armId = 0)';
        deleteArgs = [classId, term, session];
      }

      await txn.delete(
        'class_fees',
        where: deleteWhere,
        whereArgs: deleteArgs,
      );

      // Insert new fees
      for (var fee in fees) {
        await txn.insert('class_fees', {
          'classId': classId,
          'armId': armId ?? 0,
          'feeItemId': fee['feeItemId'],
          'amount': fee['amount'],
          'term': term,
          'session': session,
        });
      }
    });
  }

  // ------------------------------------------------------------------
  // SPECIAL FEE ITEMS (for new intake students)
  // ------------------------------------------------------------------
  Future<int> insertSpecialFeeItem(Map<String, dynamic> item) async {
    final db = await database;
    return db.insert('special_fee_items', item);
  }

  Future<List<Map<String, dynamic>>> getSpecialFeeItems({String? term, String? session, bool? parentsOnly, int? parentId, bool? categoriesOnly, bool? standaloneOnly}) async {
    final db = await database;

    String where = '';
    List<dynamic> args = [];

    // Build where clause
    List<String> conditions = [];

    if (term != null && session != null) {
      conditions.add('term = ? AND session = ?');
      args.addAll([term, session]);
    } else if (term != null) {
      conditions.add('term = ?');
      args.add(term);
    } else if (session != null) {
      conditions.add('session = ?');
      args.add(session);
    }

    // Filter for parent items only (categories)
    if (parentsOnly == true) {
      conditions.add('parentId IS NULL');
    }

    // Filter for children of a specific parent
    if (parentId != null) {
      conditions.add('parentId = ?');
      args.add(parentId);
    }

    // Filter for categories only (isCategory = 1)
    if (categoriesOnly == true) {
      conditions.add('isCategory = 1');
    }

    // Filter for standalone items only (parentId IS NULL AND isCategory = 0)
    if (standaloneOnly == true) {
      conditions.add('parentId IS NULL AND isCategory = 0');
    }

    if (conditions.isNotEmpty) {
      where = conditions.join(' AND ');
    }

    return db.query(
      'special_fee_items',
      where: where.isNotEmpty ? where : null,
      whereArgs: args.isNotEmpty ? args : null,
      orderBy: 'parentId ASC, name ASC',
    );
  }

  // Get parent items (categories) only
  Future<List<Map<String, dynamic>>> getSpecialFeeItemParents({String? term, String? session}) async {
    return getSpecialFeeItems(term: term, session: session, parentsOnly: true);
  }

  // Get categories only (items marked as isCategory = 1)
  Future<List<Map<String, dynamic>>> getSpecialFeeItemCategories({String? term, String? session}) async {
    return getSpecialFeeItems(term: term, session: session, parentsOnly: true, categoriesOnly: true);
  }

  // Get standalone items only (parentId IS NULL AND isCategory = 0)
  Future<List<Map<String, dynamic>>> getSpecialFeeItemStandalone({String? term, String? session}) async {
    return getSpecialFeeItems(term: term, session: session, standaloneOnly: true);
  }

  // Get child items for a specific parent
  Future<List<Map<String, dynamic>>> getSpecialFeeItemChildren(int parentId, {String? term, String? session}) async {
    return getSpecialFeeItems(term: term, session: session, parentId: parentId);
  }

  // Check if an item has children
  Future<bool> specialFeeItemHasChildren(int itemId) async {
    final db = await database;
    final result = await db.rawQuery(
      'SELECT COUNT(*) as count FROM special_fee_items WHERE parentId = ?',
      [itemId],
    );
    return (result.first['count'] as int) > 0;
  }

  // Get special fee items with hierarchy (parents with their children)
  Future<List<Map<String, dynamic>>> getSpecialFeeItemsHierarchy({String? term, String? session}) async {
    final db = await database;

    String whereClause = '';
    List<dynamic> args = [];

    if (term != null && session != null) {
      whereClause = 'WHERE term = ? AND session = ?';
      args = [term, session];
    }

    // Get all items ordered by parent first, then children
    final items = await db.rawQuery('''
      SELECT * FROM special_fee_items
      $whereClause
      ORDER BY
        CASE WHEN parentId IS NULL THEN 0 ELSE 1 END,
        COALESCE(parentId, id),
        name ASC
    ''', args);

    return items;
  }

  Future<int> updateSpecialFeeItem(int id, Map<String, dynamic> item) async {
    final db = await database;
    return db.update('special_fee_items', item,
        where: 'id = ?', whereArgs: [id]);
  }

  Future<int> deleteSpecialFeeItem(int id) async {
    final db = await database;
    // Also delete any class fee assignments for this special fee item
    await db.delete('special_class_fees', where: 'specialFeeItemId = ?', whereArgs: [id]);
    return db.delete('special_fee_items', where: 'id = ?', whereArgs: [id]);
  }

  // ------------------------------------------------------------------
  // SPECIAL CLASS FEES (special fee assignments for new intake)
  // ------------------------------------------------------------------
  Future<int> insertSpecialClassFee(Map<String, dynamic> classFee) async {
    final db = await database;
    return db.insert('special_class_fees', classFee);
  }

  Future<List<Map<String, dynamic>>> getSpecialClassFees(int classId, String term, String session, {int? armId}) async {
    final db = await database;

    String where;
    List<dynamic> whereArgs;

    if (armId != null) {
      // Get fees for specific arm
      where = 'classId = ? AND term = ? AND session = ? AND armId = ?';
      whereArgs = [classId, term, session, armId];
    } else {
      // Get fees for class without arm or with null armId
      where = 'classId = ? AND term = ? AND session = ? AND (armId IS NULL OR armId = 0)';
      whereArgs = [classId, term, session];
    }

    return db.query('special_class_fees',
        where: where,
        whereArgs: whereArgs);
  }

  Future<int> deleteSpecialClassFee(int id) async {
    final db = await database;
    return db.delete('special_class_fees', where: 'id = ?', whereArgs: [id]);
  }

  // replaceSpecialClassFeesFor: removes old special fees and inserts new ones
  Future<void> replaceSpecialClassFeesFor(int classId, String term, String session, List<Map<String, dynamic>> fees, {int? armId}) async {
    final db = await database;

    await db.transaction((txn) async {
      // Delete existing special fees for this class/term/session/arm
      String deleteWhere;
      List<dynamic> deleteArgs;

      if (armId != null) {
        deleteWhere = 'classId = ? AND term = ? AND session = ? AND armId = ?';
        deleteArgs = [classId, term, session, armId];
      } else {
        deleteWhere = 'classId = ? AND term = ? AND session = ? AND (armId IS NULL OR armId = 0)';
        deleteArgs = [classId, term, session];
      }

      await txn.delete(
        'special_class_fees',
        where: deleteWhere,
        whereArgs: deleteArgs,
      );

      // Insert new special fees
      for (var fee in fees) {
        await txn.insert('special_class_fees', {
          'classId': classId,
          'armId': armId ?? 0,
          'specialFeeItemId': fee['specialFeeItemId'],
          'amount': fee['amount'],
          'term': term,
          'session': session,
        });
      }
    });
  }

  // Get combined new intake bill (regular fees + special fees) for a class
  // Excludes fees that have been marked as excluded from new intake bills
  Future<Map<String, dynamic>> getNewIntakeBillForClass(int classId, String term, String session, {int? armId}) async {
    final db = await database;

    // Get excluded default fees for this class
    Set<int> excludedFeeIds = {};
    try {
      final excludedFees = await db.query(
        'excluded_default_fees',
        where: 'classId = ? AND term = ? AND session = ?',
        whereArgs: [classId, term, session],
      );
      excludedFeeIds = excludedFees.map((e) => e['classFeeId'] as int).toSet();
    } catch (e) {
      // Table might not exist yet, ignore
    }

    // Get regular class fees with fee item names
    List<Map<String, dynamic>> allRegularFees;
    if (armId != null) {
      // Filter by specific arm
      allRegularFees = await db.rawQuery('''
        SELECT cf.id, cf.feeItemId, cf.amount, fi.name as feeItemName
        FROM class_fees cf
        LEFT JOIN fee_items fi ON cf.feeItemId = fi.id
        WHERE cf.classId = ? AND cf.term = ? AND cf.session = ? AND cf.armId = ?
        ORDER BY fi.name ASC
      ''', [classId, term, session, armId]);
    } else {
      // No arm filter
      allRegularFees = await db.rawQuery('''
        SELECT cf.id, cf.feeItemId, cf.amount, fi.name as feeItemName
        FROM class_fees cf
        LEFT JOIN fee_items fi ON cf.feeItemId = fi.id
        WHERE cf.classId = ? AND cf.term = ? AND cf.session = ?
        ORDER BY fi.name ASC
      ''', [classId, term, session]);
    }

    // Filter out excluded fees
    final regularFees = allRegularFees.where((fee) {
      final feeId = fee['id'] as int;
      return !excludedFeeIds.contains(feeId);
    }).toList();

    // Get special class fees with special fee item names
    List<Map<String, dynamic>> specialFees;
    if (armId != null) {
      // Filter by specific arm
      specialFees = await db.rawQuery('''
        SELECT scf.id, scf.specialFeeItemId, scf.amount, sfi.name as feeItemName
        FROM special_class_fees scf
        LEFT JOIN special_fee_items sfi ON scf.specialFeeItemId = sfi.id
        WHERE scf.classId = ? AND scf.term = ? AND scf.session = ? AND scf.armId = ?
        ORDER BY sfi.name ASC
      ''', [classId, term, session, armId]);
    } else {
      // No arm filter
      specialFees = await db.rawQuery('''
        SELECT scf.id, scf.specialFeeItemId, scf.amount, sfi.name as feeItemName
        FROM special_class_fees scf
        LEFT JOIN special_fee_items sfi ON scf.specialFeeItemId = sfi.id
        WHERE scf.classId = ? AND scf.term = ? AND scf.session = ?
        ORDER BY sfi.name ASC
      ''', [classId, term, session]);
    }

    // Calculate totals
    double regularTotal = 0;
    for (var fee in regularFees) {
      regularTotal += (fee['amount'] as num?)?.toDouble() ?? 0;
    }

    double specialTotal = 0;
    for (var fee in specialFees) {
      specialTotal += (fee['amount'] as num?)?.toDouble() ?? 0;
    }

    return {
      'regularFees': regularFees,
      'specialFees': specialFees,
      'regularTotal': regularTotal,
      'specialTotal': specialTotal,
      'grandTotal': regularTotal + specialTotal,
    };
  }

  // ------------------------------------------------------------------
  // BILLS
  // ------------------------------------------------------------------
  Future<int> insertBill(Map<String, dynamic> bill, List<Map<String, dynamic>> breakdown) async {
    final db = await database;
    final studentId = bill['studentId'];
    final term = bill['term'];
    final session = bill['session'];

    final existing = await db.rawQuery('''
      SELECT id FROM student_bills
      WHERE studentId = ? AND term = ? AND session = ?
      LIMIT 1
    ''', [studentId, term, session]);

    return await db.transaction((txn) async {
      int billId;

      if (existing.isNotEmpty) {
        // override existing
        billId = existing.first['id'] as int;

        await txn.update('student_bills', {
          'totalAmount': bill['totalAmount'],
          'previousBalance': bill['previousBalance'] ?? 0,
          'billDate': bill['billDate'],
        }, where: 'id = ?', whereArgs: [billId]);

        await txn.delete('student_fee_breakdown', where: 'billId = ?', whereArgs: [billId]);
      } else {
        // new bill
        billId = await txn.insert('student_bills', bill);
      }

      for (final b in breakdown) {
        await txn.insert('student_fee_breakdown', {
          'billId': billId,
          'feeItemId': b['feeItemId'],
          'amount': b['amount'],
          'label': b['label'],
        });
      }

      return billId;
    });
  }

  // Alias for insertBill
  Future<int> insertStudentBill(Map<String, dynamic> bill, List<Map<String, dynamic>> breakdown) async {
    return insertBill(bill, breakdown);
  }

  // ------------------------------------------------------------------
  // getBillForStudent
  // ------------------------------------------------------------------
  Future<Map<String, dynamic>?> getBillForStudent(int studentId, String term, String session) async {
    final db = await database;
    final rows = await db.query('student_bills', where: 'studentId = ? AND term = ? AND session = ?', whereArgs: [studentId, term, session], orderBy: 'id DESC', limit: 1);
    return rows.isNotEmpty ? rows.first : null;
  }

  // ------------------------------------------------------------------
  // getBillBreakdown
  // ------------------------------------------------------------------
  Future<List<Map<String, dynamic>>> getBillBreakdown(int billId) async {
    final db = await database;
    return db.query('student_fee_breakdown', where: 'billId = ?', whereArgs: [billId], orderBy: 'id ASC');
  }

  // ------------------------------------------------------------------
  // computeOutstandingForTermSession (already existed)
  // ------------------------------------------------------------------
  Future<double> computeOutstandingForTermSession(int studentId, {required String term, required String session}) async {
    final db = await database;

    // Use (totalAmount - previousBalance) to get only the actual fee items for this
    // specific term — excluding any baked-in carry-over that was snapshotted at
    // bill-generation time and would otherwise compound each term.
    final bill = await db.rawQuery(
      'SELECT COALESCE(SUM(totalAmount - previousBalance), 0) AS t FROM student_bills WHERE studentId = ? AND term = ? AND session = ?',
      [studentId, term, session],
    );
    final pay = await db.rawQuery(
      'SELECT COALESCE(SUM(amount), 0) AS t FROM payments WHERE studentId = ? AND term = ? AND session = ?',
      [studentId, term, session],
    );

    final totalBills = (bill.first['t'] ?? 0) as num;
    final totalPays = (pay.first['t'] ?? 0) as num;

    return (totalBills - totalPays).toDouble();
  }

  // ------------------------------------------------------------------
  // TRANSPORTATION
  // ------------------------------------------------------------------
  static const String _kTransportFeeItemName = 'Transportation';

  Future<List<Map<String, dynamic>>> getTransportRoutes({bool includeInactive = false}) async {
    final db = await database;
    if (includeInactive) {
      return db.query('transport_routes', orderBy: 'name ASC');
    }
    return db.query('transport_routes', where: 'isActive = 1', orderBy: 'name ASC');
  }

  Future<Map<String, dynamic>?> getTransportRouteById(int id) async {
    final db = await database;
    final rows = await db.query('transport_routes', where: 'id = ?', whereArgs: [id], limit: 1);
    return rows.isNotEmpty ? rows.first : null;
  }

  Future<int> insertTransportRoute(Map<String, dynamic> data) async {
    final db = await database;
    return db.insert('transport_routes', {
      ...data,
      'createdAt': DateTime.now().toIso8601String(),
    });
  }

  Future<int> updateTransportRoute(int id, Map<String, dynamic> data) async {
    final db = await database;
    return db.update(
      'transport_routes',
      {...data, 'updatedAt': DateTime.now().toIso8601String()},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<int> deleteTransportRoute(int id) async {
    final db = await database;
    return db.delete('transport_routes', where: 'id = ?', whereArgs: [id]);
  }

  Future<int> countActiveAllocationsForRoute(int routeId) async {
    final db = await database;
    final rows = await db.rawQuery(
      'SELECT COUNT(*) AS c FROM student_transport_allocations WHERE routeId = ?',
      [routeId],
    );
    return (rows.first['c'] as num?)?.toInt() ?? 0;
  }

  Future<Map<String, dynamic>?> getStudentTransportAllocation(int studentId, String term, String session) async {
    final db = await database;
    final rows = await db.rawQuery('''
      SELECT sta.*, tr.name AS routeName, tr.description AS routeDescription, tr.fare AS routeFare
      FROM student_transport_allocations sta
      JOIN transport_routes tr ON sta.routeId = tr.id
      WHERE sta.studentId = ? AND sta.term = ? AND sta.session = ?
      LIMIT 1
    ''', [studentId, term, session]);
    return rows.isNotEmpty ? rows.first : null;
  }

  Future<List<Map<String, dynamic>>> getRouteAllocationsWithDetails(String term, String session) async {
    final db = await database;
    return db.rawQuery('''
      SELECT sta.id, sta.studentId, sta.routeId, sta.billId, sta.fareCharged, sta.term, sta.session,
             s.surname, s.firstName, s.admissionNo,
             c.name AS className, a.name AS armName,
             tr.name AS routeName, tr.fare AS routeFare
      FROM student_transport_allocations sta
      JOIN students s ON sta.studentId = s.id
      JOIN transport_routes tr ON sta.routeId = tr.id
      LEFT JOIN classes c ON s.classId = c.id
      LEFT JOIN arms a ON s.armId = a.id
      WHERE sta.term = ? AND sta.session = ? AND s.isActive = 1
      ORDER BY tr.name ASC, s.surname ASC, s.firstName ASC
    ''', [term, session]);
  }

  /// Finds the shared "Transportation" fee item, creating it if it doesn't exist yet.
  Future<int> _getOrCreateTransportFeeItemId(DatabaseExecutor txn) async {
    final existing = await txn.query(
      'fee_items',
      where: 'name = ?',
      whereArgs: [_kTransportFeeItemName],
      limit: 1,
    );
    if (existing.isNotEmpty) return existing.first['id'] as int;
    return txn.insert('fee_items', {
      'name': _kTransportFeeItemName,
      'defaultAmount': 0,
      'description': 'Auto-generated fee item for transportation route charges',
    });
  }

  /// Allocates a student to a route for the given term/session, adding the
  /// route's fare as a line item on the student's existing bill. Throws a
  /// [StateError] if the student has no bill for that term/session yet.
  Future<int> allocateStudentToRoute({
    required int studentId,
    required int routeId,
    required String term,
    required String session,
  }) async {
    final db = await database;

    final route = await getTransportRouteById(routeId);
    if (route == null || route['isActive'] != 1) {
      throw StateError('Selected route is not available.');
    }
    final fare = (route['fare'] as num).toDouble();

    final bill = await getBillForStudent(studentId, term, session);
    if (bill == null) {
      throw StateError(
        'No bill found for this student in $term, $session. Generate their bill first.',
      );
    }
    final billId = bill['id'] as int;

    return db.transaction((txn) async {
      final feeItemId = await _getOrCreateTransportFeeItemId(txn);

      // If already allocated for this term/session, reverse the previous charge first.
      final existingAlloc = await txn.query(
        'student_transport_allocations',
        where: 'studentId = ? AND term = ? AND session = ?',
        whereArgs: [studentId, term, session],
        limit: 1,
      );
      if (existingAlloc.isNotEmpty) {
        final prev = existingAlloc.first;
        final prevBillId = prev['billId'] as int;
        final prevFare = (prev['fareCharged'] as num).toDouble();
        await txn.delete(
          'student_fee_breakdown',
          where: 'billId = ? AND feeItemId = ?',
          whereArgs: [prevBillId, feeItemId],
        );
        await txn.rawUpdate(
          'UPDATE student_bills SET totalAmount = totalAmount - ? WHERE id = ?',
          [prevFare, prevBillId],
        );
        await txn.delete('student_transport_allocations', where: 'id = ?', whereArgs: [prev['id']]);
      }

      await txn.insert('student_fee_breakdown', {
        'billId': billId,
        'feeItemId': feeItemId,
        'amount': fare,
        'label': 'Transportation - ${route['name']}',
      });
      await txn.rawUpdate(
        'UPDATE student_bills SET totalAmount = totalAmount + ? WHERE id = ?',
        [fare, billId],
      );

      return txn.insert('student_transport_allocations', {
        'studentId': studentId,
        'routeId': routeId,
        'billId': billId,
        'fareCharged': fare,
        'term': term,
        'session': session,
        'createdAt': DateTime.now().toIso8601String(),
      });
    });
  }

  /// Removes a student's route allocation for the given term/session,
  /// removing the "Transportation" line from their bill and deducting the
  /// charged fare from the bill total. No-op if no allocation exists.
  Future<int> removeStudentFromRoute(int studentId, String term, String session) async {
    final db = await database;

    final allocRows = await db.query(
      'student_transport_allocations',
      where: 'studentId = ? AND term = ? AND session = ?',
      whereArgs: [studentId, term, session],
      limit: 1,
    );
    if (allocRows.isEmpty) return 0;
    final alloc = allocRows.first;
    final billId = alloc['billId'] as int;
    final fareCharged = (alloc['fareCharged'] as num).toDouble();

    return db.transaction((txn) async {
      final feeItemId = await _getOrCreateTransportFeeItemId(txn);
      await txn.delete(
        'student_fee_breakdown',
        where: 'billId = ? AND feeItemId = ?',
        whereArgs: [billId, feeItemId],
      );
      await txn.rawUpdate(
        'UPDATE student_bills SET totalAmount = MAX(totalAmount - ?, previousBalance) WHERE id = ?',
        [fareCharged, billId],
      );
      return txn.delete('student_transport_allocations', where: 'id = ?', whereArgs: [alloc['id']]);
    });
  }

  // ------------------------------------------------------------------
  // Chronological sort key helpers
  // Prevents future-term bills from leaking into "prior balance" when bills
  // are generated out of order or the active term is rolled back.
  // ------------------------------------------------------------------

  /// Returns an integer sort key: year*3 + termIndex (1st=0, 2nd=1, 3rd=2).
  static int termSortKey(String term, String session) {
    final year = int.tryParse(session.split('/').first.trim()) ?? 0;
    final t = term.trim().toLowerCase();
    final idx = t.startsWith('1') || t.contains('first')  ? 0
              : t.startsWith('2') || t.contains('second') ? 1
              : t.startsWith('3') || t.contains('third')  ? 2
              : 1;
    return year * 3 + idx;
  }

  /// Returns a SQL expression that computes the chronological sort key for
  /// a row in [alias]-prefixed columns (empty string for bare column names).
  static String _sqlTermKey([String alias = '']) {
    final p = alias.isEmpty ? '' : '$alias.';
    return "(CAST(SUBSTR(${p}session, 1, 4) AS INTEGER) * 3 + "
           "CASE LOWER(TRIM(${p}term)) "
           "WHEN '1st term' THEN 0 WHEN '1st' THEN 0 WHEN 'first term' THEN 0 WHEN 'first' THEN 0 "
           "WHEN '2nd term' THEN 1 WHEN '2nd' THEN 1 WHEN 'second term' THEN 1 WHEN 'second' THEN 1 "
           "WHEN '3rd term' THEN 2 WHEN '3rd' THEN 2 WHEN 'third term' THEN 2 WHEN 'third' THEN 2 "
           "ELSE 1 END)";
  }

  // ------------------------------------------------------------------
  // computeOutstandingBeforeTerm – Option A carry-over logic
  // ------------------------------------------------------------------
  Future<double> computeOutstandingBeforeTerm(int studentId, {required String term, required String session}) async {
    final db = await database;

    // Use chronological sort key so only genuinely earlier terms are included.
    final targetKey = termSortKey(term, session);
    final bills = await db.rawQuery(
      'SELECT COALESCE(SUM(totalAmount - previousBalance), 0) AS t FROM student_bills WHERE studentId = ? AND ${_sqlTermKey()} < ?',
      [studentId, targetKey],
    );
    final pays = await db.rawQuery(
      'SELECT COALESCE(SUM(amount), 0) AS t FROM payments WHERE studentId = ? AND ${_sqlTermKey()} < ?',
      [studentId, targetKey],
    );

    final totalFees = (bills.first['t'] ?? 0) as num;
    final totalPays = (pays.first['t'] ?? 0) as num;

    return (totalFees - totalPays).toDouble();
  }

  // ------------------------------------------------------------------
  // recalculatePreviousBalances – one-time repair utility
  // Fixes bills whose previousBalance was wrongly snapshotted at generation
  // time. For every bill: recomputes correctPrevBal as the true outstanding
  // across all prior terms (fee charges – payments), then updates both
  // previousBalance and totalAmount.
  // Returns the number of bills that were corrected.
  // ------------------------------------------------------------------
  Future<int> recalculatePreviousBalances() async {
    final db = await database;

    final bills = await db.rawQuery('''
      SELECT id, studentId, totalAmount, previousBalance, term, session
      FROM student_bills
      ORDER BY studentId, billDate ASC
    ''');

    int corrected = 0;

    await db.transaction((txn) async {
      for (final bill in bills) {
        final studentId = bill['studentId'] as int;
        final billId    = bill['id'] as int;
        final term      = bill['term'] as String;
        final session   = bill['session'] as String;

        // fee charges for this bill, independent of previousBalance
        final feeCharges = (bill['totalAmount'] as num).toDouble()
                         - (bill['previousBalance'] as num).toDouble();

        // correct previous balance = SUM of all prior fee charges – SUM of all prior payments
        final targetKey = termSortKey(term, session);
        final billsRes = await txn.rawQuery(
          'SELECT COALESCE(SUM(totalAmount - previousBalance), 0) AS t '
          'FROM student_bills '
          'WHERE studentId = ? AND ${_sqlTermKey()} < ?',
          [studentId, targetKey],
        );
        final paysRes = await txn.rawQuery(
          'SELECT COALESCE(SUM(amount), 0) AS t '
          'FROM payments '
          'WHERE studentId = ? AND ${_sqlTermKey()} < ?',
          [studentId, targetKey],
        );

        final correctPrevBal = ((billsRes.first['t'] ?? 0) as num).toDouble()
                             - ((paysRes.first['t'] ?? 0)  as num).toDouble();
        final clampedPrevBal = correctPrevBal < 0 ? 0.0 : correctPrevBal;
        final newTotal       = feeCharges + clampedPrevBal;

        final oldPrevBal = (bill['previousBalance'] as num).toDouble();
        if ((oldPrevBal - clampedPrevBal).abs() > 0.001) {
          await txn.rawUpdate(
            'UPDATE student_bills SET previousBalance = ?, totalAmount = ? WHERE id = ?',
            [clampedPrevBal, newTotal, billId],
          );
          corrected++;
        }
      }
    });

    return corrected;
  }

  // ------------------------------------------------------------------
  // PAYMENTS
  // ------------------------------------------------------------------
  Future<int> insertPayment(Map<String, dynamic> payment, {String? term, String? session}) async {
    final db = await database;

    final t = term ?? await getActiveTerm();
    final s = session ?? (await getActiveSession())?['sessionName'] ?? '';

    final payload = {
      'studentId': payment['studentId'],
      'amount': payment['amount'],
      'method': payment['method'],
      'note': payment['note'],
      'paymentDate': payment['paymentDate'],
      'term': t,
      'session': s,
      'paymentFor': payment['paymentFor'] ?? 'School Fees',
    };

    return db.insert('payments', payload);
  }

  Future<List<Map<String, dynamic>>> getPaymentsByExactDate(String date) async {
    final db = await database;
    return db.rawQuery('''
      SELECT * FROM payments
      WHERE paymentDate LIKE ?
      ORDER BY paymentDate DESC
    ''', ["$date%"]);
  }

  Future<List<Map<String, dynamic>>> getPayments(int studentId, {String? term, String? session}) async {
    final db = await database;

    final where = StringBuffer('studentId = ?');
    final args = <dynamic>[studentId];

    if (term != null) {
      where.write(' AND term = ?');
      args.add(term);
    }

    if (session != null) {
      where.write(' AND session = ?');
      args.add(session);
    }

    return db.query('payments', where: where.toString(), whereArgs: args, orderBy: 'paymentDate DESC');
  }

  // ------------------------------------------------------------------
  // EXPENSES
  // ------------------------------------------------------------------

  /// Insert new expense record
  Future<int> insertExpense(Map<String, dynamic> expense) async {
    final db = await database;

    final payload = {
      'amount': expense['amount'],
      'category': expense['category'],
      'customCategory': expense['customCategory'],
      'description': expense['description'],
      'expenseDate': expense['expenseDate'],
      'paymentMethod': expense['paymentMethod'],
      'recipient': expense['recipient'],
      'term': expense['term'],
      'session': expense['session'],
      'createdAt': expense['createdAt'] ?? DateTime.now().toIso8601String(),
      'createdBy': expense['createdBy'],
    };

    return db.insert('expenses', payload);
  }

  /// Get expenses by exact date (for daily report)
  Future<List<Map<String, dynamic>>> getExpensesByExactDate(String date) async {
    final db = await database;
    return db.rawQuery('''
      SELECT * FROM expenses
      WHERE expenseDate LIKE ?
      ORDER BY expenseDate DESC
    ''', ["$date%"]);
  }

  /// Get all expenses with optional term/session/date filter
  Future<List<Map<String, dynamic>>> getAllExpenses({
    String? term,
    String? session,
    String? startDate,
    String? endDate,
  }) async {
    final db = await database;

    List<String> whereConditions = [];
    List<dynamic> whereArgs = [];

    if (term != null) {
      whereConditions.add('term = ?');
      whereArgs.add(term);
    }

    if (session != null) {
      whereConditions.add('session = ?');
      whereArgs.add(session);
    }

    if (startDate != null) {
      whereConditions.add('expenseDate >= ?');
      whereArgs.add(startDate);
    }

    if (endDate != null) {
      whereConditions.add('expenseDate <= ?');
      whereArgs.add(endDate);
    }

    String? where;
    if (whereConditions.isNotEmpty) {
      where = whereConditions.join(' AND ');
    }

    return db.query(
      'expenses',
      where: where,
      whereArgs: whereArgs.isNotEmpty ? whereArgs : null,
      orderBy: 'expenseDate DESC',
    );
  }

  /// Get expense by ID
  Future<Map<String, dynamic>?> getExpenseById(int id) async {
    final db = await database;
    final rows = await db.query(
      'expenses',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    return rows.isNotEmpty ? rows.first : null;
  }

  /// Update expense
  Future<int> updateExpense(int id, Map<String, dynamic> expense) async {
    final db = await database;
    return db.update(
      'expenses',
      expense,
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Delete expense
  Future<int> deleteExpense(int id) async {
    final db = await database;
    return db.delete(
      'expenses',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Get expense totals by category for a date
  Future<Map<String, double>> getExpenseTotalsByCategory(String date) async {
    final db = await database;

    final results = await db.rawQuery('''
      SELECT category, customCategory, SUM(amount) as total
      FROM expenses
      WHERE expenseDate LIKE ?
      GROUP BY category, customCategory
    ''', ["$date%"]);

    final totals = <String, double>{};

    for (var row in results) {
      final category = row['category'] as String;
      final customCategory = row['customCategory'] as String?;
      final total = (row['total'] as num?)?.toDouble() ?? 0.0;

      final key = category == 'Other' && customCategory != null
          ? 'Other: $customCategory'
          : category;

      totals[key] = total;
    }

    return totals;
  }

  // ------------------------------------------------------------------
  // EXPENSE CATEGORIES
  // ------------------------------------------------------------------

  /// Get all expense categories ordered by name
  Future<List<Map<String, dynamic>>> getAllExpenseCategories() async {
    final db = await database;
    return db.query('expense_categories', orderBy: 'name ASC');
  }

  /// Insert a new expense category
  Future<int> insertExpenseCategory(String name) async {
    final db = await database;
    return db.insert('expense_categories', {
      'name': name.trim(),
      'isPreset': 0,
      'createdAt': DateTime.now().toIso8601String(),
    });
  }

  /// Update an expense category name
  Future<int> updateExpenseCategory(int id, String name) async {
    final db = await database;
    return db.update(
      'expense_categories',
      {'name': name.trim()},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Delete an expense category (only non-preset)
  Future<int> deleteExpenseCategory(int id) async {
    final db = await database;
    return db.delete(
      'expense_categories',
      where: 'id = ? AND isPreset = 0',
      whereArgs: [id],
    );
  }

  // ------------------------------------------------------------------
  // STOCK ITEMS
  // ------------------------------------------------------------------

  /// Insert new stock item
  Future<int> insertStockItem(Map<String, dynamic> item) async {
    final db = await database;
    final now = DateTime.now().toIso8601String();

    final payload = {
      'itemName': item['itemName'],
      'itemDescription': item['itemDescription'],
      'supplierName': item['supplierName'],
      'supplierContact': item['supplierContact'],
      'currentQuantity': item['currentQuantity'] ?? 0,
      'costPrice': item['costPrice'],
      'sellingPrice': item['sellingPrice'],
      'reorderLevel': item['reorderLevel'] ?? 0,
      'parentItemId': item['parentItemId'],
      'isParent': item['isParent'] ?? 0,
      'isActive': 1,
      'createdAt': now,
      'updatedAt': now,
    };

    return db.insert('stock_items', payload);
  }

  /// Get all active stock items
  Future<List<Map<String, dynamic>>> getStockItems({bool includeInactive = false}) async {
    final db = await database;

    if (includeInactive) {
      return db.query('stock_items', orderBy: 'itemName ASC');
    } else {
      return db.query(
        'stock_items',
        where: 'isActive = ?',
        whereArgs: [1],
        orderBy: 'itemName ASC',
      );
    }
  }

  /// Get stock item by ID
  Future<Map<String, dynamic>?> getStockItemById(int id) async {
    final db = await database;
    final rows = await db.query(
      'stock_items',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    return rows.isNotEmpty ? rows.first : null;
  }

  /// Update stock item
  Future<int> updateStockItem(int id, Map<String, dynamic> item) async {
    final db = await database;
    final now = DateTime.now().toIso8601String();

    item['updatedAt'] = now;

    return db.update(
      'stock_items',
      item,
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Deactivate stock item (soft delete)
  Future<int> deactivateStockItem(int id) async {
    final db = await database;
    return db.update(
      'stock_items',
      {'isActive': 0, 'updatedAt': DateTime.now().toIso8601String()},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Delete stock item (only if not used in any sales and has no children)
  Future<void> deleteStockItem(int stockItemId) async {
    final db = await database;

    // Check if stock item exists
    final stockItem = await getStockItemById(stockItemId);
    if (stockItem == null) {
      throw Exception('Stock item not found');
    }

    // Check if item is a parent with children
    final hasChildren = await hasChildItems(stockItemId);
    if (hasChildren) {
      throw Exception(
        'Cannot delete this item because it has child items under it. '
        'Please delete or reassign the child items first.',
      );
    }

    // Check if stock item has been used in any sales
    final salesCount = await db.rawQuery(
      'SELECT COUNT(*) as count FROM sales WHERE stockItemId = ?',
      [stockItemId],
    );
    final count = salesCount.first['count'] as int;

    if (count > 0) {
      throw Exception(
        'Cannot delete this stock item because it has $count sale(s) associated with it. '
        'You can deactivate it instead to hide it from the list.',
      );
    }

    // Delete stock movements first (foreign key constraint)
    await db.delete('stock_movements', where: 'stockItemId = ?', whereArgs: [stockItemId]);

    // Delete the stock item
    await db.delete('stock_items', where: 'id = ?', whereArgs: [stockItemId]);
  }

  /// Adjust stock quantity manually (with audit trail)
  Future<void> adjustStockQuantity(
    int stockItemId,
    int newQuantity,
    String note, {
    String? createdBy,
  }) async {
    final db = await database;
    final now = DateTime.now().toIso8601String();

    await db.transaction((txn) async {
      // Get current item
      final item = await txn.query(
        'stock_items',
        where: 'id = ?',
        whereArgs: [stockItemId],
        limit: 1,
      );

      if (item.isEmpty) throw Exception('Stock item not found');

      final currentQty = item.first['currentQuantity'] as int;
      final difference = newQuantity - currentQty;

      // Update stock quantity
      await txn.update(
        'stock_items',
        {'currentQuantity': newQuantity, 'updatedAt': now},
        where: 'id = ?',
        whereArgs: [stockItemId],
      );

      // Log movement
      await txn.insert('stock_movements', {
        'stockItemId': stockItemId,
        'movementType': 'Adjustment',
        'quantity': difference.abs(),
        'balanceAfter': newQuantity,
        'referenceType': 'Adjustment',
        'referenceId': null,
        'note': note,
        'movementDate': now,
        'createdBy': createdBy,
      });
    });
  }

  /// Restock an item (add inventory with purchase tracking)
  Future<void> restockItem(
    int stockItemId, {
    required int quantityAdded,
    required String supplier,
    String? invoiceNumber,
    double? newCostPrice,
    String? notes,
    String? createdBy,
  }) async {
    final db = await database;
    final now = DateTime.now().toIso8601String();

    await db.transaction((txn) async {
      // Get current item
      final item = await txn.query(
        'stock_items',
        where: 'id = ?',
        whereArgs: [stockItemId],
        limit: 1,
      );

      if (item.isEmpty) throw Exception('Stock item not found');

      final currentQty = item.first['currentQuantity'] as int;
      final newQuantity = currentQty + quantityAdded;

      // Prepare update data
      Map<String, dynamic> updateData = {
        'currentQuantity': newQuantity,
        'supplierName': supplier, // Update supplier
        'updatedAt': now,
      };

      // Update cost price if provided
      if (newCostPrice != null) {
        updateData['costPrice'] = newCostPrice;
      }

      // Update stock item
      await txn.update(
        'stock_items',
        updateData,
        where: 'id = ?',
        whereArgs: [stockItemId],
      );

      // Build detailed note
      String detailedNote = 'Restock from supplier: $supplier';
      if (invoiceNumber != null && invoiceNumber.isNotEmpty) {
        detailedNote += ' | Invoice: $invoiceNumber';
      }
      if (newCostPrice != null) {
        detailedNote += ' | New cost price: ₦$newCostPrice';
      }
      if (notes != null && notes.isNotEmpty) {
        detailedNote += ' | Notes: $notes';
      }

      // Log movement as "Restock" (different from "Adjustment")
      await txn.insert('stock_movements', {
        'stockItemId': stockItemId,
        'movementType': 'Restock',
        'quantity': quantityAdded,
        'balanceAfter': newQuantity,
        'referenceType': 'Purchase',
        'referenceId': null,
        'note': detailedNote,
        'movementDate': now,
        'createdBy': createdBy,
      });
    });
  }

  /// Get low stock items (below reorder level)
  Future<List<Map<String, dynamic>>> getLowStockItems() async {
    final db = await database;
    return db.rawQuery('''
      SELECT * FROM stock_items
      WHERE isActive = 1
        AND currentQuantity <= reorderLevel
      ORDER BY currentQuantity ASC
    ''');
  }

  // ------------------------------------------------------------------
  // PARENT-CHILD HIERARCHY METHODS
  // ------------------------------------------------------------------

  /// Get all parent items (categories)
  Future<List<Map<String, dynamic>>> getParentItems() async {
    final db = await database;
    return db.query(
      'stock_items',
      where: 'isParent = ? AND isActive = ?',
      whereArgs: [1, 1],
      orderBy: 'itemName ASC',
    );
  }

  /// Get child items for a specific parent
  Future<List<Map<String, dynamic>>> getChildItems(int parentId) async {
    final db = await database;
    return db.query(
      'stock_items',
      where: 'parentItemId = ? AND isActive = ?',
      whereArgs: [parentId, 1],
      orderBy: 'itemName ASC',
    );
  }

  /// Check if item has children (prevent deletion)
  Future<bool> hasChildItems(int itemId) async {
    final db = await database;
    final result = await db.query(
      'stock_items',
      where: 'parentItemId = ?',
      whereArgs: [itemId],
      limit: 1,
    );
    return result.isNotEmpty;
  }

  /// Validate parent-child relationship (prevent circular references)
  Future<bool> canSetAsParent(int itemId, int? proposedParentId) async {
    if (proposedParentId == null) return true;
    if (itemId == proposedParentId) return false; // Self-reference

    // Proposed parent cannot be a child of another item (only 1 level deep)
    final proposedParent = await getStockItemById(proposedParentId);
    if (proposedParent == null) return false;
    if (proposedParent['parentItemId'] != null) return false;

    return true;
  }

  // ------------------------------------------------------------------
  // SUPPLIERS
  // ------------------------------------------------------------------

  /// Insert a new supplier
  Future<int> insertSupplier(Map<String, dynamic> supplier) async {
    final db = await database;
    final now = DateTime.now().toIso8601String();

    final payload = {
      'supplierName': supplier['supplierName'],
      'contactPerson': supplier['contactPerson'],
      'phoneNumber': supplier['phoneNumber'],
      'email': supplier['email'],
      'address': supplier['address'],
      'notes': supplier['notes'],
      'isActive': 1,
      'createdAt': now,
      'updatedAt': now,
    };

    return db.insert('suppliers', payload);
  }

  /// Get all suppliers
  Future<List<Map<String, dynamic>>> getSuppliers({bool includeInactive = false}) async {
    final db = await database;

    if (includeInactive) {
      return db.query('suppliers', orderBy: 'supplierName ASC');
    }

    return db.query(
      'suppliers',
      where: 'isActive = ?',
      whereArgs: [1],
      orderBy: 'supplierName ASC',
    );
  }

  /// Get a supplier by ID
  Future<Map<String, dynamic>?> getSupplierById(int id) async {
    final db = await database;
    final results = await db.query(
      'suppliers',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );

    return results.isEmpty ? null : results.first;
  }

  /// Update a supplier
  Future<int> updateSupplier(int id, Map<String, dynamic> supplier) async {
    final db = await database;
    final now = DateTime.now().toIso8601String();

    final payload = {
      'supplierName': supplier['supplierName'],
      'contactPerson': supplier['contactPerson'],
      'phoneNumber': supplier['phoneNumber'],
      'email': supplier['email'],
      'address': supplier['address'],
      'notes': supplier['notes'],
      'updatedAt': now,
    };

    return db.update(
      'suppliers',
      payload,
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Delete a supplier (soft delete - set isActive to 0)
  Future<int> deactivateSupplier(int id) async {
    final db = await database;
    final now = DateTime.now().toIso8601String();

    return db.update(
      'suppliers',
      {'isActive': 0, 'updatedAt': now},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Permanently delete a supplier (only if not used in stock items)
  Future<void> deleteSupplier(int id) async {
    final db = await database;

    // Check if supplier is used in any stock items
    final usedInStock = await db.query(
      'stock_items',
      where: 'supplierName = (SELECT supplierName FROM suppliers WHERE id = ?)',
      whereArgs: [id],
      limit: 1,
    );

    if (usedInStock.isNotEmpty) {
      throw Exception('Cannot delete supplier that is used in stock items. Deactivate instead.');
    }

    await db.delete('suppliers', where: 'id = ?', whereArgs: [id]);
  }

  // ------------------------------------------------------------------
  // SALES
  // ------------------------------------------------------------------

  /// Record a new sale (with automatic stock deduction and movement log)
  Future<int> insertSale(Map<String, dynamic> sale, {String? createdBy}) async {
    final db = await database;
    final now = DateTime.now().toIso8601String();
    final saleQty = sale['quantity'] as int;

    // Check if this is a custom item (not in stock)
    // stockItemId = 0 is used as sentinel value for custom items due to NOT NULL constraint
    final isCustomItem = sale['isCustomItem'] == 1 || sale['stockItemId'] == null || sale['stockItemId'] == 0;
    String? itemName = sale['itemName'];

    if (isCustomItem) {
      // Custom item: No stock validation or deduction needed
      if (itemName == null || itemName.isEmpty) {
        throw Exception('Item name is required for custom items');
      }

      return await db.transaction((txn) async {
        // Insert sale record for custom item
        final saleId = await txn.insert('sales', {
          'studentId': sale['studentId'],
          'buyerName': sale['buyerName'],
          'buyerType': sale['buyerType'],
          'stockItemId': 0, // Use 0 as sentinel value for custom items (NOT NULL constraint)
          'itemName': itemName,
          'isCustomItem': 1,
          'quantity': saleQty,
          'unitPrice': sale['unitPrice'],
          'totalAmount': sale['totalAmount'],
          'paymentMethod': sale['paymentMethod'],
          'paymentStatus': sale['paymentStatus'],
          'amountPaid': sale['amountPaid'],
          'outstandingBalance': sale['outstandingBalance'],
          'note': sale['note'],
          'saleDate': sale['saleDate'] ?? now,
          'term': sale['term'],
          'session': sale['session'],
          'createdBy': createdBy,
          'createdAt': now,
        });

        return saleId;
      }).then((saleId) async {
        // Add to debtors table if there's an outstanding balance
        final outstandingBalance = sale['outstandingBalance'] as double?;
        if (outstandingBalance != null && outstandingBalance > 0) {
          await _upsertSalesDebtor(
            buyerName: sale['buyerName'],
            buyerType: sale['buyerType'],
            studentId: sale['studentId'],
            totalAmount: sale['totalAmount'],
            amountPaid: sale['amountPaid'] ?? 0.0,
            outstandingBalance: outstandingBalance,
            term: sale['term'],
            session: sale['session'],
          );
        }
        return saleId;
      });
    }

    // Stock item: Validate stock availability first
    final stockItem = await getStockItemById(sale['stockItemId']);
    if (stockItem == null) {
      throw Exception('Stock item not found');
    }

    // Get item name from stock item if not provided
    itemName ??= stockItem['itemName'] as String?;

    final currentQty = stockItem['currentQuantity'] as int;

    if (currentQty < saleQty) {
      throw Exception(
        'Insufficient stock. Available: $currentQty, Requested: $saleQty'
      );
    }

    return await db.transaction((txn) async {
      // Insert sale record
      final saleId = await txn.insert('sales', {
        'studentId': sale['studentId'],
        'buyerName': sale['buyerName'],
        'buyerType': sale['buyerType'],
        'stockItemId': sale['stockItemId'],
        'itemName': itemName,
        'isCustomItem': 0,
        'quantity': saleQty,
        'unitPrice': sale['unitPrice'],
        'totalAmount': sale['totalAmount'],
        'paymentMethod': sale['paymentMethod'],
        'paymentStatus': sale['paymentStatus'],
        'amountPaid': sale['amountPaid'],
        'outstandingBalance': sale['outstandingBalance'],
        'note': sale['note'],
        'saleDate': sale['saleDate'] ?? now,
        'term': sale['term'],
        'session': sale['session'],
        'createdBy': createdBy,
        'createdAt': now,
      });

      // Deduct stock quantity
      final newQty = currentQty - saleQty;
      await txn.update(
        'stock_items',
        {'currentQuantity': newQty, 'updatedAt': now},
        where: 'id = ?',
        whereArgs: [sale['stockItemId']],
      );

      // Log stock movement
      await txn.insert('stock_movements', {
        'stockItemId': sale['stockItemId'],
        'movementType': 'Sale',
        'quantity': saleQty,
        'balanceAfter': newQty,
        'referenceType': 'Sale',
        'referenceId': saleId,
        'note': 'Sale to ${sale['buyerName']}',
        'movementDate': now,
        'createdBy': createdBy,
      });

      return saleId;
    }).then((saleId) async {
      // Add to debtors table if there's an outstanding balance
      final outstandingBalance = sale['outstandingBalance'] as double?;
      if (outstandingBalance != null && outstandingBalance > 0) {
        await _upsertSalesDebtor(
          buyerName: sale['buyerName'],
          buyerType: sale['buyerType'],
          studentId: sale['studentId'],
          totalAmount: sale['totalAmount'],
          amountPaid: sale['amountPaid'] ?? 0.0,
          outstandingBalance: outstandingBalance,
          term: sale['term'],
          session: sale['session'],
        );
      }
      return saleId;
    });
  }

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
  }) async {
    final db = await database;
    final now = paymentTimestamp ?? DateTime.now().toIso8601String();

    // Get the original sale details to create payment receipt
    final originalSale = await db.query(
      'sales',
      where: 'id = ?',
      whereArgs: [saleId],
      limit: 1,
    );

    if (originalSale.isEmpty) {
      throw Exception('Original sale not found');
    }

    final sale = originalSale.first;

    // Create a payment receipt record for today's sales report
    // This record has quantity=0 so it won't affect stock
    // Total Amount = outstanding BEFORE this payment (current debt for this item)
    // Amount Paid = payment made NOW for this item
    // Outstanding = remaining balance AFTER this payment
    int paymentReceiptId = 0;
    if (additionalPayment > 0) {
      final outstandingBeforePayment = outstandingBalance + additionalPayment;

      paymentReceiptId = await db.insert('sales', {
        'studentId': sale['studentId'],
        'buyerName': sale['buyerName'],
        'buyerType': sale['buyerType'],
        'stockItemId': sale['stockItemId'],
        'itemName': sale['itemName'], // Copy item name for custom items
        'isCustomItem': sale['isCustomItem'], // Copy custom item flag
        'quantity': 0, // Zero quantity - this is a payment receipt, not a new sale
        'unitPrice': sale['unitPrice'],
        'totalAmount': outstandingBeforePayment, // Outstanding BEFORE this payment
        'paymentMethod': paymentMethod ?? sale['paymentMethod'],
        'paymentStatus': paymentStatus, // Payment status after this payment
        'amountPaid': additionalPayment, // The payment made today
        'outstandingBalance': outstandingBalance, // Remaining balance after this payment
        'note': 'Payment for Sale #$saleId${note != null && note.isNotEmpty ? " - $note" : ""}',
        'saleDate': now, // Today's date so it appears in today's report
        'term': term ?? sale['term'],
        'session': session ?? sale['session'],
        'createdBy': createdBy,
        'createdAt': now,
      });
    }

    // DO NOT update the original sale record - keep it unchanged to preserve historical data
    // Instead, update the debtors table with the new payment
    await updateSalesDebtorPayment(
      buyerName: sale['buyerName'] as String,
      buyerType: sale['buyerType'] as String,
      paymentAmount: additionalPayment,
      term: term ?? sale['term'] as String?,
      session: session ?? sale['session'] as String?,
    );

    return paymentReceiptId;
  }

  /// Delete a sale and restore stock quantity (for stock items only, not custom items)
  Future<void> deleteSale(int saleId, {String? deletedBy}) async {
    final db = await database;
    final now = DateTime.now().toIso8601String();

    // Get the sale record first
    final sales = await db.query('sales', where: 'id = ?', whereArgs: [saleId]);
    if (sales.isEmpty) {
      throw Exception('Sale not found');
    }

    final sale = sales.first;
    final stockItemId = sale['stockItemId'] as int;
    final saleQty = sale['quantity'] as int;

    // Check if this is a custom item (stockItemId = 0 or isCustomItem = 1)
    final isCustomItem = sale['isCustomItem'] == 1 || stockItemId == 0;

    if (isCustomItem) {
      // For custom items, just delete the sale record without restoring stock
      return await db.transaction((txn) async {
        await txn.delete('sales', where: 'id = ?', whereArgs: [saleId]);
      });
    }

    // For stock items, restore stock quantity
    final stockItem = await getStockItemById(stockItemId);
    if (stockItem == null) {
      // Stock item not found - just delete the sale without restoring stock
      return await db.transaction((txn) async {
        await txn.delete('sales', where: 'id = ?', whereArgs: [saleId]);
      });
    }

    return await db.transaction((txn) async {
      // Delete the sale record
      await txn.delete('sales', where: 'id = ?', whereArgs: [saleId]);

      // Restore stock quantity
      final currentQty = stockItem['currentQuantity'] as int;
      final newQty = currentQty + saleQty;
      await txn.update(
        'stock_items',
        {'currentQuantity': newQty, 'updatedAt': now},
        where: 'id = ?',
        whereArgs: [stockItemId],
      );

      // Log stock movement (reversal)
      await txn.insert('stock_movements', {
        'stockItemId': stockItemId,
        'movementType': 'Return',
        'quantity': saleQty,
        'balanceAfter': newQty,
        'referenceType': 'Sale Deletion',
        'referenceId': saleId,
        'note': 'Sale deleted - stock restored',
        'movementDate': now,
        'createdBy': deletedBy,
      });
    });
  }

  // ------------------------------------------------------------------
  // SALES DEBTORS MANAGEMENT
  // ------------------------------------------------------------------

  /// Add or update a debtor record in sales_debtors table
  Future<void> _upsertSalesDebtor({
    required String buyerName,
    required String buyerType,
    int? studentId,
    required double totalAmount,
    required double amountPaid,
    required double outstandingBalance,
    String? term,
    String? session,
  }) async {
    final db = await database;
    final now = DateTime.now().toIso8601String();

    // Check if debtor already exists
    final existing = await db.query(
      'sales_debtors',
      where: 'buyerName = ? AND buyerType = ? AND term = ? AND session = ?',
      whereArgs: [buyerName, buyerType, term ?? '', session ?? ''],
      limit: 1,
    );

    if (existing.isNotEmpty) {
      // Update existing debtor
      final current = existing.first;
      final newTotal = (current['totalAmount'] as num) + totalAmount;
      final newPaid = (current['amountPaid'] as num) + amountPaid;
      final newOutstanding = (current['outstandingBalance'] as num) + outstandingBalance;

      if (newOutstanding <= 0) {
        // Fully paid - delete the debtor record
        await db.delete(
          'sales_debtors',
          where: 'id = ?',
          whereArgs: [current['id']],
        );
      } else {
        // Update with new amounts
        await db.update(
          'sales_debtors',
          {
            'totalAmount': newTotal,
            'amountPaid': newPaid,
            'outstandingBalance': newOutstanding,
            'updatedAt': now,
          },
          where: 'id = ?',
          whereArgs: [current['id']],
        );
      }
    } else {
      // Insert new debtor (only if outstanding > 0)
      if (outstandingBalance > 0) {
        await db.insert('sales_debtors', {
          'buyerName': buyerName,
          'buyerType': buyerType,
          'studentId': studentId,
          'totalAmount': totalAmount,
          'amountPaid': amountPaid,
          'outstandingBalance': outstandingBalance,
          'term': term,
          'session': session,
          'createdAt': now,
          'updatedAt': now,
        });
      }
    }
  }

  /// Update debtor record when payment is made
  Future<void> updateSalesDebtorPayment({
    required String buyerName,
    required String buyerType,
    required double paymentAmount,
    String? term,
    String? session,
  }) async {
    final db = await database;
    final now = DateTime.now().toIso8601String();

    // Get existing debtor
    final existing = await db.query(
      'sales_debtors',
      where: 'buyerName = ? AND buyerType = ? AND term = ? AND session = ?',
      whereArgs: [buyerName, buyerType, term ?? '', session ?? ''],
      limit: 1,
    );

    if (existing.isEmpty) {
      throw Exception('Debtor record not found');
    }

    final debtor = existing.first;
    final newPaid = (debtor['amountPaid'] as num) + paymentAmount;
    final newOutstanding = (debtor['outstandingBalance'] as num) - paymentAmount;

    if (newOutstanding <= 0) {
      // Fully paid - delete the debtor record
      await db.delete(
        'sales_debtors',
        where: 'id = ?',
        whereArgs: [debtor['id']],
      );
    } else {
      // Update with new amounts
      await db.update(
        'sales_debtors',
        {
          'amountPaid': newPaid,
          'outstandingBalance': newOutstanding,
          'lastPaymentDate': now,
          'updatedAt': now,
        },
        where: 'id = ?',
        whereArgs: [debtor['id']],
      );
    }
  }

  /// Get all sales debtors with optional filters
  Future<List<Map<String, dynamic>>> getSalesDebtors({
    String? term,
    String? session,
  }) async {
    final db = await database;

    String where = 'outstandingBalance > 0';
    List<dynamic> whereArgs = [];

    if (term != null && session != null) {
      where += ' AND term = ? AND session = ?';
      whereArgs.addAll([term, session]);
    }

    return await db.query(
      'sales_debtors',
      where: where,
      whereArgs: whereArgs.isNotEmpty ? whereArgs : null,
      orderBy: 'outstandingBalance DESC',
    );
  }

  /// Get sales by exact date
  Future<List<Map<String, dynamic>>> getSalesByExactDate(String date) async {
    final db = await database;
    return db.rawQuery('''
      SELECT
        s.*,
        COALESCE(s.itemName, si.itemName) as itemName,
        si.costPrice
      FROM sales s
      LEFT JOIN stock_items si ON s.stockItemId = si.id
      WHERE s.saleDate LIKE ?
      ORDER BY s.saleDate DESC
    ''', ["$date%"]);
  }

  /// Get all sales with optional filters
  Future<List<Map<String, dynamic>>> getAllSales({
    String? term,
    String? session,
    String? startDate,
    String? endDate,
    int? studentId,
  }) async {
    final db = await database;

    List<String> whereConditions = [];
    List<dynamic> whereArgs = [];

    if (term != null) {
      whereConditions.add('s.term = ?');
      whereArgs.add(term);
    }

    if (session != null) {
      whereConditions.add('s.session = ?');
      whereArgs.add(session);
    }

    if (startDate != null) {
      whereConditions.add('s.saleDate >= ?');
      whereArgs.add(startDate);
    }

    if (endDate != null) {
      whereConditions.add('s.saleDate <= ?');
      whereArgs.add(endDate);
    }

    if (studentId != null) {
      whereConditions.add('s.studentId = ?');
      whereArgs.add(studentId);
    }

    String where = whereConditions.isNotEmpty
        ? 'WHERE ${whereConditions.join(' AND ')}'
        : '';

    return db.rawQuery('''
      SELECT
        s.*,
        COALESCE(s.itemName, si.itemName) as itemName,
        si.costPrice,
        st.surname,
        st.firstName,
        c.name as className,
        a.name as armName
      FROM sales s
      LEFT JOIN stock_items si ON s.stockItemId = si.id
      LEFT JOIN students st ON s.studentId = st.id
      LEFT JOIN classes c ON st.classId = c.id
      LEFT JOIN arms a ON st.armId = a.id
      $where
      ORDER BY s.saleDate DESC
    ''', whereArgs);
  }

  /// Get sale by ID
  Future<Map<String, dynamic>?> getSaleById(int id) async {
    final db = await database;
    final rows = await db.rawQuery('''
      SELECT
        s.*,
        COALESCE(s.itemName, si.itemName) as itemName,
        si.costPrice
      FROM sales s
      LEFT JOIN stock_items si ON s.stockItemId = si.id
      WHERE s.id = ?
    ''', [id]);

    return rows.isNotEmpty ? rows.first : null;
  }

  /// Get sales totals by payment method for a date
  Future<Map<String, double>> getSalesTotalsByMethod(String date) async {
    final db = await database;

    final results = await db.rawQuery('''
      SELECT paymentMethod, SUM(totalAmount) as total
      FROM sales
      WHERE saleDate LIKE ?
      GROUP BY paymentMethod
    ''', ["$date%"]);

    final totals = <String, double>{};
    for (var row in results) {
      final method = row['paymentMethod'] as String;
      final total = (row['total'] as num?)?.toDouble() ?? 0.0;
      totals[method] = total;
    }

    return totals;
  }

  // ------------------------------------------------------------------
  // STOCK MOVEMENTS (Audit Trail)
  // ------------------------------------------------------------------

  /// Get stock movements for an item
  Future<List<Map<String, dynamic>>> getStockMovements(
    int stockItemId, {
    String? startDate,
    String? endDate,
  }) async {
    final db = await database;

    List<String> whereConditions = ['stockItemId = ?'];
    List<dynamic> whereArgs = [stockItemId];

    if (startDate != null) {
      whereConditions.add('movementDate >= ?');
      whereArgs.add(startDate);
    }

    if (endDate != null) {
      whereConditions.add('movementDate <= ?');
      whereArgs.add(endDate);
    }

    String where = whereConditions.join(' AND ');

    return db.query(
      'stock_movements',
      where: where,
      whereArgs: whereArgs,
      orderBy: 'movementDate DESC',
    );
  }

  // ------------------------------------------------------------------
  // OUTSTANDING (total across all terms & sessions)
  // ------------------------------------------------------------------
  Future<double> computeOutstandingBalance(int studentId) async {
    final db = await database;

    // Use (totalAmount - previousBalance) across all terms so baked-in
    // carry-overs are not double-counted in the all-time outstanding figure.
    final bill = await db.rawQuery(
      'SELECT COALESCE(SUM(totalAmount - previousBalance), 0) AS t FROM student_bills WHERE studentId = ?',
      [studentId],
    );
    final pay = await db.rawQuery(
      'SELECT COALESCE(SUM(amount), 0) AS t FROM payments WHERE studentId = ?',
      [studentId],
    );

    final totalBills = (bill.first['t'] ?? 0) as num;
    final totalPays = (pay.first['t'] ?? 0) as num;

    return (totalBills - totalPays).toDouble();
  }

// ADD THIS METHOD TO YOUR database_helper.dart
// Place it in the "REPORTS & ANALYTICS" section (around line 800-850)

  // ------------------------------------------------------------------
  // DEBTORS LIST - Get students with outstanding balances
  // ------------------------------------------------------------------
  Future<List<Map<String, dynamic>>> getDebtorsList({
    required int classId,
    required String term,
    required String session,
    double minPercentagePaid = 0.0, // 0 = all debtors, 50 = paid less than 50%
  }) async {
    final db = await database;

    final targetKey = termSortKey(term, session);
    final result = await db.rawQuery('''
      SELECT
        s.id as studentId,
        s.admissionNo,
        s.surname,
        s.firstName,
        s.otherName,
        s.classId,
        c.name as className,
        a.name as armName,
        (COALESCE(b.totalAmount, 0) - COALESCE(b.previousBalance, 0)) as currentTermFee,
        (
          COALESCE((SELECT SUM(b2.totalAmount - b2.previousBalance) FROM student_bills b2
                    WHERE b2.studentId = s.id AND ${_sqlTermKey('b2')} < ?), 0)
          -
          COALESCE((SELECT SUM(p2.amount) FROM payments p2
                    WHERE p2.studentId = s.id AND ${_sqlTermKey('p2')} < ?), 0)
        ) as freshPreviousBalance,
        COALESCE(
          (SELECT SUM(p.amount)
           FROM payments p
           WHERE p.studentId = s.id
             AND p.term = ?
             AND p.session = ?),
          0
        ) as totalPaid
      FROM students s
      INNER JOIN classes c ON s.classId = c.id
      LEFT JOIN arms a ON s.armId = a.id
      LEFT JOIN student_bills b ON s.id = b.studentId
        AND b.term = ?
        AND b.session = ?
      WHERE s.classId = ?
        AND s.isActive = 1
      ORDER BY s.surname, s.firstName
    ''', [targetKey, targetKey, term, session, term, session, classId]);

    // Calculate grand total, outstanding and percentage, then filter
    final debtors = <Map<String, dynamic>>[];

    for (var row in result) {
      final currentTermFee = (row['currentTermFee'] as num).toDouble();
      final freshPreviousBalance = (row['freshPreviousBalance'] as num).toDouble();
      final grandTotal = currentTermFee + freshPreviousBalance;
      final totalPaid = (row['totalPaid'] as num).toDouble();
      final outstanding = grandTotal - totalPaid;

      // Calculate percentage paid (avoid division by zero)
      final percentPaid = grandTotal > 0 ? (totalPaid / grandTotal) * 100 : 0.0;

      // Filter logic:
      // - If minPercentagePaid = 0: Show ALL students with outstanding balance
      // - If minPercentagePaid = 50: Show students who paid LESS than 50%
      // - If minPercentagePaid = 80: Show students who paid LESS than 80%
      bool includeStudent = false;

      if (outstanding > 0) {
        if (minPercentagePaid == 0.0) {
          includeStudent = true;
        } else {
          includeStudent = percentPaid < minPercentagePaid;
        }
      }

      if (includeStudent) {
        debtors.add({
          'studentId': row['studentId'],
          'admissionNo': row['admissionNo'],
          'surname': row['surname'],
          'firstName': row['firstName'],
          'otherName': row['otherName'],
          'className': row['className'],
          'armName': row['armName'],
          'totalBill': grandTotal,
          'totalPaid': totalPaid,
          'outstanding': outstanding,
          'percentPaid': percentPaid,
        });
      }
    }

    return debtors;
  }

  // ------------------------------------------------------------------
  // DEBTORS SUMMARY - Get summary statistics
  // ------------------------------------------------------------------
  Future<Map<String, dynamic>> getDebtorsSummary({
    required String term,
    required String session,
    int? classId,
  }) async {
    final db = await database;

    final String classFilter = classId != null ? 'AND s.classId = ?' : '';
    final targetKey = termSortKey(term, session);
    // params: targetKey×2 (sort key for b2/p2 freshPrevBal), term×2 (totalPaid), term×2 (LEFT JOIN), [classId]
    final List<dynamic> params = [
      targetKey, targetKey,  // b2 sort key, p2 sort key for freshPreviousBalance
      term, session,         // totalPaid subquery
      term, session,         // LEFT JOIN student_bills
    ];
    if (classId != null) params.add(classId);

    // CTE computes grand total per student, then outer query aggregates
    final result = await db.rawQuery('''
      WITH student_totals AS (
        SELECT
          s.id,
          (COALESCE(b.totalAmount, 0) - COALESCE(b.previousBalance, 0)) as currentTermFee,
          (
            COALESCE((SELECT SUM(b2.totalAmount - b2.previousBalance) FROM student_bills b2
                      WHERE b2.studentId = s.id AND ${_sqlTermKey('b2')} < ?), 0)
            -
            COALESCE((SELECT SUM(p2.amount) FROM payments p2
                      WHERE p2.studentId = s.id AND ${_sqlTermKey('p2')} < ?), 0)
          ) as freshPreviousBalance,
          COALESCE(
            (SELECT SUM(p.amount) FROM payments p
             WHERE p.studentId = s.id AND p.term = ? AND p.session = ?),
            0
          ) as totalPaid
        FROM students s
        LEFT JOIN student_bills b ON s.id = b.studentId
          AND b.term = ? AND b.session = ?
        WHERE s.isActive = 1
          $classFilter
      )
      SELECT
        COUNT(*) as totalStudents,
        COUNT(CASE WHEN (currentTermFee + freshPreviousBalance - totalPaid) > 0 THEN 1 END) as totalDebtors,
        COALESCE(SUM(currentTermFee + freshPreviousBalance), 0) as totalBills,
        COALESCE(SUM(totalPaid), 0) as totalPaid
      FROM student_totals
    ''', params);

    if (result.isEmpty) {
      return {
        'totalStudents': 0,
        'totalDebtors': 0,
        'totalBills': 0.0,
        'totalPaid': 0.0,
        'totalOutstanding': 0.0,
      };
    }

    final row = result.first;
    final totalBills = (row['totalBills'] as num?)?.toDouble() ?? 0.0;
    final totalPaid = (row['totalPaid'] as num?)?.toDouble() ?? 0.0;

    return {
      'totalStudents': row['totalStudents'] ?? 0,
      'totalDebtors': row['totalDebtors'] ?? 0,
      'totalBills': totalBills,
      'totalPaid': totalPaid,
      'totalOutstanding': totalBills - totalPaid,
    };
  }

  // ------------------------------------------------------------------
  // FEES BALANCE SUMMARY - Counts/totals of balanced vs owing students
  // for a given term/session (only students who have an actual bill are
  // counted as "balanced" or "owing" — students never billed are excluded).
  // ------------------------------------------------------------------
  Future<Map<String, dynamic>> getFeesBalanceSummary({
    required String term,
    required String session,
    int classId = 0, // 0 = all classes
  }) async {
    final db = await database;

    final String classFilter = classId > 0 ? 'AND s.classId = ?' : '';
    final targetKey = termSortKey(term, session);
    final List<dynamic> params = [
      targetKey, targetKey, // b2/p2 sort key for freshPreviousBalance
      term, session,        // totalPaid subquery
      term, session,        // LEFT JOIN student_bills
    ];
    if (classId > 0) params.add(classId);

    final result = await db.rawQuery('''
      WITH student_totals AS (
        SELECT
          s.id,
          (COALESCE(b.totalAmount, 0) - COALESCE(b.previousBalance, 0)) as currentTermFee,
          (
            COALESCE((SELECT SUM(b2.totalAmount - b2.previousBalance) FROM student_bills b2
                      WHERE b2.studentId = s.id AND ${_sqlTermKey('b2')} < ?), 0)
            -
            COALESCE((SELECT SUM(p2.amount) FROM payments p2
                      WHERE p2.studentId = s.id AND ${_sqlTermKey('p2')} < ?), 0)
          ) as freshPreviousBalance,
          COALESCE(
            (SELECT SUM(p.amount) FROM payments p
             WHERE p.studentId = s.id AND p.term = ? AND p.session = ?),
            0
          ) as totalPaid
        FROM students s
        LEFT JOIN student_bills b ON s.id = b.studentId
          AND b.term = ? AND b.session = ?
        WHERE s.isActive = 1
          $classFilter
      )
      SELECT
        COUNT(CASE WHEN (currentTermFee + freshPreviousBalance) > 0 THEN 1 END) as totalBilledStudents,
        COUNT(CASE WHEN (currentTermFee + freshPreviousBalance) > 0
                    AND (currentTermFee + freshPreviousBalance - totalPaid) <= 0.005 THEN 1 END) as totalBalanced,
        COUNT(CASE WHEN (currentTermFee + freshPreviousBalance - totalPaid) > 0.005 THEN 1 END) as totalOwing,
        COALESCE(SUM(currentTermFee + freshPreviousBalance), 0) as totalBills,
        COALESCE(SUM(totalPaid), 0) as totalPaid
      FROM student_totals
    ''', params);

    if (result.isEmpty) {
      return {
        'totalBilledStudents': 0,
        'totalBalanced': 0,
        'totalOwing': 0,
        'totalBills': 0.0,
        'totalPaid': 0.0,
        'totalOutstanding': 0.0,
        'percentBalanced': 0.0,
      };
    }

    final row = result.first;
    final totalBilledStudents = (row['totalBilledStudents'] as int?) ?? 0;
    final totalBalanced = (row['totalBalanced'] as int?) ?? 0;
    final totalBills = (row['totalBills'] as num?)?.toDouble() ?? 0.0;
    final totalPaid = (row['totalPaid'] as num?)?.toDouble() ?? 0.0;

    return {
      'totalBilledStudents': totalBilledStudents,
      'totalBalanced': totalBalanced,
      'totalOwing': (row['totalOwing'] as int?) ?? 0,
      'totalBills': totalBills,
      'totalPaid': totalPaid,
      'totalOutstanding': totalBills - totalPaid,
      'percentBalanced': totalBilledStudents > 0 ? (totalBalanced / totalBilledStudents) * 100 : 0.0,
    };
  }

  // ------------------------------------------------------------------
  // BALANCED STUDENTS LIST - Students who have fully paid off their bill
  // (outstanding <= 0) for a given term/session
  // ------------------------------------------------------------------
  Future<List<Map<String, dynamic>>> getBalancedStudentsList({
    required int classId, // 0 = all classes
    required String term,
    required String session,
  }) async {
    final db = await database;

    final targetKey = termSortKey(term, session);
    final String classFilter = classId > 0 ? 'AND s.classId = ?' : '';
    final List<dynamic> params = [targetKey, targetKey, term, session, term, session];
    if (classId > 0) params.add(classId);

    final result = await db.rawQuery('''
      SELECT
        s.id as studentId,
        s.admissionNo,
        s.surname,
        s.firstName,
        s.otherName,
        s.classId,
        c.name as className,
        a.name as armName,
        (COALESCE(b.totalAmount, 0) - COALESCE(b.previousBalance, 0)) as currentTermFee,
        (
          COALESCE((SELECT SUM(b2.totalAmount - b2.previousBalance) FROM student_bills b2
                    WHERE b2.studentId = s.id AND ${_sqlTermKey('b2')} < ?), 0)
          -
          COALESCE((SELECT SUM(p2.amount) FROM payments p2
                    WHERE p2.studentId = s.id AND ${_sqlTermKey('p2')} < ?), 0)
        ) as freshPreviousBalance,
        COALESCE(
          (SELECT SUM(p.amount)
           FROM payments p
           WHERE p.studentId = s.id
             AND p.term = ?
             AND p.session = ?),
          0
        ) as totalPaid
      FROM students s
      INNER JOIN classes c ON s.classId = c.id
      LEFT JOIN arms a ON s.armId = a.id
      LEFT JOIN student_bills b ON s.id = b.studentId
        AND b.term = ?
        AND b.session = ?
      WHERE s.isActive = 1
        $classFilter
      ORDER BY s.surname, s.firstName
    ''', params);

    final balanced = <Map<String, dynamic>>[];

    for (var row in result) {
      final currentTermFee = (row['currentTermFee'] as num).toDouble();
      final freshPreviousBalance = (row['freshPreviousBalance'] as num).toDouble();
      final grandTotal = currentTermFee + freshPreviousBalance;
      final totalPaid = (row['totalPaid'] as num).toDouble();
      final outstanding = grandTotal - totalPaid;

      // Only students who were actually billed something and have paid it
      // all off (or overpaid) count as "balanced".
      if (grandTotal > 0 && outstanding <= 0.005) {
        balanced.add({
          'studentId': row['studentId'],
          'admissionNo': row['admissionNo'],
          'surname': row['surname'],
          'firstName': row['firstName'],
          'otherName': row['otherName'],
          'className': row['className'],
          'armName': row['armName'],
          'totalBill': grandTotal,
          'totalPaid': totalPaid,
          'credit': -outstanding, // positive if overpaid
        });
      }
    }

    return balanced;
  }

  // ------------------------------------------------------------------
  // LAST TERM DEBTORS - Students with carry-over previous balance
  // ------------------------------------------------------------------
  Future<List<Map<String, dynamic>>> getLastTermDebtors({
    required String term,
    required String session,
    int classId = 0, // 0 = all classes
    int armId = 0,   // 0 = all arms
  }) async {
    final db = await database;

    String whereClause = 's.isActive = 1 AND b.previousBalance > 0.005';
    final List<dynamic> params = [term, session, term, session];

    if (classId > 0) {
      whereClause += ' AND s.classId = ?';
      params.add(classId);
    }
    if (armId > 0) {
      whereClause += ' AND s.armId = ?';
      params.add(armId);
    }

    final result = await db.rawQuery('''
      SELECT
        s.id as studentId,
        s.admissionNo,
        s.surname,
        s.firstName,
        s.otherName,
        c.name as className,
        a.name as armName,
        b.previousBalance,
        (b.totalAmount - b.previousBalance) as currentTermFee,
        COALESCE(
          (SELECT SUM(p.amount) FROM payments p
           WHERE p.studentId = s.id AND p.term = ? AND p.session = ?),
          0
        ) as totalPaidThisTerm
      FROM students s
      INNER JOIN classes c ON s.classId = c.id
      LEFT JOIN arms a ON s.armId = a.id
      INNER JOIN student_bills b ON s.id = b.studentId
        AND b.term = ? AND b.session = ?
      WHERE $whereClause
      ORDER BY c.name, a.name, s.surname, s.firstName
    ''', params);

    return result.map((row) {
      final previousBalance = (row['previousBalance'] as num).toDouble();
      final currentTermFee = (row['currentTermFee'] as num).toDouble();
      final totalPaidThisTerm = (row['totalPaidThisTerm'] as num).toDouble();

      final appliedToDebt = totalPaidThisTerm >= previousBalance
          ? previousBalance
          : totalPaidThisTerm;
      final remainingDebt = (previousBalance - appliedToDebt).clamp(0.0, double.infinity);

      String debtStatus;
      if (remainingDebt <= 0.005) {
        debtStatus = 'fully_covered';
      } else if (totalPaidThisTerm > 0.005) {
        debtStatus = 'partially_covered';
      } else {
        debtStatus = 'not_covered';
      }

      return {
        'studentId': row['studentId'],
        'admissionNo': row['admissionNo'],
        'surname': row['surname'],
        'firstName': row['firstName'],
        'otherName': row['otherName'],
        'className': row['className'],
        'armName': row['armName'],
        'previousBalance': previousBalance,
        'currentTermFee': currentTermFee,
        'totalPaidThisTerm': totalPaidThisTerm,
        'appliedToDebt': appliedToDebt,
        'remainingDebt': remainingDebt,
        'debtStatus': debtStatus,
      };
    }).toList();
  }

  // ------------------------------------------------------------------
  // USER AUTHENTICATION (NEW)
  // ------------------------------------------------------------------
  
  /// Authenticate user with username and password
  Future<Map<String, dynamic>?> authenticateUser(String username, String password) async {
    final db = await database;

    // Get user by username
    final result = await db.query(
      'users',
      where: 'username = ?',
      whereArgs: [username],
      limit: 1,
    );

    if (result.isEmpty) {
      return null;
    }

    final user = result.first;
    final storedPassword = user['password'] as String;

    // Check if password is hashed or plain text (for backward compatibility)
    bool passwordMatches;
    if (PasswordHelper.isPasswordHashed(storedPassword)) {
      // Hashed password - verify using bcrypt
      passwordMatches = PasswordHelper.verifyPassword(password, storedPassword);
    } else {
      // Plain text password - direct comparison (legacy)
      passwordMatches = password == storedPassword;

      // Auto-migrate: Hash the password for next time
      if (passwordMatches) {
        final hashedPassword = PasswordHelper.hashPassword(password);
        await db.update(
          'users',
          {'password': hashedPassword},
          where: 'id = ?',
          whereArgs: [user['id']],
        );
      }
    }

    return passwordMatches ? user : null;
  }

  /// Get user by username
  Future<Map<String, dynamic>?> getUserByUsername(String username) async {
    final db = await database;
    final result = await db.query(
      'users',
      where: 'username = ?',
      whereArgs: [username],
      limit: 1,
    );
    
    return result.isNotEmpty ? result.first : null;
  }

  /// Get all users
  Future<List<Map<String, dynamic>>> getAllUsers() async {
    final db = await database;
    return db.query('users', orderBy: 'id ASC');
  }

  /// Update user credentials (only for users with canChangeCredentials = 1)
  Future<bool> updateUserCredentials({
    required int userId,
    required String newUsername,
    required String newPassword,
  }) async {
    final db = await database;
    
    // Check if user can change credentials
    final user = await db.query('users', where: 'id = ?', whereArgs: [userId], limit: 1);
    
    if (user.isEmpty) return false;
    
    final canChange = (user.first['canChangeCredentials'] as int) == 1;
    
    if (!canChange) return false;

    // Hash password before updating
    final hashedPassword = PasswordHelper.hashPassword(newPassword);

    try {
      final count = await db.update(
        'users',
        {
          'username': newUsername,
          'password': hashedPassword,
        },
        where: 'id = ?',
        whereArgs: [userId],
      );

      return count > 0;
    } catch (e) {
      // Username might already exist
      return false;
    }
  }

  /// Reset bursar credentials (only by super admin)
  Future<bool> resetBursarCredentials({
    required String newUsername,
    required String newPassword,
  }) async {
    final db = await database;

    // Hash password before updating
    final hashedPassword = PasswordHelper.hashPassword(newPassword);

    try {
      final count = await db.update(
        'users',
        {
          'username': newUsername,
          'password': hashedPassword,
        },
        where: 'userType = ?',
        whereArgs: ['bursar'],
      );

      return count > 0;
    } catch (e) {
      return false;
    }
  }

  /// Get bursar account
  Future<Map<String, dynamic>?> getBursarAccount() async {
    final db = await database;
    final result = await db.query(
      'users',
      where: 'userType = ?',
      whereArgs: ['bursar'],
      limit: 1,
    );

    return result.isNotEmpty ? result.first : null;
  }

  // ------------------------------------------------------------------
  // USER MANAGEMENT (CRUD Operations)
  // ------------------------------------------------------------------

  // Create a new user
  Future<int?> createUser({
    required String username,
    required String password,
    required String userType,
    int canChangeCredentials = 1,
  }) async {
    final db = await database;

    // Validation: Check if username already exists
    final existing = await getUserByUsername(username);
    if (existing != null) {
      return null; // Username already exists
    }

    // Validation: Prevent creating 'superadmin' username
    if (username.toLowerCase() == 'superadmin') {
      return null; // Reserved username
    }

    // Hash password before storing
    final hashedPassword = PasswordHelper.hashPassword(password);

    // Insert new user
    try {
      return await db.insert('users', {
        'username': username,
        'password': hashedPassword,
        'userType': userType,
        'canChangeCredentials': canChangeCredentials,
        'createdAt': DateTime.now().toIso8601String(),
      });
    } catch (e) {
      return null;
    }
  }

  // Update existing user (including role change)
  Future<bool> updateUser({
    required int userId,
    required String username,
    required String password,
    required String userType,
    required int canChangeCredentials,
  }) async {
    final db = await database;

    // Get user being updated
    final user = await db.query('users', where: 'id = ?', whereArgs: [userId], limit: 1);
    if (user.isEmpty) return false;

    // SECURITY: Prevent modifying the default superadmin account (id = 1)
    if (userId == 1) {
      return false; // Cannot modify default superadmin
    }

    // Validation: Check if new username conflicts (except current user)
    final existingUser = await getUserByUsername(username);
    if (existingUser != null && existingUser['id'] != userId) {
      return false; // Username already taken
    }

    // Hash password before updating
    final hashedPassword = PasswordHelper.hashPassword(password);

    try {
      final count = await db.update(
        'users',
        {
          'username': username,
          'password': hashedPassword,
          'userType': userType,
          'canChangeCredentials': canChangeCredentials,
        },
        where: 'id = ?',
        whereArgs: [userId],
      );
      return count > 0;
    } catch (e) {
      return false;
    }
  }

  // Delete user
  Future<Map<String, dynamic>> deleteUser(int userId) async {
    final db = await database;

    // SECURITY: Cannot delete default superadmin (id = 1)
    if (userId == 1) {
      return {'success': false, 'message': 'Cannot delete default super admin'};
    }

    // Get user details
    final user = await db.query('users', where: 'id = ?', whereArgs: [userId], limit: 1);
    if (user.isEmpty) {
      return {'success': false, 'message': 'User not found'};
    }

    final userType = user.first['userType'] as String;

    // SECURITY: Prevent deleting last super_admin
    if (userType == 'super_admin') {
      final superAdminCount = await countSuperAdmins();
      if (superAdminCount <= 1) {
        return {'success': false, 'message': 'Cannot delete the last super admin'};
      }
    }

    // Delete user
    try {
      await db.delete('users', where: 'id = ?', whereArgs: [userId]);
      return {'success': true, 'message': 'User deleted successfully'};
    } catch (e) {
      return {'success': false, 'message': 'Error deleting user: $e'};
    }
  }

  // Get user by ID
  Future<Map<String, dynamic>?> getUserById(int userId) async {
    final db = await database;
    final result = await db.query(
      'users',
      where: 'id = ?',
      whereArgs: [userId],
      limit: 1,
    );

    return result.isNotEmpty ? result.first : null;
  }

  // Count super admins (for validation)
  Future<int> countSuperAdmins() async {
    final db = await database;
    final result = await db.rawQuery(
      'SELECT COUNT(*) as count FROM users WHERE userType = ?',
      ['super_admin'],
    );
    return (result.first['count'] as int?) ?? 0;
  }

  // ------------------------------------------------------------------
  // SCHOOL PROFILE
  // ------------------------------------------------------------------
  Future<Map<String, dynamic>?> getSchoolProfile() async {
    final db = await database;
    final rows = await db.query('school_profile', limit: 1);
    return rows.isNotEmpty ? rows.first : null;
  }

  Future<int> saveSchoolProfile(Map<String, dynamic> data) async {
    final db = await database;
    final existing = await db.query('school_profile', limit: 1);
    if (existing.isEmpty) {
      return db.insert('school_profile', data);
    } else {
      final id = existing.first['id'] as int;
      return db.update('school_profile', data, where: 'id = ?', whereArgs: [id]);
    }
  }

  // ------------------------------------------------------------------
  // LICENSE MANAGEMENT
  // ------------------------------------------------------------------

  /// Get active license
  Future<Map<String, dynamic>?> getActiveLicense() async {
    final db = await database;
    final result = await db.query(
      'licenses',
      where: 'isActive = ?',
      whereArgs: [1],
      orderBy: 'createdAt DESC',
      limit: 1,
    );
    return result.isNotEmpty ? result.first : null;
  }

  /// Activate a new license
  Future<int> activateLicense({
    required String licenseKey,
    required String schoolName,
    required String schoolCode,
    required String deviceId,
    required DateTime expiryDate,
    int? maxStudents,
  }) async {
    final db = await database;

    // Deactivate any existing licenses
    await db.update(
      'licenses',
      {'isActive': 0},
      where: 'isActive = ?',
      whereArgs: [1],
    );

    // Insert new license
    return await db.insert('licenses', {
      'licenseKey': licenseKey,
      'schoolName': schoolName,
      'schoolCode': schoolCode,
      'deviceId': deviceId,
      'activationDate': DateTime.now().toIso8601String(),
      'expiryDate': expiryDate.toIso8601String(),
      'maxStudents': maxStudents ?? 0,
      'isActive': 1,
      'createdAt': DateTime.now().toIso8601String(),
      'lastKnownDate': DateTime.now().toIso8601String(),
    });
  }

  /// Deactivate current license
  Future<int> deactivateLicense(int licenseId) async {
    final db = await database;
    return await db.update(
      'licenses',
      {'isActive': 0},
      where: 'id = ?',
      whereArgs: [licenseId],
    );
  }

  /// Get all licenses (active and inactive)
  Future<List<Map<String, dynamic>>> getAllLicenses() async {
    final db = await database;
    return await db.query('licenses', orderBy: 'createdAt DESC');
  }

  /// Check if license key already exists
  Future<bool> licenseKeyExists(String licenseKey) async {
    final db = await database;
    final result = await db.query(
      'licenses',
      where: 'licenseKey = ?',
      whereArgs: [licenseKey],
      limit: 1,
    );
    return result.isNotEmpty;
  }

  /// Get license details by license key
  Future<Map<String, dynamic>?> getLicenseByKey(String licenseKey) async {
    final db = await database;
    final result = await db.query(
      'licenses',
      where: 'licenseKey = ?',
      whereArgs: [licenseKey],
      limit: 1,
    );
    return result.isNotEmpty ? result.first : null;
  }

  /// Persist the highest "now" the app has ever observed for a license,
  /// used to detect the system clock being turned backward.
  Future<void> updateLicenseLastKnownDate(int licenseId, DateTime date) async {
    final db = await database;
    await db.update(
      'licenses',
      {'lastKnownDate': date.toIso8601String()},
      where: 'id = ?',
      whereArgs: [licenseId],
    );
  }

  /// Reactivate a previously deactivated license
  Future<void> reactivateLicense(int licenseId) async {
    final db = await database;
    await db.update(
      'licenses',
      {'isActive': 1},
      where: 'id = ?',
      whereArgs: [licenseId],
    );
  }

  // ------------------------------------------------------------------
  // STAFF MANAGEMENT METHODS
  // ------------------------------------------------------------------

  /// Generate next staff ID (e.g., DAWOT/STF0001)
  Future<String> generateStaffId() async {
    final db = await database;

    // Get school short name from profile
    final profile = await db.query('school_profile', limit: 1);
    String shortName = profile.isNotEmpty
        ? (profile.first['shortName'] as String? ?? 'SCH')
        : 'SCH';
    shortName = shortName.toUpperCase().trim();
    if (shortName.isEmpty) shortName = 'SCH';

    // Get next serial number based on max existing serial to avoid collisions on delete
    final result = await db.rawQuery(
      "SELECT MAX(CAST(SUBSTR(staffId, INSTR(staffId, 'STF') + 3) AS INTEGER)) as maxSerial FROM staff WHERE staffId LIKE ?",
      ['$shortName/STF%'],
    );
    final maxSerial = ((result.first['maxSerial'] as int?) ?? 0);
    final serial = (maxSerial + 1).toString().padLeft(4, '0');

    return '$shortName/STF$serial';
  }

  /// Insert new staff
  Future<int> insertStaff(Map<String, dynamic> staff) async {
    final db = await database;
    final now = DateTime.now().toIso8601String();
    staff['createdAt'] = now;
    staff['updatedAt'] = now;
    return db.insert('staff', staff);
  }

  /// Get all staff (optionally include inactive)
  Future<List<Map<String, dynamic>>> getStaff({bool includeInactive = false}) async {
    final db = await database;
    if (includeInactive) {
      return db.query('staff', orderBy: 'surname ASC, firstName ASC');
    }
    return db.query('staff',
        where: 'isActive = ?',
        whereArgs: [1],
        orderBy: 'surname ASC, firstName ASC');
  }

  /// Get staff by ID
  Future<Map<String, dynamic>?> getStaffById(int id) async {
    final db = await database;
    final rows = await db.query('staff',
        where: 'id = ?', whereArgs: [id], limit: 1);
    return rows.isNotEmpty ? rows.first : null;
  }

  /// Get teaching staff only
  Future<List<Map<String, dynamic>>> getTeachingStaff() async {
    final db = await database;
    return db.query('staff',
        where: 'isActive = ? AND staffType = ?',
        whereArgs: [1, 'Teaching Staff'],
        orderBy: 'surname ASC, firstName ASC');
  }

  /// Update staff
  Future<int> updateStaff(int id, Map<String, dynamic> staff) async {
    final db = await database;
    staff['updatedAt'] = DateTime.now().toIso8601String();
    return db.update('staff', staff, where: 'id = ?', whereArgs: [id]);
  }

  /// Update staff salary
  Future<int> updateStaffSalary(int id, double salary) async {
    final db = await database;
    return db.update('staff', {
      'salary': salary,
      'updatedAt': DateTime.now().toIso8601String(),
    }, where: 'id = ?', whereArgs: [id]);
  }

  /// Deactivate staff. [deactivationDate] can be back-dated (e.g. the staff
  /// actually left months ago) so payroll/payment-record screens stop
  /// showing them for months after that date; defaults to now.
  Future<int> deactivateStaff(int id, {String? deactivationDate}) async {
    final db = await database;
    return db.update('staff', {
      'isActive': 0,
      'deactivationDate': deactivationDate ?? DateTime.now().toIso8601String(),
      'updatedAt': DateTime.now().toIso8601String(),
    }, where: 'id = ?', whereArgs: [id]);
  }

  /// Reactivate staff. Clears deactivationDate since they're active again.
  Future<int> reactivateStaff(int id) async {
    final db = await database;
    return db.update('staff', {
      'isActive': 1,
      'deactivationDate': null,
      'updatedAt': DateTime.now().toIso8601String(),
    }, where: 'id = ?', whereArgs: [id]);
  }

  /// Delete staff (use with caution)
  Future<int> deleteStaff(int id) async {
    final db = await database;
    // Also delete related allocations
    await db.delete('staff_class_allocations', where: 'staffId = ?', whereArgs: [id]);
    await db.delete('staff_office_allocations', where: 'staffId = ?', whereArgs: [id]);
    return db.delete('staff', where: 'id = ?', whereArgs: [id]);
  }

  // ------------------------------------------------------------------
  // STAFF OFFICES METHODS
  // ------------------------------------------------------------------

  /// Insert new staff office
  Future<int> insertStaffOffice(Map<String, dynamic> office) async {
    final db = await database;
    office['createdAt'] = DateTime.now().toIso8601String();
    return db.insert('staff_offices', office);
  }

  /// Get all staff offices
  Future<List<Map<String, dynamic>>> getStaffOffices() async {
    final db = await database;
    return db.query('staff_offices', orderBy: 'name ASC');
  }

  /// Get staff office by ID
  Future<Map<String, dynamic>?> getStaffOfficeById(int id) async {
    final db = await database;
    final rows = await db.query('staff_offices',
        where: 'id = ?', whereArgs: [id], limit: 1);
    return rows.isNotEmpty ? rows.first : null;
  }

  /// Update staff office
  Future<int> updateStaffOffice(int id, Map<String, dynamic> office) async {
    final db = await database;
    return db.update('staff_offices', office, where: 'id = ?', whereArgs: [id]);
  }

  /// Delete staff office
  Future<int> deleteStaffOffice(int id) async {
    final db = await database;
    // Also delete related allocations
    await db.delete('staff_office_allocations', where: 'officeId = ?', whereArgs: [id]);
    return db.delete('staff_offices', where: 'id = ?', whereArgs: [id]);
  }

  // ------------------------------------------------------------------
  // STAFF CLASS ALLOCATIONS METHODS
  // ------------------------------------------------------------------

  /// Insert staff class allocation
  Future<int> insertStaffClassAllocation(Map<String, dynamic> allocation) async {
    final db = await database;
    allocation['createdAt'] = DateTime.now().toIso8601String();
    return db.insert('staff_class_allocations', allocation);
  }

  /// Get all class allocations for a staff
  Future<List<Map<String, dynamic>>> getStaffClassAllocations(int staffId) async {
    final db = await database;
    return db.rawQuery('''
      SELECT
        sca.*,
        c.name as className,
        a.name as armName
      FROM staff_class_allocations sca
      LEFT JOIN classes c ON sca.classId = c.id
      LEFT JOIN arms a ON sca.armId = a.id
      WHERE sca.staffId = ?
      ORDER BY c.name ASC, a.name ASC
    ''', [staffId]);
  }

  /// Get all class allocations with staff info
  Future<List<Map<String, dynamic>>> getAllStaffClassAllocations() async {
    final db = await database;
    return db.rawQuery('''
      SELECT
        sca.*,
        s.surname || ' ' || s.firstName as staffName,
        s.staffType,
        c.name as className,
        a.name as armName
      FROM staff_class_allocations sca
      LEFT JOIN staff s ON sca.staffId = s.id
      LEFT JOIN classes c ON sca.classId = c.id
      LEFT JOIN arms a ON sca.armId = a.id
      WHERE s.isActive = 1
      ORDER BY s.surname ASC, s.firstName ASC
    ''');
  }

  /// Delete staff class allocation
  Future<int> deleteStaffClassAllocation(int id) async {
    final db = await database;
    return db.delete('staff_class_allocations', where: 'id = ?', whereArgs: [id]);
  }

  /// Delete all class allocations for a staff
  Future<int> deleteAllStaffClassAllocations(int staffId) async {
    final db = await database;
    return db.delete('staff_class_allocations', where: 'staffId = ?', whereArgs: [staffId]);
  }

  /// Update staff class allocation subjects
  Future<int> updateStaffClassAllocationSubjects(int id, String? subjectsTaught) async {
    final db = await database;
    return db.update('staff_class_allocations', {
      'subjectsTaught': subjectsTaught,
    }, where: 'id = ?', whereArgs: [id]);
  }

  // ------------------------------------------------------------------
  // STAFF OFFICE ALLOCATIONS METHODS
  // ------------------------------------------------------------------

  /// Insert staff office allocation
  Future<int> insertStaffOfficeAllocation(Map<String, dynamic> allocation) async {
    final db = await database;
    allocation['createdAt'] = DateTime.now().toIso8601String();
    return db.insert('staff_office_allocations', allocation);
  }

  /// Get all office allocations for a staff
  Future<List<Map<String, dynamic>>> getStaffOfficeAllocations(int staffId) async {
    final db = await database;
    return db.rawQuery('''
      SELECT
        soa.*,
        so.name as officeName
      FROM staff_office_allocations soa
      LEFT JOIN staff_offices so ON soa.officeId = so.id
      WHERE soa.staffId = ?
      ORDER BY so.name ASC
    ''', [staffId]);
  }

  /// Get all office allocations with staff info
  Future<List<Map<String, dynamic>>> getAllStaffOfficeAllocations() async {
    final db = await database;
    return db.rawQuery('''
      SELECT
        soa.*,
        s.surname || ' ' || s.firstName as staffName,
        s.staffType,
        so.name as officeName
      FROM staff_office_allocations soa
      LEFT JOIN staff s ON soa.staffId = s.id
      LEFT JOIN staff_offices so ON soa.officeId = so.id
      WHERE s.isActive = 1
      ORDER BY s.surname ASC, s.firstName ASC
    ''');
  }

  /// Delete staff office allocation
  Future<int> deleteStaffOfficeAllocation(int id) async {
    final db = await database;
    return db.delete('staff_office_allocations', where: 'id = ?', whereArgs: [id]);
  }

  /// Delete all office allocations for a staff
  Future<int> deleteAllStaffOfficeAllocations(int staffId) async {
    final db = await database;
    return db.delete('staff_office_allocations', where: 'staffId = ?', whereArgs: [staffId]);
  }

  // ------------------------------------------------------------------
  // STAFF INCENTIVES CRUD
  // ------------------------------------------------------------------

  /// Insert staff incentive
  Future<int> insertStaffIncentive(Map<String, dynamic> incentive) async {
    final db = await database;
    incentive['createdAt'] = DateTime.now().toIso8601String();
    return db.insert('staff_incentives', incentive);
  }

  /// Get all incentives for a month
  Future<List<Map<String, dynamic>>> getStaffIncentivesByMonth(String month) async {
    final db = await database;
    return db.query('staff_incentives', where: 'month = ?', whereArgs: [month], orderBy: 'createdAt DESC');
  }

  /// Get incentives for a specific staff and month
  Future<List<Map<String, dynamic>>> getStaffIncentivesForStaff(int staffId, String month) async {
    final db = await database;
    return db.query('staff_incentives', where: 'staffId = ? AND month = ?', whereArgs: [staffId, month]);
  }

  /// Get total incentives for a staff in a month
  Future<double> getTotalIncentivesForStaff(int staffId, String month) async {
    final db = await database;
    final result = await db.rawQuery(
      'SELECT SUM(amount) as total FROM staff_incentives WHERE staffId = ? AND month = ?',
      [staffId, month]
    );
    return (result.first['total'] as num?)?.toDouble() ?? 0;
  }

  /// Update staff incentive
  Future<int> updateStaffIncentive(int id, Map<String, dynamic> data) async {
    final db = await database;
    return db.update('staff_incentives', data, where: 'id = ?', whereArgs: [id]);
  }

  /// Delete staff incentive
  Future<int> deleteStaffIncentive(int id) async {
    final db = await database;
    return db.delete('staff_incentives', where: 'id = ?', whereArgs: [id]);
  }

  // ------------------------------------------------------------------
  // STAFF LOANS CRUD
  // ------------------------------------------------------------------

  /// Insert staff loan
  Future<int> insertStaffLoan(Map<String, dynamic> loan) async {
    final db = await database;
    loan['createdAt'] = DateTime.now().toIso8601String();
    return db.insert('staff_loans', loan);
  }

  /// Get all active loans
  Future<List<Map<String, dynamic>>> getActiveStaffLoans() async {
    final db = await database;
    return db.query('staff_loans', where: 'status = ?', whereArgs: ['Active'], orderBy: 'createdAt DESC');
  }

  /// Get all loans (any status) across all staff — used by screens that need
  /// full loan history (e.g. filtering Active vs Completed), unlike
  /// [getActiveStaffLoans] which only returns currently-active loans.
  Future<List<Map<String, dynamic>>> getAllStaffLoans() async {
    final db = await database;
    return db.query('staff_loans', orderBy: 'createdAt DESC');
  }

  /// Get loans for a specific staff
  Future<List<Map<String, dynamic>>> getStaffLoans(int staffId) async {
    final db = await database;
    return db.query('staff_loans', where: 'staffId = ?', whereArgs: [staffId], orderBy: 'createdAt DESC');
  }

  /// Get active loan deduction for a staff in a month
  Future<double> getLoanDeductionForStaff(int staffId) async {
    final db = await database;
    final result = await db.rawQuery(
      'SELECT SUM(deductionPerMonth) as total FROM staff_loans WHERE staffId = ? AND status = ?',
      [staffId, 'Active']
    );
    return (result.first['total'] as num?)?.toDouble() ?? 0;
  }

  /// Update staff loan
  Future<int> updateStaffLoan(int id, Map<String, dynamic> loan) async {
    final db = await database;
    return db.update('staff_loans', loan, where: 'id = ?', whereArgs: [id]);
  }

  /// Get a single staff loan by its id
  Future<Map<String, dynamic>?> getStaffLoanById(int id) async {
    final db = await database;
    final result = await db.query('staff_loans', where: 'id = ?', whereArgs: [id], limit: 1);
    return result.isNotEmpty ? result.first : null;
  }

  /// Delete staff loan
  Future<int> deleteStaffLoan(int id) async {
    final db = await database;
    return db.delete('staff_loans', where: 'id = ?', whereArgs: [id]);
  }

  // ------------------------------------------------------------------
  // STAFF DEDUCTIONS CRUD
  // ------------------------------------------------------------------

  /// Insert staff deduction
  Future<int> insertStaffDeduction(Map<String, dynamic> deduction) async {
    final db = await database;
    deduction['createdAt'] = DateTime.now().toIso8601String();
    return db.insert('staff_deductions', deduction);
  }

  /// Get all deductions for a month
  Future<List<Map<String, dynamic>>> getStaffDeductionsByMonth(String month) async {
    final db = await database;
    return db.query('staff_deductions', where: 'month = ?', whereArgs: [month], orderBy: 'date DESC');
  }

  /// Get deductions for a specific staff and month
  Future<List<Map<String, dynamic>>> getStaffDeductionsForStaff(int staffId, String month) async {
    final db = await database;
    return db.query('staff_deductions', where: 'staffId = ? AND month = ?', whereArgs: [staffId, month]);
  }

  /// Get total deductions for a staff in a month
  Future<double> getTotalDeductionsForStaff(int staffId, String month) async {
    final db = await database;
    final result = await db.rawQuery(
      'SELECT SUM(amount) as total FROM staff_deductions WHERE staffId = ? AND month = ?',
      [staffId, month]
    );
    return (result.first['total'] as num?)?.toDouble() ?? 0;
  }

  /// Delete staff deduction
  Future<int> deleteStaffDeduction(int id) async {
    final db = await database;
    return db.delete('staff_deductions', where: 'id = ?', whereArgs: [id]);
  }

  /// Update staff deduction
  Future<int> updateStaffDeduction(int id, Map<String, dynamic> data) async {
    final db = await database;
    return db.update('staff_deductions', data, where: 'id = ?', whereArgs: [id]);
  }

  // ------------------------------------------------------------------
  // STAFF SALARY PAYMENTS
  // ------------------------------------------------------------------

  /// Get staff salary payment status for a month
  Future<Map<String, dynamic>?> getStaffSalaryPayment(int staffId, String month) async {
    final db = await database;
    final result = await db.query(
      'staff_salary_payments',
      where: 'staffId = ? AND month = ?',
      whereArgs: [staffId, month],
      limit: 1,
    );
    return result.isNotEmpty ? result.first : null;
  }

  /// Get all salary payments for a month
  Future<List<Map<String, dynamic>>> getSalaryPaymentsByMonth(String month) async {
    final db = await database;
    return db.query('staff_salary_payments', where: 'month = ?', whereArgs: [month]);
  }

  /// Record (or clear, when null) which loan deductions were applied for a
  /// staff's salary payment in a given month, so marking the payment as
  /// NOT PAID can reverse exactly those deductions instead of losing track
  /// of what was taken off each loan.
  Future<void> setLoanDeductionsAppliedForPayment(int staffId, String month, String? json) async {
    final db = await database;
    await db.update(
      'staff_salary_payments',
      {'loanDeductionsApplied': json},
      where: 'staffId = ? AND month = ?',
      whereArgs: [staffId, month],
    );
  }

  /// Toggle staff salary payment status
  Future<void> toggleStaffSalaryPayment(int staffId, String month, bool isPaid, {String? paymentMethod, String? notes}) async {
    final db = await database;
    final now = DateTime.now().toIso8601String();

    // Check if record exists
    final existing = await getStaffSalaryPayment(staffId, month);

    if (existing != null) {
      // Update existing record
      await db.update(
        'staff_salary_payments',
        {
          'isPaid': isPaid ? 1 : 0,
          'paymentDate': isPaid ? now : null,
          'paymentMethod': paymentMethod,
          'notes': notes,
          'updatedAt': now,
        },
        where: 'id = ?',
        whereArgs: [existing['id']],
      );
    } else {
      // Insert new record
      await db.insert('staff_salary_payments', {
        'staffId': staffId,
        'month': month,
        'isPaid': isPaid ? 1 : 0,
        'paymentDate': isPaid ? now : null,
        'paymentMethod': paymentMethod,
        'notes': notes,
        'createdAt': now,
        'updatedAt': now,
      });
    }
  }

  /// Mark all staff as paid for a month
  Future<void> markAllStaffPaid(String month, List<int> staffIds, {String? paymentMethod}) async {
    for (var staffId in staffIds) {
      await toggleStaffSalaryPayment(staffId, month, true, paymentMethod: paymentMethod);
    }
  }

  /// Get paid staff count for a month
  Future<int> getPaidStaffCount(String month) async {
    final db = await database;
    final result = await db.rawQuery(
      'SELECT COUNT(*) as count FROM staff_salary_payments WHERE month = ? AND isPaid = 1',
      [month],
    );
    return (result.first['count'] as int?) ?? 0;
  }

  // ------------------------------------------------------------------
  // SALARY EXPENSE POSTINGS (Post to Expenses tracking)
  // ------------------------------------------------------------------

  /// Record that [amount] of a month's paid salary was posted to Expenses.
  Future<int> insertSalaryExpensePosting({
    required String month,
    required double amount,
    String? postedBy,
  }) async {
    final db = await database;
    return db.insert('salary_expense_postings', {
      'month': month,
      'amount': amount,
      'postedAt': DateTime.now().toIso8601String(),
      'postedBy': postedBy,
    });
  }

  /// Total amount already posted to Expenses for a month (sum of every
  /// posting made for it, since a month can be topped up more than once).
  Future<double> getTotalPostedForMonth(String month) async {
    final db = await database;
    final result = await db.rawQuery(
      'SELECT COALESCE(SUM(amount), 0) as total FROM salary_expense_postings WHERE month = ?',
      [month],
    );
    return (result.first['total'] as num? ?? 0).toDouble();
  }

  /// All posting records for a month, most recent first (for showing
  /// "posted ₦X on <date>" history).
  Future<List<Map<String, dynamic>>> getSalaryExpensePostings(String month) async {
    final db = await database;
    return db.query(
      'salary_expense_postings',
      where: 'month = ?',
      whereArgs: [month],
      orderBy: 'postedAt DESC',
    );
  }

  // ------------------------------------------------------------------
  // STAFF SALARY HISTORY (Increment tracking)
  // ------------------------------------------------------------------

  /// Insert a salary history entry when salary is incremented
  Future<int> insertSalaryHistory(int staffId, double salary, String effectiveMonth, {String? reason}) async {
    final db = await database;
    return db.insert('staff_salary_history', {
      'staffId': staffId,
      'salary': salary,
      'effectiveMonth': effectiveMonth,
      'reason': reason,
      'createdAt': DateTime.now().toIso8601String(),
    });
  }

  /// Get all salary history records for a staff member (newest first)
  Future<List<Map<String, dynamic>>> getSalaryHistory(int staffId) async {
    final db = await database;
    return db.query(
      'staff_salary_history',
      where: 'staffId = ?',
      whereArgs: [staffId],
      orderBy: 'createdAt DESC',
    );
  }

  /// Get salary history for all staff (for the increment overview screen)
  Future<List<Map<String, dynamic>>> getAllSalaryHistory() async {
    final db = await database;
    return db.rawQuery('''
      SELECT ssh.*, s.surname || ' ' || s.firstName as staffName, s.staffId as staffCode
      FROM staff_salary_history ssh
      JOIN staff s ON ssh.staffId = s.id
      ORDER BY ssh.createdAt DESC
    ''');
  }

  /// Delete a salary history entry
  Future<int> deleteSalaryHistory(int id) async {
    final db = await database;
    return db.delete('staff_salary_history', where: 'id = ?', whereArgs: [id]);
  }

  /// Get the applicable salary for a staff member for a given month.
  /// Looks at salary history and returns the most recent entry on or before the target month.
  /// Falls back to [fallbackSalary] (usually staff.salary) if no history found.
  Future<double> getSalaryForMonth(int staffId, String month, {double fallbackSalary = 0.0}) async {
    final db = await database;
    final history = await db.query(
      'staff_salary_history',
      where: 'staffId = ?',
      whereArgs: [staffId],
      orderBy: 'createdAt ASC',
    );

    if (history.isEmpty) return fallbackSalary;

    try {
      final targetDate = _parseMonth(month);
      if (targetDate == null) return fallbackSalary;

      double salary = fallbackSalary;
      for (final record in history) {
        final effectiveDate = _parseMonth(record['effectiveMonth'] as String);
        if (effectiveDate != null && !effectiveDate.isAfter(targetDate)) {
          salary = (record['salary'] as num).toDouble();
        }
      }
      return salary;
    } catch (_) {
      return fallbackSalary;
    }
  }

  /// Calculate salary arrears for a staff member.
  /// Arrears = sum of salary for each month before [selectedMonth] that has an
  /// explicit isPaid=0 record in staff_salary_payments.
  /// Stops accumulating when a paid month is found. Looks back up to [maxMonthsBack].
  Future<double> getSalaryArrearsForStaff(
    int staffId,
    String selectedMonth, {
    double fallbackSalary = 0.0,
    int maxMonthsBack = 24,
    String? employmentDate,
  }) async {
    double arrears = 0.0;

    try {
      final targetDate = _parseMonth(selectedMonth);
      if (targetDate == null) return 0.0;

      for (int i = 1; i <= maxMonthsBack; i++) {
        int m = targetDate.month - i;
        int y = targetDate.year;
        while (m <= 0) {
          m += 12;
          y--;
        }
        final prevMonth = _formatMonth(DateTime(y, m, 1));

        // Don't walk back past the staff's employment date — there's no
        // payroll obligation for months before they were hired.
        if (employmentDate != null && !isStaffEmployedByMonth(employmentDate, prevMonth)) break;

        final payment = await getStaffSalaryPayment(staffId, prevMonth);

        // Paid month found — stop counting arrears
        if (payment != null && (payment['isPaid'] as int) == 1) break;

        // Unpaid — either explicitly marked NOT PAID, or simply never marked
        // at all (the normal case: the toggle only ever writes a row when
        // marking PAID or reverting from it, so most unpaid months have no
        // row). Both count as arrears. Compute gross arrears for this month:
        // = Basic + Incentive − Deduction (loan NOT subtracted here;
        //   loan is tracked separately via getLoanArrearsForStaff and shown
        //   as accumulated in the loan deduction column)
        // Basic is pro-rated using whatever payroll basis (Full/Percentage/
        // Days/Weeks) was in effect for that missed month.
        final basicForMonth = await getProratedBasicSalaryForMonth(
          staffId,
          prevMonth,
          fallbackSalary: fallbackSalary,
        );
        final incentivesForMonth = await getIncentivesTotalForStaffMonth(staffId, prevMonth);
        final deductionsForMonth = await getDeductionsTotalForStaffMonth(staffId, prevMonth);
        arrears += basicForMonth + incentivesForMonth - deductionsForMonth;
      }
    } catch (_) {}

    return arrears;
  }

  /// Returns total incentives for a staff member in a specific month.
  Future<double> getIncentivesTotalForStaffMonth(int staffId, String month) async {
    final db = await database;
    final result = await db.rawQuery(
      'SELECT COALESCE(SUM(amount), 0) as total FROM staff_incentives WHERE staffId = ? AND month = ?',
      [staffId, month],
    );
    return (result.first['total'] as num? ?? 0).toDouble();
  }

  /// Returns total deductions/penalties for a staff member in a specific month.
  Future<double> getDeductionsTotalForStaffMonth(int staffId, String month) async {
    final db = await database;
    final result = await db.rawQuery(
      'SELECT COALESCE(SUM(amount), 0) as total FROM staff_deductions WHERE staffId = ? AND month = ?',
      [staffId, month],
    );
    return (result.first['total'] as num? ?? 0).toDouble();
  }

  /// Returns the total accumulated loan deduction amount for consecutive unpaid
  /// months before [selectedMonth]. Uses current active loan terms.
  Future<double> getLoanArrearsForStaff(
    int staffId,
    String selectedMonth, {
    int maxMonthsBack = 24,
    String? employmentDate,
  }) async {
    double arrears = 0.0;
    try {
      final targetDate = _parseMonth(selectedMonth);
      if (targetDate == null) return 0.0;

      final db = await database;
      final activeLoans = await db.query(
        'staff_loans',
        where: 'staffId = ? AND status = ?',
        whereArgs: [staffId, 'Active'],
      );
      if (activeLoans.isEmpty) return 0.0;

      final deductionPerMonth = activeLoans.fold<double>(
        0, (sum, l) => sum + (l['deductionPerMonth'] as num).toDouble(),
      );

      for (int i = 1; i <= maxMonthsBack; i++) {
        int m = targetDate.month - i;
        int y = targetDate.year;
        while (m <= 0) { m += 12; y--; }
        final prevMonth = _formatMonth(DateTime(y, m, 1));

        if (employmentDate != null && !isStaffEmployedByMonth(employmentDate, prevMonth)) break;

        final payment = await getStaffSalaryPayment(staffId, prevMonth);
        if (payment != null && (payment['isPaid'] as int) == 1) break;

        arrears += deductionPerMonth;
      }
    } catch (_) {}
    return arrears;
  }

  /// Returns the count of consecutive unpaid salary months before [selectedMonth].
  Future<int> getUnpaidMonthsCount(
    int staffId,
    String selectedMonth, {
    int maxMonthsBack = 24,
    String? employmentDate,
  }) async {
    int count = 0;
    try {
      final targetDate = _parseMonth(selectedMonth);
      if (targetDate == null) return 0;

      for (int i = 1; i <= maxMonthsBack; i++) {
        int m = targetDate.month - i;
        int y = targetDate.year;
        while (m <= 0) { m += 12; y--; }
        final prevMonth = _formatMonth(DateTime(y, m, 1));

        if (employmentDate != null && !isStaffEmployedByMonth(employmentDate, prevMonth)) break;

        final payment = await getStaffSalaryPayment(staffId, prevMonth);
        if (payment != null && (payment['isPaid'] as int) == 1) break;
        count++;
      }
    } catch (_) {}
    return count;
  }

  // ------------------------------------------------------------------
  // PAYROLL BASIS (Full / Percentage / Working Days / Working Weeks)
  // ------------------------------------------------------------------
  // Lets a school pro-rate staff basic salary for a month when a term
  // resumed partway through it. basisType is one of:
  //   'full'       — 100% of basic salary (default)
  //   'percentage' — percentageValue% of basic salary
  //   'days'       — workedUnits / totalUnits (Monday-Friday working days)
  //   'weeks'      — workedUnits / totalUnits (working weeks, ~4/month)
  // Only the basic salary is pro-rated; incentives, deductions and loan
  // repayments always apply in full for the month.

  /// Set (or replace) the month-wide default payroll basis. Staff without a
  /// per-staff override in staff_salary_payments use this for the month.
  Future<void> setPayrollMonthBasis(
    String month, {
    required String basisType,
    double? percentageValue,
    double? totalUnits,
    double? workedUnits,
  }) async {
    final db = await database;
    final now = DateTime.now().toIso8601String();
    final existing = await db.query(
      'payroll_month_settings',
      where: 'month = ?',
      whereArgs: [month],
      limit: 1,
    );
    final data = {
      'month': month,
      'basisType': basisType,
      'percentageValue': percentageValue,
      'totalUnits': totalUnits,
      'workedUnits': workedUnits,
      'updatedAt': now,
    };
    if (existing.isNotEmpty) {
      await db.update(
        'payroll_month_settings',
        data,
        where: 'id = ?',
        whereArgs: [existing.first['id']],
      );
    } else {
      await db.insert('payroll_month_settings', {...data, 'createdAt': now});
    }
  }

  /// Get the month-wide default payroll basis, if one has been set.
  Future<Map<String, dynamic>?> getPayrollMonthBasis(String month) async {
    final db = await database;
    final result = await db.query(
      'payroll_month_settings',
      where: 'month = ?',
      whereArgs: [month],
      limit: 1,
    );
    return result.isNotEmpty ? result.first : null;
  }

  /// Set a per-staff payroll basis override for a month. Creates the
  /// staff_salary_payments row if one doesn't exist yet (isPaid stays
  /// unaffected/defaults to unpaid).
  Future<void> setStaffPayrollBasisOverride(
    int staffId,
    String month, {
    required String basisType,
    double? percentageValue,
    double? totalUnits,
    double? workedUnits,
  }) async {
    final db = await database;
    final now = DateTime.now().toIso8601String();
    final existing = await getStaffSalaryPayment(staffId, month);
    final data = {
      'basisType': basisType,
      'percentageValue': percentageValue,
      'totalUnits': totalUnits,
      'workedUnits': workedUnits,
      'updatedAt': now,
    };
    if (existing != null) {
      await db.update(
        'staff_salary_payments',
        data,
        where: 'id = ?',
        whereArgs: [existing['id']],
      );
    } else {
      await db.insert('staff_salary_payments', {
        ...data,
        'staffId': staffId,
        'month': month,
        'isPaid': 0,
        'createdAt': now,
      });
    }
  }

  /// Clear a per-staff payroll basis override, reverting that staff to the
  /// month-wide default (or Full Payment if no default is set).
  Future<void> clearStaffPayrollBasisOverride(int staffId, String month) async {
    final db = await database;
    final existing = await getStaffSalaryPayment(staffId, month);
    if (existing == null) return;
    await db.update(
      'staff_salary_payments',
      {
        'basisType': null,
        'percentageValue': null,
        'totalUnits': null,
        'workedUnits': null,
        'updatedAt': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [existing['id']],
    );
  }

  /// Resolves the effective payroll basis for a staff member in a month:
  /// a per-staff override takes precedence, otherwise the month-wide
  /// default, otherwise Full Payment (100%).
  Future<Map<String, dynamic>> resolvePayrollBasis(int staffId, String month) async {
    final staffPayment = await getStaffSalaryPayment(staffId, month);
    if (staffPayment != null && staffPayment['basisType'] != null) {
      return {
        'basisType': staffPayment['basisType'],
        'percentageValue': staffPayment['percentageValue'],
        'totalUnits': staffPayment['totalUnits'],
        'workedUnits': staffPayment['workedUnits'],
        'isOverride': true,
      };
    }

    final monthDefault = await getPayrollMonthBasis(month);
    if (monthDefault != null) {
      return {
        'basisType': monthDefault['basisType'],
        'percentageValue': monthDefault['percentageValue'],
        'totalUnits': monthDefault['totalUnits'],
        'workedUnits': monthDefault['workedUnits'],
        'isOverride': false,
      };
    }

    return {
      'basisType': 'full',
      'percentageValue': null,
      'totalUnits': null,
      'workedUnits': null,
      'isOverride': false,
    };
  }

  /// Pro-ration factor (e.g. 0.75 for 75%) for a resolved basis map.
  double payrollBasisFactor(Map<String, dynamic> basis) {
    final type = basis['basisType'] as String? ?? 'full';
    switch (type) {
      case 'percentage':
        final pct = (basis['percentageValue'] as num?)?.toDouble() ?? 100.0;
        return pct / 100.0;
      case 'days':
      case 'weeks':
        final total = (basis['totalUnits'] as num?)?.toDouble() ?? 0.0;
        final worked = (basis['workedUnits'] as num?)?.toDouble() ?? 0.0;
        if (total <= 0) return 1.0;
        return worked / total;
      case 'full':
      default:
        return 1.0;
    }
  }

  /// Basic salary for [staffId] in [month] after applying the resolved
  /// payroll basis (Full/Percentage/Days/Weeks pro-ration).
  Future<double> getProratedBasicSalaryForMonth(
    int staffId,
    String month, {
    double fallbackSalary = 0.0,
  }) async {
    final basic = await getSalaryForMonth(staffId, month, fallbackSalary: fallbackSalary);
    final basis = await resolvePayrollBasis(staffId, month);
    return basic * payrollBasisFactor(basis);
  }

  /// Number of Monday-Friday working days in the given "MMMM yyyy" month.
  int getWorkingDaysInMonth(String month) {
    final date = _parseMonth(month);
    if (date == null) return 0;
    final daysInMonth = DateTime(date.year, date.month + 1, 0).day;
    int count = 0;
    for (int d = 1; d <= daysInMonth; d++) {
      final weekday = DateTime(date.year, date.month, d).weekday;
      if (weekday >= 1 && weekday <= 5) count++;
    }
    return count;
  }

  /// Helper: parse "MMMM yyyy" string to DateTime (day=1)
  DateTime? _parseMonth(String month) {
    try {
      final parts = month.split(' ');
      if (parts.length != 2) return null;
      const months = {
        'January': 1, 'February': 2, 'March': 3, 'April': 4,
        'May': 5, 'June': 6, 'July': 7, 'August': 8,
        'September': 9, 'October': 10, 'November': 11, 'December': 12,
      };
      final m = months[parts[0]];
      final y = int.tryParse(parts[1]);
      if (m == null || y == null) return null;
      return DateTime(y, m, 1);
    } catch (_) {
      return null;
    }
  }

  /// Helper: format DateTime to "MMMM yyyy" string
  String _formatMonth(DateTime date) {
    const names = [
      '', 'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December',
    ];
    return '${names[date.month]} ${date.year}';
  }

  /// Returns true if a staff member should appear in payroll for the given
  /// "MMMM yyyy" month — i.e. their employment date falls on or before that
  /// month. Staff hired partway through a month still appear for that same
  /// month, but never for months before they were employed. Staff with no
  /// recorded employment date are always included (legacy records).
  bool isStaffEmployedByMonth(String? dateOfEmployment, String month) {
    if (dateOfEmployment == null || dateOfEmployment.isEmpty) return true;
    final targetDate = _parseMonth(month);
    if (targetDate == null) return true;
    try {
      final empDate = DateTime.parse(dateOfEmployment);
      final empMonthStart = DateTime(empDate.year, empDate.month, 1);
      return !empMonthStart.isAfter(targetDate);
    } catch (_) {
      return true;
    }
  }

  /// Returns true if a staff member should appear in payroll for the given
  /// "MMMM yyyy" month based on their (possibly back-dated) deactivation
  /// date — i.e. the month is on or before the month they were deactivated.
  /// Staff who are still active (no deactivation date) always pass.
  bool isStaffActiveByMonth(String? deactivationDate, String month) {
    if (deactivationDate == null || deactivationDate.isEmpty) return true;
    final targetDate = _parseMonth(month);
    if (targetDate == null) return true;
    try {
      final deactDate = DateTime.parse(deactivationDate);
      final deactMonthStart = DateTime(deactDate.year, deactDate.month, 1);
      return !targetDate.isAfter(deactMonthStart);
    } catch (_) {
      return true;
    }
  }

  /// Get all inactive staff
  Future<List<Map<String, dynamic>>> getInactiveStaff() async {
    final db = await database;
    return db.query(
      'staff',
      where: 'isActive = ?',
      whereArgs: [0],
      orderBy: 'surname ASC, firstName ASC',
    );
  }

  // ------------------------------------------------------------------
  // ------------------------------------------------------------------
  // FEE PRIORITY (Fee Tracker)
  // ------------------------------------------------------------------

  Future<List<Map<String, dynamic>>> getFeePriorities({
    required String scope,
    int? classId,
    int? armId,
    required String term,
    required String session,
  }) async {
    final db = await database;
    String where = 'scope = ? AND term = ? AND session = ?';
    List<dynamic> args = [scope, term, session];

    if (scope == 'class' && classId != null) {
      where += ' AND classId = ?';
      args.add(classId);
    } else if (scope == 'class_arm' && classId != null) {
      where += ' AND classId = ?';
      args.add(classId);
      if (armId != null) {
        where += ' AND armId = ?';
        args.add(armId);
      }
    }

    return db.query('fee_priority',
      where: where,
      whereArgs: args,
      orderBy: 'priority ASC',
    );
  }

  Future<void> saveFeePriorities({
    required String scope,
    int? classId,
    int? armId,
    required String term,
    required String session,
    required List<Map<String, dynamic>> priorities,
  }) async {
    final db = await database;
    await db.transaction((txn) async {
      // Delete existing priorities for this scope
      String where = 'scope = ? AND term = ? AND session = ?';
      List<dynamic> args = [scope, term, session];

      if (scope == 'class' && classId != null) {
        where += ' AND classId = ?';
        args.add(classId);
      } else if (scope == 'class_arm' && classId != null) {
        where += ' AND classId = ?';
        args.add(classId);
        if (armId != null) {
          where += ' AND armId = ?';
          args.add(armId);
        }
      }

      await txn.delete('fee_priority', where: where, whereArgs: args);

      // Insert new priorities
      for (final p in priorities) {
        await txn.insert('fee_priority', {
          'scope': scope,
          'classId': classId,
          'armId': armId,
          'feeItemId': p['feeItemId'],
          'priority': p['priority'],
          'term': term,
          'session': session,
        });
      }
    });
  }

  /// Get effective priorities for a student (class_arm > class > global fallback)
  Future<List<Map<String, dynamic>>> getEffectiveFeePriorities({
    required int classId,
    int? armId,
    required String term,
    required String session,
  }) async {
    // Try class_arm first
    if (armId != null) {
      var priorities = await getFeePriorities(
        scope: 'class_arm', classId: classId, armId: armId,
        term: term, session: session,
      );
      if (priorities.isNotEmpty) return priorities;
    }

    // Fall back to class
    var priorities = await getFeePriorities(
      scope: 'class', classId: classId,
      term: term, session: session,
    );
    if (priorities.isNotEmpty) return priorities;

    // Fall back to global
    return getFeePriorities(
      scope: 'global', term: term, session: session,
    );
  }

  /// Get students who have a specific fee item in their bill
  Future<List<Map<String, dynamic>>> getStudentsWithFeeItem({
    required int feeItemId,
    required String term,
    required String session,
    int? classId,
    int? armId,
  }) async {
    final db = await database;

    String classFilter = '';
    final targetKey = termSortKey(term, session);
    // args order: targetKey×2 (sort key for b2/p2), term/session (payments), feeItemId, term/session (WHERE)
    List<dynamic> args = [targetKey, targetKey, term, session, feeItemId, term, session];

    if (classId != null) {
      classFilter += ' AND s.classId = ?';
      args.add(classId);
    }
    if (armId != null) {
      classFilter += ' AND s.armId = ?';
      args.add(armId);
    }

    return db.rawQuery('''
      SELECT
        s.id as studentId,
        s.admissionNo,
        s.surname,
        s.firstName,
        s.classId,
        s.armId,
        s.parentPhone,
        c.name as className,
        a.name as armName,
        sfb.amount as feeAmount,
        sb.id as billId,
        (COALESCE(sb.totalAmount, 0) - COALESCE(sb.previousBalance, 0)) as currentTermFee,
        MAX(0,
          COALESCE((SELECT SUM(b2.totalAmount - b2.previousBalance) FROM student_bills b2
                    WHERE b2.studentId = s.id AND ${_sqlTermKey('b2')} < ?), 0)
          -
          COALESCE((SELECT SUM(p2.amount) FROM payments p2
                    WHERE p2.studentId = s.id AND ${_sqlTermKey('p2')} < ?), 0)
        ) as freshPreviousBalance,
        COALESCE(
          (SELECT SUM(p.amount)
           FROM payments p
           WHERE p.studentId = s.id
             AND p.term = ?
             AND p.session = ?),
          0
        ) as totalPaid
      FROM student_fee_breakdown sfb
      JOIN student_bills sb ON sfb.billId = sb.id
      JOIN students s ON sb.studentId = s.id
      JOIN classes c ON s.classId = c.id
      LEFT JOIN arms a ON s.armId = a.id
      WHERE sfb.feeItemId = ?
        AND sb.term = ?
        AND sb.session = ?
        AND s.isActive = 1
        $classFilter
      ORDER BY s.surname, s.firstName
    ''', args);
  }

  /// Get payment progression data for students
  Future<List<Map<String, dynamic>>> getPaymentProgressionData({
    required String term,
    required String session,
    int? classId,
    int? armId,
  }) async {
    final db = await database;

    String classFilter = '';
    final targetKey = termSortKey(term, session);
    // args order: targetKey×2 (sort key for b2/p2), term/session×2 (payments & bill join)
    List<dynamic> args = [targetKey, targetKey, term, session, term, session];

    if (classId != null) {
      classFilter += ' AND s.classId = ?';
      args.add(classId);
    }
    if (armId != null) {
      classFilter += ' AND s.armId = ?';
      args.add(armId);
    }

    return db.rawQuery('''
      SELECT
        s.id as studentId,
        s.admissionNo,
        s.surname,
        s.firstName,
        s.classId,
        s.armId,
        s.parentPhone,
        c.name as className,
        a.name as armName,
        sb.id as billId,
        (COALESCE(sb.totalAmount, 0) - COALESCE(sb.previousBalance, 0)) as currentTermFee,
        MAX(0,
          COALESCE((SELECT SUM(b2.totalAmount - b2.previousBalance) FROM student_bills b2
                    WHERE b2.studentId = s.id AND ${_sqlTermKey('b2')} < ?), 0)
          -
          COALESCE((SELECT SUM(p2.amount) FROM payments p2
                    WHERE p2.studentId = s.id AND ${_sqlTermKey('p2')} < ?), 0)
        ) as freshPreviousBalance,
        COALESCE(
          (SELECT SUM(p.amount)
           FROM payments p
           WHERE p.studentId = s.id
             AND p.term = ?
             AND p.session = ?),
          0
        ) as totalPaid
      FROM students s
      JOIN classes c ON s.classId = c.id
      LEFT JOIN arms a ON s.armId = a.id
      LEFT JOIN student_bills sb ON s.id = sb.studentId
        AND sb.term = ?
        AND sb.session = ?
      WHERE s.isActive = 1
        $classFilter
      ORDER BY s.surname, s.firstName
    ''', args);
  }

  /// Get fee items that appear in student bills for a given class/arm
  /// but are NOT assigned as class-default fees — i.e., student-specific extras.
  Future<List<Map<String, dynamic>>> getExtraFeeItemsForClassArm({
    required int classId,
    int? armId,
    required String term,
    required String session,
  }) async {
    final db = await database;

    final String armStudentFilter = armId != null ? 'AND s.armId = ?' : '';
    final String armClassFeeFilter =
        armId != null ? 'AND (cf.armId IS NULL OR cf.armId = ?)' : '';

    final List<dynamic> args = [term, session, classId];
    if (armId != null) args.add(armId);
    args.addAll([classId, term, session]);
    if (armId != null) args.add(armId);

    return db.rawQuery('''
      SELECT DISTINCT
        sfb.feeItemId,
        COALESCE(fi.name, sfb.label, 'Unknown Fee') AS feeName
      FROM student_fee_breakdown sfb
      JOIN student_bills sb ON sfb.billId = sb.id
      JOIN students s ON sb.studentId = s.id
      LEFT JOIN fee_items fi ON sfb.feeItemId = fi.id
      WHERE sb.term = ?
        AND sb.session = ?
        AND s.classId = ?
        AND s.isActive = 1
        $armStudentFilter
        AND sfb.feeItemId > 0
        AND sfb.feeItemId NOT IN (
          SELECT cf.feeItemId FROM class_fees cf
          WHERE cf.classId = ?
            AND cf.term = ?
            AND cf.session = ?
            $armClassFeeFilter
        )
      ORDER BY feeName
    ''', args);
  }

  // CLOSE DB
  // ------------------------------------------------------------------
  Future<void> close() async {
    final db = await database;
    await db.close();
    _database = null;
  }
}