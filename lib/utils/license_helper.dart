// lib/utils/license_helper.dart

import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';

enum LicenseType {
  trial,      // 30 days trial
  monthly,    // 1 month license
  yearly,     // 1 year license
  lifetime,   // Lifetime license
}

enum LicenseStatus {
  valid,
  expired,
  invalid,
  notActivated,
  deviceMismatch,
}

class LicenseHelper {
  static const String _licenseKey = 'app_license_key';
  static const String _activationDateKey = 'activation_date';
  static const String _deviceIdKey = 'device_id';
  static const String _licenseTypeKey = 'license_type';
  static const String _expiryDateKey = 'expiry_date';
  static const String _schoolNameKey = 'licensed_school_name';
  
  // Secret key for license generation (keep this secret!)
  static const String _secretKey = 'TySolutions2024BursaryManager';
  
  // Trial period in days
  static const int _trialDays = 30;

  /// ================================
  /// GET DEVICE ID (Unique per device)
  /// ================================
  static Future<String> getDeviceId() async {
    try {
      final deviceInfo = DeviceInfoPlugin();
      
      if (Platform.isAndroid) {
        final androidInfo = await deviceInfo.androidInfo;
        // Create unique ID from device details
        final deviceString = '${androidInfo.id}_${androidInfo.device}_${androidInfo.model}';
        return _hashString(deviceString);
      } else if (Platform.isIOS) {
        final iosInfo = await deviceInfo.iosInfo;
        final deviceString = '${iosInfo.identifierForVendor}_${iosInfo.model}';
        return _hashString(deviceString);
      } else {
        // For other platforms
        return _hashString('${Platform.operatingSystem}_${Platform.operatingSystemVersion}');
      }
    } catch (e) {
      // Fallback: Use timestamp-based ID
      return _hashString('fallback_${DateTime.now().millisecondsSinceEpoch}');
    }
  }

  /// ================================
  /// GENERATE LICENSE KEY
  /// ================================
  static String generateLicenseKey({
    required String schoolName,
    required LicenseType licenseType,
    required String deviceId,
    DateTime? expiryDate,
  }) {
    // Format: SCHOOL-TYPE-DEVICE-EXPIRY-CHECKSUM
    
    final schoolHash = _hashString(schoolName).substring(0, 8).toUpperCase();
    final typeCode = _getLicenseTypeCode(licenseType);
    final deviceHash = deviceId.substring(0, 8).toUpperCase();
    
    String expiryCode;
    if (licenseType == LicenseType.lifetime) {
      expiryCode = 'LIFETIME';
    } else {
      expiryDate ??= _calculateExpiryDate(licenseType);
      expiryCode = DateFormat('yyyyMMdd').format(expiryDate);
    }
    
    // Create checksum
    final dataString = '$schoolHash$typeCode$deviceHash$expiryCode$_secretKey';
    final checksum = _hashString(dataString).substring(0, 6).toUpperCase();
    
    return '$schoolHash-$typeCode-$deviceHash-$expiryCode-$checksum';
  }

