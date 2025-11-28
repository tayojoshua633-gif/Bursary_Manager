import 'dart:io';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

class DBBackupHelper {
  static const String _dbName = "bursary_manager.db";
  static const String _backupFileName = "bursary_backup.db";

  /// Returns full database path
  static Future<String> _getDatabasePath() async {
    final dbPath = await getDatabasesPath();
    return join(dbPath, _dbName);
  }

  /// Returns folder for backups
  static Future<String> _getBackupFolder() async {
    final dir = await getApplicationDocumentsDirectory();
    return dir.path;
  }

  /// ================================
  /// BACKUP DATABASE
  /// ================================
  static Future<bool> backupDatabase() async {
    try {
      final dbPath = await _getDatabasePath();
      final backupFolder = await _getBackupFolder();
      final backupPath = join(backupFolder, _backupFileName);

      final sourceFile = File(dbPath);
      final destFile = File(backupPath);

      if (await sourceFile.exists()) {
        await destFile.writeAsBytes(await sourceFile.readAsBytes());
        return true;
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  /// ================================
  /// RESTORE DATABASE
  /// ================================
  static Future<bool> restoreDatabase() async {
    try {
      final dbPath = await _getDatabasePath();
      final backupFolder = await _getBackupFolder();
      final backupPath = join(backupFolder, _backupFileName);

      final backupFile = File(backupPath);
      final destFile = File(dbPath);

      if (await backupFile.exists()) {
        await destFile.writeAsBytes(await backupFile.readAsBytes());
        return true;
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  /// ================================
  /// DELETE BACKUP
  /// ================================
  static Future<bool> deleteBackupFile() async {
    try {
      final backupFolder = await _getBackupFolder();
      final backupPath = join(backupFolder, _backupFileName);
      final file = File(backupPath);

      if (await file.exists()) {
        await file.delete();
        return true;
      }
      return false;
    } catch (_) {
      return false;
    }
  }
}
