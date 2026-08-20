// lib/utils/sync_key_client.dart
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../db/database_helper.dart';
import 'central_backup_helper.dart';

/// Write-mode side of the sync-key mechanism: generates/revokes the key a
/// Read-Only device uses to pull this school's data from the central backup
/// server. The server never returns a raw key twice, so a successful
/// generate is cached locally — needed since the same key may have to be
/// handed to more than one device over time, and "show me my key again"
/// would otherwise force a destructive regenerate every time.
class SyncKeyClient {
  static const String _baseUrl = CentralBackupHelper.apiBaseUrl;
  static const String _apiSecret = CentralBackupHelper.apiSecret;
  static const String _product = 'BM';

  static const String _cachedKeyPref = 'own_sync_key';
  static const String _cachedPrefixPref = 'own_sync_key_prefix';

  /// The locally cached copy of this device's own key, if one has been
  /// generated on this device before. Null if never generated, or if it was
  /// generated on a different device/reinstalled since.
  static Future<String?> getCachedKey() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_cachedKeyPref);
  }

  static Future<String?> getCachedKeyPrefix() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_cachedPrefixPref);
  }

  /// Generates a new key (or regenerates, silently invalidating any
  /// previous one — the server enforces at most one active key per school).
  static Future<Map<String, dynamic>> generate() async {
    try {
      final license = await DatabaseHelper().getActiveLicense();
      final licenseKey = license?['licenseKey'] as String?;
      final schoolCode = (license?['schoolCode'] as String?) ?? '';
      if (licenseKey == null || licenseKey.isEmpty) {
        return {'success': false, 'message': 'No active license found.'};
      }

      final resp = await http.post(
        Uri.parse('$_baseUrl/sync_key_generate.php'),
        headers: {'X-Api-Secret': _apiSecret},
        body: {
          'product': _product,
          'license_key': licenseKey,
          'school_code': schoolCode,
        },
      ).timeout(const Duration(seconds: 20));

      final decoded = _decodeOrNull(resp.body);
      if (resp.statusCode != 200 || decoded == null || decoded['ok'] != true) {
        return {
          'success': false,
          'message': (decoded != null ? decoded['error'] as String? : null) ??
              'Could not generate a key. Check your internet connection.',
        };
      }

      final rawKey = decoded['sync_key'] as String;
      final prefix = decoded['key_prefix'] as String?;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_cachedKeyPref, rawKey);
      if (prefix != null) await prefs.setString(_cachedPrefixPref, prefix);

      return {'success': true, 'sync_key': rawKey};
    } catch (e) {
      return {'success': false, 'message': 'Failed to generate key: $e'};
    }
  }

  /// Revokes the active key, if any. Idempotent.
  static Future<Map<String, dynamic>> revoke() async {
    try {
      final license = await DatabaseHelper().getActiveLicense();
      final licenseKey = license?['licenseKey'] as String?;
      final schoolCode = (license?['schoolCode'] as String?) ?? '';
      if (licenseKey == null || licenseKey.isEmpty) {
        return {'success': false, 'message': 'No active license found.'};
      }

      final resp = await http.post(
        Uri.parse('$_baseUrl/sync_key_revoke.php'),
        headers: {'X-Api-Secret': _apiSecret},
        body: {
          'product': _product,
          'license_key': licenseKey,
          'school_code': schoolCode,
        },
      ).timeout(const Duration(seconds: 20));

      final decoded = _decodeOrNull(resp.body);
      if (resp.statusCode != 200 || decoded == null || decoded['ok'] != true) {
        return {
          'success': false,
          'message': (decoded != null ? decoded['error'] as String? : null) ??
              'Could not revoke the key. Check your internet connection.',
        };
      }

      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_cachedKeyPref);
      await prefs.remove(_cachedPrefixPref);

      return {'success': true};
    } catch (e) {
      return {'success': false, 'message': 'Failed to revoke key: $e'};
    }
  }

  static Map<String, dynamic>? _decodeOrNull(String body) {
    try {
      return jsonDecode(body) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }
}
