// lib/utils/backup_reminder_helper.dart
import 'package:shared_preferences/shared_preferences.dart';

/// Helper class for managing backup reminders with 3-tier priority system
class BackupReminderHelper {
  // SharedPreferences keys
  static const String _lastBackupKey = 'last_backup_timestamp';
  static const String _transactionCountKey = 'transactions_since_backup';
  static const String _lastReminderShownKey = 'last_reminder_shown';
  static const String _dismissedUntilKey = 'reminder_dismissed_until';

  // Default thresholds (can be overridden by user settings)
  static const int defaultTransactionThreshold = 50;
  static const int defaultWarningDays = 7;
  static const int defaultCriticalDays = 14;

  /// Get transaction threshold from settings
  static Future<int> getTransactionThreshold() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt('backup_transaction_threshold') ?? defaultTransactionThreshold;
  }

  /// Get warning days from settings
  static Future<int> getWarningDays() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt('backup_warning_days') ?? defaultWarningDays;
  }

  /// Get critical days from settings
  static Future<int> getCriticalDays() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt('backup_critical_days') ?? defaultCriticalDays;
  }

  /// Check if reminders are enabled
  static Future<bool> areRemindersEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('backup_reminders_enabled') ?? true;
  }

  /// Record that a backup was just performed
  static Future<void> recordBackup() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_lastBackupKey, DateTime.now().millisecondsSinceEpoch);
    await prefs.setInt(_transactionCountKey, 0); // Reset transaction count
  }

  /// Increment transaction counter (call after payments, bills, students added)
  static Future<void> incrementTransactionCount() async {
    final prefs = await SharedPreferences.getInstance();
    final currentCount = prefs.getInt(_transactionCountKey) ?? 0;
    await prefs.setInt(_transactionCountKey, currentCount + 1);
  }

  /// Get number of days since last backup
  static Future<int> getDaysSinceLastBackup() async {
    final prefs = await SharedPreferences.getInstance();
    final lastBackupTimestamp = prefs.getInt(_lastBackupKey);

    if (lastBackupTimestamp == null) {
      // Never backed up - return a large number
      return 999;
    }

    final lastBackup = DateTime.fromMillisecondsSinceEpoch(lastBackupTimestamp);
    final now = DateTime.now();
    final difference = now.difference(lastBackup);

    return difference.inDays;
  }

  /// Get number of transactions since last backup
  static Future<int> getTransactionsSinceBackup() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_transactionCountKey) ?? 0;
  }

  /// Check if we should show a reminder
  static Future<BackupReminderLevel> shouldShowReminder() async {
    // Check if reminders are enabled
    final enabled = await areRemindersEnabled();
    if (!enabled) {
      return BackupReminderLevel.none;
    }

    final prefs = await SharedPreferences.getInstance();

    // Check if reminder is dismissed temporarily
    final dismissedUntil = prefs.getInt(_dismissedUntilKey);
    if (dismissedUntil != null) {
      final dismissedUntilTime = DateTime.fromMillisecondsSinceEpoch(dismissedUntil);
      if (DateTime.now().isBefore(dismissedUntilTime)) {
        return BackupReminderLevel.none; // Still dismissed
      }
    }

    final daysSinceBackup = await getDaysSinceLastBackup();
    final transactions = await getTransactionsSinceBackup();

    // Get user-configured thresholds
    final criticalDays = await getCriticalDays();
    final warningDays = await getWarningDays();
    final transactionThreshold = await getTransactionThreshold();

    // CRITICAL: User-defined days without backup (cannot dismiss)
    if (daysSinceBackup >= criticalDays) {
      return BackupReminderLevel.critical;
    }

    // MEDIUM: User-defined warning days OR transaction threshold
    if (daysSinceBackup >= warningDays || transactions >= transactionThreshold) {
      return BackupReminderLevel.medium;
    }

    // GENTLE: First launch of the day
    if (await _isFirstLaunchToday()) {
      return BackupReminderLevel.gentle;
    }

    return BackupReminderLevel.none;
  }

  /// Check if this is the first dashboard launch today
  static Future<bool> _isFirstLaunchToday() async {
    final prefs = await SharedPreferences.getInstance();
    final lastReminderShown = prefs.getInt(_lastReminderShownKey);

    if (lastReminderShown == null) {
      return true; // Never shown before
    }

    final lastReminderDate = DateTime.fromMillisecondsSinceEpoch(lastReminderShown);
    final today = DateTime.now();

    // Check if last reminder was shown on a different day
    return lastReminderDate.year != today.year ||
           lastReminderDate.month != today.month ||
           lastReminderDate.day != today.day;
  }

  /// Record that reminder was shown
  static Future<void> recordReminderShown() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_lastReminderShownKey, DateTime.now().millisecondsSinceEpoch);
  }

  /// Dismiss reminder for specified duration
  static Future<void> dismissReminder(DismissDuration duration) async {
    final prefs = await SharedPreferences.getInstance();
    final now = DateTime.now();
    DateTime dismissUntil;

    switch (duration) {
      case DismissDuration.fourHours:
        dismissUntil = now.add(const Duration(hours: 4));
        break;
      case DismissDuration.laterToday:
        // Dismiss until 6 PM today, or 6 PM tomorrow if it's already past 6 PM
        dismissUntil = DateTime(now.year, now.month, now.day, 18, 0);
        if (now.isAfter(dismissUntil)) {
          dismissUntil = dismissUntil.add(const Duration(days: 1));
        }
        break;
      case DismissDuration.tomorrow:
        // Dismiss until 9 AM tomorrow
        dismissUntil = DateTime(now.year, now.month, now.day + 1, 9, 0);
        break;
    }

    await prefs.setInt(_dismissedUntilKey, dismissUntil.millisecondsSinceEpoch);
  }

  /// Clear dismissal (used when user performs backup)
  static Future<void> clearDismissal() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_dismissedUntilKey);
  }

  /// Get formatted message for reminder dialog
  static Future<String> getReminderMessage(BackupReminderLevel level) async {
    final days = await getDaysSinceLastBackup();
    final transactions = await getTransactionsSinceBackup();
    final warningDays = await getWarningDays();

    switch (level) {
      case BackupReminderLevel.gentle:
        return "Good day! It's a great time to backup your data to keep it safe.";

      case BackupReminderLevel.medium:
        if (days >= warningDays) {
          return "It's been $days days since your last backup. We recommend backing up your data regularly to prevent loss.";
        } else {
          return "You've recorded $transactions transactions since your last backup. Consider backing up your data now.";
        }

      case BackupReminderLevel.critical:
        return "⚠️ CRITICAL: It's been $days days since your last backup!\n\nYour data is at risk. Please backup immediately to protect against potential data loss.";

      case BackupReminderLevel.none:
        return "";
    }
  }
}

/// Backup reminder priority levels
enum BackupReminderLevel {
  none,      // Don't show reminder
  gentle,    // Daily gentle reminder (dismissible)
  medium,    // 7 days or 50 transactions (sticky)
  critical,  // 14+ days (must respond)
}

/// Dismiss duration options
enum DismissDuration {
  fourHours,   // Remind in 4 hours
  laterToday,  // Remind later today (6 PM)
  tomorrow,    // Remind tomorrow (9 AM)
}
