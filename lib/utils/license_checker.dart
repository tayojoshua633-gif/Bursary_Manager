// lib/utils/license_checker.dart

import 'package:flutter/material.dart';
import '../screens/license/license_activation_screen.dart';
import '../screens/auth/welcome_screen.dart';
import 'license_helper.dart';

class LicenseChecker {
  /// Main method called at app startup to check license validity
  static Future<bool> checkLicenseOnStartup(BuildContext context) async {
    try {
      // Check the current license status
      final status = await LicenseHelper.checkLicenseStatus();
      
      // If license is valid, allow app to proceed
      if (status['valid'] == true) {
        return true;
      }
      
      // License is not valid - navigate to activation screen
      if (!context.mounted) return false;
      
      await Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => const LicenseActivationScreen(),
        ),
      );
      
      return false;
    } catch (e) {
      // On error, navigate to activation screen to be safe
      if (!context.mounted) return false;
      
      await Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => const LicenseActivationScreen(),
        ),
      );
      
      return false;
    }
  }

  /// Navigate to app after successful activation
  static Future<void> navigateToApp(BuildContext context) async {
    if (!context.mounted) return;
    
    // Navigate to welcome/login screen
    await Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const WelcomeScreen()),
      (route) => false,
    );
  }

  /// Check license without navigation (for periodic checks)
  static Future<bool> checkLicense(BuildContext context) async {
    final status = await LicenseHelper.checkLicenseStatus();
    
    if (status['valid'] == true) {
      return true;
    }
    
    // Show dialog about license issue
    if (!context.mounted) return false;
    
    final shouldNavigate = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.warning, color: Colors.orange),
            SizedBox(width: 8),
            Text('License Issue'),
          ],
        ),
        content: Text(
          status['message'] ?? 'Your license is invalid or has expired.',
        ),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Activate License'),
          ),
        ],
      ),
    );
    
    if (shouldNavigate == true && context.mounted) {
      await Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => const LicenseActivationScreen(),
        ),
      );
    }
    
    return false;
  }

  /// Get license status information for display
  static Future<Map<String, dynamic>> getLicenseStatus() async {
    return await LicenseHelper.checkLicenseStatus();
  }

  /// Check if trial can be started
  static Future<bool> canStartTrial() async {
    final status = await LicenseHelper.checkLicenseStatus();
    return status['canStartTrial'] == true;
  }

  /// Get days remaining (for warnings)
  static Future<int?> getDaysRemaining() async {
    final status = await LicenseHelper.checkLicenseStatus();
    return status['daysRemaining'] as int?;
  }

  /// Show license expiry warning if needed
  static Future<void> showExpiryWarningIfNeeded(BuildContext context) async {
    final status = await LicenseHelper.checkLicenseStatus();
    
    if (status['valid'] != true) return;
    
    final daysRemaining = status['daysRemaining'] as int?;
    final isTrial = status['isTrial'] == true;
    
    // Show warning if less than 7 days remaining
    if (daysRemaining != null && daysRemaining <= 7 && daysRemaining > 0) {
      if (!context.mounted) return;
      
      final licenseType = isTrial ? 'trial' : 'license';
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Your $licenseType expires in $daysRemaining days',
          ),
          backgroundColor: Colors.orange,
          duration: const Duration(seconds: 5),
          action: SnackBarAction(
            label: 'View',
            textColor: Colors.white,
            onPressed: () {
              // Navigate to license management screen if needed
            },
          ),
        ),
      );
    }
  }
}