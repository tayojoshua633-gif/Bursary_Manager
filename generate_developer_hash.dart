// generate_developer_hash.dart
// Utility script to generate hash for developer secret code
// Run this script with: dart run generate_developer_hash.dart

import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';

String hashString(String input) {
  final bytes = utf8.encode(input);
  final hash = sha256.convert(bytes);
  return hash.toString();
}

void main() {
  // Current default secret code
  const defaultCode = 'DEV2024BURSARYMANAGER@MASTER';

  stdout.writeln('═══════════════════════════════════════════════════════════');
  stdout.writeln('  Developer Secret Code Hash Generator');
  stdout.writeln('═══════════════════════════════════════════════════════════\n');

  stdout.writeln('📌 Current Default Secret Code: "$defaultCode"');
  stdout.writeln('🔐 Current Hash: ${hashString(defaultCode)}\n');

  stdout.writeln('───────────────────────────────────────────────────────────\n');

  // Interactive mode
  stdout.write('Enter your custom secret code (or press Enter to use default): ');
  final input = stdin.readLineSync()?.trim() ?? '';

  if (input.isEmpty) {
    stdout.writeln('\n✅ Using default secret code.');
    stdout.writeln('Copy this hash to lib/utils/developer_auth_helper.dart:\n');
    stdout.writeln('static const String _secretCodeHash = \'${hashString(defaultCode)}\';');
  } else {
    final customHash = hashString(input);
    stdout.writeln('\n✅ Custom Secret Code: "$input"');
    stdout.writeln('🔐 Generated Hash:\n');
    stdout.writeln(customHash);
    stdout.writeln('\n📋 Copy this line to lib/utils/developer_auth_helper.dart:\n');
    stdout.writeln('static const String _secretCodeHash = \'$customHash\';');
  }

  stdout.writeln('\n═══════════════════════════════════════════════════════════');
  stdout.writeln('⚠️  SECURITY NOTES:');
  stdout.writeln('• Keep your secret code confidential');
  stdout.writeln('• Use a strong, unique code');
  stdout.writeln('• Update the hash in developer_auth_helper.dart');
  stdout.writeln('• Never commit the actual secret code to version control');
  stdout.writeln('═══════════════════════════════════════════════════════════\n');
}
