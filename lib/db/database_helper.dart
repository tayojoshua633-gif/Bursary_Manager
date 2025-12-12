// lib/db/database_helper.dart
import 'dart:async';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

class DatabaseHelper {
  // Singleton
  static final DatabaseHelper _instance = DatabaseHelper._internal();
  factory DatabaseHelper() => _instance;
  DatabaseHelper._internal();

  static Database? _database;
  // bumped DB version to add deactivation columns + users table
  static const int _dbVersion = 7;
  static const String _dbName = 'bursary_manager.db';
  static const String _kActiveTerm = 'activeTerm';

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
        parentName TEXT NOT NULL,
        parentPhone TEXT NOT NULL,
        parentEmail TEXT,
        parentAddress TEXT,
        photoPath TEXT,
        isActive INTEGER NOT NULL DEFAULT 1,
        leftDate TEXT,
        leftReason TEXT
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
        feeItemId INTEGER NOT NULL,
        amount REAL NOT NULL,
        term TEXT NOT NULL,
        session TEXT NOT NULL
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
        session TEXT
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
        shortName TEXT
      )
    ''');

    // SETTINGS
    await db.execute('''
      CREATE TABLE settings (
        key TEXT PRIMARY KEY,
        value TEXT
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

    // Seed default data
    await db.insert('sessions', {'sessionName': '2025/2026', 'isActive': 1});
    await db.insert('settings', {'key': _kActiveTerm, 'value': '1st Term'});

    // Seed default users
    await db.insert('users', {
      'username': 'superadmin',
      'password': 'qwerty12345',
      'userType': 'super_admin',
      'canChangeCredentials': 0,
      'createdAt': DateTime.now().toIso8601String(),
    });

    await db.insert('users', {
      'username': 'bursar',
      'password': 'admin',
      'userType': 'bursar',
      'canChangeCredentials': 1,
      'createdAt': DateTime.now().toIso8601String(),
    });
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
        await db.insert('users', {
          'username': 'superadmin',
          'password': 'qwerty12345',
          'userType': 'super_admin',
          'canChangeCredentials': 0,
          'createdAt': DateTime.now().toIso8601String(),
        });

        await db.insert('users', {
          'username': 'bursar',
          'password': 'admin',
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
  Future<int> insertStudent(Map<String, dynamic> student) async {
    final db = await database;
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

  // Convenience: only active
  Future<List<Map<String, dynamic>>> getActiveStudents() async {
    return getStudents(includeInactive: false);
  }

  // Convenience: only inactive
  Future<List<Map<String, dynamic>>> getInactiveStudents() async {
    final db = await database;
    return db.query('students',
        where: 'isActive = ?',
        whereArgs: [0],
        orderBy: 'surname ASC, firstName ASC');
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
    
    // Get count of all students (active + inactive) to generate serial number
    final result = await db.rawQuery('SELECT COUNT(*) as count FROM students');
    final count = (result.first['count'] as int?) ?? 0;
    final nextNumber = count + 1;
    final serial = nextNumber.toString().padLeft(4, '0');
    
    return '$shortName/$sessionYear/$serial';
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

  Future<List<Map<String, dynamic>>> getClassFees(int classId, String term, String session) async {
    final db = await database;
    return db.query('class_fees',
        where: 'classId = ? AND term = ? AND session = ?',
        whereArgs: [classId, term, session]);
  }

  Future<int> deleteClassFee(int id) async {
    final db = await database;
    return db.delete('class_fees', where: 'id = ?', whereArgs: [id]);
  }

  // replaceClassFeesFor: removes old fees and inserts new ones
  Future<void> replaceClassFeesFor(int classId, String term, String session, List<Map<String, dynamic>> fees) async {
    final db = await database;

    await db.transaction((txn) async {
      // Delete existing fees for this class/term/session
      await txn.delete(
        'class_fees',
        where: 'classId = ? AND term = ? AND session = ?',
        whereArgs: [classId, term, session],
      );

      // Insert new fees
      for (var fee in fees) {
        await txn.insert('class_fees', {
          'classId': classId,
          'feeItemId': fee['feeItemId'],
          'amount': fee['amount'],
          'term': term,
          'session': session,
        });
      }
    });
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

    final bill = await db.rawQuery('SELECT COALESCE(SUM(totalAmount), 0) AS t FROM student_bills WHERE studentId = ? AND term = ? AND session = ?', [studentId, term, session]);
    final pay = await db.rawQuery('SELECT COALESCE(SUM(amount), 0) AS t FROM payments WHERE studentId = ? AND term = ? AND session = ?', [studentId, term, session]);

    final totalBills = (bill.first['t'] ?? 0) as num;
    final totalPays = (pay.first['t'] ?? 0) as num;

    return (totalBills - totalPays).toDouble();
  }

  // ------------------------------------------------------------------
  // computeOutstandingBeforeTerm – Option A carry-over logic
  // (returns unpaid balance for the immediate previous term/session)
  // ------------------------------------------------------------------
  Future<double> computeOutstandingBeforeTerm(int studentId, {required String term, required String session}) async {
    // Determine previous term/session (Option A)
    final prev = _previousTermSession(term: term, session: session);
    if (prev == null) {
      // fallback: sum all previous bills/payments (safe fallback)
      return computeOutstandingBalance(studentId);
    }

    final prevTerm = prev['term']!;
    final prevSession = prev['session']!;

    return computeOutstandingForTermSession(studentId, term: prevTerm, session: prevSession);
  }

  // Helper to compute the previous term/session based on conventional ordering
  // Terms used: "1st Term", "2nd Term", "3rd Term"
  Map<String, String>? _previousTermSession({required String term, required String session}) {
    final normalizedTerm = term.trim().toLowerCase();

    // If term matches known patterns
    if (normalizedTerm == '1st term' || normalizedTerm == '1st' || normalizedTerm == 'first term') {
      // previous is 3rd Term of previous session
      final prevSession = _previousSessionName(session);
      if (prevSession == null) return null;
      return {'term': '3rd Term', 'session': prevSession};
    } else if (normalizedTerm == '2nd term' || normalizedTerm == '2nd' || normalizedTerm == 'second term') {
      return {'term': '1st Term', 'session': session};
    } else if (normalizedTerm == '3rd term' || normalizedTerm == '3rd' || normalizedTerm == 'third term') {
      return {'term': '2nd Term', 'session': session};
    } else {
      // unknown term format – fallback to null (caller can fallback further)
      return null;
    }
  }

  // Parse session like "2025/2026" -> return previous "2024/2025"
  String? _previousSessionName(String session) {
    try {
      final parts = session.split('/');
      if (parts.length == 2) {
        final a = int.tryParse(parts[0]);
        final b = int.tryParse(parts[1]);
        if (a != null && b != null && b == a + 1) {
          final prevA = a - 1;
          final prevB = a;
          return "$prevA/$prevB";
        }
      }
    } catch (_) {}
    return null;
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
  // OUTSTANDING (total across all terms & sessions)
  // ------------------------------------------------------------------
  Future<double> computeOutstandingBalance(int studentId) async {
    final db = await database;

    final bill = await db.rawQuery('SELECT COALESCE(SUM(totalAmount), 0) AS t FROM student_bills WHERE studentId = ?', [studentId]);
    final pay = await db.rawQuery('SELECT COALESCE(SUM(amount), 0) AS t FROM payments WHERE studentId = ?', [studentId]);

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

    // Query to get students with their bill and payment information
    final result = await db.rawQuery('''
      SELECT 
        s.id as studentId,
        s.admissionNo,
        s.surname,
        s.firstName,
        s.otherName,
        s.classId,
        c.name as className,
        COALESCE(b.totalAmount, 0) as totalBill,
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
      LEFT JOIN student_bills b ON s.id = b.studentId 
        AND b.term = ? 
        AND b.session = ?
      WHERE s.classId = ?
        AND s.isActive = 1
      ORDER BY s.surname, s.firstName
    ''', [term, session, term, session, classId]);

    // Calculate outstanding and percentage, then filter
    final debtors = <Map<String, dynamic>>[];

    for (var row in result) {
      final totalBill = (row['totalBill'] as num).toDouble();
      final totalPaid = (row['totalPaid'] as num).toDouble();
      final outstanding = totalBill - totalPaid;
      
      // Calculate percentage paid (avoid division by zero)
      final percentPaid = totalBill > 0 ? (totalPaid / totalBill) * 100 : 0.0;

      // Filter logic:
      // - If minPercentagePaid = 0: Show ALL students with outstanding balance
      // - If minPercentagePaid = 50: Show students who paid LESS than 50%
      // - If minPercentagePaid = 80: Show students who paid LESS than 80%
      
      bool includeStudent = false;
      
      if (outstanding > 0) {
        if (minPercentagePaid == 0.0) {
          // Show all debtors regardless of percentage
          includeStudent = true;
        } else {
          // Show only debtors who paid less than the threshold
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
          'totalBill': totalBill,
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

    String classFilter = classId != null ? 'AND s.classId = ?' : '';
    List<dynamic> params = [term, session, term, session];
    if (classId != null) params.add(classId);

    final result = await db.rawQuery('''
      SELECT 
        COUNT(DISTINCT s.id) as totalStudents,
        COUNT(DISTINCT CASE 
          WHEN COALESCE(b.totalAmount, 0) - COALESCE(
            (SELECT SUM(p.amount) 
             FROM payments p 
             WHERE p.studentId = s.id 
               AND p.term = ? 
               AND p.session = ?), 
            0
          ) > 0 THEN s.id 
        END) as totalDebtors,
        SUM(COALESCE(b.totalAmount, 0)) as totalBills,
        SUM(COALESCE(
          (SELECT SUM(p.amount) 
           FROM payments p 
           WHERE p.studentId = s.id 
             AND p.term = ? 
             AND p.session = ?), 
          0
        )) as totalPaid
      FROM students s
      LEFT JOIN student_bills b ON s.id = b.studentId 
        AND b.term = ? 
        AND b.session = ?
      WHERE s.isActive = 1
        $classFilter
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
  // USER AUTHENTICATION (NEW)
  // ------------------------------------------------------------------
  
  /// Authenticate user with username and password
  Future<Map<String, dynamic>?> authenticateUser(String username, String password) async {
    final db = await database;
    final result = await db.query(
      'users',
      where: 'username = ? AND password = ?',
      whereArgs: [username, password],
      limit: 1,
    );
    
    return result.isNotEmpty ? result.first : null;
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
    
    try {
      final count = await db.update(
        'users',
        {
          'username': newUsername,
          'password': newPassword,
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
    
    try {
      final count = await db.update(
        'users',
        {
          'username': newUsername,
          'password': newPassword,
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
  // CLOSE DB
  // ------------------------------------------------------------------
  Future<void> close() async {
    final db = await database;
    await db.close();
    _database = null;
  }
}