// lib/utils/google_drive_backup_helper.dart
import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:http/http.dart' as http;
import 'package:path/path.dart';
import 'windows_google_auth.dart';

/// Google Drive backup helper for uploading database backups
///
/// SETUP INSTRUCTIONS:
/// 1. Add dependencies to pubspec.yaml:
///    - google_sign_in: ^6.2.1
///    - googleapis: ^13.2.0
///    - http: ^1.2.0
///
/// 2. Get Google Cloud Console credentials:
///    a. Go to https://console.cloud.google.com/
///    b. Create a new project or select existing
///    c. Enable Google Drive API
///    d. Create OAuth 2.0 credentials
///    e. Add your package name and SHA-1 fingerprint (Android)
///
/// 3. Configure OAuth for Android (android/app/src/main/AndroidManifest.xml):
///    Add inside <application> tag:
///    <meta-data
///        android:name="com.google.android.gms.version"
///        android:value="@integer/google_play_services_version" />
///
/// 4. Configure OAuth for iOS (ios/Runner/Info.plist):
///    Add your reversed client ID as URL scheme
///
/// 5. Windows/Linux/macOS use the loopback OAuth flow in
///    [WindowsGoogleAuth] instead, since google_sign_in has no desktop support.
///
class GoogleDriveBackupHelper {
  // Google Sign-In configuration (Android / iOS)
  static final GoogleSignIn _googleSignIn = GoogleSignIn(
    scopes: [
      drive.DriveApi.driveFileScope, // create / upload own backups
      'https://www.googleapis.com/auth/drive.readonly', // read backups from DSM
    ],
  );

