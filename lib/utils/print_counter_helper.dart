// lib/utils/print_counter_helper.dart
// Helper class to track daily thermal printer usage statistics with historical data
//
// FEATURES:
// ====================
// - Saves print statistics for each day (historical data) in the SQLite database
// - Manual reset only (no automatic reset at midnight)
// - Two reset modes: Reset Today or Reset All History
// - Permission-based access control
//
// USAGE INSTRUCTIONS:
// ====================
// When printing from any screen, call the appropriate increment method:
//
// 1. After printing a bill:
//    await PrintCounterHelper.incrementBillsPrinted();
//
// 2. After printing a receipt:
//    await PrintCounterHelper.incrementReceiptsPrinted();
//
// 3. After printing payment history:
//    await PrintCounterHelper.incrementPaymentHistoryPrinted();
//
// 4. After reprinting a receipt from payment details in daily report:
//    await PrintCounterHelper.incrementReceiptReprintPrinted();

import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';
import 'package:intl/intl.dart';
import 'dart:convert';
import '../db/database_helper.dart';

class PrintCounterHelper {
  // Legacy SharedPreferences key — only used during one-time migration
  static const String _legacyKey = 'print_counter_historical_data';

  // Ensures migration runs at most once per app session
  static bool _migrated = false;

  static String _todayKey() => DateFormat('yyyy-MM-dd').format(DateTime.now());

  /// Migrate data from SharedPreferences into the print_counters table once.
  static Future<void> _ensureMigrated() async {
    if (_migrated) return;
    _migrated = true;

    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonString = prefs.getString(_legacyKey);
      if (jsonString == null) return;

      final decoded = json.decode(jsonString) as Map<String, dynamic>;
      final db = await DatabaseHelper().database;

      for (final entry in decoded.entries) {
        final date = entry.key;
        final data = Map<String, int>.from(entry.value as Map);
        await db.insert(
          'print_counters',
          {
            'date': date,
            'bills': data['bills'] ?? 0,
            'receipts': data['receipts'] ?? 0,
            'paymentHistory': data['paymentHistory'] ?? 0,
            'receiptReprint': data['receiptReprint'] ?? 0,
          },
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );
      }
      await prefs.remove(_legacyKey);
    } catch (_) {}
  }

  static Future<Map<String, int>> _getTodayData() async {
    await _ensureMigrated();
    final db = await DatabaseHelper().database;
    final today = _todayKey();
    final rows = await db.query(
      'print_counters',
      where: 'date = ?',
      whereArgs: [today],
    );
    if (rows.isEmpty) {
      return {'bills': 0, 'receipts': 0, 'paymentHistory': 0, 'receiptReprint': 0};
    }
    return {
      'bills': rows.first['bills'] as int? ?? 0,
      'receipts': rows.first['receipts'] as int? ?? 0,
      'paymentHistory': rows.first['paymentHistory'] as int? ?? 0,
      'receiptReprint': rows.first['receiptReprint'] as int? ?? 0,
    };
  }

  static Future<void> _updateTodayData(Map<String, int> data) async {
    final db = await DatabaseHelper().database;
    await db.insert(
      'print_counters',
      {'date': _todayKey(), ...data},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Increment bills printed counter
  static Future<void> incrementBillsPrinted() async {
    final data = await _getTodayData();
    data['bills'] = (data['bills'] ?? 0) + 1;
    await _updateTodayData(data);
  }

  /// Increment receipts printed counter
  static Future<void> incrementReceiptsPrinted() async {
    final data = await _getTodayData();
    data['receipts'] = (data['receipts'] ?? 0) + 1;
    await _updateTodayData(data);
  }

  /// Increment payment history printed counter
  static Future<void> incrementPaymentHistoryPrinted() async {
    final data = await _getTodayData();
    data['paymentHistory'] = (data['paymentHistory'] ?? 0) + 1;
    await _updateTodayData(data);
  }

  /// Increment receipt reprint counter (from payment details in daily report)
  static Future<void> incrementReceiptReprintPrinted() async {
    final data = await _getTodayData();
    data['receiptReprint'] = (data['receiptReprint'] ?? 0) + 1;
    await _updateTodayData(data);
  }

  /// Get current print statistics for today
  static Future<Map<String, int>> getTodayStats() => _getTodayData();

  /// Get total prints for today
  static Future<int> getTotalPrintsToday() async {
    final stats = await getTodayStats();
    return (stats['bills'] ?? 0) +
        (stats['receipts'] ?? 0) +
        (stats['paymentHistory'] ?? 0) +
        (stats['receiptReprint'] ?? 0);
  }

  /// Get all historical data
  static Future<Map<String, Map<String, int>>> getAllHistoricalData() async {
    await _ensureMigrated();
    final db = await DatabaseHelper().database;
    final rows = await db.query('print_counters', orderBy: 'date DESC');
    return {
      for (final row in rows)
        row['date'] as String: {
          'bills': row['bills'] as int? ?? 0,
          'receipts': row['receipts'] as int? ?? 0,
          'paymentHistory': row['paymentHistory'] as int? ?? 0,
          'receiptReprint': row['receiptReprint'] as int? ?? 0,
        }
    };
  }

  /// Get historical data for a specific date
  static Future<Map<String, int>?> getStatsForDate(String date) async {
    await _ensureMigrated();
    final db = await DatabaseHelper().database;
    final rows = await db.query(
      'print_counters',
      where: 'date = ?',
      whereArgs: [date],
    );
    if (rows.isEmpty) return null;
    return {
      'bills': rows.first['bills'] as int? ?? 0,
      'receipts': rows.first['receipts'] as int? ?? 0,
      'paymentHistory': rows.first['paymentHistory'] as int? ?? 0,
      'receiptReprint': rows.first['receiptReprint'] as int? ?? 0,
    };
  }

  /// Reset today's counters only (keeps historical data for other days)
  static Future<void> resetToday() async {
    await _ensureMigrated();
    final db = await DatabaseHelper().database;
    await db.insert(
      'print_counters',
      {
        'date': _todayKey(),
        'bills': 0,
        'receipts': 0,
        'paymentHistory': 0,
        'receiptReprint': 0,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Reset all historical data (clear everything)
  static Future<void> resetAllHistory() async {
    final db = await DatabaseHelper().database;
    await db.delete('print_counters');
    // Clear any lingering legacy SharedPreferences data
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_legacyKey);
    _migrated = true;
  }

  /// Get total number of days with data
  static Future<int> getTotalDaysWithData() async {
    await _ensureMigrated();
    final db = await DatabaseHelper().database;
    final result = await db.rawQuery('SELECT COUNT(*) as count FROM print_counters');
    return result.first['count'] as int? ?? 0;
  }

  /// Get total prints across all days
  static Future<int> getTotalPrintsAllTime() async {
    await _ensureMigrated();
    final db = await DatabaseHelper().database;
    final result = await db.rawQuery(
      'SELECT SUM(bills + receipts + paymentHistory + receiptReprint) as total FROM print_counters',
    );
    return result.first['total'] as int? ?? 0;
  }
}
