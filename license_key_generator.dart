// license_key_generator.dart
// Run this file to generate license keys for schools
// Usage: dart run license_key_generator.dart

import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';

void main() {
  print('═══════════════════════════════════════════════════════');
  print('     BURSARY MANAGER LICENSE KEY GENERATOR');
  print('═══════════════════════════════════════════════════════\n');

  // Get school details
  stdout.write('Enter School Name: ');
  final schoolName = stdin.readLineSync() ?? '';

  stdout.write('Enter School Code (e.g., SMS001): ');
  final schoolCode = stdin.readLineSync() ?? '';

  stdout.write('Enter Expiry Date (YYYY-MM-DD, e.g., 2026-12-31): ');
  final expiryDateStr = stdin.readLineSync() ?? '';

  stdout.write('Enter Max Students (or press Enter for unlimited): ');
  final maxStudentsStr = stdin.readLineSync() ?? '';
  final maxStudents = maxStudentsStr.isEmpty ? 0 : int.tryParse(maxStudentsStr) ?? 0;

  // Validate inputs
  if (schoolName.isEmpty || schoolCode.isEmpty) {
    print('\n❌ Error: School name and code are required!');
    exit(1);
  }

  DateTime expiryDate;
  try {
    expiryDate = DateTime.parse(expiryDateStr);
  } catch (e) {
    print('\n❌ Error: Invalid date format! Use YYYY-MM-DD');
    exit(1);
  }

  // Generate license key
  final licenseKey = generateLicenseKey(
    schoolName: schoolName,
    schoolCode: schoolCode,
    expiryDate: expiryDate,
    maxStudents: maxStudents,
  );

  // Display results
  print('\n═══════════════════════════════════════════════════════');
  print('     LICENSE KEY GENERATED SUCCESSFULLY!');
  print('═══════════════════════════════════════════════════════\n');

  print('School Name:    $schoolName');
  print('School Code:    $schoolCode');
  print('Expiry Date:    ${expiryDate.day}/${expiryDate.month}/${expiryDate.year}');
  print('Max Students:   ${maxStudents > 0 ? maxStudents : "Unlimited"}');
  print('Days Valid:     ${expiryDate.difference(DateTime.now()).inDays} days\n');

  print('LICENSE KEY:');
  print('┌─────────────────────────────────────────────────────┐');
  print('│  $licenseKey  │');
  print('└─────────────────────────────────────────────────────┘\n');

  print('⚠️  IMPORTANT:');
  print('   • Keep this license key secure');
  print('   • Each key can only be activated once per device');
  print('   • The key will expire on $expiryDateStr');
  print('\n═══════════════════════════════════════════════════════\n');

  // Save to file
  stdout.write('Save to file? (y/n): ');
  final save = stdin.readLineSync()?.toLowerCase() ?? 'n';

  if (save == 'y' || save == 'yes') {
    final fileName = 'license_${schoolCode}_${DateTime.now().millisecondsSinceEpoch}.txt';
    final file = File(fileName);

    file.writeAsStringSync('''
═══════════════════════════════════════════════════════
BURSARY MANAGER LICENSE KEY
═══════════════════════════════════════════════════════

School Name:    $schoolName
School Code:    $schoolCode
Expiry Date:    ${expiryDate.day}/${expiryDate.month}/${expiryDate.year}
Max Students:   ${maxStudents > 0 ? maxStudents : "Unlimited"}
Generated On:   ${DateTime.now()}

LICENSE KEY:
$licenseKey

═══════════════════════════════════════════════════════
IMPORTANT INFORMATION:
• This key can only be activated once per device
• Keep this key secure and confidential
• The license will expire on $expiryDateStr
• Contact support if you need to transfer to a new device
═══════════════════════════════════════════════════════
''');

    print('✅ License saved to: $fileName\n');
  }
}

// License key generation function (same as in your app)
String generateLicenseKey({
  required String schoolName,
  required String schoolCode,
  required DateTime expiryDate,
  int? maxStudents,
}) {
  const String secretKey = 'BURSARY_MANAGER_2024_SECRET_KEY_XYZ123';

  // Create license data
  final licenseData = {
    'school': schoolName,
    'code': schoolCode,
    'expiry': expiryDate.toIso8601String(),
    'maxStudents': maxStudents ?? 0,
    'timestamp': DateTime.now().millisecondsSinceEpoch,
  };

  // Convert to JSON and encode
  final jsonData = jsonEncode(licenseData);
  final encoded = base64Url.encode(utf8.encode(jsonData));

  // Generate checksum
  final checksum = _generateChecksum(encoded, secretKey);

  // Combine and format
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
