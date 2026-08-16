// lib/utils/sales_report_pdf_generator.dart
import 'dart:io';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:path_provider/path_provider.dart';
import 'package:intl/intl.dart';

class SalesReportPDFGenerator {
  static Future<String> generateSalesReportPDF({
    required List<Map<String, dynamic>> sales,
    required String date,
    required Map<String, dynamic> schoolProfile,
    required Map<String, dynamic> summary,
    String? term,
    String? session,
  }) async {
    final pdf = pw.Document();
    final formatter = NumberFormat('#,##0.00');

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        build: (context) => [
          // Header
          _buildHeader(schoolProfile, date, term, session),
          pw.SizedBox(height: 20),

          // Payment method breakdown
          _buildPaymentMethodBreakdown(summary, formatter),
          pw.SizedBox(height: 20),

          // Sales details table
          if (sales.isNotEmpty) ...[
            pw.Text(
              'SALES DETAILS',
              style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold),
            ),
            pw.SizedBox(height: 10),
            _buildSalesTable(sales, formatter),
          ],

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
    final fileName = 'Sales_Report_$timestamp.pdf';
    final file = File('${output.path}/$fileName');
    await file.writeAsBytes(await pdf.save());

    return file.path;
  }

  static pw.Widget _buildHeader(
    Map<String, dynamic> schoolProfile,
    String date,
    String? term,
    String? session,
  ) {
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
            color: PdfColors.indigo700,
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
          'DAILY SALES REPORT',
          style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold),
          textAlign: pw.TextAlign.center,
        ),
        pw.SizedBox(height: 5),
        pw.Text(
          'Date: ${DateFormat('EEEE, MMMM d, yyyy').format(DateTime.parse(date))}',
          style: const pw.TextStyle(fontSize: 12),
          textAlign: pw.TextAlign.center,
        ),
        if (term != null && session != null)
          pw.Text(
            'Term: $term | Session: $session',
            style: const pw.TextStyle(fontSize: 11),
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

  static pw.Widget _buildPaymentMethodBreakdown(
    Map<String, dynamic> summary,
    NumberFormat formatter,
  ) {
    final totalSale = summary['cashTotal'] + summary['posTotal'] + summary['transferTotal'];

    return pw.Container(
      padding: const pw.EdgeInsets.all(15),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.grey400),
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(5)),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            'PAYMENT METHOD BREAKDOWN',
            style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 10),
          _buildPaymentMethodRow('Cash', summary['cashTotal'], formatter, PdfColors.green),
          pw.Divider(),
          _buildPaymentMethodRow('POS', summary['posTotal'], formatter, PdfColors.blue),
          pw.Divider(),
          _buildPaymentMethodRow('Transfer', summary['transferTotal'], formatter, PdfColors.purple),
          pw.Divider(thickness: 2),
          _buildPaymentMethodRow('Total Sale', totalSale, formatter, PdfColors.deepOrange, isTotal: true),
        ],
      ),
    );
  }

  static pw.Widget _buildPaymentMethodRow(
    String method,
    double amount,
    NumberFormat formatter,
    PdfColor color, {
    bool isTotal = false,
  }) {
    return pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: [
        pw.Text(
          method,
          style: pw.TextStyle(
            fontSize: isTotal ? 13 : 11,
            fontWeight: pw.FontWeight.bold,
          ),
        ),
        pw.Text(
          'N${formatter.format(amount)}',
          style: pw.TextStyle(
            fontSize: isTotal ? 14 : 11,
            fontWeight: pw.FontWeight.bold,
            color: color,
          ),
        ),
      ],
    );
  }

  static pw.Widget _buildSalesTable(List<Map<String, dynamic>> sales, NumberFormat formatter) {
    return pw.Table(
      border: pw.TableBorder.all(color: PdfColors.grey400),
      children: [
        // Header row
        pw.TableRow(
          decoration: const pw.BoxDecoration(color: PdfColors.grey300),
          children: [
            _buildTableHeader('S/N'),
            _buildTableHeader('Time'),
            _buildTableHeader('Buyer'),
            _buildTableHeader('Item'),
            _buildTableHeader('Qty'),
            _buildTableHeader('Amount'),
            _buildTableHeader('Method'),
          ],
        ),
        // Data rows
        ...sales.asMap().entries.map((entry) {
          final index = entry.key;
          final sale = entry.value;

          return pw.TableRow(
            decoration: pw.BoxDecoration(
              color: index % 2 == 0 ? PdfColors.white : PdfColors.grey100,
            ),
            children: [
              _buildTableCell('${index + 1}'),
              _buildTableCell(
                DateFormat('HH:mm').format(DateTime.parse(sale['saleDate'])),
              ),
              _buildTableCell(
                sale['buyerName'],
                alignment: pw.Alignment.centerLeft,
              ),
              _buildTableCell(
                sale['itemName'],
                alignment: pw.Alignment.centerLeft,
              ),
              _buildTableCell('${sale['quantity']}'),
              _buildTableCell('N${formatter.format(sale['totalAmount'])}'),
              _buildTableCell(sale['paymentMethod']),
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
        style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold),
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
          style: pw.TextStyle(fontSize: 8, color: textColor),
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
