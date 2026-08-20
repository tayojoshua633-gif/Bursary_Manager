// lib/utils/school_sync_client.dart
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import '../db/database_helper.dart';
import 'central_backup_helper.dart';
import 'db_backup_helper.dart';
import 'school_sync_registry.dart';

/// Talks to the central backup server's sync endpoints (sync_resolve.php,
/// sync_list_backups.php, sync_download_backup.php) to let a Read-Only
/// device link to and refresh multiple schools' cached data.
///
/// v1 concurrency scope, deliberate: DatabaseHelper only ever has one file
/// open at a time, so only two refresh patterns are supported — refreshing
/// the currently *active* tab (pull-to-refresh), and a sequential (never
/// parallel) refresh-all-then-land-on-active-tab on app launch. Refreshing a
/// school that isn't the active tab briefly switches the active database to
/// restore into it, then switches back.
class SchoolSyncClient {
  static const String _baseUrl = CentralBackupHelper.apiBaseUrl;
  static const String _apiSecret = CentralBackupHelper.apiSecret;
  static const String _product = 'BM';

  // Tables restored on each sync — same allow-list CloudSync used, licenses
  // intentionally excluded so a linked school's data never touches this
  // device's own license activation.
  static const List<String> syncTables = [
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

  /// Resolves [syncKey], links the school if not already linked, and does
  /// the first download + restore, making it the active tab.
  static Future<Map<String, dynamic>> addSchool(String syncKey) async {
    try {
      final resolveResp = await http.post(
        Uri.parse('$_baseUrl/sync_resolve.php'),
        headers: {'X-Api-Secret': _apiSecret},
        body: {'product': _product, 'sync_key': syncKey},
      ).timeout(const Duration(seconds: 20));

      final resolved = _decodeOrNull(resolveResp.body);
      if (resolveResp.statusCode != 200 || resolved == null || resolved['ok'] != true) {
        return {
          'success': false,
          'message': (resolved != null ? resolved['error'] as String? : null) ??
              'Could not verify this sync key. Check the key and your internet connection.',
        };
      }

      final id = resolved['subscriber_id'].toString();
      final schoolName = (resolved['school_name'] as String?) ?? 'Unnamed school';
      final schoolCode = (resolved['school_code'] as String?) ?? '';

      if (await SchoolSyncRegistry.contains(id)) {
        return {'success': false, 'message': 'This school is already linked.'};
      }

      final school = LinkedSchool(
        id: id,
        schoolName: schoolName,
        schoolCode: schoolCode,
        syncKey: syncKey,
        dbFileName: 'sync_$id.db',
      );
      await SchoolSyncRegistry.add(school);

      final result = await refreshSchool(school, makeActive: true);
      if (result['success'] != true) {
        // Roll back the registry entry so a failed first sync doesn't leave
        // an empty, unusable tab behind.
        await SchoolSyncRegistry.remove(id);
        return result;
      }
      return {'success': true, 'message': 'Linked "$schoolName".', 'school': school};
    } catch (e) {
      return {'success': false, 'message': 'Failed to add school: $e'};
    }
  }

  /// Downloads the latest backup for [school] if it's newer than what's
  /// cached, and restores it via the existing selective-restore machinery.
  /// If [makeActive] is false, the active database is switched back to
  /// whatever the registry currently says is active once the restore is
  /// done — this method never leaves a non-active refresh "stuck" on screen.
  static Future<Map<String, dynamic>> refreshSchool(
    LinkedSchool school, {
    required bool makeActive,
  }) async {
    try {
      final listResp = await http.post(
        Uri.parse('$_baseUrl/sync_list_backups.php'),
        headers: {'X-Api-Secret': _apiSecret},
        body: {'product': _product, 'sync_key': school.syncKey},
      ).timeout(const Duration(seconds: 20));

      final listed = _decodeOrNull(listResp.body);
      if (listResp.statusCode != 200 || listed == null || listed['ok'] != true) {
        return {
          'success': false,
          'message': (listed != null ? listed['error'] as String? : null) ??
              'Could not reach the sync server.',
        };
      }

      final backups = (listed['backups'] as List<dynamic>?) ?? [];
      if (backups.isEmpty) {
        return {'success': false, 'message': 'This school has no backups yet.'};
      }

      final latest = backups.first as Map<String, dynamic>;
      final latestCreatedAt = latest['created_at'] as String?;
      final backupId = latest['id'].toString();

      if (latestCreatedAt != null && latestCreatedAt == school.lastBackupCreatedAt) {
        return {'success': true, 'changed': false, 'message': 'Already up to date.'};
      }

      final tempPath = await _buildTempPath('school_sync_${school.id}');
      final downloadResp = await http.post(
        Uri.parse('$_baseUrl/sync_download_backup.php'),
        headers: {'X-Api-Secret': _apiSecret},
        body: {'product': _product, 'sync_key': school.syncKey, 'backup_id': backupId},
      ).timeout(const Duration(seconds: 60));

      if (downloadResp.statusCode != 200) {
        final failed = _decodeOrNull(downloadResp.body);
        return {
          'success': false,
          'message': (failed != null ? failed['error'] as String? : null) ??
              'Download failed (HTTP ${downloadResp.statusCode}).',
        };
      }
      await File(tempPath).writeAsBytes(downloadResp.bodyBytes);

      await DatabaseHelper().switchDatabase(school.dbFileName);
      final restoreResult = await DBBackupHelper.selectiveRestoreDatabase(
        tempPath,
        syncTables,
        treatEmptyAsSuccess: true,
      );
      _deleteSilently(tempPath);

      if (restoreResult['success'] != true) {
        return {
          'success': false,
          'message': restoreResult['message'] as String? ?? 'Restore failed.',
        };
      }

      final nowIso = DateTime.now().toIso8601String();
      await SchoolSyncRegistry.update(
        school.id,
        schoolName: school.schoolName,
        lastSyncedAt: nowIso,
        lastBackupCreatedAt: latestCreatedAt,
      );

      if (makeActive) {
        await SchoolSyncRegistry.setActiveId(school.id);
      } else {
        // Leave the active database pointed at whatever the registry still
        // considers active — this refresh was a background/non-visible one.
        final activeId = await SchoolSyncRegistry.getActiveId();
        if (activeId != null && activeId != school.id) {
          final all = await SchoolSyncRegistry.getAll();
          final activeSchool = all.where((s) => s.id == activeId).firstOrNull;
          if (activeSchool != null) {
            await DatabaseHelper().switchDatabase(activeSchool.dbFileName);
          }
        }
      }

      return {'success': true, 'changed': true, 'message': 'Synced "${school.schoolName}".'};
    } catch (e) {
      return {'success': false, 'message': 'Sync failed: $e'};
    }
  }

  /// Removes a linked school from the registry and deletes its cached file.
  /// Called once at app launch, before showing the Homepage. Sequentially
  /// (never in parallel, per the class doc) refreshes every linked school,
  /// leaving whichever was already marked active as the active database
  /// once done. Best-effort — one school's failure never blocks the others.
  static Future<void> refreshAllOnLaunch() async {
    final schools = await SchoolSyncRegistry.getAll();
    if (schools.isEmpty) return;
    final activeId = await SchoolSyncRegistry.getActiveId() ?? schools.first.id;
    for (final school in schools) {
      try {
        await refreshSchool(school, makeActive: school.id == activeId);
      } catch (_) {
        // Best-effort — continue with the remaining schools.
      }
    }
  }

  static Future<void> removeSchool(String id) async {
    final all = await SchoolSyncRegistry.getAll();
    final school = all.where((s) => s.id == id).firstOrNull;
    await SchoolSyncRegistry.remove(id);
    if (school != null) {
      try {
        final dir = await getDatabasesPath();
        final file = File(p.join(dir, school.dbFileName));
        if (await file.exists()) await file.delete();
      } catch (_) {
        // Best-effort — an orphaned cache file isn't worth failing over.
      }
    }
  }

  static Future<String> _buildTempPath(String name) async {
    final dir = await getTemporaryDirectory();
    final ts = DateTime.now().millisecondsSinceEpoch;
    return p.join(dir.path, '${name}_$ts.db');
  }

  static void _deleteSilently(String path) {
    try {
      File(path).deleteSync();
    } catch (_) {}
  }

  static Map<String, dynamic>? _decodeOrNull(String body) {
    try {
      return jsonDecode(body) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }
}
