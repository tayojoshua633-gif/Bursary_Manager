// lib/utils/app_uptime.dart

/// Tracks how long the app process has been running (since [main] started).
class AppUptime {
  static final DateTime startTime = DateTime.now();

  static Duration get elapsed => DateTime.now().difference(startTime);

  /// Formats elapsed time as e.g. "2h 14m", "14m 05s", or "42s".
  static String format() {
    final d = elapsed;
    final hours = d.inHours;
    final minutes = d.inMinutes.remainder(60);
    final seconds = d.inSeconds.remainder(60);

    if (hours > 0) {
      return '${hours}h ${minutes.toString().padLeft(2, '0')}m';
    }
    if (minutes > 0) {
      return '${minutes}m ${seconds.toString().padLeft(2, '0')}s';
    }
    return '${seconds}s';
  }
}
