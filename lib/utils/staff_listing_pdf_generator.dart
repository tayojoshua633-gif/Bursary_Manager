// lib/utils/staff_listing_pdf_generator.dart

import 'dart:io';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:path_provider/path_provider.dart';
import 'package:intl/intl.dart';
import '../models/staff.dart';

class StaffListingPDFGenerator {
  static final _currencyFormat = NumberFormat.currency(symbol: 'N', decimalDigits: 0);

  static Future<String> generateStaffListingPDF({
    required List<Staff> staff,
    required Map<String, dynamic> schoolProfile,
    required String filterType,
    required int totalStaff,
    required int teachingCount,
    required int nonTeachingCount,
    required double totalSalary,
  }) async {
    final pdf = pw.Document();

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4.landscape,
        margin: const pw.EdgeInsets.all(24),
        build: (context) => [
          _buildHeader(schoolProfile, filterType),
          pw.SizedBox(height: 16),
          _buildSummary(totalStaff, teachingCount, nonTeachingCount, totalSalary),
          pw.SizedBox(height: 20),
          _buildStaffTable(staff),
          pw.SizedBox(height: 30),
          _buildFooter(),
          _buildBankDetails(schoolProfile),
        ],
        footer: (context) => _buildPageFooter(context),
      ),
    );

    final output = await getApplicationDocumentsDirectory();
    final timestamp = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
    final fileName = 'Staff_Listing_${filterType.replaceAll(' ', '_')}_$timestamp.pdf';
    final file = File('${output.path}/$fileName');
    await file.writeAsBytes(await pdf.save());

    return file.path;
  }

  static pw.Widget _buildHeader(Map<String, dynamic> schoolProfile, String filterType) {
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
          pw.Text(address, style: const pw.TextStyle(fontSize: 9), textAlign: pw.TextAlign.center),
        ],
        if (phone.isNotEmpty || email.isNotEmpty) ...[
          pw.SizedBox(height: 2),
          pw.Text(
            [if (phone.isNotEmpty) 'Tel: $phone', if (email.isNotEmpty) email].join(' | '),
            style: const pw.TextStyle(fontSize: 9), textAlign: pw.TextAlign.center,
          ),
        ],
        pw.SizedBox(height: 12),
        pw.Container(
          padding: const pw.EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: pw.BoxDecoration(
            color: PdfColors.blueGrey50,
            borderRadius: pw.BorderRadius.circular(4),
          ),
          child: pw.Text(
            'STAFF LISTING - $filterType',
            style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold, color: PdfColors.blueGrey900),
          ),
        ),
      ],
    );
  }

  static pw.Widget _buildSummary(int totalStaff, int teachingCount, int nonTeachingCount, double totalSalary) {
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
              pw.Text('Total Staff', style: pw.TextStyle(fontSize: 9, color: PdfColors.grey600)),
              pw.SizedBox(height: 4),
              pw.Text('$totalStaff', style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
            ],
          ),
          pw.Column(
            children: [
              pw.Text('Teaching Staff', style: pw.TextStyle(fontSize: 9, color: PdfColors.grey600)),
              pw.SizedBox(height: 4),
              pw.Text(
                '$teachingCount',
                style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold, color: PdfColors.green700),
              ),
            ],
          ),
          pw.Column(
            children: [
              pw.Text('Non-Teaching Staff', style: pw.TextStyle(fontSize: 9, color: PdfColors.grey600)),
              pw.SizedBox(height: 4),
              pw.Text(
                '$nonTeachingCount',
                style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold, color: PdfColors.orange700),
              ),
            ],
          ),
          pw.Column(
            children: [
              pw.Text('Total Salary', style: pw.TextStyle(fontSize: 9, color: PdfColors.grey600)),
              pw.SizedBox(height: 4),
              pw.Text(
                _currencyFormat.format(totalSalary),
                style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold, color: PdfColors.blue700),
              ),
            ],
          ),
        ],
      ),
    );
  }

  static pw.Widget _buildStaffTable(List<Staff> staff) {
    return pw.Table(
      border: pw.TableBorder.all(color: PdfColors.grey300),
      columnWidths: {
        0: const pw.FixedColumnWidth(25),   // S/N
        1: const pw.FixedColumnWidth(60),   // Staff ID
        2: const pw.FlexColumnWidth(2),     // Full Name
        3: const pw.FixedColumnWidth(50),   // Gender
        4: const pw.FlexColumnWidth(1.2),   // Staff Type
        5: const pw.FlexColumnWidth(1),     // Phone
        6: const pw.FlexColumnWidth(1),     // Salary
      },
      children: [
        pw.TableRow(
          decoration: const pw.BoxDecoration(color: PdfColors.blueGrey100),
          children: [
            _tableHeader('S/N'),
            _tableHeader('Staff ID'),
            _tableHeader('Full Name'),
            _tableHeader('Gender'),
            _tableHeader('Staff Type'),
            _tableHeader('Phone'),
            _tableHeader('Salary'),
          ],
        ),
        ...staff.asMap().entries.map((entry) {
          final index = entry.key;
          final s = entry.value;
          final isEven = index % 2 == 0;

          return pw.TableRow(
            decoration: pw.BoxDecoration(color: isEven ? PdfColors.white : PdfColors.grey50),
            children: [
              _tableCell('${index + 1}'),
              _tableCell(s.staffId),
              _tableCell(s.fullName, align: pw.TextAlign.left),
              _tableCell(s.gender),
              _tableCell(
                s.staffType,
                color: s.isTeachingStaff ? PdfColors.green700 : PdfColors.orange700,
              ),
              _tableCell(s.phone ?? '-'),
              _tableCell(s.salary > 0 ? _currencyFormat.format(s.salary) : '-'),
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
