import 'dart:io';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:path_provider/path_provider.dart';
import 'package:intl/intl.dart';

class TermlyReportPDFGenerator {
  static Future<String> generateTermlyReportPDF({
    required String term,
    required String session,
    required Map<String, dynamic> schoolProfile,
    // Income data
    required double cashReceived,
    required double posReceived,
    required double transferReceived,
    required double totalIncome,
    // Expenses data
    required Map<String, double> expenseCategoryTotals,
    required double expenseCash,
    required double expensePos,
    required double expenseTransfer,
    required double totalExpenses,
    // Net income
    required double netIncome,
    // Debt data
    required int totalStudents,
    required int totalDebtors,
    required double totalOutstanding,
    // New intake data
    required Map<String, int> newIntakeByClass,
    required int totalNewIntake,
    // Printing data
    required int billsPrinted,
    required int receiptsPrinted,
    required int paymentHistoryPrinted,
    required int reprintsPrinted,
    required int totalPrints,
    // Stock & Sales data
    required List<Map<String, dynamic>> stockSummary,
    required List<Map<String, dynamic>> salesDetails,
    required List<Map<String, dynamic>> salesDebtors,
    required double salesCashTotal,
    required double salesPosTotal,
    required double salesTransferTotal,
    required double totalSales,
    required double totalSalesDebt,
  }) async {
    final pdf = pw.Document();
    final formatter = NumberFormat('#,##0.00');

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(40),
        build: (context) => [
          // Header
          _buildHeader(schoolProfile, term, session),
          pw.SizedBox(height: 25),

          // Income Section
          _buildIncomeSection(
            cashReceived,
            posReceived,
            transferReceived,
            totalIncome,
            formatter,
            salesCashTotal,
            salesPosTotal,
            salesTransferTotal,
            totalSales,
          ),
          pw.SizedBox(height: 20),

          // Expenses Section
          _buildExpensesSection(
            expenseCategoryTotals,
            expenseCash,
            expensePos,
            expenseTransfer,
            totalExpenses,
            formatter,
          ),
          pw.SizedBox(height: 20),

          // Net Income Section
          _buildNetIncomeSection(netIncome, formatter),
          pw.SizedBox(height: 20),

          // Debt Section
          _buildDebtSection(
            totalStudents,
            totalDebtors,
            totalOutstanding,
            formatter,
          ),
          pw.SizedBox(height: 20),

          // New Intake Section
          _buildNewIntakeSection(newIntakeByClass, totalNewIntake),
          pw.SizedBox(height: 20),

          // Printing Section
          _buildPrintingSection(
            billsPrinted,
            receiptsPrinted,
            paymentHistoryPrinted,
            reprintsPrinted,
            totalPrints,
          ),

          // Stock & Sales Sections
          if (stockSummary.isNotEmpty) ...[
            pw.SizedBox(height: 20),
            _buildStockSummarySection(stockSummary),
          ],

          if (salesDetails.isNotEmpty) ...[
            pw.SizedBox(height: 20),
            _buildSalesSummarySection(salesDetails, formatter),
          ],

          if (salesDebtors.isNotEmpty) ...[
            pw.SizedBox(height: 20),
            _buildSalesDebtorsSection(salesDebtors, totalSalesDebt, formatter),
          ],

          pw.SizedBox(height: 20),

          // Bank Details
          _buildBankDetails(schoolProfile),
          pw.SizedBox(height: 30),
          _buildFooter(),
        ],
        footer: (context) => _buildPageFooter(context),
      ),
    );

    // Save file
    final dir = await getApplicationDocumentsDirectory();
    final timestamp = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
    final fileName = 'Termly_Report_${term.replaceAll(' ', '_')}_${session.replaceAll('/', '_')}_$timestamp.pdf';
    final file = File('${dir.path}/$fileName');
    await file.writeAsBytes(await pdf.save());

    return file.path;
  }

  // -----------------------------------------------------------
  // HEADER
  // -----------------------------------------------------------
  static pw.Widget _buildHeader(
    Map<String, dynamic> schoolProfile,
    String term,
    String session,
  ) {
    final schoolName = schoolProfile['name'] ?? 'School Name';
    final address = schoolProfile['address'] ?? '';
    final phone = schoolProfile['phone'] ?? '';
    final email = schoolProfile['email'] ?? '';

    return pw.Column(
      children: [
        // School Name
        pw.Text(
          schoolName.toUpperCase(),
          style: pw.TextStyle(fontSize: 22, fontWeight: pw.FontWeight.bold, color: PdfColors.indigo700),
          textAlign: pw.TextAlign.center,
        ),
        if (address.isNotEmpty) ...[
          pw.SizedBox(height: 4),
          pw.Text(address, style: const pw.TextStyle(fontSize: 10), textAlign: pw.TextAlign.center),
        ],
        if (phone.isNotEmpty || email.isNotEmpty) ...[
          pw.SizedBox(height: 4),
          pw.Text(
            [if (phone.isNotEmpty) 'Tel: $phone', if (email.isNotEmpty) email].join(' | '),
            style: const pw.TextStyle(fontSize: 9),
            textAlign: pw.TextAlign.center,
          ),
        ],
        pw.SizedBox(height: 15),
        pw.Divider(thickness: 2),
        pw.SizedBox(height: 15),

        // Report Title
        pw.Text(
          'TERMLY FINANCIAL REPORT',
          style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold),
          textAlign: pw.TextAlign.center,
        ),
        pw.SizedBox(height: 8),

        // Period Info
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.center,
          children: [
            pw.Text('Term: $term', style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(width: 20),
            pw.Text('Session: $session', style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
          ],
        ),
        pw.SizedBox(height: 6),
        pw.Text(
          'Generated: ${DateFormat('MMMM d, yyyy - h:mm a').format(DateTime.now())}',
          style: pw.TextStyle(fontSize: 9, color: PdfColors.grey700),
          textAlign: pw.TextAlign.center,
        ),
      ],
    );
  }

  // -----------------------------------------------------------
  // INCOME SECTION
  // -----------------------------------------------------------
  static pw.Widget _buildIncomeSection(
    double cashReceived,
    double posReceived,
    double transferReceived,
    double totalIncome,
    NumberFormat formatter,
    double salesCashTotal,
    double salesPosTotal,
    double salesTransferTotal,
    double totalSales,
  ) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          'INCOME REPORT (TOTAL SCHOOL FEES & OFFICE SALES)',
          style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold, color: PdfColors.green700),
        ),
        pw.SizedBox(height: 10),

        pw.Container(
          padding: const pw.EdgeInsets.all(15),
          decoration: pw.BoxDecoration(
            border: pw.Border.all(color: PdfColors.green400),
            borderRadius: const pw.BorderRadius.all(pw.Radius.circular(5)),
            color: PdfColors.green50,
          ),
          child: pw.Column(
            children: [
              _buildRow('Total Cash Received (School Fees):', 'N ${formatter.format(cashReceived)}'),
              pw.SizedBox(height: 5),
              _buildRow('Total Cash Received (Office Sales):', '₦${formatter.format(salesCashTotal)}'),
              pw.SizedBox(height: 10),
              _buildRow('Total POS Received (School Fees):', 'N ${formatter.format(posReceived)}'),
              pw.SizedBox(height: 5),
              _buildRow('Total POS Received (Office Sales):', '₦${formatter.format(salesPosTotal)}'),
              pw.SizedBox(height: 10),
              _buildRow('Total Transfer Received (School Fees):', 'N ${formatter.format(transferReceived)}'),
              pw.SizedBox(height: 5),
              _buildRow('Total Transfer Received (Office Sales):', '₦${formatter.format(salesTransferTotal)}'),
              pw.Divider(height: 16, thickness: 1.5, color: PdfColors.green400),
              _buildRow(
                'TOTAL INCOME:',
                'N ${formatter.format(totalIncome + totalSales)}',
                bold: true,
                fontSize: 14,
              ),
            ],
          ),
        ),
      ],
    );
  }

  // -----------------------------------------------------------
  // EXPENSES SECTION
  // -----------------------------------------------------------
  static pw.Widget _buildExpensesSection(
    Map<String, double> expenseCategoryTotals,
    double expenseCash,
    double expensePos,
    double expenseTransfer,
    double totalExpenses,
    NumberFormat formatter,
  ) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          'EXPENSES REPORT',
          style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold, color: PdfColors.orange800),
        ),
        pw.SizedBox(height: 10),

        pw.Container(
          padding: const pw.EdgeInsets.all(15),
          decoration: pw.BoxDecoration(
            border: pw.Border.all(color: PdfColors.orange400),
            borderRadius: const pw.BorderRadius.all(pw.Radius.circular(5)),
            color: PdfColors.orange50,
          ),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              // Category Breakdown
              if (expenseCategoryTotals.isNotEmpty) ...[
                pw.Text(
                  'By Category:',
                  style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold),
                ),
                pw.SizedBox(height: 8),
                ...expenseCategoryTotals.entries.map((entry) {
                  return pw.Padding(
                    padding: const pw.EdgeInsets.only(bottom: 6),
                    child: _buildRow(entry.key, 'N ${formatter.format(entry.value)}'),
                  );
                }),
                pw.SizedBox(height: 12),
                pw.Divider(height: 16, thickness: 1, color: PdfColors.orange300),
                pw.SizedBox(height: 8),
              ],

              // Payment Method Breakdown
              pw.Text(
                'By Payment Method:',
                style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold),
              ),
              pw.SizedBox(height: 8),
              _buildRow('Cash Paid:', 'N ${formatter.format(expenseCash)}'),
              pw.SizedBox(height: 6),
              _buildRow('POS Paid:', 'N ${formatter.format(expensePos)}'),
              pw.SizedBox(height: 6),
              _buildRow('Transfers Paid:', 'N ${formatter.format(expenseTransfer)}'),
              pw.Divider(height: 16, thickness: 1.5, color: PdfColors.orange400),
              _buildRow(
                'TOTAL EXPENSES:',
                'N ${formatter.format(totalExpenses)}',
                bold: true,
                fontSize: 14,
              ),
            ],
          ),
        ),
      ],
    );
  }

  // -----------------------------------------------------------
  // NET INCOME SECTION
  // -----------------------------------------------------------
  static pw.Widget _buildNetIncomeSection(
    double netIncome,
    NumberFormat formatter,
  ) {
    final isPositive = netIncome >= 0;
    return pw.Container(
      padding: const pw.EdgeInsets.all(18),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.blue400, width: 2),
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(5)),
        color: PdfColors.blue50,
      ),
      child: pw.Column(
        children: [
          pw.Text(
            'NET INCOME',
            style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 10),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text(
                'Income - Expenses:',
                style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold),
              ),
              pw.Text(
                'N ${formatter.format(netIncome)}',
                style: pw.TextStyle(
                  fontSize: 16,
                  fontWeight: pw.FontWeight.bold,
                  color: isPositive ? PdfColors.green800 : PdfColors.red800,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // -----------------------------------------------------------
  // DEBT SECTION
  // -----------------------------------------------------------
  static pw.Widget _buildDebtSection(
    int totalStudents,
    int totalDebtors,
    double totalOutstanding,
    NumberFormat formatter,
  ) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          'DEBT REPORT',
          style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold, color: PdfColors.red700),
        ),
        pw.SizedBox(height: 10),

        pw.Container(
          padding: const pw.EdgeInsets.all(15),
          decoration: pw.BoxDecoration(
            border: pw.Border.all(color: PdfColors.red400),
            borderRadius: const pw.BorderRadius.all(pw.Radius.circular(5)),
            color: PdfColors.red50,
          ),
          child: pw.Column(
            children: [
              _buildRow('Total Students:', '$totalStudents'),
              pw.SizedBox(height: 8),
              _buildRow('Total Debtors:', '$totalDebtors'),
              pw.SizedBox(height: 8),
              _buildRow(
                'Total Outstanding Debt:',
                'N ${formatter.format(totalOutstanding)}',
                bold: true,
                fontSize: 13,
              ),
            ],
          ),
        ),
      ],
    );
  }

  // -----------------------------------------------------------
  // NEW INTAKE SECTION
  // -----------------------------------------------------------
  static pw.Widget _buildNewIntakeSection(
    Map<String, int> newIntakeByClass,
    int totalNewIntake,
  ) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          'NEW INTAKE REPORT',
          style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold, color: PdfColors.purple700),
        ),
        pw.SizedBox(height: 6),
        pw.Text(
          'Students with Registration Fees',
          style: pw.TextStyle(fontSize: 10, color: PdfColors.grey700),
        ),
        pw.SizedBox(height: 10),

        pw.Container(
          padding: const pw.EdgeInsets.all(15),
          decoration: pw.BoxDecoration(
            border: pw.Border.all(color: PdfColors.purple400),
            borderRadius: const pw.BorderRadius.all(pw.Radius.circular(5)),
            color: PdfColors.purple50,
          ),
          child: pw.Column(
            children: [
              if (newIntakeByClass.isEmpty)
                pw.Center(
                  child: pw.Text(
                    'No new students registered this term',
                    style: pw.TextStyle(fontSize: 11, color: PdfColors.grey700),
                  ),
                )
              else ...[
                ...newIntakeByClass.entries.map((entry) {
                  return pw.Padding(
                    padding: const pw.EdgeInsets.only(bottom: 6),
                    child: _buildRow(entry.key, '${entry.value} students'),
                  );
                }),
                pw.Divider(height: 16, thickness: 1.5, color: PdfColors.purple400),
                _buildRow(
                  'TOTAL NEW INTAKE:',
                  '$totalNewIntake',
                  bold: true,
                  fontSize: 13,
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  // -----------------------------------------------------------
  // PRINTING SECTION
  // -----------------------------------------------------------
  static pw.Widget _buildPrintingSection(
    int billsPrinted,
    int receiptsPrinted,
    int paymentHistoryPrinted,
    int reprintsPrinted,
    int totalPrints,
  ) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          'THERMAL PRINTING REPORT',
          style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold, color: PdfColors.cyan700),
        ),
        pw.SizedBox(height: 6),
        pw.Text(
          'All-time Statistics',
          style: pw.TextStyle(fontSize: 10, color: PdfColors.grey700),
        ),
        pw.SizedBox(height: 10),

        pw.Container(
          padding: const pw.EdgeInsets.all(15),
          decoration: pw.BoxDecoration(
            border: pw.Border.all(color: PdfColors.cyan400),
            borderRadius: const pw.BorderRadius.all(pw.Radius.circular(5)),
            color: PdfColors.cyan50,
          ),
          child: pw.Column(
            children: [
              _buildRow('Bills Printed:', '$billsPrinted'),
              pw.SizedBox(height: 6),
              _buildRow('Receipts Printed:', '$receiptsPrinted'),
              pw.SizedBox(height: 6),
              _buildRow('Payment History Printed:', '$paymentHistoryPrinted'),
              pw.SizedBox(height: 6),
              _buildRow('Reprints:', '$reprintsPrinted'),
              pw.Divider(height: 16, thickness: 1.5, color: PdfColors.cyan400),
              _buildRow(
                'TOTAL PRINTS:',
                '$totalPrints',
                bold: true,
                fontSize: 13,
              ),
            ],
          ),
        ),
      ],
    );
  }

  // -----------------------------------------------------------
  // STOCK SUMMARY SECTION
  // -----------------------------------------------------------
  static pw.Widget _buildStockSummarySection(
    List<Map<String, dynamic>> stockSummary,
  ) {
    // Limit to 50 rows to prevent memory exhaustion
    const maxRows = 50;
    final limitedStock = stockSummary.length > maxRows
        ? stockSummary.sublist(0, maxRows)
        : stockSummary;
    final isTruncated = stockSummary.length > maxRows;

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          'STOCK SUMMARY',
          style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold, color: PdfColors.brown700),
        ),
        pw.SizedBox(height: 6),
        pw.Text(
          'Stock Movement for the Term${isTruncated ? ' (showing first $maxRows of ${stockSummary.length} items)' : ''}',
          style: pw.TextStyle(fontSize: 10, color: PdfColors.grey700),
        ),
        pw.SizedBox(height: 10),

        pw.Container(
          padding: const pw.EdgeInsets.all(12),
          decoration: pw.BoxDecoration(
            border: pw.Border.all(color: PdfColors.brown400),
            borderRadius: const pw.BorderRadius.all(pw.Radius.circular(5)),
            color: PdfColors.brown50,
          ),
          child: pw.TableHelper.fromTextArray(
            headerStyle: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold),
            cellStyle: const pw.TextStyle(fontSize: 10),
            headerDecoration: pw.BoxDecoration(color: PdfColors.brown100),
            cellHeight: 25,
            cellAlignments: {
              0: pw.Alignment.centerLeft,
              1: pw.Alignment.centerRight,
              2: pw.Alignment.centerRight,
              3: pw.Alignment.centerRight,
            },
            headers: ['Item', 'Beginning', 'Sold', 'Remaining'],
            data: limitedStock.map((stock) {
              return [
                stock['itemName'],
                '${stock['beginningQuantity']}',
                '${stock['qtySold']}',
                '${stock['remainingQuantity']}',
              ];
            }).toList(),
          ),
        ),
      ],
    );
  }

  // -----------------------------------------------------------
  // SALES SUMMARY SECTION
  // -----------------------------------------------------------
  static pw.Widget _buildSalesSummarySection(
    List<Map<String, dynamic>> salesDetails,
    NumberFormat formatter,
  ) {
    // Limit salesDetails processing to prevent memory exhaustion
    const maxSalesEntries = 100;
    final limitedSalesDetails = salesDetails.length > maxSalesEntries
        ? salesDetails.sublist(0, maxSalesEntries)
        : salesDetails;

    // Group sales by item
    Map<String, Map<String, dynamic>> itemsSummary = {};

    for (var sale in limitedSalesDetails) {
      final items = sale['items'] as List<Map<String, dynamic>>? ?? [];
      for (var item in items) {
        final baseItemName = item['itemName'] ?? 'Unknown';
        final isCustomItem = item['isCustomItem'] == true;
        // Add [Custom] suffix for custom items
        final itemName = isCustomItem ? '$baseItemName [Custom]' : baseItemName;
        final qty = (item['quantity'] as int?) ?? 0;
        final unitPrice = (item['unitPrice'] as double?) ?? 0.0;
        final amount = qty * unitPrice;

        if (!itemsSummary.containsKey(itemName)) {
          itemsSummary[itemName] = {
            'itemName': itemName,
            'qtySold': 0,
            'totalAmount': 0.0,
          };
        }

        itemsSummary[itemName]!['qtySold'] = (itemsSummary[itemName]!['qtySold'] as int) + qty;
        itemsSummary[itemName]!['totalAmount'] = (itemsSummary[itemName]!['totalAmount'] as double) + amount;
      }
    }

    // Limit items summary to 50 rows for the table
    const maxRows = 50;
    final itemsList = itemsSummary.values.toList();
    final limitedItems = itemsList.length > maxRows ? itemsList.sublist(0, maxRows) : itemsList;
    final isTruncated = itemsList.length > maxRows || salesDetails.length > maxSalesEntries;

    // Calculate total sales (from all items, not just limited)
    double totalSalesAmount = itemsSummary.values.fold(0.0, (sum, item) => sum + (item['totalAmount'] as double));

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          'SALES SUMMARY REPORT',
          style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold, color: PdfColors.teal700),
        ),
        if (isTruncated)
          pw.Padding(
            padding: const pw.EdgeInsets.only(top: 4),
            child: pw.Text(
              '(Showing first $maxRows items)',
              style: pw.TextStyle(fontSize: 9, color: PdfColors.grey700),
            ),
          ),
        pw.SizedBox(height: 10),

        pw.Container(
          padding: const pw.EdgeInsets.all(12),
          decoration: pw.BoxDecoration(
            border: pw.Border.all(color: PdfColors.teal400),
            borderRadius: const pw.BorderRadius.all(pw.Radius.circular(5)),
            color: PdfColors.teal50,
          ),
          child: pw.Column(
            children: [
              pw.TableHelper.fromTextArray(
                headerStyle: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold),
                cellStyle: const pw.TextStyle(fontSize: 10),
                headerDecoration: pw.BoxDecoration(color: PdfColors.teal100),
                cellHeight: 25,
                cellAlignments: {
                  0: pw.Alignment.center,
                  1: pw.Alignment.centerLeft,
                  2: pw.Alignment.centerRight,
                  3: pw.Alignment.centerRight,
                },
                headers: ['S/N', 'Items', 'Qty Sold', 'Total Amount'],
                data: limitedItems.asMap().entries.map((entry) {
                  final index = entry.key;
                  final item = entry.value;
                  return [
                    '${index + 1}',
                    item['itemName'],
                    '${item['qtySold']}',
                    '₦${formatter.format(item['totalAmount'])}',
                  ];
                }).toList(),
              ),
              pw.SizedBox(height: 10),
              pw.Divider(thickness: 1.5, color: PdfColors.teal400),
              pw.SizedBox(height: 6),
              _buildRow(
                'TOTAL SALES:',
                '₦${formatter.format(totalSalesAmount)}',
                bold: true,
                fontSize: 13,
              ),
            ],
          ),
        ),
      ],
    );
  }

  // -----------------------------------------------------------
  // SALES DEBTORS SECTION
  // -----------------------------------------------------------
  static pw.Widget _buildSalesDebtorsSection(
    List<Map<String, dynamic>> salesDebtors,
    double totalSalesDebt,
    NumberFormat formatter,
  ) {
    // Limit to 50 rows to prevent memory exhaustion
    const maxRows = 50;
    final limitedDebtors = salesDebtors.length > maxRows
        ? salesDebtors.sublist(0, maxRows)
        : salesDebtors;
    final isTruncated = salesDebtors.length > maxRows;

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          'SALES DEBTORS',
          style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold, color: PdfColors.red700),
        ),
        pw.SizedBox(height: 6),
        pw.Text(
          'Buyers with Outstanding Balances${isTruncated ? ' (showing first $maxRows of ${salesDebtors.length})' : ''}',
          style: pw.TextStyle(fontSize: 10, color: PdfColors.grey700),
        ),
        pw.SizedBox(height: 10),

        pw.Container(
          padding: const pw.EdgeInsets.all(12),
          decoration: pw.BoxDecoration(
            border: pw.Border.all(color: PdfColors.red400),
            borderRadius: const pw.BorderRadius.all(pw.Radius.circular(5)),
            color: PdfColors.red50,
          ),
          child: pw.Column(
            children: [
              pw.TableHelper.fromTextArray(
                headerStyle: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold),
                cellStyle: const pw.TextStyle(fontSize: 9),
                headerDecoration: pw.BoxDecoration(color: PdfColors.red100),
                cellHeight: 30,
                cellAlignments: {
                  0: pw.Alignment.centerLeft,
                  1: pw.Alignment.centerLeft,
                  2: pw.Alignment.centerRight,
                  3: pw.Alignment.centerRight,
                  4: pw.Alignment.centerRight,
                },
                headers: ['Buyer', 'Items', 'Total', 'Paid', 'Balance'],
                data: limitedDebtors.map((debtor) {
                  return [
                    '${debtor['buyerName']}${debtor['buyerType'].toString().isNotEmpty ? '\n(${debtor['buyerType']})' : ''}',
                    debtor['itemsPurchased'].toString().length > 40
                        ? '${debtor['itemsPurchased'].toString().substring(0, 40)}...'
                        : debtor['itemsPurchased'],
                    '₦${formatter.format(debtor['totalAmount'])}',
                    '₦${formatter.format(debtor['totalPaid'])}',
                    '₦${formatter.format(debtor['outstandingBalance'])}',
                  ];
                }).toList(),
              ),
              pw.SizedBox(height: 10),
              pw.Divider(thickness: 1.5, color: PdfColors.red400),
              pw.SizedBox(height: 6),
              _buildRow(
                'TOTAL SALES DEBT:',
                '₦${formatter.format(totalSalesDebt)}',
                bold: true,
                fontSize: 13,
              ),
            ],
          ),
        ),
      ],
    );
  }

  // -----------------------------------------------------------
  // BANK DETAILS
  // -----------------------------------------------------------
  static pw.Widget _buildBankDetails(Map<String, dynamic> schoolProfile) {
    final accounts = <String>[];
    for (int i = 1; i <= 3; i++) {
      final bankName = schoolProfile['bankName$i']?.toString() ?? '';
      final accNum = schoolProfile['accountNumber$i']?.toString() ?? '';
      final accName = schoolProfile['accountName$i']?.toString() ?? '';
      if (bankName.isNotEmpty && accNum.isNotEmpty) {
        accounts.add('$bankName - $accNum - $accName');
      }
    }
    if (accounts.isEmpty) return pw.SizedBox();

    return pw.Container(
      margin: const pw.EdgeInsets.only(top: 12),
      padding: const pw.EdgeInsets.all(10),
      decoration: pw.BoxDecoration(
        color: PdfColors.blue50,
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
        border: pw.Border.all(color: PdfColors.blue200),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text('Bank Account Details:',
            style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold, color: PdfColors.blue900)),
          pw.SizedBox(height: 4),
          ...accounts.map((acc) => pw.Padding(
            padding: const pw.EdgeInsets.only(bottom: 2),
            child: pw.Text(acc, style: const pw.TextStyle(fontSize: 9, color: PdfColors.blue800)),
          )),
        ],
      ),
    );
  }

  // -----------------------------------------------------------
  // FOOTER
  // -----------------------------------------------------------
  static pw.Widget _buildFooter() {
    return pw.Column(
      children: [
        pw.Divider(),
        pw.SizedBox(height: 10),
        pw.Center(
          child: pw.Text(
            'This report provides a comprehensive overview of all financial activities for the term.',
            style: pw.TextStyle(fontSize: 9, fontStyle: pw.FontStyle.italic, color: PdfColors.grey600),
            textAlign: pw.TextAlign.center,
          ),
        ),
      ],
    );
  }

  // -----------------------------------------------------------
  // PAGE FOOTER
  // -----------------------------------------------------------
  static pw.Widget _buildPageFooter(pw.Context context) {
    return pw.Container(
      alignment: pw.Alignment.centerRight,
      margin: const pw.EdgeInsets.only(top: 10),
      child: pw.Text(
        'Page ${context.pageNumber} of ${context.pagesCount}',
        style: pw.TextStyle(fontSize: 9, color: PdfColors.grey600),
      ),
    );
  }

  // -----------------------------------------------------------
  // HELPER: ROW BUILDER
  // -----------------------------------------------------------
  static pw.Widget _buildRow(
    String label,
    String value, {
    bool bold = false,
    double fontSize = 11,
  }) {
    return pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: [
        pw.Expanded(
          child: pw.Text(
            label,
            style: pw.TextStyle(
              fontSize: fontSize,
              fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
            ),
          ),
        ),
        pw.Text(
          value,
          style: pw.TextStyle(
            fontSize: fontSize,
            fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
          ),
        ),
      ],
    );
  }
}