  /// ================================
  /// VALIDATE LICENSE KEY
  /// ================================
  static Future<Map<String, dynamic>> validateLicenseKey(
    String licenseKey,
    String schoolName,
  ) async {
    try {
      // Remove spaces and convert to uppercase
      licenseKey = licenseKey.replaceAll(' ', '').toUpperCase();
      
      // Check format
      final parts = licenseKey.split('-');
      if (parts.length != 5) {
        return {
          'valid': false,
          'status': LicenseStatus.invalid,
          'message': 'Invalid license key format',
        };
      }

      final schoolHash = parts[0];
      final typeCode = parts[1];
      final deviceHash = parts[2];
      final expiryCode = parts[3];
      final providedChecksum = parts[4];

      // Verify school name
      final expectedSchoolHash = _hashString(schoolName).substring(0, 8).toUpperCase();
      if (schoolHash != expectedSchoolHash) {
        return {
          'valid': false,
          'status': LicenseStatus.invalid,
          'message': 'License key not valid for this school',
        };
      }

      // Verify device
      final currentDeviceId = await getDeviceId();
      final expectedDeviceHash = currentDeviceId.substring(0, 8).toUpperCase();
      if (deviceHash != expectedDeviceHash) {
        return {
          'valid': false,
          'status': LicenseStatus.deviceMismatch,
          'message': 'License key is bound to a different device',
        };
      }

      // Verify checksum
      final dataString = '$schoolHash$typeCode$deviceHash$expiryCode$_secretKey';
      final expectedChecksum = _hashString(dataString).substring(0, 6).toUpperCase();
      if (providedChecksum != expectedChecksum) {
        return {
          'valid': false,
          'status': LicenseStatus.invalid,
          'message': 'Invalid license key (checksum failed)',
        };
      }

      // Parse license type
      final licenseType = _parseLicenseTypeCode(typeCode);

      // Check expiry
      DateTime? expiryDate;
      if (expiryCode != 'LIFETIME') {
        try {
          expiryDate = DateFormat('yyyyMMdd').parse(expiryCode);
          if (DateTime.now().isAfter(expiryDate)) {
            return {
              'valid': false,
              'status': LicenseStatus.expired,
              'message': 'License has expired',
              'expiryDate': expiryDate,
            };
          }
        } catch (e) {
          return {
            'valid': false,
            'status': LicenseStatus.invalid,
            'message': 'Invalid expiry date format',
          };
        }
      }

      // License is valid!
      return {
        'valid': true,
        'status': LicenseStatus.valid,
        'message': 'License is valid',
        'licenseType': licenseType,
        'expiryDate': expiryDate,
        'isLifetime': expiryCode == 'LIFETIME',
      };
    } catch (e) {
      return {
        'valid': false,
        'status': LicenseStatus.invalid,
        'message': 'Error validating license: $e',
      };
    }
  }

  /// ================================
  /// ACTIVATE LICENSE
  /// ================================
  static Future<Map<String, dynamic>> activateLicense({
    required String licenseKey,
    required String schoolName,
  }) async {
    // Validate license key
    final validation = await validateLicenseKey(licenseKey, schoolName);
    
    if (validation['valid'] != true) {
      return {
        'success': false,
        ...validation,
      };
    }

    // Save license information
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_licenseKey, licenseKey);
    await prefs.setString(_activationDateKey, DateTime.now().toIso8601String());
    await prefs.setString(_deviceIdKey, await getDeviceId());
    await prefs.setString(_licenseTypeKey, validation['licenseType'].toString());
    await prefs.setString(_schoolNameKey, schoolName);
    
    if (validation['expiryDate'] != null) {
      await prefs.setString(
        _expiryDateKey,
        (validation['expiryDate'] as DateTime).toIso8601String(),
      );
    }

