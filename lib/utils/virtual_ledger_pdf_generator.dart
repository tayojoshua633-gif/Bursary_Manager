// lib/utils/virtual_ledger_pdf_generator.dart

import 'dart:io';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:path_provider/path_provider.dart';
import 'package:intl/intl.dart';

class VirtualLedgerPDFGenerator {
  static Future<String> generateVirtualLedgerPDF({
    required List<Map<String, dynamic>> ledger,
    required int maxInstalments,
    required String className,
    required String term,
    required String session,
    required Map<String, dynamic> schoolProfile,
  }) async {
    final pdf = pw.Document();

    double totalBills = 0;
    double totalPaid = 0;
    int balancedCount = 0;

    for (var row in ledger) {
      totalBills += (row['totalBill'] as num).toDouble();
      totalPaid += (row['totalPaid'] as num).toDouble();
      if (row['remark'] == 'Balanced') balancedCount++;
    }

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4.landscape,
        margin: const pw.EdgeInsets.all(24),
        build: (context) => [
          _buildHeader(schoolProfile, className, term, session),
          pw.SizedBox(height: 16),
          _buildSummary(totalBills, totalPaid, balancedCount, ledger.length),
          pw.SizedBox(height: 16),
          _buildLedgerTable(ledger, maxInstalments),
          pw.SizedBox(height: 16),
          _buildFooter(),
        ],
        footer: (context) => _buildPageFooter(context),
      ),
    );

    final output = await getApplicationDocumentsDirectory();
    final timestamp = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
    final fileName = 'VirtualLedger_${className.replaceAll(' ', '_')}_$timestamp.pdf';
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
          pw.SizedBox(height: 4),
          pw.Text(
            [if (phone.isNotEmpty) 'Tel: $phone', if (email.isNotEmpty) email].join(' | '),
            style: const pw.TextStyle(fontSize: 9),
            textAlign: pw.TextAlign.center,
          ),
        ],
        pw.SizedBox(height: 10),
        pw.Divider(thickness: 2),
        pw.SizedBox(height: 10),
        pw.Text(
          'VIRTUAL LEDGER',
          style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold),
        ),
        pw.SizedBox(height: 6),
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text('Class: $className', style: const pw.TextStyle(fontSize: 10)),
            pw.Text('Term: $term', style: const pw.TextStyle(fontSize: 10)),
            pw.Text('Session: $session', style: const pw.TextStyle(fontSize: 10)),
            pw.Text(
              'Generated: ${DateFormat('MMM d, yyyy - h:mm a').format(DateTime.now())}',
              style: pw.TextStyle(fontSize: 8, color: PdfColors.grey700),
            ),
          ],
        ),
      ],
    );
  }

  static pw.Widget _buildSummary(
    double totalBills,
    double totalPaid,
    int balancedCount,
    int studentCount,
  ) {
    final formatter = NumberFormat('#,##0.00');

    return pw.Container(
      padding: const pw.EdgeInsets.all(10),
      decoration: pw.BoxDecoration(
        color: PdfColors.indigo50,
        border: pw.Border.all(color: PdfColors.indigo200),
        borderRadius: pw.BorderRadius.circular(4),
      ),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceAround,
        children: [
          _buildSummaryItem('Total Bills', 'N${formatter.format(totalBills)}', PdfColors.blue800),
          _buildSummaryItem('Total Paid', 'N${formatter.format(totalPaid)}', PdfColors.green800),
          _buildSummaryItem('Balanced', '$balancedCount / $studentCount', PdfColors.teal800),
        ],
      ),
    );
  }

  static pw.Widget _buildSummaryItem(String label, String value, PdfColor color) {
    return pw.Column(
      children: [
        pw.Text(label, style: pw.TextStyle(fontSize: 9, color: PdfColors.grey700)),
        pw.SizedBox(height: 4),
        pw.Text(value, style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold, color: color)),
      ],
    );
  }

  static pw.Widget _buildLedgerTable(List<Map<String, dynamic>> ledger, int maxInstalments) {
    final formatter = NumberFormat('#,##0.00');
    final dateFormat = DateFormat('dd/MM/yy');

    final columnWidths = <int, pw.TableColumnWidth>{
      0: const pw.FixedColumnWidth(22),
      1: const pw.FlexColumnWidth(2.4),
      2: const pw.FlexColumnWidth(1.2),
      3: const pw.FixedColumnWidth(50),
    };
    for (int i = 0; i < maxInstalments; i++) {
      columnWidths[4 + i] = const pw.FlexColumnWidth(1);
    }
    final totalPaidColIndex = 4 + maxInstalments;
    final outstandingColIndex = totalPaidColIndex + 1;
    final remarkColIndex = outstandingColIndex + 1;
    columnWidths[totalPaidColIndex] = const pw.FixedColumnWidth(50);
    columnWidths[outstandingColIndex] = const pw.FixedColumnWidth(50);
    columnWidths[remarkColIndex] = const pw.FixedColumnWidth(48);

    return pw.Table(
      border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.5),
      columnWidths: columnWidths,
      children: [
        pw.TableRow(
          decoration: const pw.BoxDecoration(color: PdfColors.grey300),
          children: [
            _buildTableHeader('S/N'),
            _buildTableHeader('Student Name'),
            _buildTableHeader('Class'),
            _buildTableHeader('Total Bill'),
            for (int i = 1; i <= maxInstalments; i++) _buildTableHeader('P$i'),
            _buildTableHeader('Total Paid'),
            _buildTableHeader('Outstanding'),
            _buildTableHeader('Remark'),
          ],
        ),
        ...ledger.asMap().entries.map((entry) {
          final index = entry.key;
          final row = entry.value;

          final totalBill = (row['totalBill'] as num).toDouble();
          final totalPaid = (row['totalPaid'] as num).toDouble();
          final outstanding = (row['outstanding'] as num).toDouble();
          final instalments = row['instalments'] as List<Map<String, dynamic>>;
          final remark = row['remark'] as String;
          final isBalanced = remark == 'Balanced';

          return pw.TableRow(
            decoration: pw.BoxDecoration(
              color: index % 2 == 0 ? PdfColors.white : PdfColors.grey100,
            ),
            children: [
              _buildTableCell('${index + 1}'),
              _buildTableCell(
                '${row['surname']} ${row['firstName']}',
                alignment: pw.Alignment.centerLeft,
              ),
              _buildTableCell(
                '${row['className'] ?? ''}${row['armName'] != null && row['armName'] != '' ? ' - ${row['armName']}' : ''}',
                alignment: pw.Alignment.centerLeft,
              ),
              _buildTableCell(formatter.format(totalBill)),
              for (int i = 0; i < maxInstalments; i++)
                i < instalments.length
                    ? _buildInstalmentCell(instalments[i], formatter, dateFormat)
                    : _buildTableCell('-'),
              _buildTableCell(formatter.format(totalPaid), textColor: PdfColors.green800),
              _buildTableCell(
                formatter.format(outstanding > 0 ? outstanding : 0),
                textColor: isBalanced ? PdfColors.grey700 : PdfColors.red800,
              ),
              _buildTableCell(
                remark,
                textColor: isBalanced ? PdfColors.green800 : PdfColors.red800,
              ),
            ],
          );
        }),
      ],
    );
  }

  static pw.Widget _buildInstalmentCell(
    Map<String, dynamic> payment,
    NumberFormat formatter,
    DateFormat dateFormat,
  ) {
    final amount = (payment['amount'] as num).toDouble();
    final dateStr = payment['paymentDate'] as String?;
    String formattedDate = dateStr ?? '';
    if (dateStr != null) {
      final parsed = DateTime.tryParse(dateStr);
      if (parsed != null) formattedDate = dateFormat.format(parsed);
    }

    return pw.Container(
      padding: const pw.EdgeInsets.all(3),
      alignment: pw.Alignment.center,
      child: pw.Column(
        mainAxisSize: pw.MainAxisSize.min,
        children: [
          pw.Text(formattedDate, style: pw.TextStyle(fontSize: 6, color: PdfColors.grey700)),
          pw.Text(formatter.format(amount), style: const pw.TextStyle(fontSize: 7)),
        ],
      ),
    );
  }

  static pw.Widget _buildTableHeader(String text) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(4),
      alignment: pw.Alignment.center,
      child: pw.Text(
        text,
        style: pw.TextStyle(fontSize: 7, fontWeight: pw.FontWeight.bold),
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
      padding: const pw.EdgeInsets.all(4),
      alignment: alignment ?? pw.Alignment.center,
      child: pw.Text(
        text,
        style: pw.TextStyle(fontSize: 7, color: textColor),
        textAlign: alignment == pw.Alignment.centerLeft ? pw.TextAlign.left : pw.TextAlign.center,
      ),
    );
  }

  static pw.Widget _buildFooter() {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Divider(),
        pw.SizedBox(height: 8),
        pw.Text(
          'Note: "Remark" indicates whether the student\'s account is fully balanced (paid in full) or not for the period shown.',
          style: pw.TextStyle(fontSize: 7, fontStyle: pw.FontStyle.italic, color: PdfColors.grey700),
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
        style: pw.TextStyle(fontSize: 7, color: PdfColors.grey600),
      ),
    );
  }
}
