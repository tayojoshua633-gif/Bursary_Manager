import 'dart:async';
import 'dart:io';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:file_picker/file_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/foundation.dart';
import '../db/database_helper.dart';
import 'central_backup_helper.dart';

class DBBackupHelper {
  static const String _backupFolderName = "BursaryBackups";
  static const String _backupEmail = "tysolutionsmultimediatech@gmail.com";

  // Prefix used when storing SharedPreferences values inside the settings table
  static const String _prefPrefix = 'pref_';

  // Maps each preference key to its type so we can round-trip it correctly.
  // Device-specific values (login session, server URL, backup directory) are
  // intentionally omitted — they should not be copied across devices.
  static const Map<String, String> _prefKeyTypes = {
    'backup_reminders_enabled'    : 'bool',
    'backup_transaction_threshold': 'int',
    'backup_warning_days'         : 'int',
    'backup_critical_days'        : 'int',
    'auto_logout_minutes'         : 'int',
    'usb_printer_paper_size'      : 'string',
    'thermal_printer_paper_size'  : 'string',
    'default_printer'             : 'string',
    'recent_printers'             : 'string',
    'printer_paper_sizes'         : 'string',
  };

  /// Returns full database path of whichever database is currently active
  /// (a Read-Only device may have switched to a linked school's file).
  static Future<String> _getDatabasePath() async =>
      DatabaseHelper().currentDbPath;

  /// Returns folder for backups (in Downloads/BursaryBackups or custom directory)
  static Future<Directory> _getBackupFolder() async {
    // Check if user has set a custom backup directory
    final prefs = await SharedPreferences.getInstance();
    final customDirectory = prefs.getString('custom_backup_directory');

    if (customDirectory != null && customDirectory.isNotEmpty) {
      // Use custom directory
      final directory = Directory(customDirectory);

      // Create folder if it doesn't exist
      if (!await directory.exists()) {
        await directory.create(recursive: true);
      }

      return directory;
    }

    // Use default directory
    Directory? directory;

    if (Platform.isAndroid) {
      // Try to get external storage directory
      directory = await getExternalStorageDirectory();
      if (directory != null) {
        // Create custom path in Downloads area
        final backupPath = '/storage/emulated/0/Download/$_backupFolderName';
        directory = Directory(backupPath);
      }
    } else {
      // For iOS or other platforms, use app documents
      directory = await getApplicationDocumentsDirectory();
    }

    // Create folder if it doesn't exist
    if (!await directory!.exists()) {
      await directory.create(recursive: true);
    }

    return directory;
  }

  /// Request storage permissions for Android
  static Future<bool> _requestStoragePermission() async {
    if (Platform.isAndroid) {
      // Check Android version
      final androidInfo = await _getAndroidVersion();
      
      if (androidInfo >= 13) {
        // Android 13+ doesn't need storage permission for Downloads
        return true;
      } else {
        // Request storage permission for older Android
        var status = await Permission.storage.status;
        if (!status.isGranted) {
          status = await Permission.storage.request();
        }
        return status.isGranted;
      }
    }
    return true; // iOS doesn't need this permission
  }

  /// Get Android version
  static Future<int> _getAndroidVersion() async {
    if (Platform.isAndroid) {
      final version = await Process.run('getprop', ['ro.build.version.sdk']);
      return int.tryParse(version.stdout.toString().trim()) ?? 0;
    }
    return 0;
  }

  /// Get school name from database
  static Future<String> _getSchoolName() async {
    try {
      final db = DatabaseHelper();
      final database = await db.database;
      final result = await database.query('school_profile', limit: 1);
      
      if (result.isNotEmpty) {
        return result.first['name'] as String? ?? 'School';
      }
      return 'School';
    } catch (_) {
      return 'School';
    }
  }

  /// Generate backup filename with school name and timestamp
  static Future<String> _generateBackupFilename() async {
    final schoolName = await _getSchoolName();
    final now = DateTime.now();
    final dateFormat = DateFormat('yyyy-MM-dd_HHmmss');
    final timestamp = dateFormat.format(now);
    
    // Clean school name for filename (remove special characters)
    final cleanName = schoolName.replaceAll(RegExp(r'[^\w\s-]'), '').replaceAll(' ', '_');
    
    return '${cleanName}_Backup_$timestamp.db';
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Preferences ↔ DB settings table helpers
  // ─────────────────────────────────────────────────────────────────────────

  /// Writes all important SharedPreferences into the `settings` DB table so
  /// they are captured inside the .db backup file.
  static Future<void> _snapshotPrefsToDb() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final database = await DatabaseHelper().database;

      for (final entry in _prefKeyTypes.entries) {
        final key = entry.key;
        final type = entry.value;
        String? value;

        switch (type) {
          case 'bool':
            final v = prefs.getBool(key);
            if (v != null) value = v.toString();
            break;
          case 'int':
            final v = prefs.getInt(key);
            if (v != null) value = v.toString();
            break;
          case 'string':
            value = prefs.getString(key);
            break;
        }

        if (value != null) {
          await database.insert(
            'settings',
            {'key': '$_prefPrefix$key', 'value': value},
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        }
      }
    } catch (_) {
      // Non-fatal — backup continues even if the snapshot fails
    }
  }

