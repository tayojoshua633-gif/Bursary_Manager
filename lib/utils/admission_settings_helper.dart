// lib/utils/admission_settings_helper.dart

import 'package:shared_preferences/shared_preferences.dart';

/// Preferences controlling admission number behavior.
class AdmissionSettingsHelper {
  static const String _editableKey = 'admission_number_editable';
  static const String _restartSerialPerSessionKey = 'admission_serial_restart_per_session';

  /// Whether staff can manually edit the admission number field.
  /// Defaults to false (auto-generated, locked).
  static Future<bool> isEditable() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_editableKey) ?? false;
  }

  static Future<void> setEditable(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_editableKey, value);
  }

  /// Whether the serial portion of the admission number restarts at 1
  /// whenever the session year embedded in it changes.
  /// Defaults to false (serial keeps climbing across all sessions).
  static Future<bool> isRestartSerialPerSession() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_restartSerialPerSessionKey) ?? false;
  }

  static Future<void> setRestartSerialPerSession(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_restartSerialPerSessionKey, value);
  }
}
