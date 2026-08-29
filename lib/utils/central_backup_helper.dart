// lib/utils/central_backup_helper.dart
import 'dart:async';
import 'dart:io';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import '../db/database_helper.dart';
import 'license_helper.dart';
import 'school_sync_registry.dart';

/// Pushes a copy of every backup to Tysolutions' central server. Purposes:
/// (1) support can look at a school's data without asking for a file
/// manually, and (2) it's the source Read-Only devices sync from — see
/// SchoolSyncClient.
///
/// Best-effort only — every failure is swallowed so this never blocks or
/// breaks whatever local operation triggered it.
class CentralBackupHelper {
  /// Shared by every client of the central backup API (uploads and the
  /// sync-key endpoints alike) so the host isn't duplicated per file.
  static const String apiBaseUrl = 'https://backups.tysolutions.com.ng/api';
  static const String _uploadUrl = '$apiBaseUrl/upload.php';

  // Proves the request came from this app, not a random visitor — shared by
  // every install, not a per-school secret. Must match config.php's
  // api_secret on the server. Exposed publicly so SyncKeyClient and
  // SchoolSyncClient can reuse it instead of duplicating the literal.
  static const String apiSecret = '571c6607bdc5f6c575d56e950c5ad844dae36bd922d81777bcb54472742a0f2e';
  static const String _apiSecret = apiSecret;

  /// Uploads [filePath] to the central backup server for the currently
  /// active license. Returns true only on a confirmed 200 from the server.
  /// Thin wrapper over [_uploadBackupWithReason] for callers that only need
  /// the bool (fire-and-forget call sites).
  static Future<bool> uploadBackup(String filePath) async =>
      (await _uploadBackupWithReason(filePath))['success'] as bool;