  /// Reads all `pref_*` rows from an already-open [db] and writes them back
  /// into SharedPreferences.
  static Future<void> _applyPrefsFromOpenDb(Database db) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final rows = await db.query(
        'settings',
        where: 'key LIKE ?',
        whereArgs: ['$_prefPrefix%'],
      );

      for (final row in rows) {
        final fullKey = row['key'] as String;
        final value   = row['value'] as String?;
        if (value == null) continue;

        final key  = fullKey.substring(_prefPrefix.length);
        final type = _prefKeyTypes[key];
        if (type == null) continue;

        switch (type) {
          case 'bool':
            await prefs.setBool(key, value == 'true');
            break;
          case 'int':
            final intVal = int.tryParse(value);
            if (intVal != null) await prefs.setInt(key, intVal);
            break;
          case 'string':
            await prefs.setString(key, value);
            break;
        }
      }
    } catch (_) {
      // Non-fatal
    }
  }

  /// Opens the backup file as a read-only DB and applies its preferences to
  /// SharedPreferences. Used after a full restore.
  static Future<void> _restorePrefsFromBackupFile(String backupFilePath) async {
    try {
      final db = await openDatabase(backupFilePath, readOnly: true);
      await _applyPrefsFromOpenDb(db);
      await db.close();
    } catch (_) {
      // Non-fatal
    }
  }

  /// ================================
  /// BACKUP DATABASE (Enhanced)
  /// ================================
  static Future<Map<String, dynamic>> backupDatabase() async {
    try {
      // Request permission
      final hasPermission = await _requestStoragePermission();
      if (!hasPermission) {
        return {
          'success': false,
          'message': 'Storage permission denied',
          'filePath': null,
        };
      }

      // Snapshot SharedPreferences into the settings table before copying the file
      // so that user preferences travel with the backup.
      await _snapshotPrefsToDb();

      // Checkpoint WAL before backup so all recent writes are in the main .db file.
      // Without this, records written since the last checkpoint are in the .db-wal
      // file and would be missing from the copied backup.
      try {
        final db = DatabaseHelper();
        final database = await db.database;
        await database.execute('PRAGMA wal_checkpoint(TRUNCATE)');
      } catch (_) {
        // If checkpoint fails (e.g. db not open yet), proceed anyway —
        // the data already in the .db file will still be backed up.
      }

      // Get paths
      final dbPath = await _getDatabasePath();
      final backupFolder = await _getBackupFolder();
      final filename = await _generateBackupFilename();
      final backupPath = join(backupFolder.path, filename);

      // Copy database file
      final sourceFile = File(dbPath);
      final destFile = File(backupPath);

      if (await sourceFile.exists()) {
        await destFile.writeAsBytes(await sourceFile.readAsBytes());

        // Best-effort copy to the central support server — never blocks or
        // fails the backup itself if it doesn't succeed.
        unawaited(CentralBackupHelper.uploadBackup(backupPath));

        return {
          'success': true,
          'message': 'Backup created successfully',
          'filePath': backupPath,
          'filename': filename,
        };
      }

      return {
        'success': false,
        'message': 'Database file not found',
        'filePath': null,
      };
    } catch (e) {
      return {
        'success': false,
        'message': 'Backup failed: $e',
        'filePath': null,
      };
    }
  }

  /// ================================
  /// SEND BACKUP VIA EMAIL
  /// ================================
  static Future<bool> sendBackupViaEmail(String backupFilePath) async {
    try {
      final schoolName = await _getSchoolName();
      final now = DateTime.now();
      final dateFormat = DateFormat('yyyy-MM-dd HH:mm:ss');
      final timestamp = dateFormat.format(now);
      
      // Email subject
      final subject = '$schoolName BACKUP - $timestamp';
      
      // Email body
      final body = '''
Hello,

This is an automated backup from $schoolName Bursary Manager.

Backup Details:
- School: $schoolName
- Date: ${DateFormat('EEEE, MMMM d, yyyy').format(now)}
- Time: ${DateFormat('h:mm a').format(now)}
- File: ${basename(backupFilePath)}

Please find the backup file attached.

---
Sent from Bursary Manager App
      ''';

      // Create mailto URL with attachment
      // Note: mailto doesn't support attachments directly
      // We'll open email app and user needs to attach manually
      final Uri emailUri = Uri(
        scheme: 'mailto',
        path: _backupEmail,
        query: _encodeQueryParameters({
          'subject': subject,
          'body': body,
        }),
      );

      // Launch email app
      if (await canLaunchUrl(emailUri)) {
        await launchUrl(emailUri);
        return true;
      } else {
        return false;
      }
    } catch (_) {
      return false;
    }
  }

  /// ================================
  /// BACKUP AND EMAIL (Combined)
  /// ================================
  static Future<Map<String, dynamic>> backupAndEmail() async {
    try {
      // Step 1: Create backup
      final backupResult = await backupDatabase();
      
      if (!backupResult['success']) {
        return backupResult;
      }

      // Step 2: Send via email
      final filePath = backupResult['filePath'] as String;
      final emailSent = await sendBackupViaEmail(filePath);

      if (emailSent) {
        return {
          'success': true,
          'message': 'Backup created and email opened successfully',
          'filePath': filePath,
          'filename': backupResult['filename'],
          'emailOpened': true,
        };
      } else {
        return {
          'success': true,
          'message': 'Backup created but could not open email app',
          'filePath': filePath,
          'filename': backupResult['filename'],
          'emailOpened': false,
        };
      }
    } catch (e) {
      return {
        'success': false,
        'message': 'Operation failed: $e',
        'filePath': null,
      };
    }
  }

  /// Helper to encode query parameters
  static String _encodeQueryParameters(Map<String, String> params) {
    return params.entries
        .map((e) => '${Uri.encodeComponent(e.key)}=${Uri.encodeComponent(e.value)}')
        .join('&');
  }

  /// ================================
  /// RESTORE DATABASE FROM FILE PATH
  /// ================================
  static Future<Map<String, dynamic>> restoreDatabase(String backupFilePath) async {
    try {
      final dbPath = await _getDatabasePath();
      final backupFile = File(backupFilePath);
      final destFile = File(dbPath);

      if (!await backupFile.exists()) {
        return {
          'success': false,
          'message': 'Backup file not found',
        };
      }

      // Validate it's a database file
      if (!backupFilePath.endsWith('.db')) {
        return {
          'success': false,
          'message': 'Invalid backup file. Must be a .db file',
        };
      }

      // Close and reset database connection properly
      try {
        await DatabaseHelper().closeAndReset();
      } catch (_) {
        // Database might not be open, continue
      }

      // Copy backup to database location
      await destFile.writeAsBytes(await backupFile.readAsBytes());

      // Re-apply preferences stored inside the backup to SharedPreferences
      await _restorePrefsFromBackupFile(backupFilePath);

      return {
        'success': true,
        'message': 'Database restored successfully. Please restart the app to complete the restore.',
      };
    } catch (e) {
      return {
        'success': false,
        'message': 'Restore failed: $e',
      };
    }
  }

  /// ================================
  /// PICK AND RESTORE FROM FILE (NEW!)
  /// ================================
  static Future<Map<String, dynamic>> pickAndRestoreBackup() async {
    try {
      // Open file picker - use FileType.any for better compatibility
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.any,
        dialogTitle: 'Select Backup File (.db)',
        allowMultiple: false,
      );

      if (result == null || result.files.isEmpty) {
        return {
          'success': false,
          'message': 'No file selected',
          'cancelled': true,
        };
      }

      // Get the file path
      final filePath = result.files.single.path;
      
      if (filePath == null) {
        return {
          'success': false,
          'message': 'Could not access file path',
        };
      }

      // Validate file exists
      final file = File(filePath);
      if (!await file.exists()) {
        return {
          'success': false,
          'message': 'Selected file does not exist',
        };
      }

      // Get file info
      final fileName = basename(filePath);
      
      // Validate it's a .db file
      if (!fileName.toLowerCase().endsWith('.db')) {
        return {
          'success': false,
          'message': 'Please select a .db backup file',
        };
      }

      // Get file stats for confirmation
      final stat = await file.stat();

      // Return file info for user confirmation before restore
      return {
        'success': true,
        'message': 'File selected',
        'needsConfirmation': true,
        'filePath': filePath,
        'fileName': fileName,
        'fileSize': stat.size,
        'fileDate': stat.modified,
      };
    } catch (e) {
      return {
        'success': false,
        'message': 'File picker error: $e',
      };
    }
  }

  /// ================================
  /// CONFIRM AND RESTORE FROM PICKED FILE
  /// ================================
  static Future<Map<String, dynamic>> confirmRestoreFromFile(String filePath) async {
    return await restoreDatabase(filePath);
  }

  /// ================================
  /// GET ALL BACKUPS FROM BACKUP FOLDER
  /// ================================
  static Future<List<Map<String, dynamic>>> getAllBackups() async {
    try {
      final backupFolder = await _getBackupFolder();
      final files = await backupFolder.list().toList();
      
      final backups = <Map<String, dynamic>>[];
      
      for (var file in files) {
        if (file is File && file.path.endsWith('.db')) {
          final stat = await file.stat();
          backups.add({
            'name': basename(file.path),
            'path': file.path,
            'size': stat.size,
            'date': stat.modified,
          });
        }
      }
      
      // Sort by date (newest first)
      backups.sort((a, b) => (b['date'] as DateTime).compareTo(a['date'] as DateTime));
      
      return backups;
    } catch (_) {
      return [];
    }
  }

  /// ================================
  /// DELETE BACKUP
  /// ================================
  static Future<bool> deleteBackupFile(String backupFilePath) async {
    try {
      final file = File(backupFilePath);

      if (await file.exists()) {
        await file.delete();
        return true;
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  /// ================================
  /// GET BACKUP FOLDER PATH
  /// ================================
  static Future<String> getBackupFolderPath() async {
    final folder = await _getBackupFolder();
    return folder.path;
  }

  /// ================================
  /// CHECK IF BACKUP EXISTS
  /// ================================
  static Future<bool> hasBackups() async {
    final backups = await getAllBackups();
    return backups.isNotEmpty;
  }

  /// ================================
  /// GET BACKUP FILE SIZE (formatted)
  /// ================================
  static String formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(2)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB';
  }

  /// ================================
  /// VALIDATE BACKUP FILE
  /// ================================
  static Future<bool> isValidBackupFile(String filePath) async {
    try {
      final file = File(filePath);
      
      // Check if file exists
      if (!await file.exists()) return false;
      
      // Check file extension
      if (!filePath.endsWith('.db')) return false;
      
      // Check file size (should be > 0)
      final stat = await file.stat();
      if (stat.size == 0) return false;
      
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Selective restore: Restore only specific tables from backup.
  ///
  /// [treatEmptyAsSuccess]: by default (false, the existing behavior every
  /// other caller relies on), restoring zero non-empty tables is reported
  /// as a failure — a reasonable safety signal when restoring your own
  /// backup file (usually means the wrong/corrupt file was picked). But a
  /// linked school's backup can be *legitimately* empty (a brand new school
  /// with no data entered yet) — for that caller (SchoolSyncClient), pass
  /// true so a structurally valid but empty backup counts as success.
  static Future<Map<String, dynamic>> selectiveRestoreDatabase(
    String backupFilePath,
    List<String> tablesToRestore, {
    bool treatEmptyAsSuccess = false,
  }) async {
    try {
      if (tablesToRestore.isEmpty) {
        return {
          'success': false,
          'message': 'No tables selected for restore',
        };
      }

      final dbPath = await _getDatabasePath();
      final backupFile = File(backupFilePath);

      if (!await backupFile.exists()) {
        return {
          'success': false,
          'message': 'Backup file not found',
        };
      }

      // Validate it's a database file
      if (!backupFilePath.endsWith('.db')) {
        return {
          'success': false,
          'message': 'Invalid backup file. Must be a .db file',
        };
      }

      // Close current database connection
      try {
        await DatabaseHelper().closeAndReset();
      } catch (_) {
        // Database might not be open, continue
      }

      // Open both databases
      final currentDb = await openDatabase(dbPath);
      final backupDb = await openDatabase(backupFilePath, readOnly: true);

      int restoredTables = 0;
      int totalRecords = 0;

      for (String tableName in tablesToRestore) {
        try {
          // Get all data from backup table
          final backupData = await backupDb.query(tableName);

          if (backupData.isEmpty) {
            continue; // Skip empty tables
          }

          // Delete existing data in current table
          await currentDb.delete(tableName);

          // Insert backup data
          final batch = currentDb.batch();
          for (var row in backupData) {
            batch.insert(tableName, row);
          }
          await batch.commit(noResult: true);

          // If the settings table was just restored, re-apply pref_ rows to SharedPreferences
          if (tableName == 'settings') {
            await _applyPrefsFromOpenDb(currentDb);
          }

          restoredTables++;
          totalRecords += backupData.length;
        } catch (e) {
          // Skip table if error (might not exist or have schema issues)
          debugPrint('Warning: Could not restore table $tableName: $e');
        }
      }

      // Close databases
      await backupDb.close();
      await currentDb.close();

      if (restoredTables == 0 && !treatEmptyAsSuccess) {
        return {
          'success': false,
          'message': 'No tables were successfully restored',
        };
      }

      return {
        'success': true,
        'message': restoredTables == 0
            ? 'Backup is valid but contains no data yet.'
            : 'Restored $restoredTables table(s) with $totalRecords record(s). Please restart the app.',
        'tablesRestored': restoredTables,
        'recordsRestored': totalRecords,
      };
    } catch (e) {
      return {
        'success': false,
        'message': 'Selective restore failed: $e',
      };
    }
  }
}