// lib/utils/portal_student_sync_service.dart
import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

import '../db/database_helper.dart';
import 'central_backup_helper.dart';
import 'portal_student_sync_client.dart';
import 'school_sync_registry.dart';

/// School Portal Sync: brings class teachers' corrections to student details
/// from the online portal into BM, for schools whose portal sends student
/// details to Bursary Manager (portal Preferences > Student Details Receiver).
///
/// Flow: a class teacher corrects a student on the portal → [fetchAndCompare]
/// downloads the waiting corrections and compares each with this device's
/// record → the admin imports, keeps the BM value, or rejects → [apply]
/// writes the imported values, logs everything in portal_student_sync_log
/// and audit_log, tells the portal, and uploads a backup so DSM gets the
/// change on its next sync from BM.
///
/// The same rules as DSM's PortalTeacherSyncService for kind 'student',
/// except photos, which BM never receives. Teacher allocations live in DSM:
/// the portal has already checked the teacher is this student's class teacher.
class PortalStudentSyncService {
  /// What a class teacher may change on a student, by the entry's itemId —
  /// the same numbers as the portal's STUDENT_FIELDS
  /// (school_portal/lib/teacher.php) and DSM's
  /// PortalTeacherSyncService.studentFields; never renumber them. 30 (photo)
  /// is left out on purpose. [review] marks the fields that identify the
  /// child or decide which parent account sees them.
  static const Map<int, StudentField> studentFields = {
    1: StudentField('surname', 'Surname', 'text', required: true, review: true),
    2: StudentField('firstName', 'First Name', 'text', required: true, review: true),
    3: StudentField('otherName', 'Other Name', 'text', review: true),
    4: StudentField('gender', 'Gender', 'gender', required: true, review: true),
    5: StudentField('dob', 'Date of Birth', 'date', required: true, review: true),
    6: StudentField('nationality', 'Nationality', 'text'),
    7: StudentField('stateOfOrigin', 'State of Origin', 'text'),
    8: StudentField('lga', 'LGA', 'text'),
    9: StudentField('address', 'Home Address', 'long', required: true),
    10: StudentField('parentName', 'Parent / Guardian Name', 'text', required: true, review: true),
    11: StudentField('parentPhone', 'Parent Phone', 'phone', required: true, review: true),
    12: StudentField('parentEmail', 'Parent Email', 'email'),
    13: StudentField('parentAddress', 'Parent Address', 'long'),
    14: StudentField('genotype', 'Genotype', 'genotype'),
    15: StudentField('bloodGroup', 'Blood Group', 'blood'),
    16: StudentField('hasDisability', 'Has a Disability', 'yesno'),
    17: StudentField('disabilityDetails', 'Disability Details', 'long'),
    18: StudentField('allergies', 'Allergies', 'long'),
    19: StudentField('medicalConditions', 'Medical Conditions', 'long'),
    20: StudentField('medication', 'Medication', 'long'),
    21: StudentField('emergencyContactName', 'Emergency Contact Name', 'text'),
    22: StudentField('emergencyContactPhone', 'Emergency Contact Phone', 'phone'),
  };

  static const _genotypes = ['AA', 'AS', 'AC', 'SS', 'SC', 'CC', 'Unknown'];
  static const _bloodGroups = ['A+', 'A-', 'B+', 'B-', 'AB+', 'AB-', 'O+', 'O-', 'Unknown'];

  /// BM's own log of handled entries. Created here rather than in a DB
  /// migration, and never copied into DSM (BmSyncClient.excludedTables).
  static const String logTable = 'portal_student_sync_log';

  static StudentField? fieldOf(int? itemId) => itemId == null ? null : studentFields[itemId];

  /// True for a correction auto mode must leave for the admin.
  static bool alwaysReview(PortalTeacherEntry e) => fieldOf(e.itemId)?.review ?? true;

  /// Waiting-entry count from the last check, for the home tile badge.
  static final ValueNotifier<int> pendingCount = ValueNotifier<int>(0);

  static DatabaseHelper get _dbh => DatabaseHelper();

  static const String _autoPref = 'portal_student_sync_auto';
  static const String _lastPendingPref = 'portal_student_sync_last_pending';
  static const String _lastCheckPref = 'portal_student_sync_last_check';
  static const Duration autoInterval = Duration(minutes: 5);
  static Timer? _autoTimer;
  static bool _running = false;

  // ── Auto mode ────────────────────────────────────────────────────────────

