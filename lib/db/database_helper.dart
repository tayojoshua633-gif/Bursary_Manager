// lib/db/database_helper.dart
import 'dart:async';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

class DatabaseHelper {
  static final DatabaseHelper _instance = DatabaseHelper._internal();
  factory DatabaseHelper() => _instance;
  DatabaseHelper._internal();

  static Database? _database;
  static const int _dbVersion = 4;
  static const String _dbName = 'bursary_manager.db';
  static const String _kActiveTerm = 'activeTerm';

  // -------------------------------------------------------
  // GET DATABASE
  // -------------------------------------------------------
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

  // -------------------------------------------------------
  // ON CREATE
  // -------------------------------------------------------
  Future _onCreate(Database db, int version) async {
    // STUDENTS
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
        photoPath TEXT
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

    // CLASS—FEE ASSIGNMENTS
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

    // SEED DEFAULT SESSION + TERM
    await db.insert('sessions', {'sessionName': '2025/2026', 'isActive': 1});
    await db.insert('settings', {'key': _kActiveTerm, 'value': '1st Term'});
  }

  // -------------------------------------------------------
  // ON UPGRADE
  // -------------------------------------------------------
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

    // RESEED SESSION IF EMPTY
    final sess = await db.query('sessions', limit: 1);
    if (sess.isEmpty) {
      await db.insert('sessions', {'sessionName': '2025/2026', 'isActive': 1});
    }

    // RESEED TERM IF EMPTY
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

  // -------------------------------------------------------
  // TERM & SESSION
  // -------------------------------------------------------
  Future<String> getActiveTerm() async {
    final db = await database;
    final rows = await db.query(
      'settings',
      where: 'key = ?',
      whereArgs: [_kActiveTerm],
      limit: 1,
    );

    if (rows.isEmpty) return '1st Term';
    return rows.first['value']?.toString() ?? '1st Term';
  }

