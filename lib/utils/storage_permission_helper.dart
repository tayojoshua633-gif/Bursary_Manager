import 'dart:io';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:device_info_plus/device_info_plus.dart';

/// Helper class for managing storage permissions across different Android versions
class StoragePermissionHelper {
  /// Request storage permissions based on Android version
  ///
  /// Android 10 and below: Request WRITE_EXTERNAL_STORAGE
  /// Android 11-12: Request MANAGE_EXTERNAL_STORAGE
  /// Android 13+: Request READ_MEDIA permissions
  ///
  /// Returns true if permission is granted, false otherwise
  static Future<bool> requestStoragePermission(BuildContext context) async {
    if (!Platform.isAndroid) {
      // iOS and other platforms handle permissions differently
      return true;
    }

    try {
      final deviceInfo = DeviceInfoPlugin();
      final androidInfo = await deviceInfo.androidInfo;
      final sdkInt = androidInfo.version.sdkInt;

      debugPrint('📱 Android SDK Version: $sdkInt');

      // Android 13+ (SDK 33+) - Use new media permissions
      if (sdkInt >= 33) {
        debugPrint('📂 Requesting Android 13+ permissions...');

        // For database files, we still need storage permission
        final status = await Permission.manageExternalStorage.request();

        if (status.isGranted) {
          debugPrint('✅ MANAGE_EXTERNAL_STORAGE granted');
          return true;
        } else if (status.isPermanentlyDenied) {
          if (context.mounted) {
            _showPermissionDeniedDialog(context, isPermanent: true);
          }
          return false;
        } else {
          if (context.mounted) {
            _showPermissionDeniedDialog(context, isPermanent: false);
          }
          return false;
        }
      }

      // Android 11-12 (SDK 30-32) - Request MANAGE_EXTERNAL_STORAGE
      else if (sdkInt >= 30) {
        debugPrint('📂 Requesting Android 11-12 MANAGE_EXTERNAL_STORAGE...');

        final status = await Permission.manageExternalStorage.request();

        if (status.isGranted) {
          debugPrint('✅ MANAGE_EXTERNAL_STORAGE granted');
          return true;
        } else if (status.isPermanentlyDenied) {
          if (context.mounted) {
            _showPermissionDeniedDialog(context, isPermanent: true);
          }
          return false;
        } else {
          if (context.mounted) {
            _showPermissionDeniedDialog(context, isPermanent: false);
          }
          return false;
        }
      }

      // Android 10 and below (SDK 29 and below) - Request WRITE_EXTERNAL_STORAGE
      else {
        debugPrint('📂 Requesting Android 10 and below storage permission...');

        final status = await Permission.storage.request();

        if (status.isGranted) {
          debugPrint('✅ WRITE_EXTERNAL_STORAGE granted');
          return true;
        } else if (status.isPermanentlyDenied) {
          if (context.mounted) {
            _showPermissionDeniedDialog(context, isPermanent: true);
          }
          return false;
        } else {
          if (context.mounted) {
            _showPermissionDeniedDialog(context, isPermanent: false);
          }
          return false;
        }
      }
    } catch (e) {
      debugPrint('❌ Error requesting storage permission: $e');
      if (context.mounted) {
        _showErrorDialog(context, e.toString());
      }
      return false;
    }
  }

  /// Check if storage permission is already granted
  static Future<bool> hasStoragePermission() async {
    if (!Platform.isAndroid) {
      return true;
    }

    try {
      final deviceInfo = DeviceInfoPlugin();
      final androidInfo = await deviceInfo.androidInfo;
      final sdkInt = androidInfo.version.sdkInt;

      if (sdkInt >= 30) {
        // Android 11+ - Check MANAGE_EXTERNAL_STORAGE
        return await Permission.manageExternalStorage.isGranted;
      } else {
        // Android 10 and below - Check WRITE_EXTERNAL_STORAGE
        return await Permission.storage.isGranted;
      }
    } catch (e) {
      debugPrint('❌ Error checking storage permission: $e');
      return false;
    }
  }

  /// Show dialog when permission is denied
  static void _showPermissionDeniedDialog(
    BuildContext context, {
    required bool isPermanent,
  }) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.warning, color: Colors.orange),
            SizedBox(width: 8),
            Text('Storage Permission Required'),
          ],
        ),
        content: Text(
          isPermanent
              ? 'Storage permission is required to save and restore backups.\n\n'
                  'You have permanently denied this permission. Please go to Settings and manually enable storage access for this app.'
              : 'Storage permission is required to save and restore backups from Google Drive.\n\n'
                  'Please grant storage permission to continue.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          if (isPermanent)
            ElevatedButton.icon(
              onPressed: () {
                Navigator.pop(context);
                openAppSettings();
              },
              icon: const Icon(Icons.settings),
              label: const Text('Open Settings'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.indigo,
                foregroundColor: Colors.white,
              ),
            )
          else
            ElevatedButton(
              onPressed: () => Navigator.pop(context),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.indigo,
                foregroundColor: Colors.white,
              ),
              child: const Text('OK'),
            ),
        ],
      ),
    );
  }

  /// Show error dialog
  static void _showErrorDialog(BuildContext context, String error) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.error, color: Colors.red),
            SizedBox(width: 8),
            Text('Permission Error'),
          ],
        ),
        content: Text('An error occurred while requesting storage permission:\n\n$error'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  /// Request permission with user-friendly explanation dialog first
  static Future<bool> requestWithExplanation(
    BuildContext context, {
    String? customMessage,
  }) async {
    // First check if we already have permission
    final hasPermission = await hasStoragePermission();
    if (hasPermission) {
      debugPrint('✅ Storage permission already granted');
      return true;
    }

    if (!context.mounted) return false;

    // Show explanation dialog
    final shouldRequest = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.folder_open, color: Colors.indigo),
            SizedBox(width: 8),
            Text('Storage Access Required'),
          ],
        ),
        content: Text(
          customMessage ??
              'This app needs storage access to save and restore backup files from Google Drive.\n\n'
                  'Your backup files will be stored in the Downloads folder for easy access.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton.icon(
            onPressed: () => Navigator.pop(context, true),
            icon: const Icon(Icons.check),
            label: const Text('Grant Permission'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.indigo,
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ),
    );

    if (shouldRequest == true && context.mounted) {
      return await requestStoragePermission(context);
    }

    return false;
  }
}
