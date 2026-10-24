import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'app_version.dart';

/// Details of the latest Bursary Manager release published on the website.
class UpdateInfo {
  final String latestVersion;
  final String downloadUrl;
  final String? size;
  final String? updated;

  const UpdateInfo({
    required this.latestVersion,
    required this.downloadUrl,
    this.size,
    this.updated,
  });

  /// True when the website has a newer version than the one running.
  bool get isUpdateAvailable =>
      UpdateChecker.compareVersions(latestVersion, kAppVersion) > 0;

  Map<String, dynamic> toJson() => {
        'latestVersion': latestVersion,
        'downloadUrl': downloadUrl,
        'size': size,
        'updated': updated,
      };

  factory UpdateInfo.fromJson(Map<String, dynamic> json) => UpdateInfo(
        latestVersion: json['latestVersion'] as String,
        downloadUrl: json['downloadUrl'] as String,
        size: json['size'] as String?,
        updated: json['updated'] as String?,
      );
}

/// Checks the website for a newer Bursary Manager release.
///
/// The site's `downloads/info.php` reports whichever release file currently sits
/// in the BM downloads folder (version parsed from `BM_X.Y.Z.apk`),
/// so shipping a release is just uploading the new file there.
class UpdateChecker {
  static const String _siteBase = 'https://tysolutions.com.ng/apps/';
  static const String _infoUrl =
      '${_siteBase}downloads/info.php?dir=bursary-manager';
  static const String productPageUrl =
      '${_siteBase}bursary-manager.html';

  static const String _cacheKey = 'update_check_cache';
  static const String _cacheTimeKey = 'update_check_time';
  static const String _dismissedKey = 'update_dismissed_version';
  static const Duration _cacheDuration = Duration(hours: 6);

  /// Latest known result, so the dashboard tile can react to a check that
  /// finishes after it was built.
  static final ValueNotifier<UpdateInfo?> latest = ValueNotifier(null);

  /// Fetches the latest release info. Uses a cached result younger than
  /// [_cacheDuration] unless [force] is set. Returns null when offline or the
  /// site doesn't respond — callers should treat that as "nothing to show".
  static Future<UpdateInfo?> check({bool force = false}) async {
    final prefs = await SharedPreferences.getInstance();

    if (!force) {
      final cachedAt = prefs.getInt(_cacheTimeKey);
      final cached = prefs.getString(_cacheKey);
      if (cachedAt != null && cached != null) {
        final age = DateTime.now().difference(
          DateTime.fromMillisecondsSinceEpoch(cachedAt),
        );
        if (age < _cacheDuration) {
          try {
            final info = UpdateInfo.fromJson(
              jsonDecode(cached) as Map<String, dynamic>,
            );
            latest.value = info;
            return info;
          } catch (_) {
            // Corrupt cache — fall through and fetch fresh.
          }
        }
      }
    }

    try {
      final response = await http
          .get(Uri.parse(_infoUrl))
          .timeout(const Duration(seconds: 10));
      if (response.statusCode != 200) return latest.value;

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final version = data['version'] as String?;
      final relativeUrl = data['url'] as String?;
      if (data['found'] != true || version == null || relativeUrl == null) {
        return latest.value;
      }

      final info = UpdateInfo(
        latestVersion: version,
        downloadUrl: Uri.parse(_siteBase).resolve(relativeUrl).toString(),
        size: data['size'] as String?,
        updated: data['updated'] as String?,
      );
      await prefs.setString(_cacheKey, jsonEncode(info.toJson()));
      await prefs.setInt(
        _cacheTimeKey,
        DateTime.now().millisecondsSinceEpoch,
      );
      latest.value = info;
      return info;
    } catch (e) {
      debugPrint('[UpdateChecker] Check failed: $e');
      return latest.value;
    }
  }

  /// Whether the login prompt should be shown for [info] — i.e. there's an
  /// update and the user hasn't already tapped "Later" for this version.
  static Future<bool> shouldPrompt(UpdateInfo info) async {
    if (!info.isUpdateAvailable) return false;
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_dismissedKey) != info.latestVersion;
  }

  /// Silences the login prompt until a version newer than [version] appears.
  static Future<void> dismiss(String version) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_dismissedKey, version);
  }

  /// Compares dotted version strings numerically ("24.10.0" > "24.9.9").
  /// Returns >0 if [a] is newer, <0 if older, 0 if equal.
  static int compareVersions(String a, String b) {
    List<int> parts(String v) => v
        .split(RegExp(r'[^0-9]+'))
        .where((p) => p.isNotEmpty)
        .map(int.parse)
        .toList();
    final pa = parts(a);
    final pb = parts(b);
    final len = pa.length > pb.length ? pa.length : pb.length;
    for (var i = 0; i < len; i++) {
      final x = i < pa.length ? pa[i] : 0;
      final y = i < pb.length ? pb[i] : 0;
      if (x != y) return x - y;
    }
    return 0;
  }
}
