// lib/utils/report_data/termly_report_loader.dart
import 'package:flutter/foundation.dart';
import '../../data/database_helper_wrapper.dart';
import '../../db/database_helper.dart';
import '../print_counter_helper.dart';

/// Plain, immutable result of loading Termly Report data — always scoped to
/// whichever term/session is active on the currently-open database. Not
/// tied to any screen's State — safe to build off-screen (e.g. once per
/// linked school in UnifiedReportScreen).
class TermlyReportData {
  final String? activeTerm;
  final String? activeSession;
  final Map<String, dynamic>? school;

  // Income
  final double cashReceived;
  final double posReceived;
  final double transferReceived;
  final double totalIncome;

  // Expenses
  final double expenseCash;
  final double expensePos;
  final double expenseTransfer;
  final double totalExpenses;
  final Map<String, double> expenseCategoryTotals;

  // Net income
  final double netIncome;

  // Debt report
  final int totalStudents;
  final int totalDebtors;
  final double totalOutstanding;

  // New intake
  final Map<String, int> newIntakeByClass;
  final int totalNewIntake;

  // Printing (all-time, not term-scoped — see class doc on loadTermlyReportData)
  final int billsPrinted;
  final int receiptsPrinted;
  final int paymentHistoryPrinted;
  final int reprintsPrinted;
  final int totalPrints;

  // Stock & Sales
  final List<Map<String, dynamic>> stockSummary;
  final List<Map<String, dynamic>> salesDetails;
  final List<Map<String, dynamic>> salesDebtors;
  final double salesCashTotal;
  final double salesPosTotal;
  final double salesTransferTotal;
  final double totalSales;
  final double totalSalesDebt;

