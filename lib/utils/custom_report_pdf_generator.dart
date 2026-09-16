import 'dart:io';
import 'dart:typed_data';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:intl/intl.dart';
import 'custom_report_html_generator.dart';
import 'native_html_pdf_helper.dart';
import 'pdf_export_helper.dart';

// Shared row cap for every detail table in the report. Kept low (relative to
// the old per-section caps of 100/100/100/50/50, and the old per-category —
// effectively unbounded — cap on payment details) because "Full Report"
// combines every section into one in-memory document at once, and the `pdf`
// package builds the whole thing before writing anything to disk, so peak
// memory scales with the sum of every table across every section.
const int kMaxReportDetailRows = 60;

class CustomReportPDFGenerator {
  static Future<String> generateCustomReportPDF({
    required DateTime startDate,
    required DateTime endDate,
    required String? term,
    required String? session,
    required Map<String, dynamic> schoolProfile,
    // Income data
    required double cashTotal,
    required double posTotal,
    required double transferTotal,
    required double totalIncome,
    // Payment details (for category breakdown table)
    required List<Map<String, dynamic>> paymentDetails,
    // Expenses data
    required double expenseCashTotal,
    required double expensePosTotal,
    required double expenseTransferTotal,
    required double totalExpenses,
    required List<Map<String, dynamic>> expenseDetails,
    // Stock & Sales data
    required List<Map<String, dynamic>> stockSummary,
    required List<Map<String, dynamic>> salesDetails,
    required List<Map<String, dynamic>> salesDebtors,
    required double salesCashTotal,
    required double salesPosTotal,
    required double salesTransferTotal,
    required double totalSales,
    required double totalSalesDebt,
    // Section flags — controls what appears in the PDF
    bool includeIncome = true,
    bool includePaymentDetails = true,
    bool includeExpenses = true,
    bool includeStockAndSales = true,
    String reportTabLabel = 'Full Report',
    // Where to save the generated file — Downloads folder vs app-private storage (for sharing)
    bool saveToDownloads = false,
  }) async {
    final startStr = DateFormat('yyyyMMdd').format(startDate);
    final endStr = DateFormat('yyyyMMdd').format(endDate);
    final timestamp = DateFormat('HHmmss').format(DateTime.now());
    final safeLabel = reportTabLabel.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '_');
    final baseName = 'Custom_Report_${safeLabel}_${startStr}_to_${endStr}_$timestamp';

    if (Platform.isAndroid) {
      // Render as HTML and hand it to Android's native WebView print
      // pipeline — the same mechanism a browser uses for "Print / Save as
      // PDF". Pagination and layout happen in native code, not the Dart
      // heap, so this handles arbitrarily large reports without the
      // pure-Dart `pdf` package's memory characteristics (which is what
      // caused OOM crashes on constrained Android devices even for small
      // reports — see _buildCustomReportPdfBytes below, still used for
      // other platforms).
      final html = CustomReportHtmlGenerator.build(
        startDate: startDate,
        endDate: endDate,
        term: term,
        session: session,
        schoolProfile: schoolProfile,
        cashTotal: cashTotal,
        posTotal: posTotal,
        transferTotal: transferTotal,
        totalIncome: totalIncome,
        paymentDetails: paymentDetails,
        expenseCashTotal: expenseCashTotal,
        expensePosTotal: expensePosTotal,
        expenseTransferTotal: expenseTransferTotal,
        totalExpenses: totalExpenses,
        expenseDetails: expenseDetails,
        stockSummary: stockSummary,
        salesDetails: salesDetails,
        salesDebtors: salesDebtors,
        salesCashTotal: salesCashTotal,
        salesPosTotal: salesPosTotal,
        salesTransferTotal: salesTransferTotal,
        totalSales: totalSales,
        totalSalesDebt: totalSalesDebt,
        includeIncome: includeIncome,
        includePaymentDetails: includePaymentDetails,
        includeExpenses: includeExpenses,
        includeStockAndSales: includeStockAndSales,
        reportTabLabel: reportTabLabel,
      );

      return NativeHtmlPdfHelper.saveHtmlAsPdf(
        html: html,
        baseFileName: baseName,
        saveToDownloads: saveToDownloads,
      );
    }

