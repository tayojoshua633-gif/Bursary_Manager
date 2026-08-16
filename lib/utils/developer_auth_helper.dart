// lib/utils/developer_auth_helper.dart
import 'dart:convert';
import 'package:crypto/crypto.dart';

class DeveloperAuthHelper {
  // Hash of the secret code: "DEV2024BURSARYMANAGER@MASTER"
  // You can change this by running: dart run generate_developer_hash.dart
  static const String _secretCodeHash =
      '605b960096cf259fbfddeb11eb2d3ee0cc658772d70513bef5495b3a612add09';

  /// Verify if the provided secret code is correct
  static bool verifySecretCode(String code) {
    final hash = _hashString(code);
    return hash == _secretCodeHash;
  }

  /// Hash a string using SHA-256
  static String _hashString(String input) {
    final bytes = utf8.encode(input);
    final hash = sha256.convert(bytes);
    return hash.toString();
  }

  /// Generate hash for a new secret code (for admin use)
  /// Call this to create a hash for your desired secret code
  static String generateHash(String secretCode) {
    return _hashString(secretCode);
  }
}
