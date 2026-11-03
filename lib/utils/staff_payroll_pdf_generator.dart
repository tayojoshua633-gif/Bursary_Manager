// lib/utils/staff_payroll_pdf_generator.dart

import 'dart:io';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:intl/intl.dart';
import 'staff_payroll_html_generator.dart';
import 'native_html_pdf_helper.dart';
import 'pdf_export_helper.dart';

class StaffPayrollPDFGenerator {
  static final _currencyFormat = NumberFormat.currency(symbol: 'N', decimalDigits: 2);

  static Future<String> generatePayrollPDF({
    required List<Map<String, dynamic>> payrollData,
    required String month,
    required Map<String, dynamic> schoolProfile,
    bool saveToDownloads = false,
  }) async {
    final timestamp = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
    final baseName = 'Staff_Payroll_${month.replaceAll(' ', '_')}_$timestamp';

    if (Platform.isAndroid) {
      final html = StaffPayrollHtmlGenerator.build(
        payrollData: payrollData,
        month: month,
        schoolProfile: schoolProfile,
      );
      return NativeHtmlPdfHelper.saveHtmlAsPdf(
        html: html,
        baseFileName: baseName,
        saveToDownloads: saveToDownloads,
      );
    }

    final pdf = pw.Document();

    // Calculate totals
    double totalBasicSalary = 0;
    double totalIncentives = 0;
    double totalLoanDeductions = 0;
    double totalPenalties = 0;
    double totalOwingBroughtForward = 0;
    double totalNetSalary = 0; // what is actually paid out (staff who owe get ₦0)
    double totalStaffOwing = 0;

    for (var staff in payrollData) {
      totalBasicSalary += (staff['basicSalary'] as num).toDouble();
      totalIncentives += (staff['totalIncentives'] as num).toDouble();
      totalLoanDeductions += _loanTotal(staff);
      totalPenalties += (staff['totalDeductions'] as num).toDouble();
      totalOwingBroughtForward += (staff['owingBroughtForward'] as num? ?? 0).toDouble();
      final payable = _payable(staff);
      if (staff['paidWithMonth'] != null) {
        // already counted in the later salary that paid it
      } else if (payable > 0) {
        totalNetSalary += payable;
      } else {
        totalStaffOwing -= payable;
      }
    }

    // Create PDF pages
    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4.landscape,
        margin: const pw.EdgeInsets.all(24),
        build: (context) => [
          // Header
          _buildHeader(schoolProfile, month),
          pw.SizedBox(height: 16),

          // Summary
          _buildSummary(
            totalBasicSalary,
            totalIncentives,
            totalLoanDeductions,
            totalPenalties,
            totalNetSalary,
            payrollData.length,
            totalOwingBroughtForward: totalOwingBroughtForward,
            totalStaffOwing: totalStaffOwing,
          ),
          pw.SizedBox(height: 16),

          // Payroll Table
          _buildPayrollTable(payrollData),
          pw.SizedBox(height: 20),

          // Footer
          _buildFooter(),
        ],
        footer: (context) => _buildPageFooter(context),
      ),
    );

    // Save to file
    final output = await PdfExportDirectoryHelper.resolve(saveToDownloads: saveToDownloads);
    final file = File('${output.path}/$baseName.pdf');
    await file.writeAsBytes(await pdf.save());

    return file.path;
  }

  static pw.Widget _buildHeader(
    Map<String, dynamic> schoolProfile,
    String month,
  ) {
    final schoolName = schoolProfile['name'] ?? 'School Name';
    final address = schoolProfile['address'] ?? '';
    final phone = schoolProfile['phone'] ?? '';

    return pw.Column(
      children: [
        // School Name
        pw.Text(
          schoolName.toUpperCase(),
          style: pw.TextStyle(
            fontSize: 18,
            fontWeight: pw.FontWeight.bold,
          ),
          textAlign: pw.TextAlign.center,
        ),
        if (address.isNotEmpty) ...[
          pw.SizedBox(height: 4),
          pw.Text(
            address,
            style: const pw.TextStyle(fontSize: 9),
            textAlign: pw.TextAlign.center,
          ),
        ],
        if (phone.isNotEmpty) ...[
          pw.SizedBox(height: 2),
          pw.Text(
            'Tel: $phone',
            style: const pw.TextStyle(fontSize: 9),
            textAlign: pw.TextAlign.center,
          ),
        ],
        pw.SizedBox(height: 12),
        pw.Container(
          padding: const pw.EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: pw.BoxDecoration(
            color: PdfColors.blue50,
            borderRadius: pw.BorderRadius.circular(4),
          ),
          child: pw.Text(
            'STAFF PAYROLL - $month',
            style: pw.TextStyle(
              fontSize: 14,
              fontWeight: pw.FontWeight.bold,
              color: PdfColors.blue900,
            ),
          ),
        ),
      ],
    );
  }

  static pw.Widget _buildSummary(
    double totalBasicSalary,
    double totalIncentives,
    double totalLoanDeductions,
    double totalPenalties,
    double totalNetSalary,
    int staffCount, {
    double totalOwingBroughtForward = 0,
    double totalStaffOwing = 0,
  }) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(12),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.grey300),
        borderRadius: pw.BorderRadius.circular(4),
      ),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceAround,
        children: [
          _summaryItem('Staff Count', staffCount.toString()),
          _summaryItem('Total Basic', _currencyFormat.format(totalBasicSalary)),
          _summaryItem('Total Incentives', _currencyFormat.format(totalIncentives)),
          _summaryItem('Loan Deductions', _currencyFormat.format(totalLoanDeductions)),
          _summaryItem('Penalties', _currencyFormat.format(totalPenalties)),
          if (totalOwingBroughtForward > 0)
            _summaryItem('Owing B/F', _currencyFormat.format(totalOwingBroughtForward)),
          _summaryItem('Net Payroll', _currencyFormat.format(totalNetSalary), isHighlighted: true),
          if (totalStaffOwing > 0)
            _summaryItem('Owed by Staff', _currencyFormat.format(totalStaffOwing)),
        ],
      ),
    );
  }

  static pw.Widget _summaryItem(String label, String value, {bool isHighlighted = false}) {
    return pw.Column(
      children: [
        pw.Text(
          label,
          style: pw.TextStyle(
            fontSize: 8,
            color: PdfColors.grey600,
          ),
        ),
        pw.SizedBox(height: 4),
        pw.Text(
          value,
          style: pw.TextStyle(
            fontSize: 10,
            fontWeight: pw.FontWeight.bold,
            color: isHighlighted ? PdfColors.green700 : PdfColors.black,
          ),
        ),
      ],
    );
  }

  /// Loan taken from this salary: this month's repayment plus missed months.
  static double _loanTotal(Map<String, dynamic> staff) =>
      (staff['loanDeduction'] as num).toDouble() + (staff['loanArrears'] as num? ?? 0).toDouble();

  /// Final amount for the month after arrears and any amount owed from a
  /// settled month — matches the Total Payable shown on the payroll card.
  static double _payable(Map<String, dynamic> staff) =>
      (staff['totalPayable'] as num? ?? staff['netSalary'] as num).toDouble();

  static String _statusLabel(Map<String, dynamic> staff) {
    if (staff['paidWithMonth'] != null) return 'Paid with ${staff['paidWithMonth']}';
    if (staff['isSettled'] == true) return 'Settled – owing';
    if (staff['isPaid'] == true) return 'Paid';
    return _payable(staff) < -0.005 ? 'Owing' : 'Not paid';
  }

  static pw.Widget _buildPayrollTable(List<Map<String, dynamic>> payrollData) {
    return pw.Table(
      border: pw.TableBorder.all(color: PdfColors.grey300),
      columnWidths: {
        0: const pw.FixedColumnWidth(22),  // S/N
        1: const pw.FlexColumnWidth(2),    // Name
        2: const pw.FixedColumnWidth(46),  // Staff ID
        3: const pw.FlexColumnWidth(1.2),  // Basic Salary
        4: const pw.FlexColumnWidth(1.1),  // Incentives
        5: const pw.FlexColumnWidth(1.1),  // Arrears
        6: const pw.FlexColumnWidth(1.1),  // Loan Ded.
        7: const pw.FlexColumnWidth(1.1),  // Penalties
        8: const pw.FlexColumnWidth(1.1),  // Owing B/F
        9: const pw.FlexColumnWidth(1.2),  // Net Payable
        10: const pw.FlexColumnWidth(1.1), // Status
        11: const pw.FlexColumnWidth(1.3), // Bank
        12: const pw.FlexColumnWidth(1.5), // Account
      },
      children: [
        // Header row
        pw.TableRow(
          decoration: const pw.BoxDecoration(color: PdfColors.blue100),
          children: [
            _tableHeader('S/N'),
            _tableHeader('Staff Name'),
            _tableHeader('Staff ID'),
            _tableHeader('Basic Salary'),
            _tableHeader('Incentives'),
            _tableHeader('Arrears'),
            _tableHeader('Loan Ded.'),
            _tableHeader('Penalties'),
            _tableHeader('Owing B/F'),
            _tableHeader('Net Payable'),
            _tableHeader('Status'),
            _tableHeader('Bank'),
            _tableHeader('Account No.'),
          ],
        ),
        // Data rows
        ...payrollData.asMap().entries.map((entry) {
          final index = entry.key;
          final staff = entry.value;
          final isEven = index % 2 == 0;

          return pw.TableRow(
            decoration: pw.BoxDecoration(
              color: isEven ? PdfColors.white : PdfColors.grey50,
            ),
            children: [
              _tableCell('${index + 1}'),
              _tableCell(staff['staffName'] ?? '', align: pw.TextAlign.left),
              _tableCell(staff['staffId'] ?? ''),
              _tableCell(_currencyFormat.format(staff['basicSalary'])),
              _tableCell(_currencyFormat.format(staff['totalIncentives']),
                  color: PdfColors.green700),
              _tableCell(_currencyFormat.format(staff['arrears'] ?? 0),
                  color: PdfColors.green700),
              _tableCell(_currencyFormat.format(_loanTotal(staff)),
                  color: PdfColors.orange700),
              _tableCell(_currencyFormat.format(staff['totalDeductions']),
                  color: PdfColors.red700),
              _tableCell(_currencyFormat.format(staff['owingBroughtForward'] ?? 0),
                  color: PdfColors.deepOrange700),
              _tableCell(_currencyFormat.format(_payable(staff)),
                  isBold: true, color: _payable(staff) < 0 ? PdfColors.red700 : PdfColors.blue700),
              _tableCell(_statusLabel(staff),
                  color: staff['isSettled'] == true || _payable(staff) < -0.005
                      ? PdfColors.deepOrange700
                      : null),
              _tableCell(staff['bankName'] ?? '-', align: pw.TextAlign.left),
              _tableCell(staff['accountNumber'] ?? '-'),
            ],
          );
        }),
      ],
    );
  }

  static pw.Widget _tableHeader(String text) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(6),
      child: pw.Text(
        text,
        style: pw.TextStyle(
          fontSize: 8,
          fontWeight: pw.FontWeight.bold,
        ),
        textAlign: pw.TextAlign.center,
      ),
    );
  }

  static pw.Widget _tableCell(
    String text, {
    pw.TextAlign align = pw.TextAlign.center,
    bool isBold = false,
    PdfColor? color,
  }) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(5),
      child: pw.Text(
        text,
        style: pw.TextStyle(
          fontSize: 7,
          fontWeight: isBold ? pw.FontWeight.bold : pw.FontWeight.normal,
          color: color,
        ),
        textAlign: align,
      ),
    );
  }

  static pw.Widget _buildFooter() {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  'Prepared by: _______________________',
                  style: const pw.TextStyle(fontSize: 9),
                ),
                pw.SizedBox(height: 8),
                pw.Text(
                  'Date: _______________________',
                  style: const pw.TextStyle(fontSize: 9),
                ),
              ],
            ),
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  'Approved by: _______________________',
                  style: const pw.TextStyle(fontSize: 9),
                ),
                pw.SizedBox(height: 8),
                pw.Text(
                  'Signature: _______________________',
                  style: const pw.TextStyle(fontSize: 9),
                ),
              ],
            ),
          ],
        ),
      ],
    );
  }

  static pw.Widget _buildPageFooter(pw.Context context) {
    return pw.Container(
      alignment: pw.Alignment.centerRight,
      margin: const pw.EdgeInsets.only(top: 8),
      child: pw.Text(
        'Page ${context.pageNumber} of ${context.pagesCount}',
        style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600),
      ),
    );
  }
}
