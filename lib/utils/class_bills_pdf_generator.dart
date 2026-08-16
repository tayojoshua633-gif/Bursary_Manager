import 'dart:io';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:path_provider/path_provider.dart';
import 'package:intl/intl.dart';

class ClassBillsPDFGenerator {
  static Future<String> generateClassBillsPDF({
    required List<Map<String, dynamic>> studentBills,
    required String term,
    required String session,
    required Map<String, dynamic> schoolProfile,
    String? filterClassName,
  }) async {
    final pdf = pw.Document();

    // Calculate totals
    double totalBills = 0;
    double totalPaid = 0;
    double totalOutstanding = 0;

    for (var bill in studentBills) {
      final billAmount = (bill['totalBill'] as num).toDouble();
      final paidAmount = (bill['totalPaid'] as num).toDouble();
      totalBills += billAmount;
      totalPaid += paidAmount;
      totalOutstanding += (billAmount - paidAmount);
    }

    // Create PDF pages
    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4.landscape,
        margin: const pw.EdgeInsets.all(32),
        build: (context) => [
          // Header
          _buildHeader(schoolProfile, term, session, filterClassName),
          pw.SizedBox(height: 20),

          // Summary
          _buildSummary(totalBills, totalPaid, totalOutstanding, studentBills.length),
          pw.SizedBox(height: 20),

          // Student Bills Table
          _buildStudentBillsTable(studentBills),
          pw.SizedBox(height: 20),

          // Bank Details
          _buildBankDetails(schoolProfile),
          pw.SizedBox(height: 20),

          // Footer
          _buildFooter(),
        ],
        footer: (context) => _buildPageFooter(context),
      ),
    );

    // Save to file
    final output = await getApplicationDocumentsDirectory();
    final timestamp = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
    final fileName = 'Class_Bills_${filterClassName ?? 'All'}_$timestamp.pdf';
    final file = File('${output.path}/$fileName');
    await file.writeAsBytes(await pdf.save());

    return file.path;
  }

  static pw.Widget _buildHeader(
    Map<String, dynamic> schoolProfile,
    String term,
    String session,
    String? filterClassName,
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
          style: pw.TextStyle(
            fontSize: 20,
            fontWeight: pw.FontWeight.bold,
          ),
          textAlign: pw.TextAlign.center,
        ),
        if (address.isNotEmpty) ...[
          pw.SizedBox(height: 4),
          pw.Text(
            address,
            style: const pw.TextStyle(fontSize: 10),
            textAlign: pw.TextAlign.center,
          ),
        ],
        if (phone.isNotEmpty || email.isNotEmpty) ...[
          pw.SizedBox(height: 2),
          pw.Text(
            [if (phone.isNotEmpty) 'Tel: $phone', if (email.isNotEmpty) email]
                .join(' | '),
            style: const pw.TextStyle(fontSize: 10),
            textAlign: pw.TextAlign.center,
          ),
        ],
        pw.SizedBox(height: 16),
        pw.Divider(thickness: 2),
        pw.SizedBox(height: 12),

        // Report Title
        pw.Text(
          'CLASS BILLS REPORT',
          style: pw.TextStyle(
            fontSize: 16,
            fontWeight: pw.FontWeight.bold,
          ),
          textAlign: pw.TextAlign.center,
        ),
        pw.SizedBox(height: 8),
        pw.Text(
          '$term, $session',
          style: const pw.TextStyle(fontSize: 12),
          textAlign: pw.TextAlign.center,
        ),
        if (filterClassName != null) ...[
          pw.SizedBox(height: 4),
          pw.Text(
            'Class: $filterClassName',
            style: pw.TextStyle(
              fontSize: 11,
              fontWeight: pw.FontWeight.bold,
            ),
            textAlign: pw.TextAlign.center,
          ),
        ],
      ],
    );
  }

  static pw.Widget _buildSummary(
    double totalBills,
    double totalPaid,
    double totalOutstanding,
    int studentCount,
  ) {
    final formatter = NumberFormat('#,##0.00');

    return pw.Container(
      padding: const pw.EdgeInsets.all(12),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.grey400),
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
      ),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceAround,
        children: [
          _buildSummaryItem('Total Students', studentCount.toString(), PdfColors.blue700),
          _buildSummaryItem('Total Bills', 'N${formatter.format(totalBills)}', PdfColors.indigo700),
          _buildSummaryItem('Total Paid', 'N${formatter.format(totalPaid)}', PdfColors.green700),
          _buildSummaryItem('Outstanding', 'N${formatter.format(totalOutstanding)}',
              totalOutstanding > 0 ? PdfColors.red700 : PdfColors.green700),
        ],
      ),
    );
  }

  static pw.Widget _buildSummaryItem(String label, String value, PdfColor color) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.center,
      children: [
        pw.Text(
          label,
          style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700),
        ),
        pw.SizedBox(height: 4),
        pw.Text(
          value,
          style: pw.TextStyle(
            fontSize: 12,
            fontWeight: pw.FontWeight.bold,
            color: color,
          ),
        ),
      ],
    );
  }

  static pw.Widget _buildStudentBillsTable(List<Map<String, dynamic>> studentBills) {
    final formatter = NumberFormat('#,##0.00');

    return pw.Table(
      border: pw.TableBorder.all(color: PdfColors.grey400),
      columnWidths: {
        0: const pw.FlexColumnWidth(1), // S/N
        1: const pw.FlexColumnWidth(4), // Name
        2: const pw.FlexColumnWidth(3), // Class/Arm
        3: const pw.FlexColumnWidth(2.5), // Total Bill
        4: const pw.FlexColumnWidth(2.5), // Paid
        5: const pw.FlexColumnWidth(2.5), // Outstanding
        6: const pw.FlexColumnWidth(2), // Status
      },
      children: [
        // Header Row
        pw.TableRow(
          decoration: const pw.BoxDecoration(color: PdfColors.grey300),
          children: [
            _buildTableHeader('S/N'),
            _buildTableHeader('Student Name'),
            _buildTableHeader('Class/Arm'),
            _buildTableHeader('Total Bill'),
            _buildTableHeader('Paid'),
            _buildTableHeader('Outstanding'),
            _buildTableHeader('Status'),
          ],
        ),

        // Data Rows
        ...studentBills.asMap().entries.map((entry) {
          final index = entry.key;
          final bill = entry.value;

          final surname = bill['surname'] as String;
          final firstName = bill['firstName'] as String;
          final otherName = bill['otherName'] as String?;
          final fullName = '$surname $firstName ${otherName ?? ''}'.trim();

          final className = bill['className'] as String;
          final armName = bill['armName'] as String?;
          final classArm = armName != null ? '$className - $armName' : className;

          final totalBill = (bill['totalBill'] as num).toDouble();
          final totalPaid = (bill['totalPaid'] as num).toDouble();
          final outstanding = totalBill - totalPaid;

          String status;
          PdfColor statusColor;
          if (outstanding <= 0) {
            status = 'Paid';
            statusColor = PdfColors.green700;
          } else if (totalPaid > 0) {
            status = 'Partial';
            statusColor = PdfColors.orange700;
          } else {
            status = 'Unpaid';
            statusColor = PdfColors.red700;
          }

          return pw.TableRow(
            children: [
              _buildTableCell((index + 1).toString(), align: pw.TextAlign.center),
              _buildTableCell(fullName),
              _buildTableCell(classArm),
              _buildTableCell('N${formatter.format(totalBill)}', align: pw.TextAlign.right),
              _buildTableCell('N${formatter.format(totalPaid)}', align: pw.TextAlign.right),
              _buildTableCell('N${formatter.format(outstanding)}', align: pw.TextAlign.right),
              _buildTableCell(status, align: pw.TextAlign.center, color: statusColor),
            ],
          );
        }),
      ],
    );
  }

  static pw.Widget _buildTableHeader(String text) {
    return pw.Padding(
      padding: const pw.EdgeInsets.all(6),
      child: pw.Text(
        text,
        style: pw.TextStyle(
          fontSize: 9,
          fontWeight: pw.FontWeight.bold,
        ),
        textAlign: pw.TextAlign.center,
      ),
    );
  }

  static pw.Widget _buildTableCell(
    String text, {
    pw.TextAlign align = pw.TextAlign.left,
    PdfColor color = PdfColors.black,
  }) {
    return pw.Padding(
      padding: const pw.EdgeInsets.all(6),
      child: pw.Text(
        text,
        style: pw.TextStyle(fontSize: 8, color: color),
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
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Divider(thickness: 1),
        pw.SizedBox(height: 8),
        pw.Text(
          'Legend:',
          style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold),
        ),
        pw.SizedBox(height: 4),
        pw.Row(
          children: [
            pw.Container(
              width: 8,
              height: 8,
              color: PdfColors.green700,
            ),
            pw.SizedBox(width: 4),
            pw.Text('Paid - No outstanding balance', style: const pw.TextStyle(fontSize: 8)),
            pw.SizedBox(width: 16),
            pw.Container(
              width: 8,
              height: 8,
              color: PdfColors.orange700,
            ),
            pw.SizedBox(width: 4),
            pw.Text('Partial - Some payment made', style: const pw.TextStyle(fontSize: 8)),
            pw.SizedBox(width: 16),
            pw.Container(
              width: 8,
              height: 8,
              color: PdfColors.red700,
            ),
            pw.SizedBox(width: 4),
            pw.Text('Unpaid - No payment yet', style: const pw.TextStyle(fontSize: 8)),
          ],
        ),
      ],
    );
  }

  static pw.Widget _buildPageFooter(pw.Context context) {
    final now = DateTime.now();
    final dateStr = DateFormat('MMM d, yyyy h:mm a').format(now);

    return pw.Container(
      alignment: pw.Alignment.centerRight,
      margin: const pw.EdgeInsets.only(top: 10),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(
            'Generated: $dateStr',
            style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700),
          ),
          pw.Text(
            'Page ${context.pageNumber} of ${context.pagesCount}',
            style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700),
          ),
        ],
      ),
    );
  }
}
