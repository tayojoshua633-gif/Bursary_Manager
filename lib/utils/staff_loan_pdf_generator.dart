// lib/utils/staff_loan_pdf_generator.dart

import 'dart:io';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:path_provider/path_provider.dart';
import 'package:intl/intl.dart';

class StaffLoanPDFGenerator {
  static final _currencyFormat = NumberFormat.currency(symbol: 'N', decimalDigits: 2);

  static Future<String> generateLoanPDF({
    required List<Map<String, dynamic>> loans,
    required Map<String, dynamic> schoolProfile,
    required String filterStatus,
    required double totalLoans,
    required double totalBalance,
  }) async {
    final pdf = pw.Document();

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4.landscape,
        margin: const pw.EdgeInsets.all(24),
        build: (context) => [
          _buildHeader(schoolProfile, filterStatus),
          pw.SizedBox(height: 16),
          _buildSummary(loans.length, totalLoans, totalBalance),
          pw.SizedBox(height: 20),
          _buildLoanTable(loans),
          pw.SizedBox(height: 20),
          _buildBankDetails(schoolProfile),
          pw.SizedBox(height: 30),
          _buildFooter(),
        ],
        footer: (context) => _buildPageFooter(context),
      ),
    );

    final output = await getApplicationDocumentsDirectory();
    final timestamp = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
    final fileName = 'Staff_Loans_${filterStatus}_$timestamp.pdf';
    final file = File('${output.path}/$fileName');
    await file.writeAsBytes(await pdf.save());

    return file.path;
  }

  static pw.Widget _buildHeader(Map<String, dynamic> schoolProfile, String filterStatus) {
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
            color: PdfColors.orange50,
            borderRadius: pw.BorderRadius.circular(4),
          ),
          child: pw.Text(
            'STAFF LOANS REPORT - $filterStatus',
            style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold, color: PdfColors.orange900),
          ),
        ),
      ],
    );
  }

  static pw.Widget _buildSummary(int count, double totalLoans, double totalBalance) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(12),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.grey300),
        borderRadius: pw.BorderRadius.circular(4),
      ),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceAround,
        children: [
          pw.Column(
            children: [
              pw.Text('Total Records', style: pw.TextStyle(fontSize: 9, color: PdfColors.grey600)),
              pw.SizedBox(height: 4),
              pw.Text('$count', style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
            ],
          ),
          pw.Column(
            children: [
              pw.Text('Total Loan Amount', style: pw.TextStyle(fontSize: 9, color: PdfColors.grey600)),
              pw.SizedBox(height: 4),
              pw.Text(
                _currencyFormat.format(totalLoans),
                style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold, color: PdfColors.orange700),
              ),
            ],
          ),
          pw.Column(
            children: [
              pw.Text('Outstanding Balance', style: pw.TextStyle(fontSize: 9, color: PdfColors.grey600)),
              pw.SizedBox(height: 4),
              pw.Text(
                _currencyFormat.format(totalBalance),
                style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold, color: PdfColors.red700),
              ),
            ],
          ),
        ],
      ),
    );
  }

  static pw.Widget _buildLoanTable(List<Map<String, dynamic>> loans) {
    return pw.Table(
      border: pw.TableBorder.all(color: PdfColors.grey300),
      columnWidths: {
        0: const pw.FixedColumnWidth(25),   // S/N
        1: const pw.FlexColumnWidth(2),     // Staff Name
        2: const pw.FlexColumnWidth(1.5),   // Reason
        3: const pw.FlexColumnWidth(1),     // Loan Amount
        4: const pw.FlexColumnWidth(1),     // Monthly Ded.
        5: const pw.FixedColumnWidth(50),   // Months Left
        6: const pw.FlexColumnWidth(1),     // Balance
        7: const pw.FixedColumnWidth(60),   // Status
        8: const pw.FlexColumnWidth(1),     // Collection Date
      },
      children: [
        pw.TableRow(
          decoration: const pw.BoxDecoration(color: PdfColors.orange100),
          children: [
            _tableHeader('S/N'),
            _tableHeader('Staff Name'),
            _tableHeader('Reason'),
            _tableHeader('Loan Amount'),
            _tableHeader('Monthly Ded.'),
            _tableHeader('Months Left'),
            _tableHeader('Balance'),
            _tableHeader('Status'),
            _tableHeader('Collection Date'),
          ],
        ),
        ...loans.asMap().entries.map((entry) {
          final index = entry.key;
          final loan = entry.value;
          final isEven = index % 2 == 0;
          final isActive = loan['status'] == 'Active';

          // Calculate balance
          final amount = (loan['amount'] as num).toDouble();
          final deduction = (loan['deductionPerMonth'] as num).toDouble();
          final monthsRemaining = loan['monthsRemaining'] as int;
          final balance = deduction * monthsRemaining;

          // Format collection date
          String collectionDate = '-';
          if (loan['collectionDate'] != null && loan['collectionDate'].toString().isNotEmpty) {
            try {
              final date = DateTime.parse(loan['collectionDate']);
              collectionDate = DateFormat('dd/MM/yyyy').format(date);
            } catch (_) {
              collectionDate = loan['collectionDate'].toString();
            }
          }

          return pw.TableRow(
            decoration: pw.BoxDecoration(color: isEven ? PdfColors.white : PdfColors.grey50),
            children: [
              _tableCell('${index + 1}'),
              _tableCell(loan['staffName'] ?? '', align: pw.TextAlign.left),
              _tableCell(loan['reason'] ?? '', align: pw.TextAlign.left),
              _tableCell(_currencyFormat.format(amount)),
              _tableCell(_currencyFormat.format(deduction)),
              _tableCell('$monthsRemaining'),
              _tableCell(_currencyFormat.format(balance), color: PdfColors.red700),
              _tableCell(
                loan['status'] ?? '',
                color: isActive ? PdfColors.orange700 : PdfColors.green700,
              ),
              _tableCell(collectionDate),
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

  static pw.Widget _tableCell(String text, {pw.TextAlign align = pw.TextAlign.center, PdfColor? color}) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(5),
      child: pw.Text(
        text,
        style: pw.TextStyle(fontSize: 7, color: color),
        textAlign: align,
      ),
    );
  }

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
