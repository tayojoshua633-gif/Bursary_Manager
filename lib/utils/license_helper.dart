// lib/utils/license_helper.dart
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'dart:io';

class LicenseHelper {
  static const String _secretKey = 'BURSARY_MANAGER_2024_SECRET_KEY_XYZ123';
  static const String _masterLicenseKey = 'DEV2024BURSARYMANAGER@MASTER';

  /// Generate a license key for a school
  /// Format: BASE64DATA-CHECKSUM (no dashes in base64 part)
  ///
  /// If [targetDeviceId] is provided, the license will be bound to that specific device.
  /// If null, the license can be activated on any device (device binding happens during activation).
  static String generateLicenseKey({
    required String schoolName,
    required String schoolCode,
    required DateTime expiryDate,
    int? maxStudents,
    String? targetDeviceId,
  }) {
    // Create license data
    final licenseData = {
      'school': schoolName,
      'code': schoolCode,
      'expiry': expiryDate.toIso8601String(),
      'maxStudents': maxStudents ?? 0,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    };

    // Add device ID if provided (for pre-binding to specific device)
    if (targetDeviceId != null && targetDeviceId.isNotEmpty) {
      licenseData['deviceId'] = targetDeviceId;
    }

    // Convert to JSON and encode (keep case-sensitive base64)
    final jsonData = jsonEncode(licenseData);
    final encoded = base64Url.encode(utf8.encode(jsonData));

    // Generate checksum
    final checksum = _generateChecksum(encoded);

    // Combine: encoded-checksum (keep base64 case-sensitive!)
    return '$encoded-$checksum';
  }

  /// Validate a license key
  static Map<String, dynamic>? validateLicenseKey(String licenseKey) {
    try {
      // Check if this is the master license key, optionally suffixed with
      // "=<days>" and/or ",<maxStudents>" to limit its validity/student cap,
      // e.g. "DEV2024BURSARYMANAGER@MASTER=90" (90-day validity, unlimited students)
      // or  "DEV2024BURSARYMANAGER@MASTER=90,50" (90-day validity, capped at 50 students)
      // or  "DEV2024BURSARYMANAGER@MASTER=,50" (default validity, capped at 50 students)
      final trimmedKey = licenseKey.trim();
      if (trimmedKey == _masterLicenseKey ||
          trimmedKey.startsWith('$_masterLicenseKey=')) {
        var validityDays = 36500; // Default: effectively never expires
        var maxStudents = 999999; // Default: effectively unlimited

        if (trimmedKey.length > _masterLicenseKey.length) {
          final suffix = trimmedKey.substring(_masterLicenseKey.length + 1);
          final parts = suffix.split(',');
          if (parts.length > 2) return null; // Malformed suffix

          if (parts[0].isNotEmpty) {
            final parsedDays = int.tryParse(parts[0]);
            if (parsedDays == null || parsedDays <= 0) return null;
            validityDays = parsedDays;
          }

          if (parts.length == 2 && parts[1].isNotEmpty) {
            final parsedStudents = int.tryParse(parts[1]);
            if (parsedStudents == null || parsedStudents <= 0) return null;
            maxStudents = parsedStudents;
          }
        }

        final expiryDate = DateTime.now().add(Duration(days: validityDays));
        return {
          'school': 'My School',
          'code': 'MYSCHOOL/00001',
          'expiry': expiryDate.toIso8601String(),
          'maxStudents': maxStudents,
          'timestamp': DateTime.now().millisecondsSinceEpoch,
          'isExpired': false,
          'daysRemaining': validityDays,
          'isMasterKey': true, // Flag to identify master key
        };
      }

      // Remove spaces and split by last dash
      final cleanKey = licenseKey.trim().replaceAll(' ', '');

      // Split by the LAST dash only (format: ENCODED-CHECKSUM)
      final lastDashIndex = cleanKey.lastIndexOf('-');
      if (lastDashIndex == -1) return null;

      final encoded = cleanKey.substring(0, lastDashIndex);
      final checksum = cleanKey.substring(lastDashIndex + 1);

      // Verify checksum (case-insensitive comparison)
      if (_generateChecksum(encoded).toLowerCase() != checksum.toLowerCase()) {
        return null; // Tampered key
      }

      // Decode license data (base64 is case-sensitive, so preserve case)
      final jsonData = utf8.decode(base64Url.decode(encoded));
      final licenseData = jsonDecode(jsonData) as Map<String, dynamic>;

      // Check expiry
      final expiryDate = DateTime.parse(licenseData['expiry'] as String);
      licenseData['isExpired'] = DateTime.now().isAfter(expiryDate);
      licenseData['daysRemaining'] = expiryDate.difference(DateTime.now()).inDays;

      return licenseData;
    } catch (e) {
      return null; // Invalid key format
    }
  }

