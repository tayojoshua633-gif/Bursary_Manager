import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';
import '../../data/database_helper_wrapper.dart';
import '../../db/database_helper.dart';
import '../../utils/print_counter_helper.dart';
import '../../utils/termly_report_pdf_generator.dart';

class TermlyReportScreen extends StatefulWidget {
  const TermlyReportScreen({super.key});

  @override
  State<TermlyReportScreen> createState() => _TermlyReportScreenState();
}

class _TermlyReportScreenState extends State<TermlyReportScreen> {
  final DatabaseHelperWrapper db = DatabaseHelperWrapper();

  // Term & Session
  String? activeTerm;
  String? activeSession;
  Map<String, dynamic>? school;

  // Income Report
  double cashReceived = 0;
  double posReceived = 0;
  double transferReceived = 0;
  double totalIncome = 0;

  // Expenses Report
  double expenseCash = 0;
  double expensePos = 0;
  double expenseTransfer = 0;
  double totalExpenses = 0;
  Map<String, double> expenseCategoryTotals = {};

  // Net Income
  double netIncome = 0;

  // Debt Report
  int totalStudents = 0;
  int totalDebtors = 0;
  double totalOutstanding = 0;

  // New Intake Report
  Map<String, int> newIntakeByClass = {};
  int totalNewIntake = 0;

  // Printing Report
  int billsPrinted = 0;
  int receiptsPrinted = 0;
  int paymentHistoryPrinted = 0;
  int reprintsPrinted = 0;
  int totalPrints = 0;

  // Stock & Sales tracking
  List<Map<String, dynamic>> stockSummary = [];
  List<Map<String, dynamic>> salesDetails = [];
  List<Map<String, dynamic>> salesDebtors = [];
  double salesCashTotal = 0;
  double salesPosTotal = 0;
  double salesTransferTotal = 0;
  double totalSales = 0;
  double totalSalesDebt = 0;

  bool loading = false;

  @override
  void initState() {
    super.initState();
    _loadTermlyReport();
  }

