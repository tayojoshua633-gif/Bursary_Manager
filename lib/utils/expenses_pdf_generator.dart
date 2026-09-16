import 'dart:io';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:intl/intl.dart';
import 'expenses_html_generator.dart';
import 'native_html_pdf_helper.dart';
import 'pdf_export_helper.dart';

/// Generates the Expenses list report as a PDF. On Android this renders via
/// the native WebView print pipeline (see custom_report_pdf_generator.dart
/// for why); other platforms use the pure-Dart `pdf` package below.
class ExpensesPDFGenerator {
  static Future<String> generateExpensesPDF({
    required List<Map<String, dynamic>> expenses,
    required Map<String, dynamic> schoolProfile,
    String? term,
    String? session,
    String? filterLabel,
    bool saveToDownloads = false,
  }) async {
    final timestamp = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
    final baseName = 'Expenses_Report_$timestamp';

    if (Platform.isAndroid) {
      final html = ExpensesHtmlGenerator.build(
        expenses: expenses,
        schoolProfile: schoolProfile,
        term: term,
        session: session,
        filterLabel: filterLabel,
      );
      return NativeHtmlPdfHelper.saveHtmlAsPdf(
        html: html,
        baseFileName: baseName,
        saveToDownloads: saveToDownloads,
      );
    }

    final formatter = NumberFormat('#,##0.00');
    double totalAmount = 0;
    final categoryTotals = <String, double>{};
    for (final e in expenses) {
      final amount = (e['amount'] as num?)?.toDouble() ?? 0.0;
      totalAmount += amount;
      final category = (e['category'] ?? 'Uncategorized').toString();
      final customCategory = e['customCategory'];
      final displayCategory = category == 'Other' && customCategory != null ? 'Other: $customCategory' : category;
      categoryTotals[displayCategory] = (categoryTotals[displayCategory] ?? 0) + amount;
    }

    final pdf = pw.Document();
    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        build: (context) => [
          _buildHeader(schoolProfile, term, session, filterLabel),
          pw.SizedBox(height: 20),
          _buildSummary(expenses.length, totalAmount, categoryTotals, formatter),
          pw.SizedBox(height: 20),
          _buildTable(expenses, formatter),
          pw.SizedBox(height: 20),
          _buildBankDetails(schoolProfile),
        ],
        footer: (context) => _buildPageFooter(context),
      ),
    );

    final output = await PdfExportDirectoryHelper.resolve(saveToDownloads: saveToDownloads);
    final file = File('${output.path}/$baseName.pdf');
    await file.writeAsBytes(await pdf.save());
    return file.path;
  }

  static pw.Widget _buildHeader(
    Map<String, dynamic> schoolProfile,
    String? term,
    String? session,
    String? filterLabel,
  ) {
    final schoolName = schoolProfile['name'] ?? 'School Name';
    final address = schoolProfile['address'] ?? '';
    final phone = schoolProfile['phone'] ?? '';
    final email = schoolProfile['email'] ?? '';

    return pw.Column(
      children: [
        pw.Text(
          schoolName.toUpperCase(),
          style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold, color: PdfColors.brown700),
          textAlign: pw.TextAlign.center,
        ),
        if (address.isNotEmpty)
          pw.Text(address, style: const pw.TextStyle(fontSize: 10), textAlign: pw.TextAlign.center),
        if (phone.isNotEmpty || email.isNotEmpty)
          pw.Text(
            [if (phone.isNotEmpty) 'Tel: $phone', if (email.isNotEmpty) email].join(' | '),
            style: const pw.TextStyle(fontSize: 9),
            textAlign: pw.TextAlign.center,
          ),
        pw.SizedBox(height: 10),
        pw.Divider(thickness: 2),
        pw.SizedBox(height: 10),
        pw.Text('EXPENSES REPORT', style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
        if (term != null && session != null) ...[
          pw.SizedBox(height: 4),
          pw.Text('$term | $session', style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700)),
        ],
        if (filterLabel != null) ...[
          pw.SizedBox(height: 2),
          pw.Text(filterLabel, style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700)),
        ],
        pw.SizedBox(height: 4),
        pw.Text(
          'Generated: ${DateFormat('MMM d, yyyy - h:mm a').format(DateTime.now())}',
          style: pw.TextStyle(fontSize: 9, color: PdfColors.grey700),
        ),
      ],
    );
  }

  static pw.Widget _buildSummary(
    int count,
    double totalAmount,
    Map<String, double> categoryTotals,
    NumberFormat formatter,
  ) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(15),
      decoration: pw.BoxDecoration(
        color: PdfColors.brown50,
        border: pw.Border.all(color: PdfColors.brown300),
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(5)),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceAround,
            children: [
              _summaryItem('Total Records', '$count'),
              _summaryItem('Total Amount', 'N${formatter.format(totalAmount)}', color: PdfColors.red700),
            ],
          ),
          if (categoryTotals.isNotEmpty) ...[
            pw.SizedBox(height: 10),
            pw.Wrap(
              spacing: 12,
              runSpacing: 6,
              children: categoryTotals.entries
                  .map((e) => pw.Container(
                        padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: pw.BoxDecoration(
                          color: PdfColors.white,
                          border: pw.Border.all(color: PdfColors.brown200),
                          borderRadius: pw.BorderRadius.circular(4),
                        ),
                        child: pw.Text(
                          '${e.key}: N${formatter.format(e.value)}',
                          style: const pw.TextStyle(fontSize: 8),
                        ),
                      ))
                  .toList(),
            ),
          ],
        ],
      ),
    );
  }

  static pw.Widget _summaryItem(String label, String value, {PdfColor? color}) {
    return pw.Column(
      children: [
        pw.Text(label, style: pw.TextStyle(fontSize: 9, color: PdfColors.grey700)),
        pw.SizedBox(height: 4),
        pw.Text(value, style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold, color: color)),
      ],
    );
  }

  static pw.Widget _buildTable(List<Map<String, dynamic>> expenses, NumberFormat formatter) {
    return pw.TableHelper.fromTextArray(
      border: pw.TableBorder.all(color: PdfColors.brown300),
      headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9),
      cellStyle: const pw.TextStyle(fontSize: 8),
      headerDecoration: const pw.BoxDecoration(color: PdfColors.brown100),
      cellAlignments: {
        0: pw.Alignment.center,
        1: pw.Alignment.centerLeft,
        2: pw.Alignment.centerLeft,
        3: pw.Alignment.centerLeft,
        4: pw.Alignment.center,
        5: pw.Alignment.center,
        6: pw.Alignment.centerRight,
      },
      headers: ['S/N', 'Description', 'Category', 'Recipient', 'Method', 'Date', 'Amount'],
      data: expenses.asMap().entries.map((entry) {
        final index = entry.key;
        final e = entry.value;
        final category = (e['category'] ?? 'Uncategorized').toString();
        final customCategory = e['customCategory'];
        final displayCategory = category == 'Other' && customCategory != null ? 'Other: $customCategory' : category;
        final date = (e['expenseDate'] ?? '').toString();
        final dateDisplay = date.length >= 10 ? date.substring(0, 10) : date;
        return [
          '${index + 1}',
          e['description'] ?? '',
          displayCategory,
          e['recipient'] ?? '',
          e['paymentMethod'] ?? '',
          dateDisplay,
          formatter.format(e['amount'] as num? ?? 0),
        ];
      }).toList(),
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

  static pw.Widget _buildPageFooter(pw.Context context) {
    return pw.Container(
      alignment: pw.Alignment.centerRight,
      margin: const pw.EdgeInsets.only(top: 10),
      child: pw.Text(
        'Page ${context.pageNumber} of ${context.pagesCount}',
        style: pw.TextStyle(fontSize: 8, color: PdfColors.grey600),
      ),
    );
  }
}
