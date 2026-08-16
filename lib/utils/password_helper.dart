// lib/utils/password_helper.dart
// Password hashing and verification using bcrypt

import 'package:bcrypt/bcrypt.dart';

class PasswordHelper {
  /// Hash a plain text password using bcrypt
  /// Returns the hashed password string
  static String hashPassword(String plainPassword) {
    // Generate salt and hash password
    // Cost factor: 12 (good balance between security and performance)
    return BCrypt.hashpw(plainPassword, BCrypt.gensalt());
  }

  /// Verify a plain text password against a hashed password
  /// Returns true if password matches, false otherwise
  static bool verifyPassword(String plainPassword, String hashedPassword) {
    try {
      return BCrypt.checkpw(plainPassword, hashedPassword);
    } catch (e) {
      // If hashed password is invalid format, return false
      return false;
    }
  }

  /// Check if a password is already hashed (bcrypt format)
  /// Bcrypt hashes start with $2a$, $2b$, or $2y$
  static bool isPasswordHashed(String password) {
    return password.startsWith(r'$2a$') ||
           password.startsWith(r'$2b$') ||
           password.startsWith(r'$2y$');
  }

  /// Migrate plain text password to hashed password
  /// If already hashed, returns as-is
  /// If plain text, hashes and returns hashed password
  static String ensurePasswordHashed(String password) {
    if (isPasswordHashed(password)) {
      return password;
    }
    return hashPassword(password);
  }
}