  /// Get unique device identifier
  static Future<String> getDeviceId() async {
    final deviceInfo = DeviceInfoPlugin();

    try {
      if (Platform.isAndroid) {
        final androidInfo = await deviceInfo.androidInfo;
        // Combine multiple identifiers for stronger binding
        return _hashString('${androidInfo.id}_${androidInfo.device}_${androidInfo.model}');
      } else if (Platform.isIOS) {
        final iosInfo = await deviceInfo.iosInfo;
        return _hashString(iosInfo.identifierForVendor ?? 'unknown');
      } else if (Platform.isWindows) {
        final windowsInfo = await deviceInfo.windowsInfo;
        return _hashString(windowsInfo.deviceId);
      } else if (Platform.isMacOS) {
        final macInfo = await deviceInfo.macOsInfo;
        return _hashString(macInfo.systemGUID ?? 'unknown');
      } else if (Platform.isLinux) {
        final linuxInfo = await deviceInfo.linuxInfo;
        return _hashString(linuxInfo.machineId ?? 'unknown');
      }
    } catch (e) {
      // Fallback to a less secure but still unique identifier
      return _hashString('fallback_${Platform.operatingSystem}');
    }

    return 'unknown';
  }

  /// Generate checksum for license key validation
  static String _generateChecksum(String data) {
    final combined = '$data$_secretKey';
    final bytes = utf8.encode(combined);
    final hash = sha256.convert(bytes);
    return hash.toString().substring(0, 8); // Use first 8 chars
  }

  /// Hash a string using SHA-256
  static String _hashString(String input) {
    final bytes = utf8.encode(input);
    final hash = sha256.convert(bytes);
    return hash.toString();
  }


  /// Check if license is valid for current device
  static bool isDeviceAuthorized(String? storedDeviceId, String currentDeviceId) {
    if (storedDeviceId == null || storedDeviceId.isEmpty) {
      return true; // Not yet activated, allow activation
    }
    return storedDeviceId == currentDeviceId;
  }

  /// Calculate days until expiry, relative to [referenceDate] (defaults to now)
  static int getDaysUntilExpiry(DateTime expiryDate, {DateTime? referenceDate}) {
    return expiryDate.difference(referenceDate ?? DateTime.now()).inDays;
  }

  /// Check if expiry is approaching (within 30 days), relative to [referenceDate]
  static bool isExpiryApproaching(DateTime expiryDate, {DateTime? referenceDate}) {
    final daysRemaining = getDaysUntilExpiry(expiryDate, referenceDate: referenceDate);
    return daysRemaining > 0 && daysRemaining <= 30;
  }

  /// Format license key for user-friendly display
  static String formatLicenseKeyDisplay(String licenseKey) {
    final cleaned = licenseKey.replaceAll(RegExp(r'[-\s]'), '');
    final formatted = StringBuffer();

    for (var i = 0; i < cleaned.length; i += 5) {
      if (i > 0) formatted.write('-');
      final end = (i + 5 < cleaned.length) ? i + 5 : cleaned.length;
      formatted.write(cleaned.substring(i, end));
    }

    return formatted.toString().toUpperCase();
  }
}