  /// Same upload, but returns *why* it failed instead of collapsing every
  /// cause into a bare `false`. Used by [triggerAutoUpload] so a user-facing
  /// "Sync Now" button can show the real reason instead of a generic
  /// "check your internet connection" for every possible failure.
  static Future<Map<String, dynamic>> _uploadBackupWithReason(String filePath) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) {
        debugPrint('[CentralBackup] aborted: file does not exist: $filePath');
        return {'success': false, 'message': 'Backup file not found on this device.'};
      }

      final license = await DatabaseHelper().getActiveLicense();
      final licenseKey = license?['licenseKey'] as String?;
      if (licenseKey == null || licenseKey.isEmpty) {
        debugPrint('[CentralBackup] aborted: no active license found');
        return {'success': false, 'message': 'No active license found on this device.'};
      }

      final schoolName = (license?['schoolName'] as String?) ?? '';
      final schoolCode = (license?['schoolCode'] as String?) ?? '';
      final licenseExpiry = license?['expiryDate'] as String?;
      final deviceId = await LicenseHelper.getDeviceId();
      final stats = await _gatherSchoolStats();
      final appVersion = await _getAppVersion();

      final request = http.MultipartRequest('POST', Uri.parse(_uploadUrl))
        ..headers['X-Api-Secret'] = _apiSecret
        ..fields['product'] = 'BM'
        ..fields['license_key'] = licenseKey
        ..fields['school_code'] = schoolCode
        ..fields['entity_name'] = schoolName
        ..fields['device_id'] = deviceId
        ..fields['app_version'] = appVersion
        ..fields['real_entity_name'] = stats.realSchoolName ?? ''
        ..fields['entity_address'] = stats.address ?? ''
        ..fields['entity_phone'] = stats.phone ?? ''
        ..fields['entity_email'] = stats.email ?? ''
        ..fields['active_students'] = stats.activeStudents.toString()
        ..fields['active_staff'] = stats.activeStaff.toString()
        ..fields['license_expiry'] = licenseExpiry ?? ''
        ..files.add(await http.MultipartFile.fromPath(
          'backup',
          filePath,
          filename: p.basename(filePath),
        ));

      final streamedResponse = await request.send().timeout(const Duration(seconds: 30));
      if (streamedResponse.statusCode != 200) {
        final body = await streamedResponse.stream.bytesToString();
        debugPrint('[CentralBackup] server rejected upload: HTTP ${streamedResponse.statusCode} — $body');
        return {
          'success': false,
          'message': 'Server rejected the upload (HTTP ${streamedResponse.statusCode}).',
        };
      }
      debugPrint('[CentralBackup] upload succeeded for license $licenseKey');
      return {'success': true, 'message': 'Synced to central backup.'};
    } on TimeoutException {
      debugPrint('[CentralBackup] upload timed out');
      return {'success': false, 'message': 'Upload timed out — connection may be too slow.'};
    } on SocketException catch (e) {
      debugPrint('[CentralBackup] upload socket error: $e');
      return {'success': false, 'message': 'No internet connection.'};
    } catch (e, st) {
      debugPrint('[CentralBackup] upload threw: $e');
      debugPrint('$st');
      return {'success': false, 'message': 'Upload failed: $e'};
    }
  }

  /// Silent background push. Safe to call after any significant DB write.
  /// Never runs on a Read-Only device — its active database may be a
  /// linked school's cached copy, not this device's own data, and pushing
  /// that would misattribute someone else's edits to the wrong subscriber.
  /// Returns `{success, message}` — see [_uploadBackupWithReason].
  static Future<Map<String, dynamic>> triggerAutoUpload() async {
    if (await SchoolSyncRegistry.isReadOnlyMode()) {
      return {'success': false, 'message': 'This device is in Read-Only mode.'};
    }
    if (!await hasInternetConnection()) {
      debugPrint('[CentralBackup] aborted: no network interface active');
      return {'success': false, 'message': 'No internet connection detected on this device.'};
    }

    try {
      final database = await DatabaseHelper().database;

      final dir = await getTemporaryDirectory();
      final ts = DateTime.now().millisecondsSinceEpoch;
      final tempPath = p.join(dir.path, 'central_upload_$ts.db');

      // VACUUM INTO writes a complete, consistent snapshot of the database
      // in one atomic step, regardless of any pending WAL activity. This
      // replaces a checkpoint-then-raw-file-copy approach that could
      // silently upload an incomplete snapshot (missing very recent writes)
      // whenever the WAL checkpoint didn't fully complete — e.g. because
      // something else briefly had the database open at that moment. That
      // was the root cause of data appearing to "disappear" on Read-Only
      // devices until a later sync happened to catch a fully-checkpointed
      // copy. VACUUM INTO errors if the target file already exists, but
      // tempPath is freshly timestamped each call so that never collides.
      final escapedPath = tempPath.replaceAll("'", "''");
      await database.execute("VACUUM INTO '$escapedPath'");

      final result = await _uploadBackupWithReason(tempPath);
      try {
        File(tempPath).deleteSync();
      } catch (_) {}
      return result;
    } catch (e) {
      debugPrint('[CentralBackup] auto-upload threw: $e');
      return {'success': false, 'message': 'Sync failed: $e'};
    }
  }

  static Future<bool> hasInternetConnection() async {
    try {
      final results = await Connectivity().checkConnectivity();
      return results.any((r) => r != ConnectivityResult.none);
    } catch (_) {
      return false;
    }
  }

  static Future<String> _getAppVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      return '${info.version}+${info.buildNumber}';
    } catch (_) {
      return '';
    }
  }

  /// Pulls a quick snapshot of the school's current data for display on the
  /// support admin panel. Best-effort — any failure just leaves fields blank.
  static Future<_SchoolStats> _gatherSchoolStats() async {
    String? realSchoolName;
    String? address;
    String? phone;
    String? email;
    int activeStudents = 0;
    int activeStaff = 0;

    try {
      final database = await DatabaseHelper().database;

      final profileRows = await database.query('school_profile', limit: 1);
      if (profileRows.isNotEmpty) {
        final profile = profileRows.first;
        realSchoolName = profile['name'] as String?;
        address = profile['address'] as String?;
        phone = profile['phone'] as String?;
        email = profile['email'] as String?;
      }

      final studentsResult = await database.rawQuery(
        'SELECT COUNT(*) AS cnt FROM students WHERE isActive = 1',
      );
      activeStudents = Sqflite.firstIntValue(studentsResult) ?? 0;

      final staffResult = await database.rawQuery(
        'SELECT COUNT(*) AS cnt FROM staff WHERE isActive = 1',
      );
      activeStaff = Sqflite.firstIntValue(staffResult) ?? 0;
    } catch (_) {
      // Non-fatal — the upload still proceeds with whatever was gathered.
    }

    return _SchoolStats(
      realSchoolName: realSchoolName,
      address: address,
      phone: phone,
      email: email,
      activeStudents: activeStudents,
      activeStaff: activeStaff,
    );
  }
}

class _SchoolStats {
  final String? realSchoolName;
  final String? address;
  final String? phone;
  final String? email;
  final int activeStudents;
  final int activeStaff;

  const _SchoolStats({
    required this.realSchoolName,
    required this.address,
    required this.phone,
    required this.email,
    required this.activeStudents,
    required this.activeStaff,
  });
}
