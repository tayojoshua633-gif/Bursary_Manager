// lib/utils/report_data/daily_custom_report_loader.dart
import 'package:flutter/foundation.dart';
import '../../data/database_helper_wrapper.dart';

/// Plain, immutable result of loading Daily/Custom report data for a date
/// range against whichever database is currently active on
/// DatabaseHelper()/DatabaseHelperWrapper() at call time. Not tied to any
/// screen's State — safe to build off-screen (e.g. once per linked school
/// in UnifiedReportScreen).
class DailyCustomReportData {
  final DateTime startDate;
  final DateTime endDate;
  final String? activeTerm;
  final String? activeSession;
  final Map<String, dynamic>? school;

  // Income (school-fee payments)
  final double cashTotal;
  final double posTotal;
  final double transferTotal;
  final double totalIncome;
  final List<Map<String, dynamic>> paymentDetails;

  // Expenses
  final double expenseCashTotal;
  final double expensePosTotal;
  final double expenseTransferTotal;
  final double totalExpenses;
  final Map<String, double> expenseCategoryTotals;
  final List<Map<String, dynamic>> expenseDetails;

  // Stock & Sales
  final List<Map<String, dynamic>> stockSummary;
  final List<Map<String, dynamic>> salesDetails;
  final List<Map<String, dynamic>> salesDebtors;
  final double salesCashTotal;
  final double salesPosTotal;
  final double salesTransferTotal;
  final double totalSales;
  final double totalSalesDebt;

  const DailyCustomReportData({
    required this.startDate,
    required this.endDate,
    required this.activeTerm,
    required this.activeSession,
    required this.school,
    required this.cashTotal,
    required this.posTotal,
    required this.transferTotal,
    required this.totalIncome,
    required this.paymentDetails,
    required this.expenseCashTotal,
    required this.expensePosTotal,
    required this.expenseTransferTotal,
    required this.totalExpenses,
    required this.expenseCategoryTotals,
    required this.expenseDetails,
    required this.stockSummary,
    required this.salesDetails,
    required this.salesDebtors,
    required this.salesCashTotal,
    required this.salesPosTotal,
    required this.salesTransferTotal,
    required this.totalSales,
    required this.totalSalesDebt,
  });
}

