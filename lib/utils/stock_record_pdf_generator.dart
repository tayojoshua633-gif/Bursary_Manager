// lib/utils/stock_record_pdf_generator.dart
import 'dart:io';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:path_provider/path_provider.dart';
import 'package:intl/intl.dart';

class StockRecordPDFGenerator {
  static Future<String> generateStockRecordPDF({
    required List<Map<String, dynamic>> stockRecords,
    required Map<String, dynamic> schoolProfile,
  }) async {
    final pdf = pw.Document();
    final formatter = NumberFormat('#,##0.00');

    // Calculate totals
    double totalSuppliedValue = 0;
    double totalSoldValue = 0;
    double totalRemainingValue = 0;
    int totalQtySupplied = 0;
    int totalQtySold = 0;
    int totalQtyRemaining = 0;

    for (final record in stockRecords) {
      totalQtySupplied += record['qtySupplied'] as int;
      totalQtySold += record['qtySold'] as int;
      totalQtyRemaining += record['qtyRemaining'] as int;
      totalSuppliedValue += (record['totalSellingValue'] as num).toDouble();
      totalSoldValue += (record['soldValue'] as num).toDouble();
      totalRemainingValue += (record['remainingValue'] as num).toDouble();
    }

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4.landscape,
        margin: const pw.EdgeInsets.all(32),
        build: (context) => [
          // Header
          _buildHeader(schoolProfile),
          pw.SizedBox(height: 20),

          // Summary boxes
          _buildSummary(
            totalSuppliedValue,
            totalSoldValue,
            totalRemainingValue,
            totalQtySupplied,
            totalQtySold,
            totalQtyRemaining,
            formatter,
          ),
          pw.SizedBox(height: 20),

          // Stock records table
          _buildStockTable(stockRecords, formatter),

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
    final fileName = 'Stock_Record_Report_$timestamp.pdf';
    final file = File('${output.path}/$fileName');
    await file.writeAsBytes(await pdf.save());

    return file.path;
  }

  static pw.Widget _buildHeader(Map<String, dynamic> schoolProfile) {
    final schoolName = schoolProfile['name']?.toString() ?? 'School';
    final address = schoolProfile['address']?.toString() ?? '';
    final phone = schoolProfile['phone']?.toString() ?? '';
    final email = schoolProfile['email']?.toString() ?? '';

    return pw.Column(
      children: [
        pw.Text(
          schoolName.toUpperCase(),
          style: pw.TextStyle(
            fontSize: 20,
            fontWeight: pw.FontWeight.bold,
            color: PdfColors.brown700,
          ),
          textAlign: pw.TextAlign.center,
        ),
        if (address.isNotEmpty)
          pw.Text(
            address,
            style: const pw.TextStyle(fontSize: 10),
            textAlign: pw.TextAlign.center,
          ),
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
          'STOCK RECORD REPORT',
          style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold),
          textAlign: pw.TextAlign.center,
        ),
        pw.SizedBox(height: 5),
        pw.Text(
          'Generated: ${DateFormat('MMMM d, yyyy - h:mm a').format(DateTime.now())}',
          style: pw.TextStyle(fontSize: 9, color: PdfColors.grey700),
          textAlign: pw.TextAlign.center,
        ),
      ],
    );
  }

  static pw.Widget _buildSummary(
    double totalSuppliedValue,
    double totalSoldValue,
    double totalRemainingValue,
    int totalQtySupplied,
    int totalQtySold,
    int totalQtyRemaining,
    NumberFormat formatter,
  ) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(15),
      decoration: pw.BoxDecoration(
        color: PdfColors.brown50,
        border: pw.Border.all(color: PdfColors.brown300),
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(5)),
      ),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceAround,
        children: [
          _buildSummaryItem(
            'Total Supplied',
            '$totalQtySupplied units',
            'N${formatter.format(totalSuppliedValue)}',
            PdfColors.blue,
          ),
          _buildSummaryItem(
            'Total Sold',
            '$totalQtySold units',
            'N${formatter.format(totalSoldValue)}',
            PdfColors.green,
          ),
          _buildSummaryItem(
            'Remaining Stock',
            '$totalQtyRemaining units',
            'N${formatter.format(totalRemainingValue)}',
            PdfColors.orange,
          ),
        ],
      ),
    );
  }

  static pw.Widget _buildSummaryItem(
    String title,
    String quantity,
    String value,
    PdfColor color,
  ) {
    return pw.Column(
      children: [
        pw.Text(
          title,
          style: pw.TextStyle(
            fontSize: 10,
            color: PdfColors.grey800,
            fontWeight: pw.FontWeight.bold,
          ),
        ),
        pw.SizedBox(height: 4),
        pw.Text(
          quantity,
          style: pw.TextStyle(
            fontSize: 12,
            fontWeight: pw.FontWeight.bold,
            color: color,
          ),
        ),
        pw.Text(
          value,
          style: pw.TextStyle(
            fontSize: 11,
            fontWeight: pw.FontWeight.bold,
            color: color,
          ),
        ),
      ],
    );
  }

  static pw.Widget _buildStockTable(List<Map<String, dynamic>> stockRecords, NumberFormat formatter) {
    return pw.Table(
      border: pw.TableBorder.all(color: PdfColors.grey400),
      columnWidths: {
        0: const pw.FlexColumnWidth(2.5),
        1: const pw.FlexColumnWidth(2),
        2: const pw.FlexColumnWidth(1.2),
        3: const pw.FlexColumnWidth(1.2),
        4: const pw.FlexColumnWidth(1.2),
        5: const pw.FlexColumnWidth(1.5),
        6: const pw.FlexColumnWidth(1.5),
        7: const pw.FlexColumnWidth(1.8),
      },
      children: [
        // Header row
        pw.TableRow(
          decoration: const pw.BoxDecoration(color: PdfColors.brown200),
          children: [
            _buildTableHeader('Item Name'),
            _buildTableHeader('Supplier'),
            _buildTableHeader('Qty\nSupplied'),
            _buildTableHeader('Qty\nSold'),
            _buildTableHeader('Qty\nRemain'),
            _buildTableHeader('Cost\nPrice'),
            _buildTableHeader('Selling\nPrice'),
            _buildTableHeader('Stock\nValue'),
          ],
        ),
        // Data rows
        ...stockRecords.asMap().entries.map((entry) {
          final index = entry.key;
          final record = entry.value;

          return pw.TableRow(
            decoration: pw.BoxDecoration(
              color: index % 2 == 0 ? PdfColors.white : PdfColors.grey100,
            ),
            children: [
              _buildTableCell(record['itemName'], alignment: pw.Alignment.centerLeft),
              _buildTableCell(record['supplierName'], alignment: pw.Alignment.centerLeft),
              _buildTableCell('${record['qtySupplied']}'),
              _buildTableCell('${record['qtySold']}'),
              _buildTableCell(
                '${record['qtyRemaining']}',
                textColor: record['qtyRemaining'] > 0 ? PdfColors.green800 : PdfColors.red800,
              ),
              _buildTableCell('N${formatter.format(record['costPrice'])}'),
              _buildTableCell('N${formatter.format(record['sellingPrice'])}'),
              _buildTableCell(
                'N${formatter.format(record['remainingValue'])}',
                textColor: PdfColors.brown800,
              ),
            ],
          );
        }),
      ],
    );
  }

  static pw.Widget _buildTableHeader(String text) {
    return pw.Padding(
      padding: const pw.EdgeInsets.all(4),
      child: pw.Text(
        text,
        style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold),
        textAlign: pw.TextAlign.center,
      ),
    );
  }

  static pw.Widget _buildTableCell(
    String text, {
    pw.Alignment alignment = pw.Alignment.center,
    PdfColor? textColor,
  }) {
    return pw.Padding(
      padding: const pw.EdgeInsets.all(4),
      child: pw.Align(
        alignment: alignment,
        child: pw.Text(
          text,
          style: pw.TextStyle(
            fontSize: 7,
            color: textColor,
            fontWeight: textColor != null ? pw.FontWeight.bold : null,
          ),
          textAlign: alignment == pw.Alignment.centerLeft
              ? pw.TextAlign.left
              : pw.TextAlign.center,
        ),
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
    return pw.Container(
      padding: const pw.EdgeInsets.all(10),
      decoration: pw.BoxDecoration(
        color: PdfColors.grey100,
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(5)),
      ),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.center,
        children: [
          pw.Text(
            'This is a computer-generated document. No signature required.',
            style: pw.TextStyle(fontSize: 8, fontStyle: pw.FontStyle.italic),
          ),
        ],
      ),
    );
  }

  static pw.Widget _buildPageFooter(pw.Context context) {
    return pw.Container(
      alignment: pw.Alignment.centerRight,
      margin: const pw.EdgeInsets.only(top: 10),
      child: pw.Text(
        'Page ${context.pageNumber} of ${context.pagesCount}',
        style: const pw.TextStyle(fontSize: 8),
      ),
    );
  }
}