    // Other platforms (Windows desktop, etc.): existing pure-Dart pdf
    // package path.
    final dir = await PdfExportDirectoryHelper.resolve(saveToDownloads: saveToDownloads);
    final bytes = await _buildCustomReportPdfBytes({
      'startDate': startDate.millisecondsSinceEpoch,
      'endDate': endDate.millisecondsSinceEpoch,
      'term': term,
      'session': session,
      'schoolProfile': schoolProfile,
      'cashTotal': cashTotal,
      'posTotal': posTotal,
      'transferTotal': transferTotal,
      'totalIncome': totalIncome,
      'paymentDetails': paymentDetails,
      'expenseCashTotal': expenseCashTotal,
      'expensePosTotal': expensePosTotal,
      'expenseTransferTotal': expenseTransferTotal,
      'totalExpenses': totalExpenses,
      'expenseDetails': expenseDetails,
      'stockSummary': stockSummary,
      'salesDetails': salesDetails,
      'salesDebtors': salesDebtors,
      'salesCashTotal': salesCashTotal,
      'salesPosTotal': salesPosTotal,
      'salesTransferTotal': salesTransferTotal,
      'totalSales': totalSales,
      'totalSalesDebt': totalSalesDebt,
      'includeIncome': includeIncome,
      'includePaymentDetails': includePaymentDetails,
      'includeExpenses': includeExpenses,
      'includeStockAndSales': includeStockAndSales,
      'reportTabLabel': reportTabLabel,
    });

    final file = File('${dir.path}/$baseName.pdf');
    await file.writeAsBytes(bytes);

