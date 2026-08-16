// lib/utils/overpayment_tracker_pdf_generator.dart

import 'dart:io';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:path_provider/path_provider.dart';
import 'package:intl/intl.dart';

class OverpaymentTrackerPDFGenerator {
  static Future<String> generateOverpaymentTrackerPDF({
    required String term,
    required String session,
    required Map<String, dynamic> schoolProfile,
    required List<Map<String, dynamic>> overpayments,
  }) async {
    final pdf = pw.Document();
    final formatter = NumberFormat('#,##0.00');

    // Calculate totals
    double totalBills = 0;
    double totalPaid = 0;
    double totalOverpaid = 0;

    for (var item in overpayments) {
      totalBills += (item['billAmount'] as num?)?.toDouble() ?? 0.0;
      totalPaid += (item['paidAmount'] as num?)?.toDouble() ?? 0.0;
      totalOverpaid += (item['overpaid'] as num?)?.toDouble() ?? 0.0;
    }

    // Create PDF pages
    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        build: (context) => [
          // Header
          _buildHeader(schoolProfile, term, session),
          pw.SizedBox(height: 20),

          // Summary
          _buildSummary(overpayments.length, totalBills, totalPaid, totalOverpaid, formatter),
          pw.SizedBox(height: 20),

          // Overpayments Table
          _buildOverpaymentsTable(overpayments, formatter),
          pw.SizedBox(height: 20),

          // Footer
          _buildFooter(),

          // Bank Details
          _buildBankDetails(schoolProfile),
        ],
        footer: (context) => _buildPageFooter(context),
      ),
    );

    // Save to file
    final output = await getApplicationDocumentsDirectory();
    final timestamp = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
    final fileName = 'Overpayment_Tracker_${term}_${session}_$timestamp.pdf';
    final file = File('${output.path}/$fileName');
    await file.writeAsBytes(await pdf.save());

    return file.path;
  }

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
      crossAxisAlignment: pw.CrossAxisAlignment.center,
      children: [
        pw.Text(
          schoolName.toUpperCase(),
          style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold),
        ),
        if (address.isNotEmpty)
          pw.Text(
            address,
            style: const pw.TextStyle(fontSize: 10),
          ),
        if (phone.isNotEmpty || email.isNotEmpty)
          pw.Text(
            [if (phone.isNotEmpty) 'Tel: $phone', if (email.isNotEmpty) email].where((s) => s.isNotEmpty).join(' | '),
            style: const pw.TextStyle(fontSize: 10),
          ),
        pw.SizedBox(height: 10),
        pw.Container(
          padding: const pw.EdgeInsets.symmetric(vertical: 8, horizontal: 16),
          decoration: pw.BoxDecoration(
            border: pw.Border.all(color: PdfColors.purple, width: 2),
            borderRadius: pw.BorderRadius.circular(4),
          ),
          child: pw.Text(
            'OVERPAYMENT TRACKER',
            style: pw.TextStyle(
              fontSize: 16,
              fontWeight: pw.FontWeight.bold,
              color: PdfColors.purple,
            ),
          ),
        ),
        pw.SizedBox(height: 8),
        pw.Text(
          '$term - $session',
          style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold),
        ),
        pw.Text(
          'Generated: ${DateFormat('dd MMM yyyy, hh:mm a').format(DateTime.now())}',
          style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700),
        ),
      ],
    );
  }

  static pw.Widget _buildSummary(
    int totalStudents,
    double totalBills,
    double totalPaid,
    double totalOverpaid,
    NumberFormat formatter,
  ) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(12),
      decoration: pw.BoxDecoration(
        color: PdfColors.purple50,
        border: pw.Border.all(color: PdfColors.purple, width: 1),
        borderRadius: pw.BorderRadius.circular(4),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            'SUMMARY',
            style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 8),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text('Total Students with Overpayments:', style: const pw.TextStyle(fontSize: 11)),
              pw.Text(
                totalStudents.toString(),
                style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold),
              ),
            ],
          ),
          pw.SizedBox(height: 4),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text('Total Bills:', style: const pw.TextStyle(fontSize: 11)),
              pw.Text(
                'N ${formatter.format(totalBills)}',
                style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold),
              ),
            ],
          ),
          pw.SizedBox(height: 4),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text('Total Paid:', style: const pw.TextStyle(fontSize: 11)),
              pw.Text(
                'N ${formatter.format(totalPaid)}',
                style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold),
              ),
            ],
          ),
          pw.SizedBox(height: 4),
          pw.Divider(color: PdfColors.purple, thickness: 1),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text(
                'Total Overpaid:',
                style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold),
              ),
              pw.Text(
                'N ${formatter.format(totalOverpaid)}',
                style: pw.TextStyle(
                  fontSize: 12,
                  fontWeight: pw.FontWeight.bold,
                  color: PdfColors.purple,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  static pw.Widget _buildOverpaymentsTable(
    List<Map<String, dynamic>> overpayments,
    NumberFormat formatter,
  ) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          'STUDENT DETAILS',
          style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold),
        ),
        pw.SizedBox(height: 8),
        pw.TableHelper.fromTextArray(
          headerStyle: pw.TextStyle(
            fontWeight: pw.FontWeight.bold,
            fontSize: 9,
            color: PdfColors.white,
          ),
          cellStyle: const pw.TextStyle(fontSize: 8),
          headerDecoration: const pw.BoxDecoration(color: PdfColors.purple),
          cellAlignment: pw.Alignment.centerLeft,
          headerAlignment: pw.Alignment.center,
          cellPadding: const pw.EdgeInsets.all(4),
          headers: ['S/N', 'Adm. No', 'Student Name', 'Class/Arm', 'Bill (N)', 'Paid (N)', 'Overpaid (N)'],
          data: List.generate(
            overpayments.length,
            (index) {
              final item = overpayments[index];
              final surname = item['surname'] ?? '';
              final firstName = item['firstName'] ?? '';
              final admissionNo = item['admissionNo'] ?? '';
              final className = item['className'] ?? 'N/A';
              final armName = item['armName'] ?? 'N/A';
              final billAmount = (item['billAmount'] as num?)?.toDouble() ?? 0.0;
              final paidAmount = (item['paidAmount'] as num?)?.toDouble() ?? 0.0;
              final overpaid = (item['overpaid'] as num?)?.toDouble() ?? 0.0;

              return [
                (index + 1).toString(),
                admissionNo,
                '$surname $firstName',
                '$className - $armName',
                formatter.format(billAmount),
                formatter.format(paidAmount),
                formatter.format(overpaid),
              ];
            },
          ),
        ),
      ],
    );
  }

  static pw.Widget _buildFooter() {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Divider(color: PdfColors.grey400),
        pw.SizedBox(height: 8),
        pw.Text(
          'Note: This report shows students who have paid more than their total bill for the current term/session.',
          style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700),
        ),
        pw.SizedBox(height: 4),
        pw.Text(
          'Overpayments may be applied to future terms or refunded as per school policy.',
          style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700),
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
        style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey600),
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