String _formatDate(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// Extracted verbatim from CustomReportScreen._loadCustomReport() (the
/// BETWEEN-based query form) — DailyReportScreen calls this with
/// startDate == endDate == selectedDate instead of running its own
/// LIKE '%date%' queries. Behaviorally equivalent when the range collapses
/// to a single day, and this BETWEEN+date() form is already proven correct
/// by Custom Report's own week/month presets today.
Future<DailyCustomReportData> loadDailyCustomReportData({
  required DateTime startDate,
  required DateTime endDate,
  DatabaseHelperWrapper? dbOverride,
}) async {
  final db = dbOverride ?? DatabaseHelperWrapper();

  final activeTerm = await db.getActiveTerm();
  final activeSession = (await db.getActiveSession())?['sessionName'] as String?;
  final school = await db.getSchoolProfile();

  final startStr = _formatDate(startDate);
  final endStr = _formatDate(endDate);

  final database = await db.database;

  // ── Income (payments) ─────────────────────────────────────────────────
  final raw = await database.rawQuery('''
    SELECT
      p.*,
      s.surname,
      s.firstName,
      s.admissionNo,
      c.name as className,
      a.name as armName
    FROM payments p
    INNER JOIN students s ON p.studentId = s.id
    LEFT JOIN classes c ON s.classId = c.id
    LEFT JOIN arms a ON s.armId = a.id
    WHERE date(p.paymentDate) BETWEEN ? AND ?
    ORDER BY p.paymentDate DESC
  ''', [startStr, endStr]);

  double cashTotal = 0;
  double posTotal = 0;
  double transferTotal = 0;
  final paymentDetails = <Map<String, dynamic>>[];

  for (var p in raw) {
    final paymentTerm = p['term']?.toString() ?? '';
    final paymentSession = p['session']?.toString() ?? '';

    if (activeSession != null) {
      if (paymentTerm != activeTerm || paymentSession != activeSession) {
        continue;
      }
    }

    final method = (p['method'] ?? '').toString().toUpperCase();
    final amount = (p['amount'] is num)
        ? p['amount'] as num
        : double.tryParse(p['amount'].toString()) ?? 0.0;

    paymentDetails.add({
      'paymentId': p['id'],
      'studentId': p['studentId'],
      'studentName': '${p['surname']} ${p['firstName']}',
      'admissionNo': p['admissionNo'],
      'className': p['className'] ?? 'N/A',
      'armName': p['armName'] ?? 'N/A',
      'method': method,
      'amount': amount,
      'paymentDate': p['paymentDate'],
      'term': p['term'],
      'session': p['session'],
      'paymentFor': p['paymentFor']?.toString() ?? 'School Fees',
    });

    if (method == 'CASH') {
      cashTotal += amount;
    } else if (method == 'POS') {
      posTotal += amount;
    } else if (method == 'TRANSFER' || method == 'BANK TRANSFER') {
      transferTotal += amount;
    }
  }

  final totalIncome = cashTotal + posTotal + transferTotal;

  // ── Expenses ───────────────────────────────────────────────────────────
  double expenseCashTotal = 0;
  double expensePosTotal = 0;
  double expenseTransferTotal = 0;
  double totalExpenses = 0;
  final expenseDetails = <Map<String, dynamic>>[];
  final expenseCategoryTotals = <String, double>{};

  try {
    final expensesRaw = await database.rawQuery('''
      SELECT * FROM expenses
      WHERE date(expenseDate) BETWEEN ? AND ?
      ORDER BY expenseDate DESC
    ''', [startStr, endStr]);

    for (var e in expensesRaw) {
      final expenseTerm = e['term']?.toString() ?? '';
      final expenseSession = e['session']?.toString() ?? '';

      if (activeSession != null) {
        if (expenseTerm != activeTerm || expenseSession != activeSession) {
          continue;
        }
      }

      final method = (e['paymentMethod'] ?? '').toString().toUpperCase();
      final amount = (e['amount'] is num)
          ? (e['amount'] as num).toDouble()
          : double.tryParse(e['amount'].toString()) ?? 0.0;

      final category = (e['category'] ?? 'Uncategorized').toString();
      final customCategory = e['customCategory']?.toString();
      final displayCategory = category == 'Other' && customCategory != null
          ? 'Other: $customCategory'
          : category;

      expenseDetails.add({
        'description': e['description'],
        'category': displayCategory,
        'recipient': e['recipient'],
        'method': method,
        'amount': amount,
        'expenseDate': e['expenseDate'],
      });

      if (method == 'CASH') {
        expenseCashTotal += amount;
      } else if (method == 'POS') {
        expensePosTotal += amount;
      } else if (method == 'TRANSFER' || method == 'BANK TRANSFER') {
        expenseTransferTotal += amount;
      }

      expenseCategoryTotals[displayCategory] =
          (expenseCategoryTotals[displayCategory] ?? 0) + amount;
    }

    totalExpenses = expenseCashTotal + expensePosTotal + expenseTransferTotal;
  } catch (e) {
    debugPrint('[UnifiedReport] Error loading expenses: $e');
    totalExpenses = 0;
  }

  // ── Stock & Sales ──────────────────────────────────────────────────────
  double salesCashTotal = 0;
  double salesPosTotal = 0;
  double salesTransferTotal = 0;
  double totalSales = 0;
  double totalSalesDebt = 0;
  var salesDetails = <Map<String, dynamic>>[];
  var stockSummary = <Map<String, dynamic>>[];
  final salesDebtors = <Map<String, dynamic>>[];

  try {
    final salesRaw = await database.rawQuery('''
      SELECT
        s.*,
        COALESCE(si.itemName, s.itemName) as itemName,
        si.costPrice,
        si.currentQuantity as currentStockQuantity
      FROM sales s
      LEFT JOIN stock_items si ON s.stockItemId = si.id AND s.stockItemId > 0
      WHERE date(s.saleDate) BETWEEN ? AND ?
      ORDER BY s.saleDate DESC
    ''', [startStr, endStr]);

    final salesByBuyer = <String, Map<String, dynamic>>{};
    final stockMovement = <int, Map<String, dynamic>>{};

    for (var sale in salesRaw) {
      final saleTerm = sale['term']?.toString() ?? '';
      final saleSession = sale['session']?.toString() ?? '';

      if (activeSession != null) {
        if (saleTerm != activeTerm || saleSession != activeSession) {
          continue;
        }
      }

      final qty = (sale['quantity'] as int);
      if (qty == 0) continue;

      final method = (sale['paymentMethod'] ?? '').toString().toUpperCase();
      final totalAmount = (sale['totalAmount'] as num).toDouble();
      final amountPaid = (sale['amountPaid'] as num).toDouble();
      final paymentStatus = sale['paymentStatus']?.toString() ?? 'Unpaid';
      final stockItemId = sale['stockItemId'] as int;
      final itemName = sale['itemName']?.toString() ?? 'Unknown Item';
      final buyerName = sale['buyerName']?.toString() ?? 'Unknown';
      final buyerType = sale['buyerType']?.toString() ?? '';
      final currentStockQty = (sale['currentStockQuantity'] as int?) ?? 0;

      final isCustomItem = sale['isCustomItem'] == 1 || stockItemId == 0;

      final buyerKey = '$buyerName|$buyerType';
      if (!salesByBuyer.containsKey(buyerKey)) {
        salesByBuyer[buyerKey] = {
          'buyerName': buyerName,
          'buyerType': buyerType,
          'items': <Map<String, dynamic>>[],
          'totalQtySold': 0,
          'totalAmount': 0.0,
          'totalPaid': 0.0,
          'paymentStatus': paymentStatus,
        };
      }

      salesByBuyer[buyerKey]!['items'].add({
        'itemName': itemName,
        'quantity': qty,
        'unitPrice': (sale['unitPrice'] as num).toDouble(),
        'isCustomItem': isCustomItem,
      });
      salesByBuyer[buyerKey]!['totalQtySold'] += qty;
      salesByBuyer[buyerKey]!['totalAmount'] += totalAmount;
      salesByBuyer[buyerKey]!['totalPaid'] += amountPaid;

      if (!isCustomItem && stockItemId > 0) {
        if (!stockMovement.containsKey(stockItemId)) {
          stockMovement[stockItemId] = {
            'itemName': itemName,
            'qtySold': 0,
            'currentQuantity': currentStockQty,
          };
        }
        stockMovement[stockItemId]!['qtySold'] += qty;
      }

      if (method == 'CASH') {
        salesCashTotal += amountPaid;
      } else if (method == 'POS') {
        salesPosTotal += amountPaid;
      } else if (method == 'TRANSFER' || method == 'BANK TRANSFER') {
        salesTransferTotal += amountPaid;
      }

      totalSales += amountPaid;
    }

    salesDetails = salesByBuyer.values.toList();

    final allStockItems = await database.query('stock_items', orderBy: 'itemName');

    stockSummary = allStockItems.map((stockItem) {
      final stockItemId = stockItem['id'] as int;
      final itemName = stockItem['itemName']?.toString() ?? 'Unknown';
      final currentQty = (stockItem['currentQuantity'] as int?) ?? 0;

      final qtySold = stockMovement.containsKey(stockItemId)
          ? (stockMovement[stockItemId]!['qtySold'] as int)
          : 0;

      final beginningQty = currentQty + qtySold;

      return {
        'itemName': itemName,
        'beginningQuantity': beginningQty,
        'qtySold': qtySold,
        'remainingQuantity': currentQty,
      };
    }).toList();

    final debtorsRaw = await database.rawQuery('''
      SELECT DISTINCT
        sd.buyerName,
        sd.buyerType,
        sd.studentId,
        sd.totalAmount,
        sd.amountPaid,
        sd.outstandingBalance
      FROM sales_debtors sd
      INNER JOIN sales s ON sd.buyerName = s.buyerName AND sd.buyerType = s.buyerType
      WHERE date(s.saleDate) BETWEEN ? AND ? AND s.quantity > 0 AND sd.outstandingBalance > 0
    ''', [startStr, endStr]);

    for (var debtor in debtorsRaw) {
      final buyerName = debtor['buyerName']?.toString() ?? 'Unknown';
      final buyerType = debtor['buyerType']?.toString() ?? '';

      final debtorSalesRaw = await database.rawQuery('''
        SELECT COALESCE(si.itemName, s.itemName) as itemName, s.quantity, s.stockItemId, s.isCustomItem
        FROM sales s
        LEFT JOIN stock_items si ON s.stockItemId = si.id AND s.stockItemId > 0
        WHERE s.buyerName = ? AND s.buyerType = ? AND date(s.saleDate) BETWEEN ? AND ? AND s.quantity > 0
      ''', [buyerName, buyerType, startStr, endStr]);

      final itemsList = debtorSalesRaw.map((item) {
        final iName = item['itemName']?.toString() ?? '';
        final qty = item['quantity'] as int;
        final isCustomItem = item['isCustomItem'] == 1 || item['stockItemId'] == 0;
        return isCustomItem ? '$iName [Custom] (x$qty)' : '$iName (x$qty)';
      }).join(', ');

      salesDebtors.add({
        'buyerName': buyerName,
        'buyerType': buyerType,
        'itemsPurchased': itemsList,
        'totalAmount': (debtor['totalAmount'] as num).toDouble(),
        'totalPaid': (debtor['amountPaid'] as num).toDouble(),
        'outstandingBalance': (debtor['outstandingBalance'] as num).toDouble(),
      });

      totalSalesDebt += (debtor['outstandingBalance'] as num).toDouble();
    }
  } catch (e) {
    debugPrint('[UnifiedReport] Error loading stock & sales data: $e');
    salesCashTotal = 0;
    salesPosTotal = 0;
    salesTransferTotal = 0;
    totalSales = 0;
    totalSalesDebt = 0;
    salesDetails = [];
    stockSummary = [];
    salesDebtors.clear();
  }

  return DailyCustomReportData(
    startDate: startDate,
    endDate: endDate,
    activeTerm: activeTerm,
    activeSession: activeSession,
    school: school,
    cashTotal: cashTotal,
    posTotal: posTotal,
    transferTotal: transferTotal,
    totalIncome: totalIncome,
    paymentDetails: paymentDetails,
    expenseCashTotal: expenseCashTotal,
    expensePosTotal: expensePosTotal,
    expenseTransferTotal: expenseTransferTotal,
    totalExpenses: totalExpenses,
    expenseCategoryTotals: expenseCategoryTotals,
    expenseDetails: expenseDetails,
    stockSummary: stockSummary,
    salesDetails: salesDetails,
    salesDebtors: salesDebtors,
    salesCashTotal: salesCashTotal,
    salesPosTotal: salesPosTotal,
    salesTransferTotal: salesTransferTotal,
    totalSales: totalSales,
    totalSalesDebt: totalSalesDebt,
  );
}