  // True when the current platform needs the loopback OAuth flow.
  static bool get _isDesktop =>
      !kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS);

  /// Check if user is currently signed in.
  /// Attempts a silent sign-in first to restore sessions after app restart.
  static Future<bool> isSignedIn() async {
    if (_isDesktop) return WindowsGoogleAuth.isSignedIn();
    if (_googleSignIn.currentUser != null) return true;
    try {
      // Reaches accounts.google.com — on a network with no internet uplink
      // this never resolves on its own, which would stall the home screen.
      final account = await _googleSignIn
          .signInSilently()
          .timeout(const Duration(seconds: 5));
      return account != null;
    } catch (_) {
      return false;
    }
  }

  /// Get current signed-in user email (mobile only — always null on
  /// desktop; use [getEmailAsync] there).
  static String? getCurrentUserEmail() {
    if (_isDesktop) return null;
    return _googleSignIn.currentUser?.email;
  }

  /// Async email fetch — works on all platforms.
  static Future<String?> getEmailAsync() async {
    if (_isDesktop) return WindowsGoogleAuth.getEmail();
    return _googleSignIn.currentUser?.email;
  }

  /// Sign in to Google account
  static Future<Map<String, dynamic>> signIn() async {
    if (_isDesktop) return WindowsGoogleAuth.signIn();
    try {
      final account = await _googleSignIn.signIn();

      if (account == null) {
        return {
          'success': false,
          'message': 'Sign-in cancelled by user',
        };
      }

      return {
        'success': true,
        'message': 'Signed in successfully',
        'email': account.email,
      };
    } catch (e) {
      return {
        'success': false,
        'message': 'Sign-in failed: $e',
      };
    }
  }

  /// Sign out from Google account
  static Future<void> signOut() async {
    if (_isDesktop) {
      await WindowsGoogleAuth.signOut();
      return;
    }
    await _googleSignIn.signOut();
  }

  /// Get authenticated HTTP client for Drive API
  static Future<http.Client?> _getAuthenticatedClient() async {
    if (_isDesktop) return WindowsGoogleAuth.getAuthenticatedClient();
    final account = _googleSignIn.currentUser;
    if (account == null) return null;

    final authHeaders = await account.authHeaders;
    return _GoogleAuthClient(authHeaders);
  }

  /// Upload backup file to Google Drive
  static Future<Map<String, dynamic>> uploadBackupToDrive(String filePath) async {
    try {
      // Check if signed in
      if (!await isSignedIn()) {
        return {
          'success': false,
          'message': 'Not signed in to Google account',
        };
      }

      // Get authenticated client
      final client = await _getAuthenticatedClient();
      if (client == null) {
        return {
          'success': false,
          'message': 'Failed to authenticate with Google',
        };
      }

      // Create Drive API instance
      final driveApi = drive.DriveApi(client);

      // Read file
      final file = File(filePath);
      if (!await file.exists()) {
        return {
          'success': false,
          'message': 'Backup file not found',
        };
      }

      final fileName = basename(filePath);
      final fileBytes = await file.readAsBytes();

      // Create metadata for the file
      final driveFile = drive.File()
        ..name = fileName
        ..description = 'Bursary Manager database backup'
        ..mimeType = fileName.toLowerCase().endsWith('.zip')
            ? 'application/zip'
            : 'application/x-sqlite3';

      // Check if folder exists, create if not
      final folderId = await _getOrCreateBackupFolder(driveApi);
      if (folderId != null) {
        driveFile.parents = [folderId];
      }

      // Upload file
      final media = drive.Media(
        Stream.value(fileBytes),
        fileBytes.length,
      );

      final uploadedFile = await driveApi.files.create(
        driveFile,
        uploadMedia: media,
      );

      if (folderId != null) await _pruneBackupFolder(driveApi, folderId);
      client.close();

      return {
        'success': true,
        'message': 'Backup uploaded to Google Drive successfully',
        'fileName': fileName,
        'fileId': uploadedFile.id,
        'webViewLink': uploadedFile.webViewLink,
      };
    } catch (e) {
      return {
        'success': false,
        'message': 'Upload failed: $e',
      };
    }
  }

  /// How many backups the "Bursary Backups" folder keeps. It holds both the
  /// Online Backup screen's uploads and the automatic ones, so without a
  /// limit it would grow until the Google account's storage is full — at
  /// which point every backup to Drive starts failing.
  static const int maxDriveBackups = 5;

  /// Deletes all but the newest [maxDriveBackups] backups in the folder.
  /// Best-effort: a failed delete just leaves an extra file behind.
  static Future<void> _pruneBackupFolder(drive.DriveApi driveApi, String folderId) async {
    try {
      final listed = await driveApi.files.list(
        q: "(name contains '.db' or name contains '.zip') and '$folderId' in parents and trashed=false",
        spaces: 'drive',
        orderBy: 'createdTime desc',
        $fields: 'files(id)',
      );
      final files = listed.files ?? [];
      for (final f in files.skip(maxDriveBackups)) {
        try { await driveApi.files.delete(f.id!); } catch (_) {}
      }
    } catch (_) {}
  }

  /// Get or create "Bursary Backups" folder in Drive
  static Future<String?> _getOrCreateBackupFolder(drive.DriveApi driveApi) async {
    try {
      const folderName = 'Bursary Backups';

      // Search for existing folder
      final query = "name='$folderName' and mimeType='application/vnd.google-apps.folder' and trashed=false";
      final fileList = await driveApi.files.list(
        q: query,
        spaces: 'drive',
        $fields: 'files(id, name)',
      );

      if (fileList.files != null && fileList.files!.isNotEmpty) {
        // Folder exists, return its ID
        return fileList.files!.first.id;
      }

      // Folder doesn't exist, create it
      final folder = drive.File()
        ..name = folderName
        ..mimeType = 'application/vnd.google-apps.folder'
        ..description = 'Backup folder for Bursary Manager database backups';

      final createdFolder = await driveApi.files.create(folder);
      return createdFolder.id;
    } catch (e) {
      // If folder creation fails, return null (file will be in root)
      return null;
    }
  }

  /// List backup files in Google Drive
  static Future<List<Map<String, dynamic>>> listBackupsInDrive() async {
    try {
      if (!await isSignedIn()) {
        return [];
      }

      final client = await _getAuthenticatedClient();
      if (client == null) return [];

      final driveApi = drive.DriveApi(client);

      // Search for .db / .zip backups in Bursary Backups folder
      final folderId = await _getOrCreateBackupFolder(driveApi);
      String query = "(name contains '.db' or name contains '.zip') and trashed=false";
      if (folderId != null) {
        query += " and '$folderId' in parents";
      }

      final fileList = await driveApi.files.list(
        q: query,
        spaces: 'drive',
        orderBy: 'modifiedTime desc',
        $fields: 'files(id, name, size, createdTime, modifiedTime, webViewLink)',
      );

      client.close();

      if (fileList.files == null || fileList.files!.isEmpty) {
        return [];
      }

      return fileList.files!.map((file) {
        return {
          'id': file.id,
          'name': file.name,
          'size': file.size,
          'createdTime': file.createdTime,
          'modifiedTime': file.modifiedTime,
          'webViewLink': file.webViewLink,
        };
      }).toList();
    } catch (e) {
      return [];
    }
  }

  /// Download backup file from Google Drive
  static Future<Map<String, dynamic>> downloadBackupFromDrive(
    String fileId,
    String destinationPath,
  ) async {
    try {
      if (!await isSignedIn()) {
        return {
          'success': false,
          'message': 'Not signed in to Google account',
        };
      }

      final client = await _getAuthenticatedClient();
      if (client == null) {
        return {
          'success': false,
          'message': 'Failed to authenticate with Google',
        };
      }

      final driveApi = drive.DriveApi(client);

      // Download file
      final media = await driveApi.files.get(
        fileId,
        downloadOptions: drive.DownloadOptions.fullMedia,
      ) as drive.Media;

      // Save to destination
      final file = File(destinationPath);
      final sink = file.openWrite();

      await for (var chunk in media.stream) {
        sink.add(chunk);
      }

      await sink.close();
      client.close();

      return {
        'success': true,
        'message': 'Backup downloaded successfully',
        'filePath': destinationPath,
      };
    } catch (e) {
      return {
        'success': false,
        'message': 'Download failed: $e',
      };
    }
  }

  /// Delete backup file from Google Drive
  static Future<Map<String, dynamic>> deleteBackupFromDrive(String fileId) async {
    try {
      if (!await isSignedIn()) {
        return {
          'success': false,
          'message': 'Not signed in to Google account',
        };
      }

      final client = await _getAuthenticatedClient();
      if (client == null) {
        return {
          'success': false,
          'message': 'Failed to authenticate with Google',
        };
      }

      final driveApi = drive.DriveApi(client);
      await driveApi.files.delete(fileId);
      client.close();

      return {
        'success': true,
        'message': 'Backup deleted from Google Drive',
      };
    } catch (e) {
      return {
        'success': false,
        'message': 'Delete failed: $e',
      };
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // DSM sync folder (read-only — does NOT create, only reads what DSM made)
  // ─────────────────────────────────────────────────────────────────────────

  /// The desktop DSM app's backup folder: its Online Backup screen, home
  /// Sync button and auto-backup all upload a zip (database + photos) here.
  static const String dsmFolderName = 'DSM Backup';

  /// Folder used by older DSM versions' CloudSync (raw .db files). Still
  /// read so backups made before DSM switched folders stay available.
  static const String _legacyDsmFolderName = 'DSM CloudSync';

  /// Finds (but does NOT create) every DSM backup folder on this account.
  static Future<List<String>> _getDsmFolders(drive.DriveApi driveApi) async {
    try {
      final query = "(name='$dsmFolderName' or name='$_legacyDsmFolderName') "
          "and mimeType='application/vnd.google-apps.folder' and trashed=false";
      final fileList = await driveApi.files.list(
        q: query,
        spaces: 'drive',
        $fields: 'files(id, name)',
      );
      return [
        for (final f in fileList.files ?? <drive.File>[])
          if (f.id != null) f.id!,
      ];
    } catch (_) {
      return [];
    }
  }

  /// Lists all .db / .zip backups from the desktop DSM app's Drive folders
  /// ("DSM Backup", plus the older "DSM CloudSync"), newest first. Returns
  /// an empty list when not signed in or DSM has never backed up to Drive
  /// on this account.
  static Future<List<Map<String, dynamic>>> listDsmBackups() async {
    try {
      if (!await isSignedIn()) return [];
      final client = await _getAuthenticatedClient();
      if (client == null) return [];

      final driveApi = drive.DriveApi(client);
      final folderIds = await _getDsmFolders(driveApi);
      if (folderIds.isEmpty) { client.close(); return []; }

      final inFolders = folderIds.map((id) => "'$id' in parents").join(' or ');
      final fileList = await driveApi.files.list(
        q: "($inFolders) and (name contains '.db' or name contains '.zip') and trashed=false",
        spaces: 'drive',
        orderBy: 'modifiedTime desc',
        $fields: 'files(id, name, size, createdTime, modifiedTime)',
      );
      client.close();

      if (fileList.files == null || fileList.files!.isEmpty) return [];
      return fileList.files!.map((f) => {
        'id': f.id,
        'name': f.name,
        'size': f.size,
        'createdTime': f.createdTime,
        'modifiedTime': f.modifiedTime,
      }).toList();
    } catch (_) {
      return [];
    }
  }

  // ─────────────────────────────────────────────────────────────────────────

  /// Create backup and upload to Google Drive in one operation
  static Future<Map<String, dynamic>> backupAndUploadToDrive(
    String backupFilePath,
  ) async {
    try {
      // Check if signed in
      if (!await isSignedIn()) {
        // Attempt to sign in
        final signInResult = await signIn();
        if (!signInResult['success']) {
          return signInResult;
        }
      }

      // Upload the backup file
      return await uploadBackupToDrive(backupFilePath);
    } catch (e) {
      return {
        'success': false,
        'message': 'Backup and upload failed: $e',
      };
    }
  }
}

/// Custom HTTP client that adds auth headers to requests
class _GoogleAuthClient extends http.BaseClient {
  final Map<String, String> _headers;
  final http.Client _client = http.Client();

  _GoogleAuthClient(this._headers);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    return _client.send(request..headers.addAll(_headers));
  }

  @override
  void close() {
    _client.close();
  }
}
