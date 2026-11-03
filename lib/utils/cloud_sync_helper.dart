// lib/utils/cloud_sync_helper.dart
import 'dart:async';
import 'dart:io';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:shared_preferences/shared_preferences.dart';

import 'backup_reminder_helper.dart';
import 'db_backup_helper.dart';
import 'google_drive_backup_helper.dart';
import 'school_sync_registry.dart';

/// Automatic and one-click backups to Google Drive.
///
/// Every backup is the same full zip (database + photos) that the Online
/// Backup screen uploads, into the same "Bursary Backups" Drive folder.
/// Read-Only devices (those with linked schools, see [SchoolSyncRegistry])
/// never back up — their data comes from the linked schools instead.
class CloudSyncHelper {
  // ── SharedPreferences keys ─────────────────────────────────────────────────
  static const String _autoBackupKey = 'cloud_sync_auto_backup'; // bool
  static const String _autoBackupIntervalKey = 'cloud_sync_auto_backup_interval_hours'; // int
  static const String _lastBackupKey = 'cloud_sync_last_backup'; // ISO-8601

  /// Auto-backup frequency choices, in hours. There is deliberately no
  /// "after every change" option: each backup is a full zip (database +
  /// photos), too heavy to upload after every payment.
  static const List<int> autoBackupIntervalOptions = [1, 3, 6, 12, 24, 168];
  static const int _defaultAutoBackupIntervalHours = 1;

  static String describeInterval(int hours) {
    switch (hours) {
      case 1: return 'Every hour';
      case 24: return 'Daily';
      case 168: return 'Weekly';
      default: return 'Every $hours hours';
    }
  }

  /// How often the periodic timer checks whether a backup is due.
  static const Duration _periodicCheckEvery = Duration(minutes: 5);
  static Timer? _periodicTimer;
  static bool _backupRunning = false;

  // ── Getters ────────────────────────────────────────────────────────────────

  static Future<bool> isReadOnlyMode() => SchoolSyncRegistry.isReadOnlyMode();

  static Future<bool> isAutoBackupEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_autoBackupKey) ?? false;
  }

  static Future<int> getAutoBackupIntervalHours() async {
    final prefs = await SharedPreferences.getInstance();
    final hours = prefs.getInt(_autoBackupIntervalKey);
    return autoBackupIntervalOptions.contains(hours)
        ? hours!
        : _defaultAutoBackupIntervalHours;
  }

  static Future<DateTime?> getLastBackupTime() async {
    final prefs = await SharedPreferences.getInstance();
    final s = prefs.getString(_lastBackupKey);
    return s != null ? DateTime.tryParse(s) : null;
  }

  /// When the next periodic auto-backup is due, or null when auto-backup is off.
  static Future<DateTime?> getNextAutoBackupDue() async {
    if (!await isAutoBackupEnabled()) return null;
    final hours = await getAutoBackupIntervalHours();
    final last = await getLastBackupTime();
    if (last == null) return DateTime.now();
    return last.add(Duration(hours: hours));
  }

  // ── Setters ────────────────────────────────────────────────────────────────

  static Future<void> setAutoBackupEnabled(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_autoBackupKey, value);
  }

  static Future<void> setAutoBackupIntervalHours(int hours) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_autoBackupIntervalKey, hours);
  }

  /// True when the user is signed in to Google (Drive backup is usable).
  static Future<bool> isAvailable() => GoogleDriveBackupHelper.isSignedIn();

  // ── Connectivity ───────────────────────────────────────────────────────────

  static Future<bool> hasInternetConnection() async {
    if (kIsWeb) return true;
    try {
      final results = await Connectivity().checkConnectivity();
      return results.any((r) => r != ConnectivityResult.none);
    } catch (_) {
      return false;
    }
  }

  // ── Auto Backup ────────────────────────────────────────────────────────────

  /// Starts (or restarts) the timer that runs periodic auto-backups.
  /// Checks immediately — so a backup missed while the app was closed runs
  /// on launch — then every few minutes. Safe to call more than once.
  static Future<void> startPeriodicAutoBackup() async {
    if (kIsWeb) return;
    _periodicTimer?.cancel();
    unawaited(_runPeriodicIfDue());
    _periodicTimer = Timer.periodic(
      _periodicCheckEvery,
      (_) => unawaited(_runPeriodicIfDue()),
    );
  }

  static Future<void> _runPeriodicIfDue() async {
    final due = await getNextAutoBackupDue();
    if (due == null || DateTime.now().isBefore(due)) return;
    if (await isReadOnlyMode()) return;
    if (!await GoogleDriveBackupHelper.isSignedIn()) return;
    if (!await hasInternetConnection()) return;
    // The central server has its own schedule (AutoSyncService), so
    // automatic runs only go to Drive.
    await _backupToDrive();
  }

  /// Manual backup — same as auto but always runs (ignores the toggle).
  /// Only uploads to Google Drive; the home screen's Sync button pushes to
  /// the central server separately so it can report that result too.
  static Future<Map<String, dynamic>> manualBackup() async {
    if (kIsWeb) return {'success': false, 'message': 'Not available on web'};
    if (await isReadOnlyMode()) {
      return {'success': false, 'message': 'This device is in Read-Only mode.'};
    }
    if (!await GoogleDriveBackupHelper.isSignedIn()) {
      return {'success': false, 'message': 'Not signed in to Google account'};
    }
    if (!await hasInternetConnection()) {
      return {'success': false, 'message': 'No internet connection'};
    }
    return _backupToDrive();
  }

  /// Builds the full backup zip in the temp folder, uploads it and records
  /// the time. Only one backup runs at a time.
  static Future<Map<String, dynamic>> _backupToDrive() async {
    if (_backupRunning) {
      return {'success': false, 'message': 'A backup is already running'};
    }
    _backupRunning = true;
    String? path;
    try {
      final archive = await DBBackupHelper.createOnlineBackupArchive(
        keepLocalCopy: false,
        sendToCentral: false,
      );
      path = archive['filePath'] as String?;
      if (archive['success'] != true || path == null) {
        return {
          'success': false,
          'message': archive['message'] ?? 'Failed to create backup file',
        };
      }
      final result = await GoogleDriveBackupHelper.uploadBackupToDrive(path);
      if (result['success'] == true) await _recordSuccessfulBackup();
      return result;
    } catch (e) {
      return {'success': false, 'message': 'Backup failed: $e'};
    } finally {
      if (path != null) {
        try { File(path).deleteSync(); } catch (_) {}
      }
      _backupRunning = false;
    }
  }

  /// Also called by the Online Backup screen after its own upload, so the
  /// auto-backup timer counts from the newest backup of either kind.
  static Future<void> recordSuccessfulBackup() => _recordSuccessfulBackup();

  static Future<void> _recordSuccessfulBackup() async {
    final now = DateTime.now();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_lastBackupKey, now.toIso8601String());
    await BackupReminderHelper.recordBackup();
    await BackupReminderHelper.recordOnlineBackup(now);
  }
}
