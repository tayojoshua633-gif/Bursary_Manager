// lib/utils/portal_student_sync_client.dart
import 'dart:convert';
import 'dart:math';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// Talks to the online portal's Teacher Sync API
/// (portal.tysolutions.com.ng/api/teacher_sync, school_portal/api/teacher_sync/)
/// as Bursary Manager, for School Portal Sync.
///
/// Class teachers send corrections to their students' details on the portal.
/// When the portal's Student Details Receiver (Preferences) is Bursary
/// Manager, those corrections come here instead of DSM, because this school
/// keeps its students in BM and DSM syncs them from BM. Photos are never sent
/// to BM.
///
/// The portal knows the school by its DSM school code and lets BM in with a
/// BM sync token generated in DSM (Class/Subject Teacher Sync > Settings).
/// Both are pasted here once and kept in this device's SharedPreferences.
class PortalStudentSyncClient {
  static const String defaultBaseUrl = 'https://portal.tysolutions.com.ng/api/teacher_sync';

  static const String _schoolCodePref = 'portal_student_sync_school_code';
  static const String _tokenPref = 'portal_student_sync_token';

  /// Developer/testing override of [defaultBaseUrl] (e.g. a local preview
  /// at http://127.0.0.1:8899/api/teacher_sync). Not shown in the UI.
  static const String baseUrlPref = 'portal_student_sync_base_url';

  static const Duration _timeout = Duration(seconds: 30);

  static Future<String> baseUrl() async {
    final prefs = await SharedPreferences.getInstance();
    final custom = (prefs.getString(baseUrlPref) ?? '').trim();
    return custom.isNotEmpty ? custom.replaceAll(RegExp(r'/+$'), '') : defaultBaseUrl;
  }

  static Future<String?> schoolCode() async {
    final prefs = await SharedPreferences.getInstance();
    final c = (prefs.getString(_schoolCodePref) ?? '').trim();
    return c.isEmpty ? null : c;
  }

  static Future<String?> token() async {
    final prefs = await SharedPreferences.getInstance();
    final t = (prefs.getString(_tokenPref) ?? '').trim();
    return t.isEmpty ? null : t;
  }

  static Future<bool> isLinked() async => await schoolCode() != null && await token() != null;

  static Future<void> link(String schoolCode, String token) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_schoolCodePref, schoolCode.trim().toUpperCase());
    await prefs.setString(_tokenPref, token.trim().toLowerCase());
  }

  static Future<void> unlink() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_schoolCodePref);
    await prefs.remove(_tokenPref);
  }

  static Future<Map<String, String>> _headers() async {
    final code = await schoolCode();
    final t = await token();
    if (code == null || t == null) {
      throw const PortalSyncException('Enter the DSM school code and BM sync token first.');
    }
    return {
      'X-School-Code': code,
      'X-Sync-Token': t,
      'X-Sync-Client': 'BM',
      'Accept': 'application/json',
    };
  }

  static Map<String, dynamic> _decode(http.Response r) {
    Map<String, dynamic>? body;
    try {
      final d = jsonDecode(r.body);
      if (d is Map<String, dynamic>) body = d;
    } catch (_) {}
    if (r.statusCode == 200 && body != null && body['ok'] == true) return body;
    final msg = body?['error'] as String?;
    final code = body?['code'] as String?;
    if (code == 'token_not_in_backup') {
      throw const PortalSyncException(
          'The portal has not received the BM sync token yet. It arrives with DSM\'s next online backup (usually a few minutes after generating it). Try again shortly.');
    }
    if (code == 'receiver_not_bm') {
      throw PortalSyncException(msg ?? 'The portal sends student details to DSM, not Bursary Manager.');
    }
    if (r.statusCode == 401) {
      throw PortalSyncException(code == 'token_mismatch'
          ? 'The portal did not accept this BM sync token. Check it was pasted correctly, or generate a new one in DSM and wait for DSM\'s next backup.'
          : 'The portal did not accept the school code or token. Check the DSM school code.');
    }
    if (r.statusCode == 429) {
      throw const PortalSyncException('Too many failed attempts from this network. Wait 15 minutes and try again.');
    }
    throw PortalSyncException(msg ?? 'The portal answered with an error (HTTP ${r.statusCode}).');
  }

  static Future<http.Response> _send(Future<http.Response> Function() call) async {
    try {
      return await call().timeout(_timeout);
    } catch (e) {
      throw PortalSyncException('Could not reach the online portal. Check this device\'s internet connection. ($e)');
    }
  }

  /// Connection test + counts: {schoolName, pending, review, ...}.
  static Future<Map<String, dynamic>> status() async {
    final h = await _headers();
    final base = await baseUrl();
    return _decode(await _send(() => http.get(Uri.parse('$base/status.php'), headers: h)));
  }

  /// Every student-details entry still waiting for BM, oldest first.
  static Future<List<PortalTeacherEntry>> fetchPending() async {
    final h = await _headers();
    final base = await baseUrl();
    final out = <PortalTeacherEntry>[];
    var after = 0;
    for (var page = 0; page < 200; page++) {
      final body = _decode(await _send(() => http.get(Uri.parse('$base/pending.php?after=$after&limit=500'), headers: h)));
      final list = (body['entries'] as List? ?? const []).whereType<Map<String, dynamic>>();
      out.addAll(list.map(PortalTeacherEntry.fromJson));
      after = (body['lastId'] as num?)?.toInt() ?? after;
      if (body['more'] != true) break;
    }
    return out;
  }

  /// Reports what was done with entries: [{id, action: applied|rejected|review, reason?}].
  static Future<List<int>> ack(List<Map<String, dynamic>> actions, {required String by}) async {
    if (actions.isEmpty) return const [];
    final h = await _headers();
    final base = await baseUrl();
    final skipped = <int>[];
    for (var i = 0; i < actions.length; i += 1000) {
      final chunk = actions.sublist(i, min(i + 1000, actions.length));
      final body = _decode(await _send(() => http.post(
            Uri.parse('$base/ack.php'),
            headers: {...h, 'Content-Type': 'application/json'},
            body: jsonEncode({'by': by, 'actions': chunk}),
          )));
      skipped.addAll((body['skipped'] as List? ?? const []).map((e) => (e as num).toInt()));
    }
    return skipped;
  }
}