  const TermlyReportData({
    required this.activeTerm,
    required this.activeSession,
    required this.school,
    required this.cashReceived,
    required this.posReceived,
    required this.transferReceived,
    required this.totalIncome,
    required this.expenseCash,
    required this.expensePos,
    required this.expenseTransfer,
    required this.totalExpenses,
    required this.expenseCategoryTotals,
    required this.netIncome,
    required this.totalStudents,
    required this.totalDebtors,
    required this.totalOutstanding,
    required this.newIntakeByClass,
    required this.totalNewIntake,
    required this.billsPrinted,
    required this.receiptsPrinted,
    required this.paymentHistoryPrinted,
    required this.reprintsPrinted,
    required this.totalPrints,
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

/// Extracted verbatim from TermlyReportScreen._loadTermlyReport() (steps
/// 1-8). Any exception in steps 1-7 propagates to the caller (the screen's
/// own try/catch shows a SnackBar; the multi-school coordinator captures it
/// per-school) — only step 8 (stock & sales) keeps its own internal
/// try/catch, matching the original's resilience posture of degrading that
/// one section gracefully rather than failing the whole report.
///
/// Printing stats are all-time totals from PrintCounterHelper, NOT scoped
/// to the active term/session — same as before extraction. Callers
/// displaying this per-school (Unified Report) must label that explicitly.
Future<TermlyReportData> loadTermlyReportData({
  DatabaseHelperWrapper? dbOverride,
}) async {
  final db = dbOverride ?? DatabaseHelperWrapper();

  // Step 1: term, session, school profile
  final activeTerm = await db.getActiveTerm();
  final activeSession = (await db.getActiveSession())?['sessionName'] as String?;
  final school = await db.getSchoolProfile();

  final database = await db.database;

  // Step 2: Income Report (Payment Method Breakdown)
  final paymentsRaw = await database.rawQuery('''
    SELECT method, SUM(amount) as total
    FROM payments
    WHERE term = ? AND session = ?
    GROUP BY method
  ''', [activeTerm, activeSession]);

  double cashReceived = 0;
  double posReceived = 0;
  double transferReceived = 0;

  for (var row in paymentsRaw) {
    final method = (row['method'] ?? '').toString().toUpperCase();
    final amount = (row['total'] as num?)?.toDouble() ?? 0.0;

    if (method == 'CASH') {
      cashReceived = amount;
    } else if (method == 'POS') {
      posReceived = amount;
    } else if (method == 'TRANSFER' || method == 'BANK TRANSFER') {
      transferReceived += amount;
    }
  }

  final totalIncome = cashReceived + posReceived + transferReceived;

  // Step 3: Expenses Report (Category & Payment Method Breakdown)
  final expensesRaw = await DatabaseHelper().getAllExpenses(
    term: activeTerm,
    session: activeSession,
  );

  double expenseCash = 0;
  double expensePos = 0;
  double expenseTransfer = 0;
  final expenseCategoryTotals = <String, double>{};

  for (var expense in expensesRaw) {
    final amount = (expense['amount'] as num?)?.toDouble() ?? 0.0;
    final method = (expense['paymentMethod'] ?? '').toString().toUpperCase();

    if (method == 'CASH') {
      expenseCash += amount;
    } else if (method == 'POS') {
      expensePos += amount;
    } else if (method == 'TRANSFER' || method == 'BANK TRANSFER') {
      expenseTransfer += amount;
    }

    final category = expense['category'] ?? 'Uncategorized';
    final customCategory = expense['customCategory'];
    final displayCategory = category == 'Other' && customCategory != null
        ? 'Other: $customCategory'
        : category;

    expenseCategoryTotals[displayCategory] =
        (expenseCategoryTotals[displayCategory] ?? 0) + amount;
  }

  final totalExpenses = expenseCash + expensePos + expenseTransfer;

  // Step 8 runs before step 4's netIncome calc below needs totalSales — keep
  // the same declare-then-fill-later shape as the original by initializing
  // sales totals up front (matches original's field-already-declared-on-
  // State pattern; here just declared as locals ahead of use).
  double salesCashTotal = 0;
  double salesPosTotal = 0;
  double salesTransferTotal = 0;
  double totalSales = 0;
  double totalSalesDebt = 0;
  var salesDetails = <Map<String, dynamic>>[];
  var stockSummary = <Map<String, dynamic>>[];
  final salesDebtors = <Map<String, dynamic>>[];

  // Step 4: Net Income (computed again, correctly, after step 8 populates
  // totalSales below — see reordering note above _computeNetIncome).

  // Step 5: Debt Report — fresh grand total (all prior outstanding + current term fee)
  final targetKey = DatabaseHelperWrapper.termSortKey(activeTerm, activeSession ?? '');
  final debtQuery = await database.rawQuery('''
    WITH student_totals AS (
      SELECT
        s.id,
        (COALESCE(b.totalAmount, 0) - COALESCE(b.previousBalance, 0))
        + (
            COALESCE((SELECT SUM(b2.totalAmount - b2.previousBalance) FROM student_bills b2
                      WHERE b2.studentId = s.id
                        AND ${DatabaseHelperWrapper.sqlTermKeyExpr('b2')} < ?), 0)
            -
            COALESCE((SELECT SUM(p2.amount) FROM payments p2
                      WHERE p2.studentId = s.id
                        AND ${DatabaseHelperWrapper.sqlTermKeyExpr('p2')} < ?), 0)
          ) as grandTotal,
        COALESCE(
          (SELECT SUM(amount) FROM payments
           WHERE studentId = s.id AND term = ? AND session = ?), 0
        ) as totalPaid
      FROM students s
      LEFT JOIN student_bills b ON s.id = b.studentId
        AND b.term = ? AND b.session = ?
      WHERE s.isActive = 1
    )
    SELECT
      COUNT(*) as totalStudents,
      COUNT(CASE WHEN (grandTotal - totalPaid) > 0 THEN 1 END) as totalDebtors,
      COALESCE(SUM(grandTotal), 0) as totalBills,
      COALESCE(SUM(totalPaid), 0) as totalPayments
    FROM student_totals
  ''', [targetKey, targetKey, activeTerm, activeSession, activeTerm, activeSession]);

  int totalStudents = 0;
  int totalDebtors = 0;
  double totalOutstanding = 0.0;
  if (debtQuery.isNotEmpty) {
    final row = debtQuery.first;
    totalStudents = (row['totalStudents'] as int?) ?? 0;
    totalDebtors = (row['totalDebtors'] as int?) ?? 0;
    final totalBills = (row['totalBills'] as num?)?.toDouble() ?? 0.0;
    final totalPayments = (row['totalPayments'] as num?)?.toDouble() ?? 0.0;
    totalOutstanding = totalBills - totalPayments;
  }

  // Step 6: New Intake Report
  final newIntakeByClass = <String, int>{};
  int totalNewIntake = 0;

  final billsRaw = await database.rawQuery('''
    SELECT DISTINCT sb.id, sb.studentId
    FROM student_bills sb
    WHERE sb.term = ? AND sb.session = ?
  ''', [activeTerm, activeSession]);

  for (var billRow in billsRaw) {
    final billId = billRow['id'] as int;
    final studentId = billRow['studentId'] as int;

    final breakdown = await db.getBillBreakdown(billId);

    bool hasRegistrationFee = false;
    for (var item in breakdown) {
      final label = (item['label'] ?? '').toString().toLowerCase();
      if (label.contains('registration') ||
          label.contains('reg. fee') ||
          label.contains('reg fee') ||
          label == 'reg.' ||
          label == 'reg') {
        hasRegistrationFee = true;
        break;
      }
    }

    if (hasRegistrationFee) {
      final studentRaw = await database.rawQuery('''
        SELECT s.classId, c.name as className
        FROM students s
        LEFT JOIN classes c ON s.classId = c.id
        WHERE s.id = ?
      ''', [studentId]);

      if (studentRaw.isNotEmpty) {
        final className = studentRaw.first['className']?.toString() ?? 'Unknown';
        newIntakeByClass[className] = (newIntakeByClass[className] ?? 0) + 1;
        totalNewIntake++;
      }
    }
  }

  // Step 7: Thermal Printing Report (all-time, not term-scoped)
  final allHistoricalData = await PrintCounterHelper.getAllHistoricalData();

  int billsPrinted = 0;
  int receiptsPrinted = 0;
  int paymentHistoryPrinted = 0;
  int reprintsPrinted = 0;

  for (var dayData in allHistoricalData.values) {
    billsPrinted += (dayData['bills'] ?? 0);
    receiptsPrinted += (dayData['receipts'] ?? 0);
    paymentHistoryPrinted += (dayData['paymentHistory'] ?? 0);
    reprintsPrinted += (dayData['receiptReprint'] ?? 0);
  }

  final totalPrints = billsPrinted + receiptsPrinted + paymentHistoryPrinted + reprintsPrinted;

  // Step 8: Stock & Sales — own try/catch, degrades gracefully on error
  // rather than failing the whole report (matches original behavior).
  try {
    final salesRaw = await database.rawQuery('''
      SELECT
        s.*,
        COALESCE(si.itemName, s.itemName) as itemName,
        si.costPrice,
        si.currentQuantity as currentStockQuantity
      FROM sales s
      LEFT JOIN stock_items si ON s.stockItemId = si.id AND s.stockItemId > 0
      WHERE s.term = ? AND s.session = ? AND s.quantity > 0
      ORDER BY s.saleDate DESC
      LIMIT 500
    ''', [activeTerm, activeSession]);

    final salesByBuyer = <String, Map<String, dynamic>>{};
    final stockMovement = <int, Map<String, dynamic>>{};

    for (var sale in salesRaw) {
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

    final allStockItems = await database.query(
      'stock_items',
      orderBy: 'itemName',
      limit: 100,
    );

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
      WHERE sd.outstandingBalance > 0
      ORDER BY sd.outstandingBalance DESC
      LIMIT 50
    ''');

    int debtorsProcessed = 0;
    for (var debtor in debtorsRaw) {
      if (debtorsProcessed >= 30) break;
      final buyerName = debtor['buyerName']?.toString() ?? 'Unknown';
      final buyerType = debtor['buyerType']?.toString() ?? '';

      final hasSalesInTerm = await database.rawQuery('''
        SELECT COUNT(*) as count
        FROM sales
        WHERE buyerName = ? AND buyerType = ? AND term = ? AND session = ? AND quantity > 0
      ''', [buyerName, buyerType, activeTerm, activeSession]);

      if ((hasSalesInTerm.first['count'] as int) == 0) {
        continue;
      }

      final debtorSalesRaw = await database.rawQuery('''
        SELECT COALESCE(si.itemName, s.itemName) as itemName, s.quantity, s.stockItemId, s.isCustomItem
        FROM sales s
        LEFT JOIN stock_items si ON s.stockItemId = si.id AND s.stockItemId > 0
        WHERE s.buyerName = ? AND s.buyerType = ? AND s.term = ? AND s.session = ? AND s.quantity > 0
      ''', [buyerName, buyerType, activeTerm, activeSession]);

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
      debtorsProcessed++;
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

  // Step 4: Net Income — computed here (after totalSales is known from step
  // 8 above), matching the original's field-order-independent behavior:
  // the screen declares netIncome as a field and only reads it in build(),
  // by which point step 8 has always already run since both are inside the
  // same synchronous-await sequence.
  final netIncome = (totalIncome + totalSales) - totalExpenses;

  return TermlyReportData(
    activeTerm: activeTerm,
    activeSession: activeSession,
    school: school,
    cashReceived: cashReceived,
    posReceived: posReceived,
    transferReceived: transferReceived,
    totalIncome: totalIncome,
    expenseCash: expenseCash,
    expensePos: expensePos,
    expenseTransfer: expenseTransfer,
    totalExpenses: totalExpenses,
    expenseCategoryTotals: expenseCategoryTotals,
    netIncome: netIncome,
    totalStudents: totalStudents,
    totalDebtors: totalDebtors,
    totalOutstanding: totalOutstanding,
    newIntakeByClass: newIntakeByClass,
    totalNewIntake: totalNewIntake,
    billsPrinted: billsPrinted,
    receiptsPrinted: receiptsPrinted,
    paymentHistoryPrinted: paymentHistoryPrinted,
    reprintsPrinted: reprintsPrinted,
    totalPrints: totalPrints,
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
