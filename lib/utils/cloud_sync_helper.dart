// lib/utils/cloud_sync_helper.dart
import 'dart:io';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

import '../db/database_helper.dart';
import 'central_backup_helper.dart';
import 'db_backup_helper.dart';
import 'google_drive_backup_helper.dart';

/// Manages CloudSync: auto-backup (write mode) and auto-restore (read-only mode).
///
/// Write mode  — default. Backs up to Google Drive after significant changes.
/// Read-only   — secondary devices. Auto-restores from Drive on launch.
///               Switching modes requires [_syncPassword].
class CloudSyncHelper {
  // ── SharedPreferences keys ─────────────────────────────────────────────────
  static const String _modeKey        = 'cloud_sync_mode';        // 'write' | 'readonly'
  static const String _autoBackupKey  = 'cloud_sync_auto_backup'; // bool
  static const String _autoRestoreKey = 'cloud_sync_auto_restore';// bool
  static const String _lastBackupKey  = 'cloud_sync_last_backup'; // ISO-8601
  static const String _lastRestoreKey = 'cloud_sync_last_restore';// ISO-8601

  // Password required to switch between write ↔ read-only mode
  static const String _syncPassword = '1234512345';

  // Tables restored during auto-sync — licenses intentionally excluded
  // so each receiving device keeps its own licence activation.
  static const List<String> _syncTables = [
    // Auth & config
    'users', 'permissions', 'settings',

    // School structure
    'school_profile',
    'classes', 'arms', 'sessions',

    // Students & parents
    'students', 'parents', 'promotion_history',

    // Fees & billing
    'fee_items', 'class_fees',
    'special_fee_items', 'special_class_fees', 'excluded_default_fees',
    'fee_priority',
    'student_bills', 'student_fee_breakdown',

    // Payments
    'payments',

    // Expenses
    'expenses', 'expense_categories',

    // Print counters
    'print_counters',

    // Stock & sales
    'stock_items', 'suppliers',
    'sales', 'stock_movements', 'sales_debtors',

    // Staff
    'staff',
    'staff_offices', 'staff_class_allocations', 'staff_office_allocations',
    'staff_incentives', 'staff_loans', 'staff_deductions',
    'staff_salary_payments', 'staff_salary_history',
    'payroll_month_settings', 'salary_expense_postings',

    // CA Portal — academic setup
    'school_divisions', 'division_class_allocations',
    'subjects', 'activities',
    'class_subject_allocations', 'class_activity_allocations',
    'class_teacher_allocations', 'subject_teacher_allocations',
    'exams', 'grading_definitions',

    // CA Portal — student results
    'psychomotor_skills', 'affective_traits',
    'student_scores',
    'student_psychomotor_scores', 'student_affective_scores',
    'result_computations',

    // External examinations
    'external_examinations', 'examination_registrations',

    // Transportation
    'transport_routes', 'student_transport_allocations',

    // Financial activity/audit trail
    'audit_log',

    // SMS notification log
    'sms_log',
  ];

  // ── Getters ────────────────────────────────────────────────────────────────

