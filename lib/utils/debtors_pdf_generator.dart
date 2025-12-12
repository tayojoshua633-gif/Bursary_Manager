// lib/utils/debtors_pdf_generator.dart

import 'dart:io';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:path_provider/path_provider.dart';
import 'package:intl/intl.dart';

class DebtorsPDFGenerator {
  static Future<String> generateDebtorsPDF({
    required List<Map<String, dynamic>> debtors,
    required String className,
    required String term,
    required String session,
    required Map<String, dynamic> schoolProfile,
    required String filterType,
    required double minPercentage,
  }) async {
    final pdf = pw.Document();

    // Calculate totals
    double totalBills = 0;
    double totalPaid = 0;
    double totalOutstanding = 0;

    for (var debtor in debtors) {
      totalBills += (debtor['totalBill'] as num).toDouble();
      totalPaid += (debtor['totalPaid'] as num).toDouble();
      totalOutstanding += (debtor['outstanding'] as num).toDouble();
    }

    // Create PDF pages
    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        build: (context) => [
          // Header
          _buildHeader(schoolProfile, className, term, session),
          pw.SizedBox(height: 20),

          // Filter Info
          _buildFilterInfo(filterType, minPercentage, debtors.length),
          pw.SizedBox(height: 20),

          // Summary
          _buildSummary(totalBills, totalPaid, totalOutstanding),
          pw.SizedBox(height: 20),

          // Debtors Table
          _buildDebtorsTable(debtors),
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
    final fileName = 'Debtors_${className.replaceAll(' ', '_')}_$timestamp.pdf';
    final file = File('${output.path}/$fileName');
    await file.writeAsBytes(await pdf.save());

    return file.path;
  }

  static pw.Widget _buildHeader(
    Map<String, dynamic> schoolProfile,
    String className,
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
          pw.SizedBox(height: 4),
          pw.Text(
            [if (phone.isNotEmpty) 'Tel: $phone', if (email.isNotEmpty) email]
                .join(' | '),
            style: const pw.TextStyle(fontSize: 9),
            textAlign: pw.TextAlign.center,
          ),
        ],
        pw.SizedBox(height: 12),
        pw.Divider(thickness: 2),
        pw.SizedBox(height: 12),

        // Report Title
        pw.Text(
          'DEBTORS LIST',
          style: pw.TextStyle(
            fontSize: 16,
            fontWeight: pw.FontWeight.bold,
          ),
        ),
        pw.SizedBox(height: 8),

        // Period Info
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text('Class: $className', style: const pw.TextStyle(fontSize: 11)),
            pw.Text('Term: $term', style: const pw.TextStyle(fontSize: 11)),
            pw.Text('Session: $session', style: const pw.TextStyle(fontSize: 11)),
          ],
        ),
        pw.SizedBox(height: 4),
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text(
              'Generated: ${DateFormat('MMM d, yyyy - h:mm a').format(DateTime.now())}',
              style: pw.TextStyle(fontSize: 9, color: PdfColors.grey700),
            ),
          ],
        ),
      ],
    );
  }

  static pw.Widget _buildFilterInfo(
    String filterType,
    double minPercentage,
    int debtorsCount,
  ) {
    final filterDesc = filterType == 'all'
        ? 'All students with outstanding balances'
        : 'Students who paid less than ${minPercentage.toStringAsFixed(0)}% of their bills';

    return pw.Container(
      padding: const pw.EdgeInsets.all(10),
      decoration: pw.BoxDecoration(
        color: PdfColors.blue50,
        border: pw.Border.all(color: PdfColors.blue200),
        borderRadius: pw.BorderRadius.circular(4),
      ),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Expanded(
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  'Filter Applied:',
                  style: pw.TextStyle(
                    fontSize: 10,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
                pw.SizedBox(height: 2),
                pw.Text(
                  filterDesc,
                  style: const pw.TextStyle(fontSize: 9),
                ),
              ],
            ),
          ),
          pw.Container(
            padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: pw.BoxDecoration(
              color: PdfColors.red100,
              borderRadius: pw.BorderRadius.circular(4),
            ),
            child: pw.Text(
              '$debtorsCount Debtor${debtorsCount != 1 ? 's' : ''}',
              style: pw.TextStyle(
                fontSize: 10,
                fontWeight: pw.FontWeight.bold,
                color: PdfColors.red800,
              ),
            ),
          ),
        ],
      ),
    );
  }

  static pw.Widget _buildSummary(
    double totalBills,
    double totalPaid,
    double totalOutstanding,
  ) {
    final formatter = NumberFormat('#,##0.00');

    return pw.Container(
      padding: const pw.EdgeInsets.all(12),
      decoration: pw.BoxDecoration(
        color: PdfColors.red50,
        border: pw.Border.all(color: PdfColors.red200),
        borderRadius: pw.BorderRadius.circular(4),
      ),
      child: pw.Column(
        children: [
          pw.Text(
            'FINANCIAL SUMMARY',
            style: pw.TextStyle(
              fontSize: 12,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
          pw.SizedBox(height: 10),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceAround,
            children: [
              _buildSummaryItem('Total Bills', totalBills, PdfColors.blue800, formatter),
              _buildSummaryItem('Total Paid', totalPaid, PdfColors.green800, formatter),
              _buildSummaryItem('Outstanding', totalOutstanding, PdfColors.red800, formatter),
            ],
          ),
        ],
      ),
    );
  }

  static pw.Widget _buildSummaryItem(
    String label,
    double amount,
    PdfColor color,
    NumberFormat formatter,
  ) {
    return pw.Column(
      children: [
        pw.Text(
          label,
          style: pw.TextStyle(
            fontSize: 9,
            color: PdfColors.grey700,
          ),
        ),
        pw.SizedBox(height: 4),
        pw.Text(
          '₦${formatter.format(amount)}',
          style: pw.TextStyle(
            fontSize: 11,
            fontWeight: pw.FontWeight.bold,
            color: color,
          ),
        ),
      ],
    );
  }

  static pw.Widget _buildDebtorsTable(List<Map<String, dynamic>> debtors) {
    final formatter = NumberFormat('#,##0.00');

    return pw.Table(
      border: pw.TableBorder.all(color: PdfColors.grey400),
      columnWidths: {
        0: const pw.FixedColumnWidth(30),
        1: const pw.FixedColumnWidth(70),
        2: const pw.FlexColumnWidth(2),
        3: const pw.FixedColumnWidth(70),
        4: const pw.FixedColumnWidth(70),
        5: const pw.FixedColumnWidth(70),
        6: const pw.FixedColumnWidth(50),
      },
      children: [
        // Header Row
        pw.TableRow(
          decoration: const pw.BoxDecoration(color: PdfColors.grey300),
          children: [
            _buildTableHeader('S/N'),
            _buildTableHeader('Adm. No'),
            _buildTableHeader('Student Name'),
            _buildTableHeader('Total Bill'),
            _buildTableHeader('Paid'),
            _buildTableHeader('Outstanding'),
            _buildTableHeader('% Paid'),
          ],
        ),
        // Data Rows
        ...debtors.asMap().entries.map((entry) {
          final index = entry.key;
          final debtor = entry.value;

          final totalBill = (debtor['totalBill'] as num).toDouble();
          final totalPaid = (debtor['totalPaid'] as num).toDouble();
          final outstanding = (debtor['outstanding'] as num).toDouble();
          final percentPaid = (debtor['percentPaid'] as num).toDouble();

          return pw.TableRow(
            decoration: pw.BoxDecoration(
              color: index % 2 == 0 ? PdfColors.white : PdfColors.grey100,
            ),
            children: [
              _buildTableCell('${index + 1}'),
              _buildTableCell(debtor['admissionNo'] ?? ''),
              _buildTableCell(
                '${debtor['surname']} ${debtor['firstName']}',
                alignment: pw.Alignment.centerLeft,
              ),
              _buildTableCell('₦${formatter.format(totalBill)}'),
              _buildTableCell('₦${formatter.format(totalPaid)}'),
              _buildTableCell(
                '₦${formatter.format(outstanding)}',
                textColor: PdfColors.red800,
              ),
              _buildTableCell('${percentPaid.toStringAsFixed(1)}%'),
            ],
          );
        }),
      ],
    );
  }

  static pw.Widget _buildTableHeader(String text) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(6),
      alignment: pw.Alignment.center,
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
    pw.Alignment? alignment,
    PdfColor? textColor,
  }) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(6),
      alignment: alignment ?? pw.Alignment.center,
      child: pw.Text(
        text,
        style: pw.TextStyle(
          fontSize: 8,
          color: textColor,
        ),
        textAlign: alignment == pw.Alignment.centerLeft
            ? pw.TextAlign.left
            : pw.TextAlign.center,
      ),
    );
  }

  static pw.Widget _buildFooter() {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Divider(),
        pw.SizedBox(height: 10),
        pw.Text(
          'Note: This report shows students with outstanding fee balances. Please follow up with parents/guardians for payment.',
          style: pw.TextStyle(
            fontSize: 8,
            fontStyle: pw.FontStyle.italic,
            color: PdfColors.grey700,
          ),
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
        style: pw.TextStyle(
          fontSize: 8,
          color: PdfColors.grey600,
        ),
      ),
    );
  }
}