// lib/utils/central_backup_helper.dart
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';
import '../db/database_helper.dart';
import 'license_helper.dart';

/// Pushes a copy of every backup to Tysolutions' central server, alongside
/// whatever the user does with Google Drive. Purpose: support can look at a
/// school's data without asking them to send a file manually.
///
/// Best-effort only — every failure is swallowed so this never blocks or
/// breaks the local/Drive backup it rides along with.
class CentralBackupHelper {
  static const String _uploadUrl = 'https://backups.tysolutions.com.ng/api/upload.php';

  // Proves the request came from this app, not a random visitor — shared by
  // every install, not a per-school secret. Must match config.php's
  // api_secret on the server.
  static const String _apiSecret = '571c6607bdc5f6c575d56e950c5ad844dae36bd922d81777bcb54472742a0f2e';

  /// Uploads [filePath] to the central backup server for the currently
  /// active license. Returns true only on a confirmed 200 from the server.
  static Future<bool> uploadBackup(String filePath) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) {
        debugPrint('[CentralBackup] aborted: file does not exist: $filePath');
        return false;
      }

      final license = await DatabaseHelper().getActiveLicense();
      final licenseKey = license?['licenseKey'] as String?;
      if (licenseKey == null || licenseKey.isEmpty) {
        debugPrint('[CentralBackup] aborted: no active license found');
        return false;
      }

      final schoolName = (license?['schoolName'] as String?) ?? '';
      final licenseExpiry = license?['expiryDate'] as String?;
      final deviceId = await LicenseHelper.getDeviceId();
      final stats = await _gatherSchoolStats();
      final appVersion = await _getAppVersion();

      final request = http.MultipartRequest('POST', Uri.parse(_uploadUrl))
        ..headers['X-Api-Secret'] = _apiSecret
        ..fields['product'] = 'BM'
        ..fields['license_key'] = licenseKey
        ..fields['school_name'] = schoolName
        ..fields['device_id'] = deviceId
        ..fields['app_version'] = appVersion
        ..fields['real_school_name'] = stats.realSchoolName ?? ''
        ..fields['school_address'] = stats.address ?? ''
        ..fields['school_phone'] = stats.phone ?? ''
        ..fields['school_email'] = stats.email ?? ''
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
        return false;
      }
      debugPrint('[CentralBackup] upload succeeded for license $licenseKey');
      return true;
    } catch (e, st) {
      debugPrint('[CentralBackup] upload threw: $e');
      debugPrint('$st');
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