  static Future<String> getSyncMode() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_modeKey) ?? 'write';
  }

  static Future<bool> isReadOnlyMode() async =>
      (await getSyncMode()) == 'readonly';

  static Future<bool> isAutoBackupEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_autoBackupKey) ?? false;
  }

  static Future<bool> isAutoRestoreEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_autoRestoreKey) ?? false;
  }

  static Future<DateTime?> getLastBackupTime() async {
    final prefs = await SharedPreferences.getInstance();
    final s = prefs.getString(_lastBackupKey);
    return s != null ? DateTime.tryParse(s) : null;
  }

  static Future<DateTime?> getLastRestoreTime() async {
    final prefs = await SharedPreferences.getInstance();
    final s = prefs.getString(_lastRestoreKey);
    return s != null ? DateTime.tryParse(s) : null;
  }

  // ── Setters ────────────────────────────────────────────────────────────────

  static Future<void> setAutoBackupEnabled(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_autoBackupKey, value);
  }

  static Future<void> setAutoRestoreEnabled(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_autoRestoreKey, value);
  }

  // ── Mode switching ─────────────────────────────────────────────────────────

  static bool verifyPassword(String input) => input == _syncPassword;

  /// Switch to Read-Only mode. Returns false if password is wrong.
  static Future<bool> switchToReadOnly(String password) async {
    if (!verifyPassword(password)) return false;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_modeKey, 'readonly');
    await prefs.setBool(_autoBackupKey, false);
    await prefs.setBool(_autoRestoreKey, true);
    return true;
  }

  /// Switch back to Write mode. Returns false if password is wrong.
  static Future<bool> switchToWriteMode(String password) async {
    if (!verifyPassword(password)) return false;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_modeKey, 'write');
    await prefs.setBool(_autoRestoreKey, false);
    return true;
  }

  /// True when the user is signed in to Google (CloudSync is usable).
  static Future<bool> isAvailable() => GoogleDriveBackupHelper.isSignedIn();

  // ── Connectivity ───────────────────────────────────────────────────────────

  static Future<bool> hasInternetConnection() async {
    try {
      final results = await Connectivity().checkConnectivity();
      return results.any((r) => r != ConnectivityResult.none);
    } catch (_) {
      return false;
    }
  }

  // ── Auto Backup ────────────────────────────────────────────────────────────

  /// Silent background backup. Safe to call after any significant DB write.
  /// Returns true only if upload succeeded.
  static Future<bool> triggerAutoBackup() async {
    if (!await isAutoBackupEnabled()) return false;
    if (await isReadOnlyMode()) return false;
    if (!await GoogleDriveBackupHelper.isSignedIn()) return false;
    if (!await hasInternetConnection()) return false;

    try {
      final tempPath = await _buildTempPath('cloudsync_upload');
      if (!await _copyDatabaseTo(tempPath)) return false;

      final result = await GoogleDriveBackupHelper.uploadSyncBackup(tempPath);
      await CentralBackupHelper.uploadBackup(tempPath);
      _deleteSilently(tempPath);

      if (result['success'] == true) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_lastBackupKey, DateTime.now().toIso8601String());
        return true;
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  /// Manual backup — identical to auto but always runs (ignores toggle).
  static Future<Map<String, dynamic>> manualBackup() async {
    if (!await GoogleDriveBackupHelper.isSignedIn()) {
      return {'success': false, 'message': 'Not signed in to Google account'};
    }
    if (!await hasInternetConnection()) {
      return {'success': false, 'message': 'No internet connection'};
    }
    try {
      final tempPath = await _buildTempPath('cloudsync_manual');
      if (!await _copyDatabaseTo(tempPath)) {
        return {'success': false, 'message': 'Failed to create backup file'};
      }
      final result = await GoogleDriveBackupHelper.uploadSyncBackup(tempPath);
      await CentralBackupHelper.uploadBackup(tempPath);
      _deleteSilently(tempPath);
      if (result['success'] == true) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_lastBackupKey, DateTime.now().toIso8601String());
      }
      return result;
    } catch (e) {
      return {'success': false, 'message': 'Backup failed: $e'};
    }
  }

  // ── Auto Restore ───────────────────────────────────────────────────────────

  /// Called at app launch when auto-restore is enabled.
  /// Downloads the latest Drive backup and restores all tables except licenses.
  /// Returns true if data was actually restored.
  static Future<bool> triggerAutoRestoreOnLaunch() async {
    if (!await isAutoRestoreEnabled()) return false;
    if (!await GoogleDriveBackupHelper.isSignedIn()) return false;
    if (!await hasInternetConnection()) return false;

    return _performRestore();
  }

  /// Manual restore — identical to auto but always runs (ignores toggle).
  static Future<Map<String, dynamic>> manualRestore() async {
    if (!await GoogleDriveBackupHelper.isSignedIn()) {
      return {'success': false, 'message': 'Not signed in to Google account'};
    }
    if (!await hasInternetConnection()) {
      return {'success': false, 'message': 'No internet connection'};
    }
    final ok = await _performRestore();
    if (ok) return {'success': true, 'message': 'Data restored successfully from Google Drive'};
    return {'success': false, 'message': 'No sync backup found or restore failed'};
  }

  static Future<bool> _performRestore() async {
    try {
      final backups = await GoogleDriveBackupHelper.listSyncBackupsInDrive();
      if (backups.isEmpty) return false;

      final latest = backups.first;
      final fileId = latest['id'] as String?;
      final fileName = latest['name'] as String? ?? 'sync.db';
      if (fileId == null) return false;

      final tempPath = await _buildTempPath('cloudsync_restore_$fileName');

      final dl = await GoogleDriveBackupHelper.downloadBackupFromDrive(fileId, tempPath);
      if (dl['success'] != true) { _deleteSilently(tempPath); return false; }

      final restore = await DBBackupHelper.selectiveRestoreDatabase(tempPath, _syncTables);
      _deleteSilently(tempPath);

      if (restore['success'] == true) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_lastRestoreKey, DateTime.now().toIso8601String());
        return true;
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  // ── Private helpers ────────────────────────────────────────────────────────

  static Future<String> _buildTempPath(String name) async {
    final dir = await getTemporaryDirectory();
    final ts = DateTime.now().millisecondsSinceEpoch;
    return p.join(dir.path, '${name}_$ts.db');
  }

  static Future<bool> _copyDatabaseTo(String destPath) async {
    try {
      // Checkpoint WAL before copying so all recent writes are in the main
      // .db file — otherwise records written since the last checkpoint sit
      // in the .db-wal file and would be missing from the uploaded copy.
      try {
        final database = await DatabaseHelper().database;
        await database.execute('PRAGMA wal_checkpoint(TRUNCATE)');
      } catch (_) {
        // Proceed anyway — data already in the .db file will still sync.
      }

      final dbDir = await getDatabasesPath();
      final srcPath = p.join(dbDir, 'bursary_manager.db');
      await File(srcPath).copy(destPath);
      return true;
    } catch (_) {
      return false;
    }
  }

  static void _deleteSilently(String path) {
    try { File(path).deleteSync(); } catch (_) {}
  }
}