    return file.path;
  }

  // -----------------------------------------------------------
  // HEADER
  // -----------------------------------------------------------
  static pw.Widget _buildHeader(
    Map<String, dynamic> schoolProfile,
    DateTime startDate,
    DateTime endDate,
    String? term,
    String? session,
    String reportTabLabel,
  ) {
    final schoolName = schoolProfile['name'] ?? 'School Name';
    final address = schoolProfile['address'] ?? '';
    final phone = schoolProfile['phone'] ?? '';
    final email = schoolProfile['email'] ?? '';
    final rangeStr =
        '${DateFormat('MMM d, yyyy').format(startDate)} - ${DateFormat('MMM d, yyyy').format(endDate)}';

    return pw.Column(
      children: [
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

        pw.Text(
          reportTabLabel.toUpperCase(),
          style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold),
          textAlign: pw.TextAlign.center,
        ),
        pw.SizedBox(height: 8),
        pw.Text(
          'Period: $rangeStr',
          style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold),
          textAlign: pw.TextAlign.center,
        ),
        if (term != null && session != null) ...[
          pw.SizedBox(height: 4),
          pw.Text(
            'Term: $term | Session: $session',
            style: pw.TextStyle(fontSize: 11, color: PdfColors.grey700),
            textAlign: pw.TextAlign.center,
          ),
        ],
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
    double cashTotal,
    double posTotal,
    double transferTotal,
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
          'INCOME SUMMARY (SCHOOL FEES & OFFICE SALES)',
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
              _buildRow('Cash Received (School Fees):', 'N ${formatter.format(cashTotal)}'),
              pw.SizedBox(height: 5),
              _buildRow('Cash Received (Office Sales):', 'N ${formatter.format(salesCashTotal)}'),
              pw.SizedBox(height: 10),
              _buildRow('POS Received (School Fees):', 'N ${formatter.format(posTotal)}'),
              pw.SizedBox(height: 5),
              _buildRow('POS Received (Office Sales):', 'N ${formatter.format(salesPosTotal)}'),
              pw.SizedBox(height: 10),
              _buildRow('Transfer Received (School Fees):', 'N ${formatter.format(transferTotal)}'),
              pw.SizedBox(height: 5),
              _buildRow('Transfer Received (Office Sales):', 'N ${formatter.format(salesTransferTotal)}'),
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
  // PAYMENT DETAILS SECTION (grouped by paymentFor category)
  // -----------------------------------------------------------
  static pw.Widget _buildPaymentDetailsSection(
    List<Map<String, dynamic>> paymentDetails,
    NumberFormat formatter,
  ) {
    // Cap the TOTAL number of detail rows across all categories combined —
    // capping per-category only (as before) left the section effectively
    // unbounded when a report had many categories, which is a major
    // contributor to out-of-memory failures on large "Full Report" exports.
    final isOverallTruncated = paymentDetails.length > kMaxReportDetailRows;
    final cappedPayments = isOverallTruncated
        ? paymentDetails.sublist(0, kMaxReportDetailRows)
        : paymentDetails;

    final grouped = <String, List<Map<String, dynamic>>>{};
    for (final p in cappedPayments) {
      final cat = p['paymentFor']?.toString() ?? 'School Fees';
      (grouped[cat] ??= []).add(p);
    }

    final widgets = <pw.Widget>[
      pw.Text(
        'SCHOOL FEES PAYMENT DETAILS (${paymentDetails.length} transactions)'
        '${isOverallTruncated ? ' — showing first $kMaxReportDetailRows' : ''}',
        style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold),
      ),
      pw.SizedBox(height: 10),
    ];

    grouped.forEach((category, payments) {
      final categoryTotal = payments.fold<double>(
          0, (sum, p) => sum + ((p['amount'] as num).toDouble()));

      widgets.add(pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(
            category.toUpperCase(),
            style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 11, color: PdfColors.green800),
          ),
          pw.Text(
            '${payments.length} transaction(s) — Total: N ${formatter.format(categoryTotal)}',
            style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700),
          ),
        ],
      ));
      widgets.add(pw.SizedBox(height: 4));
      widgets.add(pw.TableHelper.fromTextArray(
        headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9),
        cellStyle: const pw.TextStyle(fontSize: 8),
        headerDecoration: const pw.BoxDecoration(color: PdfColors.green100),
        cellAlignments: {
          0: pw.Alignment.centerLeft,
          1: pw.Alignment.centerLeft,
          2: pw.Alignment.centerLeft,
          3: pw.Alignment.center,
          4: pw.Alignment.centerRight,
        },
        data: [
          ['Student Name', 'Adm No', 'Class/Arm', 'Method', 'Amount (N)'],
          ...payments.map((p) {
            return [
              p['studentName'],
              p['admissionNo'],
              '${p['className']} - ${p['armName']}',
              p['method'],
              formatter.format(p['amount'] as num),
            ];
          }),
        ],
      ));
      widgets.add(pw.SizedBox(height: 14));
    });

    return pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: widgets);
  }

  // -----------------------------------------------------------
  // EXPENSES SECTION
  // -----------------------------------------------------------
  static pw.Widget _buildExpensesSection(
    double expenseCashTotal,
    double expensePosTotal,
    double expenseTransferTotal,
    double totalExpenses,
    List<Map<String, dynamic>> expenseDetails,
    NumberFormat formatter,
  ) {
    final limited = expenseDetails.length > kMaxReportDetailRows
        ? expenseDetails.sublist(0, kMaxReportDetailRows)
        : expenseDetails;
    final isTruncated = expenseDetails.length > kMaxReportDetailRows;

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          'EXPENSES',
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
            children: [
              _buildRow('Cash Paid:', 'N ${formatter.format(expenseCashTotal)}'),
              pw.SizedBox(height: 6),
              _buildRow('POS Paid:', 'N ${formatter.format(expensePosTotal)}'),
              pw.SizedBox(height: 6),
              _buildRow('Transfers Paid:', 'N ${formatter.format(expenseTransferTotal)}'),
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
        pw.SizedBox(height: 14),
        pw.Text(
          'EXPENSES DETAILS (${expenseDetails.length} transactions)'
          '${isTruncated ? ' — showing first $kMaxReportDetailRows' : ''}',
          style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold),
        ),
        pw.SizedBox(height: 8),
        pw.TableHelper.fromTextArray(
          headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9),
          cellStyle: const pw.TextStyle(fontSize: 8),
          headerDecoration: const pw.BoxDecoration(color: PdfColors.orange100),
          cellAlignments: {
            0: pw.Alignment.centerLeft,
            1: pw.Alignment.centerLeft,
            2: pw.Alignment.centerLeft,
            3: pw.Alignment.center,
            4: pw.Alignment.centerRight,
          },
          data: [
            ['Description', 'Category', 'Recipient', 'Method', 'Amount (N)'],
            ...limited.map((e) {
              return [
                e['description'],
                e['category'],
                e['recipient'],
                e['method'],
                formatter.format(e['amount'] as num),
              ];
            }),
          ],
        ),
      ],
    );
  }

  // -----------------------------------------------------------
  // NET INCOME SECTION
  // -----------------------------------------------------------
  static pw.Widget _buildNetIncomeSection(double netIncome, NumberFormat formatter) {
    final isPositive = netIncome >= 0;
    return pw.Container(
      padding: const pw.EdgeInsets.all(18),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.blue400, width: 2),
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(5)),
        color: PdfColors.blue50,
      ),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(
            'NET INCOME (Income - Expenses):',
            style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold),
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
    );
  }

  // -----------------------------------------------------------
  // STOCK SUMMARY SECTION
  // -----------------------------------------------------------
  static pw.Widget _buildStockSummarySection(List<Map<String, dynamic>> stockSummary) {
    final limited = stockSummary.length > kMaxReportDetailRows
        ? stockSummary.sublist(0, kMaxReportDetailRows)
        : stockSummary;
    final isTruncated = stockSummary.length > kMaxReportDetailRows;

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          'STOCK SUMMARY',
          style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold, color: PdfColors.brown700),
        ),
        pw.SizedBox(height: 6),
        pw.Text(
          'Stock Movement for the Period${isTruncated ? ' (showing first $kMaxReportDetailRows of ${stockSummary.length} items)' : ''}',
          style: pw.TextStyle(fontSize: 10, color: PdfColors.grey700),
        ),
        pw.SizedBox(height: 10),
        pw.TableHelper.fromTextArray(
          border: pw.TableBorder.all(color: PdfColors.brown400),
          headerStyle: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold),
          cellStyle: const pw.TextStyle(fontSize: 10),
          headerDecoration: pw.BoxDecoration(color: PdfColors.brown100),
          rowDecoration: pw.BoxDecoration(color: PdfColors.brown50),
          cellHeight: 25,
          cellAlignments: {
            0: pw.Alignment.centerLeft,
            1: pw.Alignment.centerRight,
            2: pw.Alignment.centerRight,
            3: pw.Alignment.centerRight,
          },
          headers: ['Item', 'Beginning', 'Sold', 'Remaining'],
          data: limited.map((stock) {
            return [
              stock['itemName'],
              '${stock['beginningQuantity']}',
              '${stock['qtySold']}',
              '${stock['remainingQuantity']}',
            ];
          }).toList(),
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
    final limited = salesDetails.length > kMaxReportDetailRows
        ? salesDetails.sublist(0, kMaxReportDetailRows)
        : salesDetails;
    final isTruncated = salesDetails.length > kMaxReportDetailRows;

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          'SALES SUMMARY',
          style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold, color: PdfColors.teal700),
        ),
        if (isTruncated)
          pw.Padding(
            padding: const pw.EdgeInsets.only(top: 4),
            child: pw.Text(
              '(Showing first $kMaxReportDetailRows of ${salesDetails.length})',
              style: pw.TextStyle(fontSize: 9, color: PdfColors.grey700),
            ),
          ),
        pw.SizedBox(height: 10),
        pw.TableHelper.fromTextArray(
          headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9),
          cellStyle: const pw.TextStyle(fontSize: 8),
          headerDecoration: const pw.BoxDecoration(color: PdfColors.teal200),
          cellAlignments: {
            0: pw.Alignment.centerLeft,
            1: pw.Alignment.centerLeft,
            2: pw.Alignment.center,
            3: pw.Alignment.center,
            4: pw.Alignment.centerRight,
            5: pw.Alignment.centerLeft,
          },
          data: [
            ['S/N', 'Item(s) Sold', 'Qty', 'Payment Status', 'Amount Paid', 'Buyer Details'],
            ...limited.asMap().entries.map((entry) {
              final index = entry.key;
              final sale = entry.value;
              final items = sale['items'] as List<Map<String, dynamic>>;
              final itemsText = items.map((item) {
                final isCustom = item['isCustomItem'] == true;
                return isCustom
                    ? '${item['itemName']} [Custom] (x${item['quantity']})'
                    : '${item['itemName']} (x${item['quantity']})';
              }).join(', ');
              final totalPaid = (sale['totalPaid'] as num).toDouble();
              final totalAmount = (sale['totalAmount'] as num).toDouble();
              final outstanding = totalAmount - totalPaid;

              String paymentStatus;
              if (outstanding <= 0) {
                paymentStatus = 'Paid';
              } else if (totalPaid > 0) {
                paymentStatus = 'Part Payment';
              } else {
                paymentStatus = 'Unpaid';
              }

              return [
                '${index + 1}',
                itemsText,
                '${sale['totalQtySold']}',
                paymentStatus,
                'N ${formatter.format(totalPaid)}',
                '${sale['buyerName']} (${sale['buyerType']})',
              ];
            }),
          ],
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
    final limited = salesDebtors.length > kMaxReportDetailRows
        ? salesDebtors.sublist(0, kMaxReportDetailRows)
        : salesDebtors;
    final isTruncated = salesDebtors.length > kMaxReportDetailRows;

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          'SALES DEBTORS',
          style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold, color: PdfColors.red700),
        ),
        pw.SizedBox(height: 6),
        pw.Text(
          'Buyers with Outstanding Balances${isTruncated ? ' (showing first $kMaxReportDetailRows of ${salesDebtors.length})' : ''}',
          style: pw.TextStyle(fontSize: 10, color: PdfColors.grey700),
        ),
        pw.SizedBox(height: 10),
        pw.TableHelper.fromTextArray(
          border: pw.TableBorder.all(color: PdfColors.red400),
          headerStyle: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold),
          cellStyle: const pw.TextStyle(fontSize: 9),
          headerDecoration: pw.BoxDecoration(color: PdfColors.red100),
          rowDecoration: pw.BoxDecoration(color: PdfColors.red50),
          cellHeight: 30,
          cellAlignments: {
            0: pw.Alignment.centerLeft,
            1: pw.Alignment.centerLeft,
            2: pw.Alignment.centerRight,
            3: pw.Alignment.centerRight,
            4: pw.Alignment.centerRight,
          },
          headers: ['Buyer', 'Items', 'Total', 'Paid', 'Balance'],
          data: limited.map((debtor) {
            return [
              '${debtor['buyerName']}${debtor['buyerType'].toString().isNotEmpty ? '\n(${debtor['buyerType']})' : ''}',
              debtor['itemsPurchased'].toString().length > 40
                  ? '${debtor['itemsPurchased'].toString().substring(0, 40)}...'
                  : debtor['itemsPurchased'],
              'N ${formatter.format(debtor['totalAmount'])}',
              'N ${formatter.format(debtor['totalPaid'])}',
              'N ${formatter.format(debtor['outstandingBalance'])}',
            ];
          }).toList(),
        ),
        pw.SizedBox(height: 10),
        pw.Divider(thickness: 1.5, color: PdfColors.red400),
        pw.SizedBox(height: 6),
        _buildRow(
          'TOTAL SALES DEBT:',
          'N ${formatter.format(totalSalesDebt)}',
          bold: true,
          fontSize: 13,
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
            'This report provides a financial overview for the selected date range.',
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

// -----------------------------------------------------------
// ISOLATE ENTRY POINT
// -----------------------------------------------------------
// Top-level function so it can be handed to compute() and run on a
// background isolate — building the pw.Document and rendering it to bytes
// is the CPU-heavy part that used to block the UI thread.
Future<Uint8List> _buildCustomReportPdfBytes(Map<String, dynamic> args) async {
  final startDate = DateTime.fromMillisecondsSinceEpoch(args['startDate'] as int);
  final endDate = DateTime.fromMillisecondsSinceEpoch(args['endDate'] as int);
  final term = args['term'] as String?;
  final session = args['session'] as String?;
  final schoolProfile = args['schoolProfile'] as Map<String, dynamic>;

  final cashTotal = args['cashTotal'] as double;
  final posTotal = args['posTotal'] as double;
  final transferTotal = args['transferTotal'] as double;
  final totalIncome = args['totalIncome'] as double;
  final paymentDetails = args['paymentDetails'] as List<Map<String, dynamic>>;

  final expenseCashTotal = args['expenseCashTotal'] as double;
  final expensePosTotal = args['expensePosTotal'] as double;
  final expenseTransferTotal = args['expenseTransferTotal'] as double;
  final totalExpenses = args['totalExpenses'] as double;
  final expenseDetails = args['expenseDetails'] as List<Map<String, dynamic>>;

  final stockSummary = args['stockSummary'] as List<Map<String, dynamic>>;
  final salesDetails = args['salesDetails'] as List<Map<String, dynamic>>;
  final salesDebtors = args['salesDebtors'] as List<Map<String, dynamic>>;
  final salesCashTotal = args['salesCashTotal'] as double;
  final salesPosTotal = args['salesPosTotal'] as double;
  final salesTransferTotal = args['salesTransferTotal'] as double;
  final totalSales = args['totalSales'] as double;
  final totalSalesDebt = args['totalSalesDebt'] as double;

  final includeIncome = args['includeIncome'] as bool;
  final includePaymentDetails = args['includePaymentDetails'] as bool;
  final includeExpenses = args['includeExpenses'] as bool;
  final includeStockAndSales = args['includeStockAndSales'] as bool;
  final reportTabLabel = args['reportTabLabel'] as String;

  final pdf = pw.Document();
  final formatter = NumberFormat('#,##0.00');
  final showNetIncome = includeIncome && includeExpenses;

  // ignore: avoid_print
  print(
    'CUSTOM REPORT PDF BUILD: '
    'paymentDetails=${paymentDetails.length}, '
    'expenseDetails=${expenseDetails.length}, '
    'salesDetails=${salesDetails.length}, '
    'stockSummary=${stockSummary.length}, '
    'salesDebtors=${salesDebtors.length}, '
    'includeIncome=$includeIncome, includePaymentDetails=$includePaymentDetails, '
    'includeExpenses=$includeExpenses, includeStockAndSales=$includeStockAndSales',
  );

  pdf.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(40),
      build: (context) => [
        CustomReportPDFGenerator._buildHeader(
            schoolProfile, startDate, endDate, term, session, reportTabLabel),
        pw.SizedBox(height: 25),

        if (includeIncome) ...[
          CustomReportPDFGenerator._buildIncomeSection(
            cashTotal, posTotal, transferTotal, totalIncome, formatter,
            salesCashTotal, salesPosTotal, salesTransferTotal, totalSales,
          ),
          pw.SizedBox(height: 20),
        ],

        if (includePaymentDetails && paymentDetails.isNotEmpty) ...[
          CustomReportPDFGenerator._buildPaymentDetailsSection(paymentDetails, formatter),
          pw.SizedBox(height: 20),
        ],

        if (includeStockAndSales && salesDetails.isNotEmpty) ...[
          CustomReportPDFGenerator._buildSalesSummarySection(salesDetails, formatter),
          pw.SizedBox(height: 20),
        ],

        if (includeExpenses && expenseDetails.isNotEmpty) ...[
          CustomReportPDFGenerator._buildExpensesSection(
            expenseCashTotal, expensePosTotal, expenseTransferTotal,
            totalExpenses, expenseDetails, formatter,
          ),
          pw.SizedBox(height: 20),
        ],

        if (showNetIncome) ...[
          CustomReportPDFGenerator._buildNetIncomeSection(
            (totalIncome + totalSales) - totalExpenses,
            formatter,
          ),
          pw.SizedBox(height: 20),
        ],

        if (includeStockAndSales && stockSummary.isNotEmpty) ...[
          CustomReportPDFGenerator._buildStockSummarySection(stockSummary),
          pw.SizedBox(height: 20),
        ],

        if (includeStockAndSales && salesDebtors.isNotEmpty) ...[
          CustomReportPDFGenerator._buildSalesDebtorsSection(salesDebtors, totalSalesDebt, formatter),
          pw.SizedBox(height: 20),
        ],

        CustomReportPDFGenerator._buildBankDetails(schoolProfile),
        pw.SizedBox(height: 30),
        CustomReportPDFGenerator._buildFooter(),
      ],
      footer: (context) => CustomReportPDFGenerator._buildPageFooter(context),
    ),
  );

  return pdf.save();
}