class PortalSyncException implements Exception {
  final String message;
  const PortalSyncException(this.message);
  @override
  String toString() => message;
}

/// A value: a yes/no in [number], anything else in [text].
class PortalValue {
  final double? number;
  final String? text;
  const PortalValue({this.number, this.text});

  factory PortalValue.fromJson(Map<String, dynamic>? j) => PortalValue(
        number: (j?['num'] as num?)?.toDouble(),
        text: j?['text'] as String?,
      );

  Map<String, dynamic> toJson() => {'num': number, 'text': text, 'pm': null};

  bool sameAs(PortalValue? o) {
    if (o == null) return false;
    final a = number, b = o.number;
    final numSame = (a == null && b == null) || (a != null && b != null && (a - b).abs() < 0.0001);
    return numSame && (text ?? '').trim() == (o.text ?? '').trim();
  }
}

/// One entry from api/teacher_sync/pending.php (always kind 'student' here).
class PortalTeacherEntry {
  final int id;
  final String kind;
  final int classId;
  final int armId;
  final int studentId;
  final int? itemId;
  final String entryKey;
  final PortalValue value;
  final bool baseSet;
  final PortalValue base;
  final int userId;
  final String username;
  final String teacherName;
  final String status; // pending | review
  final DateTime? createdAt;

  PortalTeacherEntry({
    required this.id,
    required this.kind,
    required this.classId,
    required this.armId,
    required this.studentId,
    this.itemId,
    required this.entryKey,
    required this.value,
    required this.baseSet,
    required this.base,
    required this.userId,
    required this.username,
    required this.teacherName,
    required this.status,
    this.createdAt,
  });

  String get sender => teacherName.isNotEmpty ? teacherName : username;

  factory PortalTeacherEntry.fromJson(Map<String, dynamic> j) => PortalTeacherEntry(
        id: (j['id'] as num).toInt(),
        kind: j['kind'] as String,
        classId: (j['classId'] as num).toInt(),
        armId: (j['armId'] as num).toInt(),
        studentId: (j['studentId'] as num).toInt(),
        itemId: (j['itemId'] as num?)?.toInt(),
        entryKey: j['entryKey'] as String,
        value: PortalValue.fromJson(j['value'] as Map<String, dynamic>?),
        baseSet: (j['base'] as Map?)?['set'] == true,
        base: PortalValue.fromJson(j['base'] as Map<String, dynamic>?),
        userId: (j['userId'] as num).toInt(),
        username: j['username'] as String? ?? '',
        teacherName: j['teacherName'] as String? ?? '',
        status: j['status'] as String? ?? 'pending',
        createdAt: DateTime.tryParse((j['createdAt'] as String? ?? '').replaceFirst(' ', 'T'))?.toLocal(),
      );
}
