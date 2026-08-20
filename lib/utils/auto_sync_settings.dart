// lib/utils/auto_sync_settings.dart
import 'package:shared_preferences/shared_preferences.dart';

/// Stores how often this device auto-syncs in the background while the app
/// is open. One shared setting drives both directions — a device is only
/// ever Write or Read-Only at a time (see SchoolSyncRegistry.isReadOnlyMode),
/// so there's no scenario where both would need to differ.
class AutoSyncSettings {
  static const String _key = 'auto_sync_interval_minutes';

  /// 0 = Off. Kept short — long intervals mostly defeat the point of
  /// "auto", and this is a foreground-only timer (see AutoSyncService), so
  /// there's no battery cost to weigh against picking something frequent.
  static const List<int> options = [0, 5, 10, 15, 30, 60, 120];

  static Future<int> getIntervalMinutes() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getInt(_key) ?? 0;
    return options.contains(stored) ? stored : 0;
  }

  static Future<void> setIntervalMinutes(int minutes) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_key, minutes);
  }

  static String label(int minutes) {
    if (minutes <= 0) return 'Off';
    if (minutes < 60) return 'Every $minutes min';
    final hours = minutes ~/ 60;
    return hours == 1 ? 'Every 1 hour' : 'Every $hours hours';
  }
}
