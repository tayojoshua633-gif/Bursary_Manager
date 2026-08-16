// test_license.dart
// Quick test to debug license generation and validation

import 'dart:convert';
import 'package:crypto/crypto.dart';

void main() {
  print('Testing License Generation and Validation\n');

  // Generate a license
  final schoolName = 'DAWOT KIDS AND COLLEGE';
  final schoolCode = 'DAWOT001';
  final expiryDate = DateTime(2026, 12, 31);
  final maxStudents = 500;

  print('=== GENERATING LICENSE ===');
  final licenseKey = generateLicenseKey(
    schoolName: schoolName,
    schoolCode: schoolCode,
    expiryDate: expiryDate,
    maxStudents: maxStudents,
  );

  print('Generated Key: $licenseKey');
  print('Key Length: ${licenseKey.length}');
  print('');

  // Now validate it
  print('=== VALIDATING LICENSE ===');
  final result = validateLicenseKey(licenseKey);

  if (result == null) {
    print('❌ VALIDATION FAILED - Key is invalid');

    // Debug: Show what we're working with
    final cleanKey = licenseKey.replaceAll(RegExp(r'[-\s]'), '').toLowerCase();
    print('\nDebug Info:');
    print('Clean Key: $cleanKey');
    print('Clean Key Length: ${cleanKey.length}');

    if (cleanKey.length >= 10) {
      final checksum = cleanKey.substring(cleanKey.length - 8);
      final encoded = cleanKey.substring(0, cleanKey.length - 8);
      final expectedChecksum = _generateChecksum(encoded).toLowerCase();

      print('Extracted Checksum: $checksum');
      print('Expected Checksum:  $expectedChecksum');
      print('Match: ${checksum == expectedChecksum}');

      // Try to decode
      try {
        final jsonData = utf8.decode(base64Url.decode(encoded));
        print('Decoded JSON: $jsonData');
      } catch (e) {
        print('Decode Error: $e');
      }
    }
  } else {
    print('✅ VALIDATION SUCCESSFUL');
    print('School: ${result['school']}');
    print('Code: ${result['code']}');
    print('Expiry: ${result['expiry']}');
    print('Max Students: ${result['maxStudents']}');
    print('Is Expired: ${result['isExpired']}');
  }
}

String generateLicenseKey({
  required String schoolName,
  required String schoolCode,
  required DateTime expiryDate,
  int? maxStudents,
}) {
  final licenseData = {
    'school': schoolName,
    'code': schoolCode,
    'expiry': expiryDate.toIso8601String(),
    'maxStudents': maxStudents ?? 0,
    'timestamp': DateTime.now().millisecondsSinceEpoch,
  };

  final jsonData = jsonEncode(licenseData);
  final encoded = base64Url.encode(utf8.encode(jsonData));
  final checksum = _generateChecksum(encoded);
  return '$encoded-$checksum';
}

Map<String, dynamic>? validateLicenseKey(String licenseKey) {
  try {
    final cleanKey = licenseKey.trim().replaceAll(' ', '');

    final lastDashIndex = cleanKey.lastIndexOf('-');
    if (lastDashIndex == -1) return null;

    final encoded = cleanKey.substring(0, lastDashIndex);
    final checksum = cleanKey.substring(lastDashIndex + 1);

    if (_generateChecksum(encoded).toLowerCase() != checksum.toLowerCase()) {
      return null;
    }

    final jsonData = utf8.decode(base64Url.decode(encoded));
    final licenseData = jsonDecode(jsonData) as Map<String, dynamic>;

    final expiryDate = DateTime.parse(licenseData['expiry'] as String);
    licenseData['isExpired'] = DateTime.now().isAfter(expiryDate);
    licenseData['daysRemaining'] = expiryDate.difference(DateTime.now()).inDays;

    return licenseData;
  } catch (e) {
    print('Validation Exception: $e');
    return null;
  }
}

String _generateChecksum(String data) {
  const String secretKey = 'BURSARY_MANAGER_2024_SECRET_KEY_XYZ123';
  final combined = '$data$secretKey';
  final bytes = utf8.encode(combined);
  final hash = sha256.convert(bytes);
  return hash.toString().substring(0, 8);
}

