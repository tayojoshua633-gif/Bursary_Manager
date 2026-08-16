// lib/utils/staff_deduction_pdf_generator.dart

import 'dart:io';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:path_provider/path_provider.dart';
import 'package:intl/intl.dart';

class StaffDeductionPDFGenerator {
  static final _currencyFormat = NumberFormat.currency(symbol: 'N', decimalDigits: 2);

  static Future<String> generateDeductionPDF({
    required List<Map<String, dynamic>> deductions,
    required String month,
    required Map<String, dynamic> schoolProfile,
    required double totalAmount,
    required Map<String, double> reasonTotals,
  }) async {
    final pdf = pw.Document();

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        build: (context) => [
          _buildHeader(schoolProfile, month),
          pw.SizedBox(height: 20),
          _buildSummary(deductions.length, totalAmount, reasonTotals),
          pw.SizedBox(height: 20),
          _buildDeductionTable(deductions),
          pw.SizedBox(height: 30),
          _buildFooter(),
          _buildBankDetails(schoolProfile),
        ],
        footer: (context) => _buildPageFooter(context),
      ),
    );

    final output = await getApplicationDocumentsDirectory();
    final timestamp = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
    final fileName = 'Staff_Deductions_${month.replaceAll(' ', '_')}_$timestamp.pdf';
    final file = File('${output.path}/$fileName');
    await file.writeAsBytes(await pdf.save());

    return file.path;
  }

  static pw.Widget _buildHeader(Map<String, dynamic> schoolProfile, String month) {
    final schoolName = schoolProfile['name'] ?? 'School Name';
    final address = schoolProfile['address'] ?? '';
    final phone = schoolProfile['phone'] ?? '';
    final email = schoolProfile['email'] ?? '';

    return pw.Column(
      children: [
        pw.Text(
          schoolName.toUpperCase(),
          style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold),
          textAlign: pw.TextAlign.center,
        ),
        if (address.isNotEmpty) ...[
          pw.SizedBox(height: 4),
          pw.Text(address, style: const pw.TextStyle(fontSize: 10), textAlign: pw.TextAlign.center),
        ],
        if (phone.isNotEmpty || email.isNotEmpty) ...[
          pw.SizedBox(height: 2),
          pw.Text(
            [if (phone.isNotEmpty) 'Tel: $phone', if (email.isNotEmpty) email].join(' | '),
            style: const pw.TextStyle(fontSize: 10), textAlign: pw.TextAlign.center,
          ),
        ],
        pw.SizedBox(height: 16),
        pw.Container(
          padding: const pw.EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          decoration: pw.BoxDecoration(
            color: PdfColors.red50,
            borderRadius: pw.BorderRadius.circular(4),
          ),
          child: pw.Text(
            'STAFF PENALTY/DEDUCTION REPORT - $month',
            style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold, color: PdfColors.red900),
          ),
        ),
      ],
    );
  }

  static pw.Widget _buildSummary(int count, double totalAmount, Map<String, double> reasonTotals) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(16),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.grey300),
        borderRadius: pw.BorderRadius.circular(4),
      ),
      child: pw.Column(
        children: [
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceAround,
            children: [
              pw.Column(
                children: [
                  pw.Text('Total Records', style: pw.TextStyle(fontSize: 10, color: PdfColors.grey600)),
                  pw.SizedBox(height: 4),
                  pw.Text('$count', style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
                ],
              ),
              pw.Column(
                children: [
                  pw.Text('Total Amount', style: pw.TextStyle(fontSize: 10, color: PdfColors.grey600)),
                  pw.SizedBox(height: 4),
                  pw.Text(
                    _currencyFormat.format(totalAmount),
                    style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold, color: PdfColors.red700),
                  ),
                ],
              ),
            ],
          ),
          if (reasonTotals.isNotEmpty) ...[
            pw.SizedBox(height: 12),
            pw.Divider(),
            pw.SizedBox(height: 8),
            pw.Text('Breakdown by Reason:', style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 8),
            pw.Wrap(
              spacing: 16,
              runSpacing: 8,
              children: reasonTotals.entries.map((e) => pw.Container(
                padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: pw.BoxDecoration(
                  color: PdfColors.grey100,
                  borderRadius: pw.BorderRadius.circular(4),
                ),
                child: pw.Text(
                  '${e.key}: ${_currencyFormat.format(e.value)}',
                  style: const pw.TextStyle(fontSize: 9),
                ),
              )).toList(),
            ),
          ],
        ],
      ),
    );
  }

  static pw.Widget _buildDeductionTable(List<Map<String, dynamic>> deductions) {
    return pw.Table(
      border: pw.TableBorder.all(color: PdfColors.grey300),
      columnWidths: {
        0: const pw.FixedColumnWidth(30),   // S/N
        1: const pw.FlexColumnWidth(2),     // Staff Name
        2: const pw.FlexColumnWidth(1.2),   // Reason
        3: const pw.FlexColumnWidth(1.5),   // Description
        4: const pw.FixedColumnWidth(70),   // Date
        5: const pw.FlexColumnWidth(1),     // Amount
      },
      children: [
        pw.TableRow(
          decoration: const pw.BoxDecoration(color: PdfColors.red100),
          children: [
            _tableHeader('S/N'),
            _tableHeader('Staff Name'),
            _tableHeader('Reason'),
            _tableHeader('Description'),
            _tableHeader('Date'),
            _tableHeader('Amount'),
          ],
        ),
        ...deductions.asMap().entries.map((entry) {
          final index = entry.key;
          final ded = entry.value;
          final isEven = index % 2 == 0;

          return pw.TableRow(
            decoration: pw.BoxDecoration(color: isEven ? PdfColors.white : PdfColors.grey50),
            children: [
              _tableCell('${index + 1}'),
              _tableCell(ded['staffName'] ?? '', align: pw.TextAlign.left),
              _tableCell(ded['reason'] ?? ''),
              _tableCell(ded['description'] ?? '-', align: pw.TextAlign.left),
              _tableCell(ded['date'] ?? ''),
              _tableCell(_currencyFormat.format(ded['amount']), color: PdfColors.red700),
            ],
          );
        }),
      ],
    );
  }

  static pw.Widget _tableHeader(String text) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(8),
      child: pw.Text(
        text,
        style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold),
        textAlign: pw.TextAlign.center,
      ),
    );
  }

  static pw.Widget _tableCell(String text, {pw.TextAlign align = pw.TextAlign.center, PdfColor? color}) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(8),
      child: pw.Text(
        text,
        style: pw.TextStyle(fontSize: 9, color: color),
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
            pw.Text('Prepared by: _______________________', style: const pw.TextStyle(fontSize: 10)),
            pw.SizedBox(height: 8),
            pw.Text('Date: _______________________', style: const pw.TextStyle(fontSize: 10)),
          ],
        ),
        pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text('Approved by: _______________________', style: const pw.TextStyle(fontSize: 10)),
            pw.SizedBox(height: 8),
            pw.Text('Signature: _______________________', style: const pw.TextStyle(fontSize: 10)),
          ],
        ),
      ],
    );
  }

  static pw.Widget _buildPageFooter(pw.Context context) {
    return pw.Container(
      alignment: pw.Alignment.centerRight,
      margin: const pw.EdgeInsets.only(top: 10),
      child: pw.Text(
        'Page ${context.pageNumber} of ${context.pagesCount}',
        style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600),
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
}