  /// Auto-import is on unless the admin switched it off on this device.
  static Future<bool> autoImportEnabled() async =>
      (await SharedPreferences.getInstance()).getBool(_autoPref) ?? true;

  static Future<void> setAutoImport(bool on) async {
    await (await SharedPreferences.getInstance()).setBool(_autoPref, on);
    await startAutoImportIfEnabled();
  }

  static Future<DateTime?> lastCheck() async =>
      DateTime.tryParse((await SharedPreferences.getInstance()).getString(_lastCheckPref) ?? '');

  static Future<void> _noteCheck(int pending) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_lastCheckPref, DateTime.now().toIso8601String());
    await prefs.setInt(_lastPendingPref, pending);
    pendingCount.value = pending;
  }

  /// Starts (or stops) the background import. Called once after login next
  /// to AutoSyncService.start, and whenever the connection or switch changes.
  static Future<void> startAutoImportIfEnabled() async {
    _autoTimer?.cancel();
    _autoTimer = null;
    pendingCount.value = (await SharedPreferences.getInstance()).getInt(_lastPendingPref) ?? 0;
    if (!await canImportHere() || !await PortalStudentSyncClient.isLinked() || !await autoImportEnabled()) return;
    _autoTimer = Timer.periodic(autoInterval, (_) => unawaited(runAutoImport()));
    unawaited(Future.delayed(const Duration(seconds: 45), runAutoImport));
  }

  static bool _started = false;

  /// [startAutoImportIfEnabled] once per app run; HomeScreen calls this
  /// every time it is built, after either way of logging in.
  static Future<void> ensureStarted() async {
    if (_started) return;
    _started = true;
    await startAutoImportIfEnabled();
  }

  static void stopAutoImport() {
    _autoTimer?.cancel();
    _autoTimer = null;
  }

  /// One auto-mode pass: imports New and Changed corrections to fields that
  /// need no check, marks Same ones done, and sends the rest to review so
  /// the teacher sees "Under review" on the portal.
  static Future<SyncApplyResult?> runAutoImport() async {
    if (_running) return null;
    try {
      if (!await canImportHere() || !await PortalStudentSyncClient.isLinked() || !await autoImportEnabled()) return null;
      final rows = await fetchAndCompare();
      final decisions = <int, SyncDecision>{};
      for (final r in rows) {
        if (r.clean && (r.status == SyncStatus.same || !alwaysReview(r.entry))) {
          decisions[r.entry.id] = SyncDecision.import;
        } else if (r.entry.status != 'review') {
          decisions[r.entry.id] = SyncDecision.review;
        }
      }
      if (decisions.isEmpty) return null;
      final res = await apply(rows, decisions, actedBy: 'Auto import');
      debugPrint('[PortalStudentSync] auto: ${res.imported} imported, ${res.reviewed} to review');
      return res;
    } catch (e) {
      debugPrint('[PortalStudentSync] auto import skipped: $e');
      return null;
    }
  }

  /// Only the device that holds the school's own database imports: not a
  /// network client, and not a Read-Only device (which shows linked
  /// schools' data).
  static Future<bool> canImportHere() async {
    if (kIsWeb) return false;
    final prefs = await SharedPreferences.getInstance();
    if ((prefs.getString('app_mode') ?? 'standalone') == 'client') return false;
    return !await SchoolSyncRegistry.isReadOnlyMode();
  }

  static Future<Database> _db() async {
    final db = await _dbh.database;
    await db.execute('''
      CREATE TABLE IF NOT EXISTS $logTable (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        portalEntryId INTEGER NOT NULL UNIQUE,
        entryKey TEXT,
        studentId INTEGER,
        classId INTEGER,
        armId INTEGER,
        field INTEGER,
        action TEXT NOT NULL,
        reason TEXT,
        localBefore TEXT,
        valueImported TEXT,
        submittedBy TEXT,
        teacherName TEXT,
        submittedAt TEXT,
        actedBy TEXT,
        actedAt TEXT NOT NULL,
        acked INTEGER NOT NULL DEFAULT 0
      )
    ''');
    return db;
  }

  // ── Fetch + compare ──────────────────────────────────────────────────────

  /// Re-sends any acknowledgements the portal hasn't received, then
  /// downloads the waiting corrections and compares each with this device.
  static Future<List<SyncRow>> fetchAndCompare() async {
    _running = true;
    try {
      return await _fetchAndCompare();
    } finally {
      _running = false;
    }
  }

  static Future<List<SyncRow>> _fetchAndCompare() async {
    final db = await _db();
    await resendUnackedAcks();
    final entries = (await PortalStudentSyncClient.fetchPending()).where((e) => e.kind == 'student').toList();

    // Entries already handled here whose acknowledgement got lost: just ack again.
    final handled = <int, Map<String, dynamic>>{};
    for (var i = 0; i < entries.length; i += 500) {
      final ids = entries.sublist(i, (i + 500).clamp(0, entries.length)).map((e) => e.id).join(',');
      for (final r in await db.rawQuery('SELECT * FROM $logTable WHERE portalEntryId IN ($ids)')) {
        handled[(r['portalEntryId'] as num).toInt()] = r;
      }
    }
    if (handled.isNotEmpty) {
      await _ack(db, handled.values.map(_ackFor).toList(), by: 'BM');
    }

    final fresh = entries.where((e) => !handled.containsKey(e.id)).toList();
    final byKey = <String, List<PortalTeacherEntry>>{};
    for (final e in fresh) {
      byKey.putIfAbsent(e.entryKey, () => []).add(e);
    }
    final students = <int, Map<String, dynamic>?>{};
    final names = <String, String>{};
    Future<String> name(String table, int id) async {
      final k = '$table#$id';
      if (!names.containsKey(k)) {
        final r = await db.query(table, columns: ['name'], where: 'id = ?', whereArgs: [id], limit: 1);
        names[k] = r.isEmpty ? '' : (r.first['name'] as String? ?? '');
      }
      return names[k]!;
    }

    final rows = <SyncRow>[];
    for (final e in fresh) {
      if (!students.containsKey(e.studentId)) {
        final r = await db.query('students', where: 'id = ?', whereArgs: [e.studentId], limit: 1);
        students[e.studentId] = r.isEmpty ? null : r.first;
      }
      final st = students[e.studentId];
      final f = fieldOf(e.itemId);
      final local = _localValue(st, f);
      final block = _blockReason(st, f, e);
      final rivals = byKey[e.entryKey]!.where((o) => o.id != e.id && o.userId != e.userId && !o.value.sameAs(e.value));
      SyncStatus status;
      String? note;
      if (block != null) {
        status = SyncStatus.blocked;
        note = block;
      } else if (local != null && local.sameAs(e.value)) {
        status = SyncStatus.same;
      } else if (rivals.isNotEmpty) {
        status = SyncStatus.conflict;
        note = 'Another teacher (${rivals.first.sender}) sent a different value.';
      } else if (local == null && !e.baseSet) {
        status = SyncStatus.newValue;
      } else if (local != null && e.baseSet && local.sameAs(e.base)) {
        status = SyncStatus.changed;
      } else if (local == null) {
        status = SyncStatus.conflict;
        note = 'The value was removed in BM after the teacher saw it.';
      } else {
        status = SyncStatus.conflict;
        note = e.baseSet ? 'Changed in BM after the teacher saw it.' : 'BM already has a value the teacher didn\'t see.';
      }
      rows.add(SyncRow(
        entry: e,
        status: status,
        note: note,
        local: local,
        studentName: st == null ? 'Student #${e.studentId}' : '${st['surname'] ?? ''} ${st['firstName'] ?? ''}'.trim(),
        admissionNo: st?['admissionNo'] as String? ?? '',
        classLabel: '${await name('classes', e.classId)} ${await name('arms', e.armId)}'.trim(),
        itemLabel: f?.label ?? 'Detail',
      ));
    }
    await _noteCheck(rows.length);
    return rows;
  }

  /// The value BM has now for the entry's field, or null.
  static PortalValue? _localValue(Map<String, dynamic>? st, StudentField? f) {
    if (st == null || f == null) return null;
    final v = st[f.column];
    if (v == null) return null;
    if (f.type == 'yesno') return PortalValue(number: (v as num).toDouble() == 1 ? 1 : 0);
    final t = v.toString().trim();
    return t.isEmpty ? null : PortalValue(text: t);
  }

  /// Why an entry can't be imported (null if it can).
  static String? _blockReason(Map<String, dynamic>? st, StudentField? f, PortalTeacherEntry e) {
    if (f == null) return e.itemId == 30 ? 'Photos are imported in DSM, not BM.' : 'Unknown student detail.';
    if (st == null) return 'Student no longer exists in BM.';
    if ((st['isActive'] as num?)?.toInt() != 1) return 'Student is no longer active.';
    if ((st['armId'] as num?)?.toInt() != e.armId || (st['classId'] as num?)?.toInt() != e.classId) {
      return 'Student is no longer in this class.';
    }
    return _valueProblem(f, e.value);
  }

  /// The same checks as the portal's student_field_problem().
  static String? _valueProblem(StudentField f, PortalValue v) {
    if (f.type == 'yesno') return (v.number == 0 || v.number == 1) ? null : 'Choose Yes or No.';
    final t = (v.text ?? '').trim();
    if (t.isEmpty) return f.required ? '${f.label} is required.' : null;
    if (t.length > (f.type == 'long' ? 500 : 120)) return '${f.label} is too long.';
    switch (f.type) {
      case 'gender':
        return const ['Male', 'Female'].contains(t) ? null : 'Gender must be Male or Female.';
      case 'date':
        final d = DateTime.tryParse(t);
        if (d == null || !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(t)) return '${f.label} is not a valid date.';
        return (d.isAfter(DateTime.now()) || d.year < 1950) ? '${f.label} is out of range.' : null;
      case 'phone':
        final digits = t.replaceAll(RegExp(r'\D'), '').length;
        return RegExp(r'^\+?[0-9 ()-]+$').hasMatch(t) && digits >= 7 && digits <= 15 ? null : '${f.label} is not a valid phone number.';
      case 'email':
        return RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(t) ? null : '${f.label} is not a valid email address.';
      case 'genotype':
        return _genotypes.contains(t) ? null : 'Unknown genotype.';
      case 'blood':
        return _bloodGroups.contains(t) ? null : 'Unknown blood group.';
    }
    return null;
  }

  // ── Apply ────────────────────────────────────────────────────────────────

  /// Carries out the decisions (keyed by portal entry id). Writes imported
  /// values in one transaction, logs every decision, then tells the portal.
  static Future<SyncApplyResult> apply(
    List<SyncRow> rows,
    Map<int, SyncDecision> decisions, {
    required String actedBy,
    Map<int, String> reasons = const {},
  }) async {
    final db = await _db();
    final now = DateTime.now().toIso8601String();
    final prefs = await SharedPreferences.getInstance();
    final ackActions = <Map<String, dynamic>>[];
    var imported = 0, rejected = 0, kept = 0, reviewed = 0, changedRecords = 0;

    await db.transaction((txn) async {
      for (final r in rows) {
        final d = decisions[r.entry.id];
        if (d == null) continue;
        final e = r.entry;
        final f = fieldOf(e.itemId);
        if (d == SyncDecision.review) {
          // Stays waiting; only the teacher's status changes.
          ackActions.add({'id': e.id, 'action': 'review', 'reason': reasons[e.id] ?? r.note ?? 'Waiting for the school to review.'});
          reviewed++;
          continue;
        }
        String action;
        String? reason;
        if (d == SyncDecision.import) {
          if (r.status == SyncStatus.blocked || f == null) continue; // never write a blocked entry
          if (r.status != SyncStatus.same) {
            final text = (e.value.text ?? '').trim();
            final values = <String, Object?>{
              f.column: f.type == 'yesno' ? e.value.number!.round() : (text.isEmpty ? null : text),
            };
            // As HealthInfoController: no disability, no details.
            if (f.type == 'yesno' && e.value.number == 0) values['disabilityDetails'] = null;
            await txn.update('students', values, where: 'id = ?', whereArgs: [e.studentId]);
            changedRecords++;
            await txn.insert('audit_log', {
              'entityType': 'portal_teacher_entry',
              'entityId': e.id,
              'action': 'import_student',
              'studentId': e.studentId,
              'changes': jsonEncode({
                'item': r.itemLabel,
                'class': r.classLabel,
                'from': r.local?.toJson(),
                'to': e.value.toJson(),
                'teacher': e.sender,
                'approvedBy': actedBy,
              }),
              'userId': prefs.getInt('userId'),
              'username': prefs.getString('username') ?? actedBy,
              'timestamp': now,
            });
          }
          action = 'applied';
          imported++;
        } else if (d == SyncDecision.keepLocal) {
          action = 'kept_local';
          reason = reasons[e.id] ?? 'The school kept the value it already had.';
          kept++;
        } else {
          action = 'rejected';
          reason = reasons[e.id] ?? r.note ?? 'Rejected by the school.';
          rejected++;
        }
        await txn.insert(
          logTable,
          {
            'portalEntryId': e.id,
            'entryKey': e.entryKey,
            'studentId': e.studentId,
            'classId': e.classId,
            'armId': e.armId,
            'field': e.itemId,
            'action': action,
            'reason': reason,
            'localBefore': r.local == null ? null : jsonEncode(r.local!.toJson()),
            'valueImported': action == 'applied' ? jsonEncode(e.value.toJson()) : null,
            'submittedBy': e.username,
            'teacherName': e.teacherName,
            'submittedAt': e.createdAt?.toIso8601String(),
            'actedBy': actedBy,
            'actedAt': now,
            'acked': 0,
          },
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );
        ackActions.add({'id': e.id, 'action': action == 'applied' ? 'applied' : 'rejected', 'reason': ?reason});
      }
    });

    // DSM pulls students from BM's online backup, so send one now.
    if (changedRecords > 0) unawaited(CentralBackupHelper.triggerAutoUpload());
    String? ackError;
    try {
      await _ack(db, ackActions, by: actedBy);
    } catch (e) {
      ackError = e.toString();
    }
    await _noteCheck(rows.where((r) => !decisions.containsKey(r.entry.id) || decisions[r.entry.id] == SyncDecision.review).length);
    return SyncApplyResult(imported: imported, rejected: rejected, keptLocal: kept, reviewed: reviewed, ackError: ackError);
  }

  static Map<String, dynamic> _ackFor(Map<String, dynamic> row) => {
        'id': (row['portalEntryId'] as num).toInt(),
        'action': row['action'] == 'applied' ? 'applied' : 'rejected',
        'reason': ?row['reason'],
      };

  /// Sends acknowledgements and marks the logged ones as delivered.
  static Future<void> _ack(Database db, List<Map<String, dynamic>> actions, {required String by}) async {
    if (actions.isEmpty) return;
    await PortalStudentSyncClient.ack(actions, by: by);
    final ids = actions.where((a) => a['action'] != 'review').map((a) => a['id'] as int).toList();
    for (var i = 0; i < ids.length; i += 500) {
      await db.rawUpdate('UPDATE $logTable SET acked = 1 WHERE portalEntryId IN (${ids.sublist(i, (i + 500).clamp(0, ids.length)).join(',')})');
    }
  }

  /// Acknowledgements that didn't reach the portal (offline at the time).
  static Future<void> resendUnackedAcks() async {
    final db = await _db();
    final rows = await db.query(logTable, where: 'acked = 0', limit: 5000);
    if (rows.isEmpty) return;
    await _ack(db, rows.map(_ackFor).toList(), by: 'BM');
  }

  /// Handled entries, newest first, for the log tab.
  static Future<List<Map<String, dynamic>>> history({int limit = 300}) async {
    final db = await _db();
    return db.rawQuery('''
      SELECT l.*, s.surname, s.firstName, c.name AS className, a.name AS armName
        FROM $logTable l
        LEFT JOIN students s ON s.id = l.studentId
        LEFT JOIN classes c ON c.id = l.classId
        LEFT JOIN arms a ON a.id = l.armId
       ORDER BY l.id DESC
       LIMIT $limit
    ''');
  }

  /// A value as the compare screen shows it.
  static String formatValue(PortalValue? v, {int? field}) {
    if (v == null) return '—';
    if (studentFields[field]?.type == 'yesno') return v.number == null ? '—' : (v.number == 1 ? 'Yes' : 'No');
    final t = (v.text ?? '').trim();
    return t.isEmpty ? '(blank)' : t;
  }
}

