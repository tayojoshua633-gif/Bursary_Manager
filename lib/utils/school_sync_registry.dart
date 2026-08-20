// lib/utils/school_sync_registry.dart
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

/// A school this Read-Only device has linked via a sync key. Stored in
/// SharedPreferences (not inside a swappable per-school .db file) since the
/// registry itself must survive DatabaseHelper.switchDatabase() calls.
class LinkedSchool {
  /// The server's subscriber_id, as a string.
  final String id;
  final String schoolName;
  /// The school's stable identifying code, shown instead of [schoolName] in
  /// the linked-schools list and the home screen tabs. Empty for schools
  /// linked before this field existed, until they're removed and re-added.
  final String schoolCode;
  final String syncKey;
  final String dbFileName;
  final String? lastSyncedAt;
  final String? lastBackupCreatedAt;

  const LinkedSchool({
    required this.id,
    required this.schoolName,
    this.schoolCode = '',
    required this.syncKey,
    required this.dbFileName,
    this.lastSyncedAt,
    this.lastBackupCreatedAt,
  });

  /// What to display for this school — the code when known, falling back to
  /// the name for schools linked before schoolCode existed.
  String get displayLabel => schoolCode.isNotEmpty ? schoolCode : schoolName;

  LinkedSchool copyWith({
    String? schoolName,
    String? schoolCode,
    String? syncKey,
    String? lastSyncedAt,
    String? lastBackupCreatedAt,
  }) {
    return LinkedSchool(
      id: id,
      schoolName: schoolName ?? this.schoolName,
      schoolCode: schoolCode ?? this.schoolCode,
      syncKey: syncKey ?? this.syncKey,
      dbFileName: dbFileName,
      lastSyncedAt: lastSyncedAt ?? this.lastSyncedAt,
      lastBackupCreatedAt: lastBackupCreatedAt ?? this.lastBackupCreatedAt,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'schoolName': schoolName,
        'schoolCode': schoolCode,
        'syncKey': syncKey,
        'dbFileName': dbFileName,
        'lastSyncedAt': lastSyncedAt,
        'lastBackupCreatedAt': lastBackupCreatedAt,
      };

  factory LinkedSchool.fromJson(Map<String, dynamic> json) => LinkedSchool(
        id: json['id'] as String,
        schoolName: json['schoolName'] as String,
        schoolCode: json['schoolCode'] as String? ?? '',
        syncKey: json['syncKey'] as String,
        dbFileName: json['dbFileName'] as String,
        lastSyncedAt: json['lastSyncedAt'] as String?,
        lastBackupCreatedAt: json['lastBackupCreatedAt'] as String?,
      );
}

class SchoolSyncRegistry {
  static const String _listKey = 'linked_schools';
  static const String _activeKey = 'active_school_id';

  /// A device is Read-Only purely by virtue of having linked at least one
  /// school — there's no separate mode flag to fall out of sync with the
  /// list. Linking the first school switches a device into Read-Only mode;
  /// removing the last one switches it back to Write mode.
  static Future<bool> isReadOnlyMode() async => (await getAll()).isNotEmpty;

  static Future<List<LinkedSchool>> getAll() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_listKey);
    if (raw == null || raw.isEmpty) return [];
    try {
      final decoded = jsonDecode(raw) as List<dynamic>;
      return decoded
          .map((e) => LinkedSchool.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  static Future<void> _saveAll(List<LinkedSchool> schools) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _listKey,
      jsonEncode(schools.map((s) => s.toJson()).toList()),
    );
  }

  static Future<bool> contains(String id) async {
    final all = await getAll();
    return all.any((s) => s.id == id);
  }

  static Future<void> add(LinkedSchool school) async {
    final all = await getAll();
    if (all.any((s) => s.id == school.id)) return;
    all.add(school);
    await _saveAll(all);
  }

  static Future<void> update(
    String id, {
    String? schoolName,
    String? syncKey,
    String? lastSyncedAt,
    String? lastBackupCreatedAt,
  }) async {
    final all = await getAll();
    final idx = all.indexWhere((s) => s.id == id);
    if (idx == -1) return;
    all[idx] = all[idx].copyWith(
      schoolName: schoolName,
      syncKey: syncKey,
      lastSyncedAt: lastSyncedAt,
      lastBackupCreatedAt: lastBackupCreatedAt,
    );
    await _saveAll(all);
  }

  /// Removes a school from the registry only. Does NOT delete its cached
  /// .db file — callers (SchoolSyncClient.removeSchool) own that, since this
  /// class only tracks the list, not the files it points to.
  static Future<void> remove(String id) async {
    final all = await getAll();
    all.removeWhere((s) => s.id == id);
    await _saveAll(all);
    if (await getActiveId() == id) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_activeKey);
    }
  }

  static Future<String?> getActiveId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_activeKey);
  }

  static Future<void> setActiveId(String id) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_activeKey, id);
  }
}
