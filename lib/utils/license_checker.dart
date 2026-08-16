// lib/utils/license_checker.dart
import 'package:flutter/material.dart';
import '../db/database_helper.dart';
import 'license_helper.dart';

class LicenseChecker {
  static final DatabaseHelper _db = DatabaseHelper();

  /// Tolerance for benign clock drift (timezone changes, NTP correction, DST)
  /// before a backward jump is treated as deliberate tampering.
  static const Duration _clockRollbackTolerance = Duration(hours: 6);

  /// Check if app has valid license
  static Future<LicenseStatus> checkLicense() async {
    try {
      final license = await _db.getActiveLicense();

      if (license == null) {
        return LicenseStatus(
          isValid: false,
          message: 'No active license found',
          requiresActivation: true,
        );
      }

      final licenseId = license['id'] as int;
      final now = DateTime.now();
      final lastKnownDateRaw = license['lastKnownDate'] as String?;
      final lastKnownDate =
          lastKnownDateRaw != null ? DateTime.parse(lastKnownDateRaw) : null;

      // Detect the system clock being wound backward to dodge expiry.
      if (lastKnownDate != null &&
          now.isBefore(lastKnownDate.subtract(_clockRollbackTolerance))) {
        return LicenseStatus(
          isValid: false,
          message:
              'System date/time appears to have been changed backward. '
              'Please correct your device clock to continue.',
          isClockTampered: true,
        );
      }

      // Use the highest date ever observed so expiry can't be dodged by
      // rolling the clock back; only advances forward, never backward.
      final effectiveNow =
          (lastKnownDate != null && lastKnownDate.isAfter(now))
              ? lastKnownDate
              : now;

      if (lastKnownDate == null || now.isAfter(lastKnownDate)) {
        await _db.updateLicenseLastKnownDate(licenseId, now);
      }

      // Check if expired
      final expiryDate = DateTime.parse(license['expiryDate'] as String);
      if (effectiveNow.isAfter(expiryDate)) {
        return LicenseStatus(
          isValid: false,
          message: 'License expired on ${_formatDate(expiryDate)}',
          isExpired: true,
          expiryDate: expiryDate,
        );
      }

      // Check device binding
      final currentDeviceId = await LicenseHelper.getDeviceId();
      final storedDeviceId = license['deviceId'] as String?;

      if (storedDeviceId != null &&
          storedDeviceId.isNotEmpty &&
          storedDeviceId != currentDeviceId) {
        return LicenseStatus(
          isValid: false,
          message: 'License is bound to a different device',
          isDeviceMismatch: true,
        );
      }

      // Check if approaching expiry (30 days)
      final daysRemaining = LicenseHelper.getDaysUntilExpiry(
        expiryDate,
        referenceDate: effectiveNow,
      );
      final isApproaching = LicenseHelper.isExpiryApproaching(
        expiryDate,
        referenceDate: effectiveNow,
      );

      return LicenseStatus(
        isValid: true,
        message: 'License is active',
        expiryDate: expiryDate,
        daysRemaining: daysRemaining,
        isExpiryApproaching: isApproaching,
        schoolName: license['schoolName'] as String?,
        maxStudents: license['maxStudents'] as int?,
      );
    } catch (e) {
      return LicenseStatus(
        isValid: false,
        message: 'Error checking license: $e',
        hasError: true,
      );
    }
  }

  /// Show license warning dialog if expiry is approaching
  static Future<void> showExpiryWarningIfNeeded(BuildContext context) async {
    final status = await checkLicense();

    if (!context.mounted) return;

    if (status.isExpiryApproaching && status.daysRemaining != null) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          icon: const Icon(Icons.warning, color: Colors.orange, size: 48),
          title: const Text('License Expiring Soon'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Your license will expire in ${status.daysRemaining} days',
                style: const TextStyle(fontSize: 16),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              if (status.expiryDate != null)
                Text(
                  'Expiry Date: ${_formatDate(status.expiryDate!)}',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              const SizedBox(height: 16),
              const Text(
                'Please contact support to renew your license before it expires.',
                style: TextStyle(fontSize: 14),
                textAlign: TextAlign.center,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('OK'),
            ),
          ],
        ),
      );
    }
  }

  /// Format date for display
  static String _formatDate(DateTime date) {
    return '${date.day}/${date.month}/${date.year}';
  }
}

/// License status result
class LicenseStatus {
  final bool isValid;
  final String message;
  final bool requiresActivation;
  final bool isExpired;
  final bool isDeviceMismatch;
  final bool hasError;
  final bool isExpiryApproaching;
  final bool isClockTampered;
  final DateTime? expiryDate;
  final int? daysRemaining;
  final String? schoolName;
  final int? maxStudents;

  LicenseStatus({
    required this.isValid,
    required this.message,
    this.requiresActivation = false,
    this.isExpired = false,
    this.isDeviceMismatch = false,
    this.hasError = false,
    this.isExpiryApproaching = false,
    this.isClockTampered = false,
    this.expiryDate,
    this.daysRemaining,
    this.schoolName,
    this.maxStudents,
  });
}
