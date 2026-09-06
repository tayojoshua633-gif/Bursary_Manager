// lib/utils/license_helper.dart
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:ed25519_edwards/ed25519_edwards.dart' as ed;
import 'dart:io';

class LicenseHelper {
  // Public half of the license_manager private key that signs whole-app
  // BM/DSM licenses (same key used for bursary_manager_desktop's CBT add-on
  // codes) — can verify a signature but cannot be used to produce one.
  static const String _licenseSigningPublicKeyBase64 =
      '2p+t4hZgtXCqFwj85HKpIGbgeOVvU4g6WKo10pnViWk=';

  /// Validate a license key
  static Map<String, dynamic>? validateLicenseKey(String licenseKey) {
    try {
      // Remove spaces
      final cleanKey = licenseKey.trim().replaceAll(' ', '');

      // Ed25519-signed license is the only format accepted (see
      // signed_license_engine.dart on the license_manager side). The old
      // shared-secret checksum format and the hardcoded master license key
      // were retired: both values were public (committed in this repo's
      // history), which let anyone forge a valid license without ever
      // touching license_manager's private key.
      final signedPayload = _verifySignedLicense(cleanKey);
      if (signedPayload == null) return null;

      final expiryDate = DateTime.parse(signedPayload['expiry'] as String);
      signedPayload['isExpired'] = DateTime.now().isAfter(expiryDate);
      signedPayload['daysRemaining'] = expiryDate.difference(DateTime.now()).inDays;
      return signedPayload;
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

  /// Returns the decoded payload iff [cleanKey] carries a genuine Ed25519
  /// signature from the license_manager private key; null on any
  /// tamper/format/wrong-prefix/garbage input.
  static Map<String, dynamic>? _verifySignedLicense(String cleanKey) {
    try {
      final parts = cleanKey.split('.');
      if (parts.length != 3 || parts[0] != 'LIC1') return null;

      final publicKey = ed.PublicKey(base64Decode(_licenseSigningPublicKeyBase64));
      final message = utf8.encode(parts[1]);
      final signature = base64Url.decode(parts[2]);

      if (!ed.verify(publicKey, message, signature)) return null;

      final payloadJson = utf8.decode(base64Url.decode(parts[1]));
      return jsonDecode(payloadJson) as Map<String, dynamic>;
    } catch (_) {
      return null; // Invalid/tampered/malformed key
    }
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
