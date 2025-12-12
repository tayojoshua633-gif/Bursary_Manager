import 'dart:io';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:file_picker/file_picker.dart';
import '../db/database_helper.dart';

class DBBackupHelper {
  static const String _dbName = "bursary_manager.db";
  static const String _backupFolderName = "BursaryBackups";
  static const String _backupEmail = "tysolutionsmultimediatech@gmail.com";

  /// Returns full database path
  static Future<String> _getDatabasePath() async {
    final dbPath = await getDatabasesPath();
    return join(dbPath, _dbName);
  }

  /// Returns folder for backups (in Downloads/BursaryBackups)
  static Future<Directory> _getBackupFolder() async {
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

      // Close any open database connections
      try {
        final db = await DatabaseHelper().database;
        await db.close();
      } catch (_) {
        // Database might not be open, continue
      }

      // Copy backup to database location
      await destFile.writeAsBytes(await backupFile.readAsBytes());

      return {
        'success': true,
        'message': 'Database restored successfully',
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
}