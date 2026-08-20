import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';
import '../../data/database_helper_wrapper.dart';
import '../../utils/termly_report_pdf_generator.dart';
import '../../utils/report_data/termly_report_loader.dart';

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
      final r = await loadTermlyReportData();

      activeTerm = r.activeTerm;
      activeSession = r.activeSession;
      school = r.school;

      cashReceived = r.cashReceived;
      posReceived = r.posReceived;
      transferReceived = r.transferReceived;
      totalIncome = r.totalIncome;

      expenseCash = r.expenseCash;
      expensePos = r.expensePos;
      expenseTransfer = r.expenseTransfer;
      totalExpenses = r.totalExpenses;
      expenseCategoryTotals = r.expenseCategoryTotals;

      netIncome = r.netIncome;

      totalStudents = r.totalStudents;
      totalDebtors = r.totalDebtors;
      totalOutstanding = r.totalOutstanding;

      newIntakeByClass = r.newIntakeByClass;
      totalNewIntake = r.totalNewIntake;

      billsPrinted = r.billsPrinted;
      receiptsPrinted = r.receiptsPrinted;
      paymentHistoryPrinted = r.paymentHistoryPrinted;
      reprintsPrinted = r.reprintsPrinted;
      totalPrints = r.totalPrints;

      salesCashTotal = r.salesCashTotal;
      salesPosTotal = r.salesPosTotal;
      salesTransferTotal = r.salesTransferTotal;
      totalSales = r.totalSales;
      totalSalesDebt = r.totalSalesDebt;
      salesDetails = r.salesDetails;
      stockSummary = r.stockSummary;
      salesDebtors = r.salesDebtors;

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
