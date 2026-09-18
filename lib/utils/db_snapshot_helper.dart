import 'dart:io';
import 'package:sqflite/sqflite.dart';

/// Writes a consistent on-disk snapshot of [database] to [destPath].
///
/// Normally uses `VACUUM INTO`, which writes a complete, consistent copy in
/// one atomic step regardless of any pending WAL activity. That statement
/// requires SQLite >= 3.27.0 (2019), but `sqflite` on Android calls through
/// to whichever SQLite build is baked into that device's system image —
/// some older/OEM devices ship something older, where `VACUUM INTO` is
/// invalid syntax and raises `near "INTO": syntax error`. When that happens,
/// this falls back to checkpointing the WAL (a no-op if the database isn't
/// in WAL mode) and raw-copying the database file, which works on any
/// SQLite version.
Future<void> snapshotDatabaseTo(Database database, String destPath) async {
  final escapedPath = destPath.replaceAll("'", "''");
  try {
    await database.execute("VACUUM INTO '$escapedPath'");
    return;
  } on DatabaseException catch (e) {
    if (!e.toString().contains('near "INTO"')) rethrow;
  }

  try {
    await database.execute('PRAGMA wal_checkpoint(TRUNCATE)');
  } catch (_) {
    // Not in WAL mode, or checkpoint unsupported on this SQLite build —
    // safe to ignore, the file copy below still works.
  }
  await File(database.path).copy(destPath);
}
