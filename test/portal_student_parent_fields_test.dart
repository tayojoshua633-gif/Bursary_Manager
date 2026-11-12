// test/portal_student_parent_fields_test.dart
//
// Class teachers' Parent Phone 2 / Occupation / Office Address corrections
// (Teacher Sync student fields 23–25) are kept on the family's parents row.

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:bursary_manager/utils/portal_student_sync_service.dart';

void main() {
  late Database db;
  const now = '2026-11-12T10:00:00.000';

  setUpAll(sqfliteFfiInit);

  setUp(() async {
    db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    await db.execute('''CREATE TABLE students (id INTEGER PRIMARY KEY, parentName TEXT, parentPhone TEXT,
        parentEmail TEXT, parentAddress TEXT)''');
    await db.execute('''CREATE TABLE parents (id INTEGER PRIMARY KEY AUTOINCREMENT, parentName TEXT NOT NULL,
        phoneNumber TEXT NOT NULL, phoneNumber2 TEXT, homeAddress TEXT NOT NULL, occupation TEXT,
        officeAddress TEXT, emailAddress TEXT, createdAt TEXT NOT NULL, updatedAt TEXT NOT NULL)''');
  });

  tearDown(() => db.close());

  test('fields 23–25 are parents columns; phone 2 always waits for review', () {
    final f = PortalStudentSyncService.studentFields;
    expect(f[23]!.parentColumn, 'phoneNumber2');
    expect(f[24]!.parentColumn, 'occupation');
    expect(f[25]!.parentColumn, 'officeAddress');
    expect(f[23]!.review, isTrue);
    expect(f[11]!.parentColumn, isNull);
  });

  test('finds the parent by phone 1, preferring the same name, and updates it', () async {
    await db.insert('students', {'id': 1, 'parentName': 'Mrs. Felix', 'parentPhone': ' 0803 '});
    final row = {'phoneNumber': '0803', 'homeAddress': 'Ore', 'createdAt': now, 'updatedAt': now};
    await db.insert('parents', {...row, 'parentName': 'Someone Else'});
    final felix = await db.insert('parents', {...row, 'parentName': 'Mrs. Felix', 'phoneNumber2': '0700'});

    expect((await studentParent(db, 1))?['id'], felix);
    await writeStudentParent(db, 1, 'phoneNumber2', '0812', '2026-11-12T11:00:00.000');
    final p = (await db.query('parents', where: 'id = ?', whereArgs: [felix])).single;
    expect(p['phoneNumber2'], '0812');
    expect(p['updatedAt'], '2026-11-12T11:00:00.000');
    expect(await db.query('parents'), hasLength(2));
  });

  test('adds a parents row from the student when the family has none', () async {
    await db.insert('students', {'id': 2, 'parentName': 'Mr. Ade', 'parentPhone': '0805', 'parentAddress': 'Akure', 'parentEmail': ''});
    expect(await studentParent(db, 2), isNull);
    await writeStudentParent(db, 2, 'occupation', 'Farmer', now);
    final p = (await db.query('parents')).single;
    expect(p['parentName'], 'Mr. Ade');
    expect(p['phoneNumber'], '0805');
    expect(p['homeAddress'], 'Akure');
    expect(p['emailAddress'], isNull);
    expect(p['occupation'], 'Farmer');
  });

  test('does nothing when the student has no parent phone', () async {
    await db.insert('students', {'id': 3, 'parentName': 'X', 'parentPhone': '  '});
    await writeStudentParent(db, 3, 'occupation', 'Farmer', now);
    expect(await db.query('parents'), isEmpty);
  });
}