/// One student detail a class teacher may change. [type]: text | long |
/// email | phone | date | gender | genotype | blood | yesno.
class StudentField {
  final String column;
  final String label;
  final String type;
  final bool required;
  final bool review;
  const StudentField(this.column, this.label, this.type, {this.required = false, this.review = false});
}

enum SyncStatus { newValue, changed, same, conflict, blocked }

/// [review]: leave it waiting, but show the teacher "Under review".
enum SyncDecision { import, keepLocal, reject, review }

class SyncRow {
  final PortalTeacherEntry entry;
  final SyncStatus status;
  final String? note;
  final PortalValue? local;
  final String studentName;
  final String admissionNo;
  final String classLabel;
  final String itemLabel;

  SyncRow({
    required this.entry,
    required this.status,
    this.note,
    this.local,
    required this.studentName,
    required this.admissionNo,
    required this.classLabel,
    required this.itemLabel,
  });

  bool get clean => status == SyncStatus.newValue || status == SyncStatus.changed || status == SyncStatus.same;
}

class SyncApplyResult {
  final int imported;
  final int rejected;
  final int keptLocal;
  final int reviewed;
  final String? ackError;
  const SyncApplyResult({required this.imported, required this.rejected, required this.keptLocal, this.reviewed = 0, this.ackError});
}