  Future<void> setActiveTerm(String term) async {
    final db = await database;
    await db.insert(
      'settings',
      {'key': _kActiveTerm, 'value': term},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<Map<String, dynamic>>> getSessions() async {
    final db = await database;
    return db.query('sessions', orderBy: 'sessionName DESC');
  }

  Future<Map<String, dynamic>?> getActiveSession() async {
    final db = await database;
    final r = await db.query('sessions', where: 'isActive = 1', limit: 1);
    return r.isNotEmpty ? r.first : null;
  }

  // -------------------------------------------------------
  // ADMISSION NUMBER GENERATOR
  // -------------------------------------------------------
  Future<String> generateAdmissionNumber() async {
    final db = await database;

    // GET SCHOOL SHORT NAME
    final schoolRows = await db.query('school_profile', limit: 1);
    final shortName = (schoolRows.isNotEmpty &&
            schoolRows.first['shortName'] != null &&
            schoolRows.first['shortName'].toString().trim().isNotEmpty)
        ? schoolRows.first['shortName'].toString().trim().toUpperCase()
        : 'SCHOOL';

    // GET ACTIVE SESSION
    final sess = await getActiveSession();
    String sessionName = '2025/2026';
    if (sess != null && sess['sessionName'] != null) {
      sessionName = sess['sessionName'].toString();
    }

    final startYear = sessionName.split('/').first;

    // COUNT EXISTING STUDENTS
    final res = await db.rawQuery(
      "SELECT COUNT(*) AS c FROM students WHERE admissionNo LIKE ?",
      ["$shortName/$startYear/%"],
    );

    final raw = res.first['c'];
    final int count =
        raw is int ? raw : int.tryParse(raw.toString()) ?? 0;

    final next = count + 1;

    return "$shortName/$startYear/${next.toString().padLeft(4, '0')}";
  }

  // -------------------------------------------------------
  // STUDENTS
  // -------------------------------------------------------
  Future<int> insertStudent(Map<String, dynamic> data) async {
    final db = await database;
    return await db.insert('students', data);
  }

  Future<int> updateStudent(int id, Map<String, dynamic> data) async {
    final db = await database;
    return db.update('students', data,
        where: 'id = ?', whereArgs: [id]);
  }

  Future<int> deleteStudent(int id) async {
    final db = await database;
    return db.delete('students', where: 'id = ?', whereArgs: [id]);
  }

  Future<Map<String, dynamic>?> getStudentById(int id) async {
    final db = await database;
    final rows = await db.rawQuery('''
      SELECT s.*, c.name AS className, a.name AS armName
      FROM students s
      LEFT JOIN classes c ON s.classId = c.id
      LEFT JOIN arms a ON s.armId = a.id
      WHERE s.id = ?
    ''', [id]);
    return rows.isNotEmpty ? rows.first : null;
  }

  Future<List<Map<String, dynamic>>> getAllStudents() async {
    final db = await database;
    return db.rawQuery('''
      SELECT s.*, c.name AS className, a.name AS armName
      FROM students s
      LEFT JOIN classes c ON s.classId = c.id
      LEFT JOIN arms a ON s.armId = a.id
      ORDER BY s.surname ASC
    ''');
  }

  Future<List<Map<String, dynamic>>> searchStudents(String kw) async {
    final db = await database;
    return db.rawQuery(
      '''
      SELECT s.*, c.name AS className, a.name AS armName
      FROM students s
      LEFT JOIN classes c ON s.classId = c.id
      LEFT JOIN arms a ON s.armId = a.id
      WHERE s.surname LIKE ? 
         OR s.firstName LIKE ? 
         OR s.admissionNo LIKE ?
      ORDER BY s.surname ASC
    ''',
      ['%$kw%', '%$kw%', '%$kw%'],
    );
  }

  // -------------------------------------------------------
  // CLASSES & ARMS
  // -------------------------------------------------------
  Future<List<Map<String, dynamic>>> getClasses() async {
    final db = await database;
    return db.query('classes', orderBy: 'name ASC');
  }

  Future<int> insertClass(Map<String, dynamic> data) async {
    final db = await database;
    return db.insert('classes', data);
  }

  Future<int> updateClass(int id, Map<String, dynamic> data) async {
    final db = await database;
    return db.update('classes', data,
        where: 'id = ?', whereArgs: [id]);
  }

  Future<int> deleteClass(int id) async {
    final db = await database;
    return db.delete('classes', where: 'id = ?', whereArgs: [id]);
  }

  Future<List<Map<String, dynamic>>> getArms(int classId) async {
    final db = await database;
    return db.query('arms',
        where: 'classId = ?', whereArgs: [classId], orderBy: 'name ASC');
  }

  // -------------------------------------------------------
  // FEE ITEMS
  // -------------------------------------------------------
  Future<List<Map<String, dynamic>>> getFeeItems({
    String? term,
    String? session,
  }) async {
    final db = await database;
    final activeTerm = term ?? await getActiveTerm();
    final activeSession =
        session ?? (await getActiveSession())?['sessionName'] ?? '';

    return db.query(
      'fee_items',
      where: 'term = ? AND session = ?',
      whereArgs: [activeTerm, activeSession],
      orderBy: 'name ASC',
    );
  }

  Future<int> insertFeeItem(Map<String, dynamic> data,
      {String? term, String? session}) async {
    final db = await database;

    final activeTerm = term ?? await getActiveTerm();
    final activeSession =
        session ?? (await getActiveSession())?['sessionName'] ?? '';

    final payload = {
      'name': data['name'],
      'defaultAmount': data['defaultAmount'] ?? 0.0,
      'description': data['description'],
      'term': activeTerm,
      'session': activeSession,
    };

    return db.insert('fee_items', payload);
  }

  Future<int> updateFeeItem(int id, Map<String, dynamic> data,
      {String? term, String? session}) async {
    final db = await database;

    final activeTerm = term ?? await getActiveTerm();
    final activeSession =
        session ?? (await getActiveSession())?['sessionName'] ?? '';

    final payload = {
      'name': data['name'],
      'defaultAmount': data['defaultAmount'],
      'description': data['description'],
      'term': activeTerm,
      'session': activeSession,
    };

    return db.update('fee_items', payload,
        where: 'id = ?', whereArgs: [id]);
  }

  Future<int> deleteFeeItem(int id) async {
    final db = await database;
    return db.delete('fee_items', where: 'id = ?', whereArgs: [id]);
  }

  // -------------------------------------------------------
  // CLASS FEE ASSIGNMENTS
  // -------------------------------------------------------
  Future<List<Map<String, dynamic>>> getClassFees(
    int classId, {
    required String term,
    required String session,
  }) async {
    final db = await database;
    return db.rawQuery(
      '''
      SELECT cf.id, cf.classId, cf.feeItemId, cf.amount, cf.term, cf.session,
             fi.name AS feeItemName
      FROM class_fees cf
      LEFT JOIN fee_items fi 
             ON fi.id = cf.feeItemId
      WHERE cf.classId = ? AND cf.term = ? AND cf.session = ?
      ORDER BY fi.name ASC
    ''',
      [classId, term, session],
    );
  }

  Future<void> replaceClassFeesFor(
    int classId, {
    required String term,
    required String session,
    required List<Map<String, dynamic>> fees,
  }) async {
    final db = await database;

    await db.transaction((txn) async {
      await txn.delete('class_fees',
          where: 'classId = ? AND term = ? AND session = ?',
          whereArgs: [classId, term, session]);

      for (final f in fees) {
        await txn.insert('class_fees', {
          'classId': classId,
          'feeItemId': f['feeItemId'],
          'amount': f['amount'],
          'term': term,
          'session': session,
        });
      }
    });
  }

  // -------------------------------------------------------
  // BILLING
  // -------------------------------------------------------
  Future<int> insertStudentBill(
      Map<String, dynamic> bill,
      List<Map<String, dynamic>> breakdown) async {
    final db = await database;

    return await db.transaction((txn) async {
      final billId = await txn.insert('student_bills', bill);

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

  // -------------------------------------------------------
  // PAYMENTS
  // -------------------------------------------------------
  Future<int> insertPayment(Map<String, dynamic> payment,
      {String? term, String? session}) async {
    final db = await database;

    final activeTerm = term ?? await getActiveTerm();
    final activeSession =
        session ?? (await getActiveSession())?['sessionName'] ?? '';

    final payload = {
      'studentId': payment['studentId'],
      'amount': payment['amount'],
      'method': payment['method'],
      'note': payment['note'],
      'paymentDate': payment['paymentDate'],
      'term': activeTerm,
      'session': activeSession,
    };

    return db.insert('payments', payload);
  }

  Future<List<Map<String, dynamic>>> getPaymentsByExactDate(
      String date) async {
    final db = await database;

    return db.rawQuery(
      '''
      SELECT *
      FROM payments
      WHERE paymentDate LIKE ? 
      ORDER BY paymentDate DESC
    ''',
      ["$date%"],
    );
  }

  // -------------------------------------------------------
  // OUTSTANDING BALANCES
  // -------------------------------------------------------
  Future<double> computeOutstandingBalance(int studentId) async {
    final db = await database;

    final bill =
        await db.rawQuery('SELECT COALESCE(SUM(totalAmount), 0) AS t FROM student_bills WHERE studentId = ?', [studentId]);

    final pay =
        await db.rawQuery('SELECT COALESCE(SUM(amount), 0) AS t FROM payments WHERE studentId = ?', [studentId]);

    final totalBills = (bill.first['t'] ?? 0) as num;
    final totalPays = (pay.first['t'] ?? 0) as num;

    return (totalBills - totalPays).toDouble();
  }

  // -------------------------------------------------------
  // SCHOOL PROFILE
  // -------------------------------------------------------
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
      final rawId = existing.first['id'];
      final int id =
          rawId is int ? rawId : int.tryParse(rawId.toString()) ?? 0;

      return db.update(
        'school_profile',
        data,
        where: 'id = ?',
        whereArgs: [id],
      );
    }
  }

  // -------------------------------------------------------
  // DATABASE CLOSE
  // -------------------------------------------------------
  Future<void> close() async {
    final db = await database;
    await db.close();
    _database = null;
  }
}
