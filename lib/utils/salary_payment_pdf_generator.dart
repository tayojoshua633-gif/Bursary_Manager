// lib/utils/salary_payment_pdf_generator.dart

import 'dart:io';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:path_provider/path_provider.dart';
import 'package:intl/intl.dart';

class SalaryPaymentPDFGenerator {
  static final _currencyFormat = NumberFormat.currency(symbol: 'N', decimalDigits: 2);

  static Future<String> generateSalaryPaymentPDF({
    required List<Map<String, dynamic>> paymentRecords,
    required String month,
    required Map<String, dynamic> schoolProfile,
    required int totalStaff,
    required int paidCount,
    required int unpaidCount,
    required double totalPaidAmount,
    required double totalUnpaidAmount,
  }) async {
    final pdf = pw.Document();

    // Separate paid and unpaid
    final paidRecords = paymentRecords.where((r) => r['isPaid'] == true).toList();
    final unpaidRecords = paymentRecords.where((r) => r['isPaid'] == false).toList();

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4.landscape,
        margin: const pw.EdgeInsets.all(24),
        build: (context) => [
          _buildHeader(schoolProfile, month),
          pw.SizedBox(height: 16),
          _buildSummary(totalStaff, paidCount, unpaidCount, totalPaidAmount, totalUnpaidAmount),
          pw.SizedBox(height: 20),

          // Paid Staff Section
          if (paidRecords.isNotEmpty) ...[
            _buildSectionHeader('PAID STAFF', PdfColors.green700),
            pw.SizedBox(height: 8),
            _buildPaymentTable(paidRecords, true),
            pw.SizedBox(height: 20),
          ],

          // Unpaid Staff Section
          if (unpaidRecords.isNotEmpty) ...[
            _buildSectionHeader('UNPAID STAFF', PdfColors.red700),
            pw.SizedBox(height: 8),
            _buildPaymentTable(unpaidRecords, false),
            pw.SizedBox(height: 20),
          ],

          _buildFooter(),
        ],
        footer: (context) => _buildPageFooter(context),
      ),
    );

    final output = await getApplicationDocumentsDirectory();
    final timestamp = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
    final fileName = 'Salary_Payment_Record_${month.replaceAll(' ', '_')}_$timestamp.pdf';
    final file = File('${output.path}/$fileName');
    await file.writeAsBytes(await pdf.save());

    return file.path;
  }

  static pw.Widget _buildHeader(Map<String, dynamic> schoolProfile, String month) {
    final schoolName = schoolProfile['name'] ?? 'School Name';
    final address = schoolProfile['address'] ?? '';
    final phone = schoolProfile['phone'] ?? '';

    return pw.Column(
      children: [
        pw.Text(
          schoolName.toUpperCase(),
          style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold),
          textAlign: pw.TextAlign.center,
        ),
        if (address.isNotEmpty) ...[
          pw.SizedBox(height: 4),
          pw.Text(address, style: const pw.TextStyle(fontSize: 9), textAlign: pw.TextAlign.center),
        ],
        if (phone.isNotEmpty) ...[
          pw.SizedBox(height: 2),
          pw.Text('Tel: $phone', style: const pw.TextStyle(fontSize: 9), textAlign: pw.TextAlign.center),
        ],
        pw.SizedBox(height: 12),
        pw.Container(
          padding: const pw.EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: pw.BoxDecoration(
            color: PdfColors.teal50,
            borderRadius: pw.BorderRadius.circular(4),
          ),
          child: pw.Text(
            'SALARY PAYMENT RECORD - $month',
            style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold, color: PdfColors.teal900),
          ),
        ),
      ],
    );
  }

  static pw.Widget _buildSummary(
    int totalStaff,
    int paidCount,
    int unpaidCount,
    double totalPaidAmount,
    double totalUnpaidAmount,
  ) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(12),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.grey300),
        borderRadius: pw.BorderRadius.circular(4),
      ),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceAround,
        children: [
          _summaryItem('Total Staff', totalStaff.toString()),
          _summaryItem('Paid', paidCount.toString(), color: PdfColors.green700),
          _summaryItem('Unpaid', unpaidCount.toString(), color: PdfColors.red700),
          _summaryItem('Total Paid', _currencyFormat.format(totalPaidAmount), color: PdfColors.green700),
          _summaryItem('Outstanding', _currencyFormat.format(totalUnpaidAmount), color: PdfColors.red700),
        ],
      ),
    );
  }

  static pw.Widget _summaryItem(String label, String value, {PdfColor? color}) {
    return pw.Column(
      children: [
        pw.Text(label, style: pw.TextStyle(fontSize: 8, color: PdfColors.grey600)),
        pw.SizedBox(height: 4),
        pw.Text(
          value,
          style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: color ?? PdfColors.black),
        ),
      ],
    );
  }

  static pw.Widget _buildSectionHeader(String title, PdfColor color) {
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: pw.BoxDecoration(
        color: color,
        borderRadius: pw.BorderRadius.circular(4),
      ),
      child: pw.Text(
        title,
        style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: PdfColors.white),
      ),
    );
  }

  static pw.Widget _buildPaymentTable(List<Map<String, dynamic>> records, bool isPaid) {
    return pw.Table(
      border: pw.TableBorder.all(color: PdfColors.grey300),
      columnWidths: {
        0: const pw.FixedColumnWidth(25),  // S/N
        1: const pw.FlexColumnWidth(2),    // Name
        2: const pw.FixedColumnWidth(50),  // Staff ID
        3: const pw.FlexColumnWidth(1.2),  // Basic
        4: const pw.FlexColumnWidth(1),    // Incentive
        5: const pw.FlexColumnWidth(1),    // Loan
        6: const pw.FlexColumnWidth(1),    // Penalty
        7: const pw.FlexColumnWidth(1.2),  // Net Salary
        8: const pw.FlexColumnWidth(1.5),  // Bank
        9: const pw.FlexColumnWidth(1.2),  // Account
      },
      children: [
        pw.TableRow(
          decoration: pw.BoxDecoration(color: isPaid ? PdfColors.green50 : PdfColors.red50),
          children: [
            _tableHeader('S/N'),
            _tableHeader('Staff Name'),
            _tableHeader('Staff ID'),
            _tableHeader('Basic'),
            _tableHeader('Incentive'),
            _tableHeader('Loan Ded.'),
            _tableHeader('Penalty'),
            _tableHeader('Net Salary'),
            _tableHeader('Bank'),
            _tableHeader('Account No.'),
          ],
        ),
        ...records.asMap().entries.map((entry) {
          final index = entry.key;
          final record = entry.value;
          final isEven = index % 2 == 0;

          return pw.TableRow(
            decoration: pw.BoxDecoration(color: isEven ? PdfColors.white : PdfColors.grey50),
            children: [
              _tableCell('${index + 1}'),
              _tableCell(record['staffName'] ?? '', align: pw.TextAlign.left),
              _tableCell(record['staffId'] ?? ''),
              _tableCell(_currencyFormat.format(record['basicSalary'])),
              _tableCell(_currencyFormat.format(record['incentives']), color: PdfColors.green700),
              _tableCell(_currencyFormat.format(record['loanDeduction']), color: PdfColors.orange700),
              _tableCell(_currencyFormat.format(record['penalties']), color: PdfColors.red700),
              _tableCell(_currencyFormat.format(record['netSalary']), isBold: true, color: PdfColors.blue700),
              _tableCell(record['bankName'] ?? '-', align: pw.TextAlign.left),
              _tableCell(record['accountNumber'] ?? '-'),
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
        style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold),
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
    return pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: [
        pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text('Prepared by: _______________________', style: const pw.TextStyle(fontSize: 9)),
            pw.SizedBox(height: 8),
            pw.Text('Date: _______________________', style: const pw.TextStyle(fontSize: 9)),
          ],
        ),
        pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text('Approved by: _______________________', style: const pw.TextStyle(fontSize: 9)),
            pw.SizedBox(height: 8),
            pw.Text('Signature: _______________________', style: const pw.TextStyle(fontSize: 9)),
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
