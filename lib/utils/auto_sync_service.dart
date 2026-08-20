// lib/utils/auto_sync_service.dart
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'auto_sync_settings.dart';
import 'central_backup_helper.dart';
import 'school_sync_client.dart';
import 'school_sync_registry.dart';

/// App-wide periodic auto-sync. Deliberately not tied to any screen's
/// State — HomeScreen gets disposed/rebuilt on navigation, which would stop
/// a timer living there the moment the user left the screen. This is a
/// plain static timer instead, started once from main.dart after login and
/// alive for the rest of the app session regardless of which screen is
/// showing.
class AutoSyncService {
  static Timer? _timer;
  static bool _running = false;

  /// Call once after login. Reads the current interval and schedules the
  /// timer accordingly (no-ops if the setting is Off).
  static Future<void> start() => restart();

  /// Re-reads the interval setting and reschedules. Call this any time the
  /// setting changes from a settings screen — cheap, safe to call anytime.
  static Future<void> restart() async {
    _timer?.cancel();
    _timer = null;

    final minutes = await AutoSyncSettings.getIntervalMinutes();
    if (minutes <= 0) return;

    _timer = Timer.periodic(Duration(minutes: minutes), (_) => _tick());
  }

  static void stop() {
    _timer?.cancel();
    _timer = null;
  }

  /// Write devices push their own data; Read-Only devices refresh every
  /// linked school. Skips the tick entirely if a previous one is still
  /// running (e.g. a slow connection) rather than stacking overlapping
  /// syncs — both underlying calls are already internet/read-only-safe on
  /// their own, this just adds the "don't overlap" guarantee.
  static Future<void> _tick() async {
    if (_running) return;
    _running = true;
    try {
      if (await SchoolSyncRegistry.isReadOnlyMode()) {
        await SchoolSyncClient.refreshAllOnLaunch();
      } else {
        await CentralBackupHelper.triggerAutoUpload();
      }
    } catch (e) {
      debugPrint('[AutoSync] tick failed: $e');
    } finally {
      _running = false;
    }
  }
}