  // -----------------------------------------------------------
  // LOAD TERMLY REPORT
  // -----------------------------------------------------------
  Future<void> _loadTermlyReport() async {
    if (!mounted) return;

    setState(() => loading = true);

    try {
      // Step 1: Load term, session, school profile
      activeTerm = await db.getActiveTerm();
      activeSession = (await db.getActiveSession())?['sessionName'];
      school = await db.getSchoolProfile();

      final database = await db.database;

      // Step 2: Income Report (Payment Method Breakdown)
      final paymentsRaw = await database.rawQuery('''
        SELECT method, SUM(amount) as total
        FROM payments
        WHERE term = ? AND session = ?
        GROUP BY method
      ''', [activeTerm, activeSession]);

      cashReceived = 0;
      posReceived = 0;
      transferReceived = 0;

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

      totalIncome = cashReceived + posReceived + transferReceived;

      // Step 3: Expenses Report (Category & Payment Method Breakdown)
      final expensesRaw = await DatabaseHelper().getAllExpenses(
        term: activeTerm,
        session: activeSession,
      );

      expenseCash = 0;
      expensePos = 0;
      expenseTransfer = 0;
      expenseCategoryTotals = {};

      for (var expense in expensesRaw) {
        final amount = (expense['amount'] as num?)?.toDouble() ?? 0.0;
        final method = (expense['paymentMethod'] ?? '').toString().toUpperCase();

        // Track by payment method
        if (method == 'CASH') {
          expenseCash += amount;
        } else if (method == 'POS') {
          expensePos += amount;
        } else if (method == 'TRANSFER' || method == 'BANK TRANSFER') {
          expenseTransfer += amount;
        }

        // Track by category
        final category = expense['category'] ?? 'Uncategorized';
        final customCategory = expense['customCategory'];
        final displayCategory = category == 'Other' && customCategory != null
            ? 'Other: $customCategory'
            : category;

        expenseCategoryTotals[displayCategory] =
            (expenseCategoryTotals[displayCategory] ?? 0) + amount;
      }

      totalExpenses = expenseCash + expensePos + expenseTransfer;

      // Step 4: Net Income Calculation (Include sales in income)
      netIncome = (totalIncome + totalSales) - totalExpenses;

      // Step 5: Debt Report — uses fresh grand total (all prior outstanding + current term fee)
      final targetKey = DatabaseHelperWrapper.termSortKey(activeTerm ?? '', activeSession ?? '');
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

      if (debtQuery.isNotEmpty) {
        final row = debtQuery.first;
        totalStudents = (row['totalStudents'] as int?) ?? 0;
        totalDebtors = (row['totalDebtors'] as int?) ?? 0;
        final totalBills = (row['totalBills'] as num?)?.toDouble() ?? 0.0;
        final totalPayments = (row['totalPayments'] as num?)?.toDouble() ?? 0.0;
        totalOutstanding = totalBills - totalPayments;
      } else {
        totalStudents = 0;
        totalDebtors = 0;
        totalOutstanding = 0.0;
      }

      // Step 6: New Intake Report
      newIntakeByClass = {};
      totalNewIntake = 0;

      // Get all students with bills in current term/session
      final billsRaw = await database.rawQuery('''
        SELECT DISTINCT sb.id, sb.studentId
        FROM student_bills sb
        WHERE sb.term = ? AND sb.session = ?
      ''', [activeTerm, activeSession]);

      for (var billRow in billsRaw) {
        final billId = billRow['id'] as int;
        final studentId = billRow['studentId'] as int;

        // Get bill breakdown
        final breakdown = await db.getBillBreakdown(billId);

        // Check if any fee item contains "registration" or "reg"
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
          // Get student's class via raw query
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

      // Step 7: Thermal Printing Report
      final allHistoricalData = await PrintCounterHelper.getAllHistoricalData();

      billsPrinted = 0;
      receiptsPrinted = 0;
      paymentHistoryPrinted = 0;
      reprintsPrinted = 0;

      for (var dayData in allHistoricalData.values) {
        billsPrinted += dayData['bills'] ?? 0;
        receiptsPrinted += dayData['receipts'] ?? 0;
        paymentHistoryPrinted += dayData['paymentHistory'] ?? 0;
        reprintsPrinted += dayData['receiptReprint'] ?? 0;
      }

      totalPrints = billsPrinted + receiptsPrinted + paymentHistoryPrinted + reprintsPrinted;

      // Step 8: Load Stock & Sales data
      try {
        // Reset stock & sales totals
        salesCashTotal = 0;
        salesPosTotal = 0;
        salesTransferTotal = 0;
        totalSales = 0;
        totalSalesDebt = 0;
        salesDetails = [];
        stockSummary = [];
        salesDebtors = [];

        // Get sales for the term/session - LIMITED to prevent memory exhaustion
        // Only include ORIGINAL sales (quantity > 0), exclude payment receipts (quantity = 0)
        // Use LEFT JOIN to include custom items (stockItemId = 0)
        const int maxSalesRows = 500; // Limit to prevent heap exhaustion
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
          LIMIT $maxSalesRows
        ''', [activeTerm, activeSession]);

        // Group sales by buyer for sales summary
        Map<String, Map<String, dynamic>> salesByBuyer = {};
        Map<int, Map<String, dynamic>> stockMovement = {};

        for (var sale in salesRaw) {
          final qty = (sale['quantity'] as int);

          // Skip payment receipts (quantity = 0)
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

          // Check if this is a custom item (stockItemId = 0 or isCustomItem = 1)
          final isCustomItem = sale['isCustomItem'] == 1 || stockItemId == 0;

          // Track sales by buyer for sales summary
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

          // Track stock movement for stock summary (only for non-custom items)
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

          // Calculate sales payment breakdown
          if (method == 'CASH') {
            salesCashTotal += amountPaid;
          } else if (method == 'POS') {
            salesPosTotal += amountPaid;
          } else if (method == 'TRANSFER' || method == 'BANK TRANSFER') {
            salesTransferTotal += amountPaid;
          }

          totalSales += amountPaid;
        }

        // Convert sales by buyer to list
        salesDetails = salesByBuyer.values.toList();

        // Prepare stock summary - LIMITED to prevent memory exhaustion
        const int maxStockItems = 100;
        final allStockItems = await database.query(
          'stock_items',
          orderBy: 'itemName',
          limit: maxStockItems,
        );

        stockSummary = allStockItems.map((stockItem) {
          final stockItemId = stockItem['id'] as int;
          final itemName = stockItem['itemName']?.toString() ?? 'Unknown';
          final currentQty = (stockItem['currentQuantity'] as int?) ?? 0;

          // Check if this item has sales in the selected period
          final qtySold = stockMovement.containsKey(stockItemId)
              ? (stockMovement[stockItemId]!['qtySold'] as int)
              : 0;

          final beginningQty = currentQty + qtySold; // Current stock + what was sold = beginning stock

          return {
            'itemName': itemName,
            'beginningQuantity': beginningQty,
            'qtySold': qtySold,
            'remainingQuantity': currentQty,
          };
        }).toList();

        // Load sales debtors for the term/session - LIMITED to prevent memory exhaustion
        const int maxDebtors = 50;
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
          LIMIT $maxDebtors
        ''');

        // Process debtors data - check if they had sales in the current term/session
        int debtorsProcessed = 0;
        const int maxDebtorsToProcess = 30; // Limit processing to avoid N+1 query overload
        for (var debtor in debtorsRaw) {
          if (debtorsProcessed >= maxDebtorsToProcess) break;
          final buyerName = debtor['buyerName']?.toString() ?? 'Unknown';
          final buyerType = debtor['buyerType']?.toString() ?? '';

          // Check if this debtor had purchases in the current term/session
          final hasSalesInTerm = await database.rawQuery('''
            SELECT COUNT(*) as count
            FROM sales
            WHERE buyerName = ? AND buyerType = ? AND term = ? AND session = ? AND quantity > 0
          ''', [buyerName, buyerType, activeTerm, activeSession]);

          if ((hasSalesInTerm.first['count'] as int) == 0) {
            continue; // Skip debtors with no purchases in this term
          }

          // Get all items purchased by this debtor in the term/session
          // Use LEFT JOIN to include custom items (stockItemId = 0)
          final debtorSalesRaw = await database.rawQuery('''
            SELECT COALESCE(si.itemName, s.itemName) as itemName, s.quantity, s.stockItemId, s.isCustomItem
            FROM sales s
            LEFT JOIN stock_items si ON s.stockItemId = si.id AND s.stockItemId > 0
            WHERE s.buyerName = ? AND s.buyerType = ? AND s.term = ? AND s.session = ? AND s.quantity > 0
          ''', [buyerName, buyerType, activeTerm, activeSession]);

          final itemsList = debtorSalesRaw.map((item) {
            final itemName = item['itemName']?.toString() ?? '';
            final qty = item['quantity'] as int;
            final isCustomItem = item['isCustomItem'] == 1 || item['stockItemId'] == 0;
            return isCustomItem ? '$itemName [Custom] (x$qty)' : '$itemName (x$qty)';
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
        print('Error loading stock & sales data: $e');

        salesCashTotal = 0;
        salesPosTotal = 0;
        salesTransferTotal = 0;
        totalSales = 0;
        totalSalesDebt = 0;
        salesDetails = [];
        stockSummary = [];
        salesDebtors = [];
      }

      if (mounted) {
        setState(() => loading = false);
      }
    } catch (e) {
      if (mounted) {
        setState(() => loading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading report: $e')),
        );
      }
    }
  }

  // -----------------------------------------------------------
  // EXPORT TERMLY REPORT AS PDF
  // -----------------------------------------------------------
  Future<void> _exportTermlyReportPDF() async {
    try {
      if (!mounted) return;
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => const Center(child: CircularProgressIndicator()),
      );

      // Allow UI to render loading indicator before heavy PDF work
      await Future.delayed(const Duration(milliseconds: 100));

      final filePath = await TermlyReportPDFGenerator.generateTermlyReportPDF(
        term: activeTerm ?? '',
        session: activeSession ?? '',
        schoolProfile: school ?? {},
        cashReceived: cashReceived,
        posReceived: posReceived,
        transferReceived: transferReceived,
        totalIncome: totalIncome,
        expenseCategoryTotals: expenseCategoryTotals,
        expenseCash: expenseCash,
        expensePos: expensePos,
        expenseTransfer: expenseTransfer,
        totalExpenses: totalExpenses,
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

      if (!mounted) return;
      Navigator.pop(context);

      await Share.shareXFiles(
        [XFile(filePath)],
        subject: 'Termly Report - $activeTerm $activeSession',
        text: 'Termly financial report for $activeTerm, $activeSession',
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Termly report PDF exported successfully!')),
      );
    } catch (e) {
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error exporting PDF: $e')),
      );
    }
  }

  // -----------------------------------------------------------
  // UI
  // -----------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("Termly Report - $activeTerm, $activeSession"),
        backgroundColor: Colors.indigo,
        actions: [
          IconButton(
            icon: const Icon(Icons.picture_as_pdf),
            onPressed: _exportTermlyReportPDF,
            tooltip: 'Export PDF',
          ),
        ],
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              physics: const ClampingScrollPhysics(),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    // Header Card
                    Card(
                      elevation: 3,
                      color: Colors.blue.shade50,
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Row(
                          children: [
                            Icon(Icons.assessment, color: Colors.blue.shade700, size: 28),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'TERMLY FINANCIAL REPORT',
                                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'Report for: $activeTerm - $activeSession',
                                    style: TextStyle(fontSize: 14, color: Colors.grey.shade700),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(height: 20),

                    // Income Report Card (School Fees & Office Sales)
                    Card(
                      elevation: 4,
                      color: Colors.green.shade50,
                      child: Padding(
                        padding: const EdgeInsets.all(18),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(Icons.attach_money, color: Colors.green.shade700, size: 28),
                                const SizedBox(width: 8),
                                const Text(
                                  'INCOME REPORT (TOTAL SCHOOL FEES & OFFICE SALES)',
                                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                                ),
                              ],
                            ),
                            const Divider(height: 20),
                            _row("Total Cash Received (School Fees)", "N ${NumberFormat('#,##0.00').format(cashReceived)}"),
                            const SizedBox(height: 5),
                            _row("Total Cash Received (Office Sales)", "₦${NumberFormat('#,##0.00').format(salesCashTotal)}"),
                            const SizedBox(height: 10),
                            _row("Total POS Received (School Fees)", "N ${NumberFormat('#,##0.00').format(posReceived)}"),
                            const SizedBox(height: 5),
                            _row("Total POS Received (Office Sales)", "₦${NumberFormat('#,##0.00').format(salesPosTotal)}"),
                            const SizedBox(height: 10),
                            _row("Total Transfer Received (School Fees)", "N ${NumberFormat('#,##0.00').format(transferReceived)}"),
                            const SizedBox(height: 5),
                            _row("Total Transfer Received (Office Sales)", "₦${NumberFormat('#,##0.00').format(salesTransferTotal)}"),
                            const Divider(height: 25),
                            _row(
                              "TOTAL INCOME",
                              "N ${NumberFormat('#,##0.00').format(totalIncome + totalSales)}",
                              bold: true,
                              color: Colors.green.shade800,
                            ),
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(height: 20),

                    // Expenses Report Card
                    Card(
                      elevation: 4,
                      color: Colors.orange.shade50,
                      child: Padding(
                        padding: const EdgeInsets.all(18),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(Icons.receipt_long, color: Colors.orange.shade800, size: 28),
                                const SizedBox(width: 8),
                                const Text(
                                  'EXPENSES REPORT',
                                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                                ),
                              ],
                            ),
                            const Divider(height: 20),

                            // Category breakdown
                            if (expenseCategoryTotals.isNotEmpty) ...[
                              Text(
                                'By Category:',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.grey.shade700,
                                ),
                              ),
                              const SizedBox(height: 10),
                              ...expenseCategoryTotals.entries.map((entry) {
                                return Padding(
                                  padding: const EdgeInsets.only(bottom: 8),
                                  child: _row(
                                    entry.key,
                                    "N ${NumberFormat('#,##0.00').format(entry.value)}",
                                  ),
                                );
                              }),
                              const Divider(height: 20),
                            ],

                            // Payment method breakdown
                            Text(
                              'By Payment Method:',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: Colors.grey.shade700,
                              ),
                            ),
                            const SizedBox(height: 10),
                            _row("Cash Paid", "N ${NumberFormat('#,##0.00').format(expenseCash)}"),
                            const SizedBox(height: 10),
                            _row("POS Paid", "N ${NumberFormat('#,##0.00').format(expensePos)}"),
                            const SizedBox(height: 10),
                            _row("Transfers Paid", "N ${NumberFormat('#,##0.00').format(expenseTransfer)}"),
                            const Divider(height: 25),
                            _row(
                              "TOTAL EXPENSES",
                              "N ${NumberFormat('#,##0.00').format(totalExpenses)}",
                              bold: true,
                              color: Colors.red.shade800,
                            ),
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(height: 20),

                    // Net Income Card
                    Card(
                      elevation: 5,
                      child: Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.blue.shade400, width: 2),
                          borderRadius: BorderRadius.circular(12),
                          color: Colors.blue.shade50,
                        ),
                        child: Row(
                          children: [
                            Icon(
                              netIncome >= 0 ? Icons.trending_up : Icons.trending_down,
                              color: netIncome >= 0 ? Colors.green.shade700 : Colors.red.shade700,
                              size: 32,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: _row(
                                "NET INCOME (Income - Expenses)",
                                "N ${NumberFormat('#,##0.00').format(netIncome)}",
                                bold: true,
                                color: netIncome >= 0 ? Colors.green.shade800 : Colors.red.shade800,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(height: 20),

                    // Debt Report Card
                    Card(
                      elevation: 4,
                      color: Colors.red.shade50,
                      child: Padding(
                        padding: const EdgeInsets.all(18),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(Icons.warning_amber, color: Colors.red.shade700, size: 28),
                                const SizedBox(width: 8),
                                const Text(
                                  'DEBT REPORT',
                                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                                ),
                              ],
                            ),
                            const Divider(height: 20),
                            _row("Total Students", "$totalStudents"),
                            const SizedBox(height: 10),
                            _row("Total Debtors", "$totalDebtors", color: Colors.red.shade700),
                            const SizedBox(height: 10),
                            _row(
                              "Total Outstanding Debt",
                              "N ${NumberFormat('#,##0.00').format(totalOutstanding)}",
                              bold: true,
                              color: Colors.red.shade800,
                            ),
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(height: 20),

                    // New Intake Report Card
                    Card(
                      elevation: 4,
                      color: Colors.purple.shade50,
                      child: Padding(
                        padding: const EdgeInsets.all(18),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(Icons.person_add, color: Colors.purple.shade700, size: 28),
                                const SizedBox(width: 8),
                                const Text(
                                  'NEW INTAKE REPORT',
                                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Students with Registration Fees',
                              style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
                            ),
                            const Divider(height: 20),

                            if (newIntakeByClass.isEmpty)
                              Center(
                                child: Padding(
                                  padding: const EdgeInsets.all(16),
                                  child: Text(
                                    "No new students registered this term",
                                    style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
                                  ),
                                ),
                              )
                            else ...[
                              ...newIntakeByClass.entries.map((entry) {
                                return Padding(
                                  padding: const EdgeInsets.only(bottom: 8),
                                  child: _row(entry.key, "${entry.value} students"),
                                );
                              }),
                              const Divider(height: 25),
                              _row(
                                "TOTAL NEW INTAKE",
                                "$totalNewIntake",
                                bold: true,
                                color: Colors.purple.shade800,
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(height: 20),

                    // Thermal Printing Report Card
                    Card(
                      elevation: 4,
                      color: Colors.cyan.shade50,
                      child: Padding(
                        padding: const EdgeInsets.all(18),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(Icons.print, color: Colors.cyan.shade700, size: 28),
                                const SizedBox(width: 8),
                                const Text(
                                  'THERMAL PRINTING REPORT',
                                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'All-time Statistics',
                              style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
                            ),
                            const Divider(height: 20),
                            _row("Bills Printed", "$billsPrinted"),
                            const SizedBox(height: 10),
                            _row("Receipts Printed", "$receiptsPrinted"),
                            const SizedBox(height: 10),
                            _row("Payment History Printed", "$paymentHistoryPrinted"),
                            const SizedBox(height: 10),
                            _row("Reprints", "$reprintsPrinted"),
                            const Divider(height: 25),
                            _row(
                              "TOTAL PRINTS",
                              "$totalPrints",
                              bold: true,
                              color: Colors.cyan.shade800,
                            ),
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(height: 20),

                    // Stock Summary Card
                    if (stockSummary.isNotEmpty)
                      Card(
                        elevation: 4,
                        color: Colors.brown.shade50,
                        child: Padding(
                          padding: const EdgeInsets.all(18),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Icon(Icons.inventory_outlined, color: Colors.brown.shade700, size: 28),
                                  const SizedBox(width: 8),
                                  const Text(
                                    'STOCK SUMMARY',
                                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Stock Movement for the Term',
                                style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
                              ),
                              const Divider(height: 20),
                              // Stock table
                              SingleChildScrollView(
                                scrollDirection: Axis.horizontal,
                                child: DataTable(
                                  columnSpacing: 20,
                                  headingRowColor: WidgetStateColor.resolveWith(
                                    (states) => Colors.brown.shade100,
                                  ),
                                  columns: const [
                                    DataColumn(label: Text('Item', style: TextStyle(fontWeight: FontWeight.bold))),
                                    DataColumn(label: Text('Beginning', style: TextStyle(fontWeight: FontWeight.bold)), numeric: true),
                                    DataColumn(label: Text('Sold', style: TextStyle(fontWeight: FontWeight.bold)), numeric: true),
                                    DataColumn(label: Text('Remaining', style: TextStyle(fontWeight: FontWeight.bold)), numeric: true),
                                  ],
                                  rows: stockSummary.map((stock) {
                                    return DataRow(cells: [
                                      DataCell(Text(stock['itemName'])),
                                      DataCell(Text('${stock['beginningQuantity']}')),
                                      DataCell(Text('${stock['qtySold']}', style: const TextStyle(color: Colors.red))),
                                      DataCell(Text('${stock['remainingQuantity']}')),
                                    ]);
                                  }).toList(),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),

                    if (stockSummary.isNotEmpty) const SizedBox(height: 20),

                    // Sales Summary Report Card
                    if (salesDetails.isNotEmpty)
                      Card(
                        elevation: 4,
                        color: Colors.teal.shade50,
                        child: Padding(
                          padding: const EdgeInsets.all(18),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Icon(Icons.point_of_sale_outlined, color: Colors.teal.shade700, size: 28),
                                  const SizedBox(width: 8),
                                  const Text(
                                    'SALES SUMMARY REPORT',
                                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                                  ),
                                ],
                              ),
                              const Divider(height: 20),
                              // Sales table grouped by items
                              SingleChildScrollView(
                                scrollDirection: Axis.horizontal,
                                child: DataTable(
                                  columnSpacing: 30,
                                  headingRowColor: WidgetStateColor.resolveWith(
                                    (states) => Colors.teal.shade100,
                                  ),
                                  columns: const [
                                    DataColumn(label: Text('S/N', style: TextStyle(fontWeight: FontWeight.bold))),
                                    DataColumn(label: Text('Items', style: TextStyle(fontWeight: FontWeight.bold))),
                                    DataColumn(label: Text('Qty Sold', style: TextStyle(fontWeight: FontWeight.bold)), numeric: true),
                                    DataColumn(label: Text('Total Amount', style: TextStyle(fontWeight: FontWeight.bold)), numeric: true),
                                  ],
                                  rows: () {
                                    // Group sales by item
                                    Map<String, Map<String, dynamic>> itemsSummary = {};

                                    for (var sale in salesDetails) {
                                      final items = sale['items'] as List<Map<String, dynamic>>;
                                      for (var item in items) {
                                        final baseItemName = item['itemName'];
                                        final isCustomItem = item['isCustomItem'] == true;
                                        // Add [Custom] suffix for custom items
                                        final itemName = isCustomItem ? '$baseItemName [Custom]' : baseItemName;
                                        final qty = item['quantity'] as int;
                                        final unitPrice = item['unitPrice'] as double;
                                        final amount = qty * unitPrice;

                                        if (!itemsSummary.containsKey(itemName)) {
                                          itemsSummary[itemName] = {
                                            'itemName': itemName,
                                            'qtySold': 0,
                                            'totalAmount': 0.0,
                                          };
                                        }

                                        itemsSummary[itemName]!['qtySold'] += qty;
                                        itemsSummary[itemName]!['totalAmount'] += amount;
                                      }
                                    }

                                    // Convert to list and create rows
                                    final itemsList = itemsSummary.values.toList();
                                    return itemsList.asMap().entries.map((entry) {
                                      final index = entry.key;
                                      final item = entry.value;
                                      return DataRow(cells: [
                                        DataCell(Text('${index + 1}')),
                                        DataCell(Text(item['itemName'])),
                                        DataCell(Text('${item['qtySold']}')),
                                        DataCell(Text('₦${NumberFormat('#,##0.00').format(item['totalAmount'])}')),
                                      ]);
                                    }).toList();
                                  }(),
                                ),
                              ),
                              const Divider(height: 20),
                              _row(
                                "TOTAL SALES",
                                "₦${NumberFormat('#,##0.00').format(totalSales)}",
                                bold: true,
                                color: Colors.teal.shade800,
                              ),
                            ],
                          ),
                        ),
                      ),

                    if (salesDetails.isNotEmpty) const SizedBox(height: 20),

                    // Sales Debtors Card
                    if (salesDebtors.isNotEmpty)
                      Card(
                        elevation: 4,
                        color: Colors.red.shade50,
                        child: Padding(
                          padding: const EdgeInsets.all(18),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Icon(Icons.account_balance_wallet_outlined, color: Colors.red.shade700, size: 28),
                                  const SizedBox(width: 8),
                                  const Text(
                                    'SALES DEBTORS',
                                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Buyers with Outstanding Balances',
                                style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
                              ),
                              const Divider(height: 20),
                              // Debtors table
                              SingleChildScrollView(
                                scrollDirection: Axis.horizontal,
                                child: DataTable(
                                  columnSpacing: 15,
                                  headingRowColor: WidgetStateColor.resolveWith(
                                    (states) => Colors.red.shade100,
                                  ),
                                  columns: const [
                                    DataColumn(label: Text('Buyer', style: TextStyle(fontWeight: FontWeight.bold))),
                                    DataColumn(label: Text('Items', style: TextStyle(fontWeight: FontWeight.bold))),
                                    DataColumn(label: Text('Total', style: TextStyle(fontWeight: FontWeight.bold)), numeric: true),
                                    DataColumn(label: Text('Paid', style: TextStyle(fontWeight: FontWeight.bold)), numeric: true),
                                    DataColumn(label: Text('Balance', style: TextStyle(fontWeight: FontWeight.bold)), numeric: true),
                                  ],
                                  rows: salesDebtors.map((debtor) {
                                    return DataRow(cells: [
                                      DataCell(Text('${debtor['buyerName']}${debtor['buyerType'].isNotEmpty ? '\n(${debtor['buyerType']})' : ''}')),
                                      DataCell(
                                        SizedBox(
                                          width: 150,
                                          child: Text(
                                            debtor['itemsPurchased'],
                                            style: const TextStyle(fontSize: 12),
                                            overflow: TextOverflow.ellipsis,
                                            maxLines: 2,
                                          ),
                                        ),
                                      ),
                                      DataCell(Text('₦${NumberFormat('#,##0.00').format(debtor['totalAmount'])}')),
                                      DataCell(Text('₦${NumberFormat('#,##0.00').format(debtor['totalPaid'])}')),
                                      DataCell(
                                        Text(
                                          '₦${NumberFormat('#,##0.00').format(debtor['outstandingBalance'])}',
                                          style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
                                        ),
                                      ),
                                    ]);
                                  }).toList(),
                                ),
                              ),
                              const Divider(height: 20),
                              _row(
                                "TOTAL SALES DEBT",
                                "₦${NumberFormat('#,##0.00').format(totalSalesDebt)}",
                                bold: true,
                                color: Colors.red.shade800,
                              ),
                            ],
                          ),
                        ),
                      ),

                    if (salesDebtors.isNotEmpty) const SizedBox(height: 30),

                    if (salesDebtors.isEmpty && totalSales == 0 && stockSummary.isEmpty)
                      const SizedBox(height: 30),

                    // Export Button
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: _exportTermlyReportPDF,
                        icon: const Icon(Icons.picture_as_pdf, size: 24),
                        label: const Text(
                          'Export PDF Report',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.red.shade700,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          elevation: 3,
                        ),
                      ),
                    ),

                    const SizedBox(height: 20),
                  ],
                ),
              ),
            ),
    );
  }

  // -----------------------------------------------------------
  // ROW BUILDER
  // -----------------------------------------------------------
  Widget _row(
    String label,
    String value, {
    bool bold = false,
    Color color = Colors.black,
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              fontSize: 16,
              fontWeight: bold ? FontWeight.bold : FontWeight.w500,
            ),
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: 17,
            fontWeight: bold ? FontWeight.bold : FontWeight.normal,
            color: color,
          ),
        ),
      ],
    );
  }
}