    return {
      'success': true,
      'message': 'License activated successfully',
      ...validation,
    };
  }

  /// ================================
  /// CHECK LICENSE STATUS
  /// ================================
  static Future<Map<String, dynamic>> checkLicenseStatus() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      
      // Check if license exists
      final licenseKey = prefs.getString(_licenseKey);
      if (licenseKey == null || licenseKey.isEmpty) {
        // Check for trial
        return await _checkTrialStatus();
      }

      // Get stored data
      final activationDate = prefs.getString(_activationDateKey);
      final deviceId = prefs.getString(_deviceIdKey);
      final licenseTypeStr = prefs.getString(_licenseTypeKey);
      final expiryDateStr = prefs.getString(_expiryDateKey);
      final schoolName = prefs.getString(_schoolNameKey);

      // Verify device hasn't changed
      final currentDeviceId = await getDeviceId();
      if (deviceId != currentDeviceId) {
        return {
          'valid': false,
          'status': LicenseStatus.deviceMismatch,
          'message': 'Device mismatch detected',
        };
      }

      // For trial licenses, skip key validation and just check expiry
      // This prevents validation errors with trial keys
      final isTrial = licenseTypeStr == LicenseType.trial.toString();
      
      if (!isTrial) {
        // Only validate purchased licenses against school name
        if (schoolName != null && schoolName.isNotEmpty) {
          final validation = await validateLicenseKey(licenseKey, schoolName);
          if (validation['valid'] != true) {
            return validation;
          }
        }
      }

      // Check expiry
      if (expiryDateStr != null && expiryDateStr.isNotEmpty) {
        final expiryDate = DateTime.parse(expiryDateStr);
        if (DateTime.now().isAfter(expiryDate)) {
          return {
            'valid': false,
            'status': LicenseStatus.expired,
            'message': isTrial ? 'Trial period has expired' : 'License has expired',
            'expiryDate': expiryDate,
            'isTrial': isTrial,
          };
        }

        // Calculate days remaining
        final daysRemaining = expiryDate.difference(DateTime.now()).inDays;
        
        return {
          'valid': true,
          'status': LicenseStatus.valid,
          'message': isTrial ? 'Trial is active' : 'License is active',
          'licenseType': _parseLicenseTypeString(licenseTypeStr),
          'activationDate': activationDate != null ? DateTime.parse(activationDate) : null,
          'expiryDate': expiryDate,
          'daysRemaining': daysRemaining,
          'isLifetime': false,
          'isTrial': isTrial,
        };
      } else {
        // Lifetime license
        return {
          'valid': true,
          'status': LicenseStatus.valid,
          'message': 'License is active',
          'licenseType': LicenseType.lifetime,
          'activationDate': activationDate != null ? DateTime.parse(activationDate) : null,
          'isLifetime': true,
          'isTrial': false,
        };
      }
    } catch (e) {
      return {
        'valid': false,
        'status': LicenseStatus.invalid,
        'message': 'Error checking license: $e',
      };
    }
  }

  /// ================================
  /// START TRIAL (FIXED)
  /// ================================
  static Future<Map<String, dynamic>> startTrial(String schoolName) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      
      // Check if trial or license already started
      final existingLicense = prefs.getString(_licenseKey);
      final trialStarted = prefs.getString(_activationDateKey);
      
      if (existingLicense != null || trialStarted != null) {
        // Already has trial or license - check status
        final status = await _checkTrialStatus();
        
        // If trial is still valid, return success so user can proceed
        if (status['valid'] == true) {
          return {
            'success': true,
            'message': 'Trial is already active',
            ...status,
          };
        } else {
          // Trial expired or invalid
          return {
            'success': false,
            'message': status['message'] ?? 'Cannot start trial',
            ...status,
          };
        }
      }

      // Start new trial
      final deviceId = await getDeviceId();
      final trialLicense = generateLicenseKey(
        schoolName: schoolName,
        licenseType: LicenseType.trial,
        deviceId: deviceId,
      );

      await prefs.setString(_licenseKey, trialLicense);
      await prefs.setString(_activationDateKey, DateTime.now().toIso8601String());
      await prefs.setString(_deviceIdKey, deviceId);
      await prefs.setString(_licenseTypeKey, LicenseType.trial.toString());
      await prefs.setString(_schoolNameKey, schoolName);
      
      final expiryDate = DateTime.now().add(Duration(days: _trialDays));
      await prefs.setString(_expiryDateKey, expiryDate.toIso8601String());

      return {
        'success': true,
        'message': 'Trial started successfully',
        'valid': true,
        'status': LicenseStatus.valid,
        'licenseType': LicenseType.trial,
        'expiryDate': expiryDate,
        'daysRemaining': _trialDays,
        'isTrial': true,
      };
    } catch (e) {
      return {
        'success': false,
        'valid': false,
        'message': 'Error starting trial: $e',
      };
    }
  }

  /// ================================
  /// CHECK TRIAL STATUS
  /// ================================
  static Future<Map<String, dynamic>> _checkTrialStatus() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      
      final activationDateStr = prefs.getString(_activationDateKey);
      final expiryDateStr = prefs.getString(_expiryDateKey);
      
      if (activationDateStr == null || activationDateStr.isEmpty) {
        return {
          'valid': false,
          'status': LicenseStatus.notActivated,
          'message': 'No license or trial activated',
          'canStartTrial': true,
        };
      }

      final activationDate = DateTime.parse(activationDateStr);
      
      // Try to get expiry from storage first
      DateTime expiryDate;
      if (expiryDateStr != null && expiryDateStr.isNotEmpty) {
        expiryDate = DateTime.parse(expiryDateStr);
      } else {
        // Calculate from activation date
        expiryDate = activationDate.add(Duration(days: _trialDays));
      }
      
      if (DateTime.now().isAfter(expiryDate)) {
        return {
          'valid': false,
          'status': LicenseStatus.expired,
          'message': 'Trial period has expired',
          'isTrial': true,
          'expiryDate': expiryDate,
          'canStartTrial': false,
        };
      }

      final daysRemaining = expiryDate.difference(DateTime.now()).inDays;
      
      return {
        'valid': true,
        'status': LicenseStatus.valid,
        'message': 'Trial is active',
        'licenseType': LicenseType.trial,
        'activationDate': activationDate,
        'expiryDate': expiryDate,
        'daysRemaining': daysRemaining,
        'isTrial': true,
        'canStartTrial': false,
      };
    } catch (e) {
      return {
        'valid': false,
        'status': LicenseStatus.invalid,
        'message': 'Error checking trial: $e',
        'canStartTrial': true,
      };
    }
  }

  /// ================================
  /// DEACTIVATE LICENSE
  /// ================================
  static Future<void> deactivateLicense() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_licenseKey);
    await prefs.remove(_activationDateKey);
    await prefs.remove(_deviceIdKey);
    await prefs.remove(_licenseTypeKey);
    await prefs.remove(_expiryDateKey);
    await prefs.remove(_schoolNameKey);
  }

  /// ================================
  /// GET LICENSE INFO (for display)
  /// ================================
  static Future<Map<String, dynamic>> getLicenseInfo() async {
    final prefs = await SharedPreferences.getInstance();
    
    return {
      'licenseKey': prefs.getString(_licenseKey),
      'activationDate': prefs.getString(_activationDateKey),
      'licenseType': prefs.getString(_licenseTypeKey),
      'expiryDate': prefs.getString(_expiryDateKey),
      'schoolName': prefs.getString(_schoolNameKey),
    };
  }

  /// ================================
  /// HELPER METHODS
  /// ================================
  
  static String _hashString(String input) {
    final bytes = utf8.encode(input);
    final digest = sha256.convert(bytes);
    return digest.toString();
  }

  static String _getLicenseTypeCode(LicenseType type) {
    switch (type) {
      case LicenseType.trial:
        return 'TRL';
      case LicenseType.monthly:
        return 'MTH';
      case LicenseType.yearly:
        return 'YER';
      case LicenseType.lifetime:
        return 'LTM';
    }
  }

  static LicenseType _parseLicenseTypeCode(String code) {
    switch (code) {
      case 'TRL':
        return LicenseType.trial;
      case 'MTH':
        return LicenseType.monthly;
      case 'YER':
        return LicenseType.yearly;
      case 'LTM':
        return LicenseType.lifetime;
      default:
        return LicenseType.trial;
    }
  }

  static LicenseType? _parseLicenseTypeString(String? typeStr) {
    if (typeStr == null || typeStr.isEmpty) return null;
    try {
      return LicenseType.values.firstWhere(
        (e) => e.toString() == typeStr,
        orElse: () => LicenseType.trial,
      );
    } catch (e) {
      return LicenseType.trial;
    }
  }

  static DateTime _calculateExpiryDate(LicenseType type) {
    final now = DateTime.now();
    switch (type) {
      case LicenseType.trial:
        return now.add(Duration(days: _trialDays));
      case LicenseType.monthly:
        return DateTime(now.year, now.month + 1, now.day);
      case LicenseType.yearly:
        return DateTime(now.year + 1, now.month, now.day);
      case LicenseType.lifetime:
        return DateTime(2099, 12, 31); // Far future date
    }
  }

  /// ================================
  /// FORMAT LICENSE TYPE FOR DISPLAY
  /// ================================
  static String formatLicenseType(LicenseType type) {
    switch (type) {
      case LicenseType.trial:
        return 'Trial';
      case LicenseType.monthly:
        return 'Monthly';
      case LicenseType.yearly:
        return 'Yearly';
      case LicenseType.lifetime:
        return 'Lifetime';
    }
  }

  /// ================================
  /// GET CONTACT INFO FOR PURCHASE
  /// ================================
  static Map<String, String> getContactInfo() {
    return {
      'company': 'Ty Solutions Multimedia Technologies',
      'email': 'tysolutionsmultimediatech@gmail.com',
      'phone': '+234 XXX XXX XXXX', // Add actual phone number
      'website': 'www.tysolutions.com.ng',
      'whatsapp': '+234 XXX XXX XXXX', // Add WhatsApp number
    };
  }
}