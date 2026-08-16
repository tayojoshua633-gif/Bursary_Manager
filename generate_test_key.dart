// generate_test_key.dart
// Quick license key generator
// Usage: dart run generate_test_key.dart

import 'dart:convert';
import 'package:crypto/crypto.dart';

void main() {
  print('═══════════════════════════════════════════════════════');
  print('     BURSARY MANAGER LICENSE KEY GENERATOR');
  print('═══════════════════════════════════════════════════════\n');

  // EDIT THESE VALUES TO GENERATE YOUR LICENSE KEY
  final schoolName = 'DAWOT KIDS AND COLLEGE';           // Change this
  final schoolCode = 'DAWOTOOO1';                // Change this
  final expiryDate = DateTime(2026, 12, 31);  // Change this (YYYY, MM, DD)
  final maxStudents = 500;                     // Change this (0 = unlimited)

  // Generate license key
  final licenseKey = generateLicenseKey(
    schoolName: schoolName,
    schoolCode: schoolCode,
    expiryDate: expiryDate,
    maxStudents: maxStudents,
  );

  // Display results
  print('School Name:    $schoolName');
  print('School Code:    $schoolCode');
  print('Expiry Date:    ${expiryDate.day}/${expiryDate.month}/${expiryDate.year}');
  print('Max Students:   ${maxStudents > 0 ? maxStudents : "Unlimited"}');
  print('Days Valid:     ${expiryDate.difference(DateTime.now()).inDays} days\n');

  print('LICENSE KEY:');
  print('┌─────────────────────────────────────────────────────┐');
  print('│  $licenseKey  │');
  print('└─────────────────────────────────────────────────────┘\n');

  print('⚠️  Copy this license key to activate the app!\n');
  print('═══════════════════════════════════════════════════════\n');
}

String generateLicenseKey({
  required String schoolName,
  required String schoolCode,
  required DateTime expiryDate,
  int? maxStudents,
}) {
  const String secretKey = 'BURSARY_MANAGER_2024_SECRET_KEY_XYZ123';

  final licenseData = {
    'school': schoolName,
    'code': schoolCode,
    'expiry': expiryDate.toIso8601String(),
    'maxStudents': maxStudents ?? 0,
    'timestamp': DateTime.now().millisecondsSinceEpoch,
  };

  final jsonData = jsonEncode(licenseData);
  final encoded = base64Url.encode(utf8.encode(jsonData));
  final checksum = _generateChecksum(encoded, secretKey);
  final fullKey = '$encoded.$checksum';
  return _formatLicenseKey(fullKey);
}

String _generateChecksum(String data, String secretKey) {
  final combined = '$data$secretKey';
  final bytes = utf8.encode(combined);
  final hash = sha256.convert(bytes);
  return hash.toString().substring(0, 8);
}

String _formatLicenseKey(String key) {
  final parts = key.split('.');
  final dataOnly = parts[0];
  final checksum = parts.length > 1 ? parts[1] : '';

  final formatted = StringBuffer();
  for (var i = 0; i < dataOnly.length; i += 5) {
    if (i > 0) formatted.write('-');
    final end = (i + 5 < dataOnly.length) ? i + 5 : dataOnly.length;
    formatted.write(dataOnly.substring(i, end));
  }

  if (checksum.isNotEmpty) {
    formatted.write('-$checksum');
  }

  return formatted.toString().toUpperCase();
}
