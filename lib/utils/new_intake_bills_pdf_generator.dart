import 'dart:io';
import 'dart:typed_data';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:path_provider/path_provider.dart';
import 'package:intl/intl.dart';

class NewIntakeBillsPDFGenerator {
  static Future<String> generateNewIntakeBillPDF({
    required List<Map<String, dynamic>> regularFees,
    required List<Map<String, dynamic>> groupedCategories,
    required List<Map<String, dynamic>> standaloneItems,
    required double grandTotal,
    required String term,
    required String session,
    required String className,
    String? armName,
    required Map<String, dynamic> schoolProfile,
    String title = 'NEW INTAKE BILL',
    String filePrefix = 'NewIntakeBill',
  }) async {
    final pdfBytes = await generateNewIntakeBillPDFBytes(
      regularFees: regularFees,
      groupedCategories: groupedCategories,
      standaloneItems: standaloneItems,
      grandTotal: grandTotal,
      term: term,
      session: session,
      className: className,
      armName: armName,
      schoolProfile: schoolProfile,
      title: title,
    );

    // Save to file in Download folder
    final timestamp = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
    final classLabel = className.replaceAll(' ', '_');
    final fileName = '${filePrefix}_${classLabel}_$timestamp.pdf';

    String filePath;
    if (Platform.isAndroid) {
      filePath = '/storage/emulated/0/Download/$fileName';
    } else if (Platform.isIOS) {
      final output = await getApplicationDocumentsDirectory();
      filePath = '${output.path}/$fileName';
    } else {
      final output = await getApplicationDocumentsDirectory();
      filePath = '${output.path}/$fileName';
    }

    final file = File(filePath);
    await file.writeAsBytes(pdfBytes);

    return file.path;
  }

  static Future<Uint8List> generateNewIntakeBillPDFBytes({
    required List<Map<String, dynamic>> regularFees,
    required List<Map<String, dynamic>> groupedCategories,
    required List<Map<String, dynamic>> standaloneItems,
    required double grandTotal,
    required String term,
    required String session,
    required String className,
    String? armName,
    required Map<String, dynamic> schoolProfile,
    String title = 'NEW INTAKE BILL',
  }) async {
    pw.MemoryImage? logoImage;
    final logoPath = schoolProfile['logoPath']?.toString() ?? '';
    if (logoPath.isNotEmpty) {
      final logoFile = File(logoPath);
      if (await logoFile.exists()) {
        logoImage = pw.MemoryImage(await logoFile.readAsBytes());
      }
    }

    final pdf = pw.Document();

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(40),
        header: (context) => context.pageNumber == 1
            ? pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.stretch,
                children: [
                  _buildHeader(schoolProfile, term, session, className, armName, title, logoImage),
                  pw.SizedBox(height: 24),
                ],
              )
            : pw.SizedBox(),
        footer: (context) => _buildFooter(),
        build: (context) => [
          // Fee Items - Grouped by category
          _buildGroupedFeesTable(regularFees, groupedCategories, standaloneItems),
          pw.SizedBox(height: 16),

          // Grand Total
          _buildGrandTotal(grandTotal),

          // Bank Details
          _buildBankDetails(schoolProfile),
        ],
      ),
    );

    return await pdf.save();
  }

  static pw.Widget _buildHeader(
    Map<String, dynamic> schoolProfile,
    String term,
    String session,
    String className,
    String? armName,
    String title,
    pw.MemoryImage? logo,
  ) {
    final schoolName = schoolProfile['name'] ?? 'School Name';
    final address = schoolProfile['address'] ?? '';
    final phone = schoolProfile['phone'] ?? '';
    final email = schoolProfile['email'] ?? '';

    return pw.Column(
      children: [
        if (logo != null) ...[
          pw.Image(logo, width: 60, height: 60),
          pw.SizedBox(height: 8),
        ],
        pw.Text(
          schoolName.toUpperCase(),
          style: pw.TextStyle(
            fontSize: 22,
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
        pw.Divider(thickness: 2, color: PdfColors.deepOrange),
        pw.SizedBox(height: 16),

        pw.Container(
          padding: const pw.EdgeInsets.symmetric(vertical: 12, horizontal: 24),
          decoration: pw.BoxDecoration(
            color: PdfColors.deepOrange50,
            borderRadius: const pw.BorderRadius.all(pw.Radius.circular(8)),
          ),
          child: pw.Column(
            children: [
              pw.Text(
                title,
                style: pw.TextStyle(
                  fontSize: 18,
                  fontWeight: pw.FontWeight.bold,
                  color: PdfColors.deepOrange,
                ),
                textAlign: pw.TextAlign.center,
              ),
              pw.SizedBox(height: 8),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.center,
                children: [
                  _buildInfoChip('Class: $className${armName != null ? ' - $armName' : ''}'),
                  pw.SizedBox(width: 16),
                  _buildInfoChip('$term | $session'),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  static pw.Widget _buildInfoChip(String text) {
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: pw.BoxDecoration(
        color: PdfColors.white,
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
        border: pw.Border.all(color: PdfColors.deepOrange200),
      ),
      child: pw.Text(
        text,
        style: pw.TextStyle(
          fontSize: 10,
          fontWeight: pw.FontWeight.bold,
        ),
      ),
    );
  }

  static pw.Widget _buildGroupedFeesTable(
    List<Map<String, dynamic>> regularFees,
    List<Map<String, dynamic>> groupedCategories,
    List<Map<String, dynamic>> standaloneItems,
  ) {
    final formatter = NumberFormat('#,##0');
    int serialNumber = 0;

    List<pw.TableRow> rows = [];

    // Header Row
    rows.add(
      pw.TableRow(
        decoration: const pw.BoxDecoration(color: PdfColors.black),
        children: [
          _buildTableCell('S/N', isHeader: true, isWhiteText: true),
          _buildTableCell('Fee Item', isHeader: true, isWhiteText: true),
          _buildTableCell('Amount (N)', isHeader: true, alignRight: true, isWhiteText: true),
        ],
      ),
    );

    // === REGISTRATION FEES (standalone items) - shown first ===
    if (standaloneItems.isNotEmpty) {
      double sectionTotal = 0;
      rows.add(_buildCategoryHeaderRow('REGISTRATION FEES'));

      for (var item in standaloneItems) {
        serialNumber++;
        final name = item['name'] ?? 'Unknown';
        final amount = (item['amount'] as num?)?.toDouble() ?? 0;
        sectionTotal += amount;

        rows.add(
          pw.TableRow(
            decoration: pw.BoxDecoration(
              color: serialNumber.isOdd ? PdfColors.grey50 : PdfColors.white,
            ),
            children: [
              _buildTableCell('$serialNumber'),
              _buildTableCell('  $name'),
              _buildTableCell(formatter.format(amount), alignRight: true),
            ],
          ),
        );
      }

      rows.add(_buildSubtotalRow('Registration Fees Subtotal', sectionTotal, formatter));
    }

    // === CURRENT TERM FEES section ===
    if (regularFees.isNotEmpty) {
      double sectionTotal = 0;
      rows.add(_buildCategoryHeaderRow('CURRENT TERM FEES'));

      for (var fee in regularFees) {
        serialNumber++;
        final name = fee['feeItemName'] ?? 'Unknown';
        final amount = (fee['amount'] as num?)?.toDouble() ?? 0;
        sectionTotal += amount;

        rows.add(
          pw.TableRow(
            decoration: pw.BoxDecoration(
              color: serialNumber.isOdd ? PdfColors.grey50 : PdfColors.white,
            ),
            children: [
              _buildTableCell('$serialNumber'),
              _buildTableCell('  $name'),
              _buildTableCell(formatter.format(amount), alignRight: true),
            ],
          ),
        );
      }

      rows.add(_buildSubtotalRow('Current Term Fees Subtotal', sectionTotal, formatter));
    }

    // === CATEGORY sections ===
    for (var category in groupedCategories) {
      final categoryName = category['categoryName'] ?? 'Unknown';
      final items = category['items'] as List<Map<String, dynamic>>? ?? [];
      final categoryTotal = (category['categoryTotal'] as num?)?.toDouble() ?? 0;

      if (items.isEmpty) continue;

      rows.add(_buildCategoryHeaderRow(categoryName.toUpperCase()));

      for (var item in items) {
        serialNumber++;
        final name = item['name'] ?? 'Unknown';
        final amount = (item['amount'] as num?)?.toDouble() ?? 0;

        rows.add(
          pw.TableRow(
            decoration: pw.BoxDecoration(
              color: serialNumber.isOdd ? PdfColors.grey50 : PdfColors.white,
            ),
            children: [
              _buildTableCell('$serialNumber'),
              _buildTableCell('  $name'),
              _buildTableCell(formatter.format(amount), alignRight: true),
            ],
          ),
        );
      }

      rows.add(_buildSubtotalRow('$categoryName Subtotal', categoryTotal, formatter));
    }

    return pw.Table(
      border: pw.TableBorder.all(color: PdfColors.grey300),
      columnWidths: const {
        0: pw.FlexColumnWidth(1),  // S/N
        1: pw.FlexColumnWidth(6),  // Fee Item
        2: pw.FlexColumnWidth(3),  // Amount
      },
      children: rows,
    );
  }

  static pw.TableRow _buildCategoryHeaderRow(String categoryName) {
    return pw.TableRow(
      decoration: const pw.BoxDecoration(color: PdfColors.blueGrey50),
      children: [
        _buildTableCell('', isHeader: true),
        pw.Container(
          padding: const pw.EdgeInsets.all(8),
          alignment: pw.Alignment.centerLeft,
          child: pw.Text(
            categoryName,
            style: pw.TextStyle(
              fontSize: 11,
              fontWeight: pw.FontWeight.bold,
              color: PdfColors.blueGrey800,
            ),
          ),
        ),
        _buildTableCell('', isHeader: true),
      ],
    );
  }

  static pw.TableRow _buildSubtotalRow(String label, double total, NumberFormat formatter) {
    return pw.TableRow(
      decoration: const pw.BoxDecoration(color: PdfColors.grey100),
      children: [
        _buildTableCell(''),
        pw.Container(
          padding: const pw.EdgeInsets.all(8),
          alignment: pw.Alignment.centerRight,
          child: pw.Text(
            label,
            style: pw.TextStyle(
              fontSize: 10,
              fontWeight: pw.FontWeight.bold,
              fontStyle: pw.FontStyle.italic,
            ),
          ),
        ),
        pw.Container(
          padding: const pw.EdgeInsets.all(8),
          alignment: pw.Alignment.centerRight,
          child: pw.Text(
            formatter.format(total),
            style: pw.TextStyle(
              fontSize: 10,
              fontWeight: pw.FontWeight.bold,
              fontStyle: pw.FontStyle.italic,
            ),
          ),
        ),
      ],
    );
  }

  static pw.Widget _buildTableCell(
    String text, {
    bool isHeader = false,
    bool alignRight = false,
    bool isWhiteText = false,
  }) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(8),
      alignment: alignRight ? pw.Alignment.centerRight : pw.Alignment.centerLeft,
      child: pw.Text(
        text,
        style: pw.TextStyle(
          fontSize: isHeader ? 10 : 11,
          fontWeight: isHeader ? pw.FontWeight.bold : pw.FontWeight.normal,
          color: isWhiteText ? PdfColors.white : PdfColors.black,
        ),
      ),
    );
  }

  static pw.Widget _buildGrandTotal(double grandTotal) {
    final formatter = NumberFormat('#,##0');

    return pw.Container(
      padding: const pw.EdgeInsets.all(16),
      decoration: pw.BoxDecoration(
        color: PdfColors.green50,
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(8)),
        border: pw.Border.all(color: PdfColors.green300, width: 2),
      ),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Row(
            children: [
              pw.Container(
                width: 24,
                height: 24,
                decoration: const pw.BoxDecoration(
                  color: PdfColors.green,
                  shape: pw.BoxShape.circle,
                ),
                child: pw.Center(
                  child: pw.Text(
                    'N',
                    style: pw.TextStyle(
                      color: PdfColors.white,
                      fontWeight: pw.FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                ),
              ),
              pw.SizedBox(width: 12),
              pw.Text(
                'GRAND TOTAL',
                style: pw.TextStyle(
                  fontSize: 14,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
            ],
          ),
          pw.Text(
            'N${formatter.format(grandTotal)}',
            style: pw.TextStyle(
              fontSize: 20,
              fontWeight: pw.FontWeight.bold,
              color: PdfColors.green700,
            ),
          ),
        ],
      ),
    );
  }

  static pw.Widget _buildBankDetails(Map<String, dynamic> schoolProfile) {
    final accounts = <Map<String, String>>[];
    for (int i = 1; i <= 3; i++) {
      final bankName = schoolProfile['bankName$i']?.toString() ?? '';
      final accNum = schoolProfile['accountNumber$i']?.toString() ?? '';
      final accName = schoolProfile['accountName$i']?.toString() ?? '';
      if (bankName.isNotEmpty && accNum.isNotEmpty) {
        accounts.add({'bankName': bankName, 'accountNumber': accNum, 'accountName': accName});
      }
    }
    if (accounts.isEmpty) return pw.SizedBox();

    return pw.Container(
      margin: const pw.EdgeInsets.only(top: 12),
      padding: const pw.EdgeInsets.all(12),
      decoration: pw.BoxDecoration(
        color: PdfColors.blue50,
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
        border: pw.Border.all(color: PdfColors.blue200),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text('SCHOOL ACCOUNT DETAILS',
            style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold, color: PdfColors.blue900)),
          pw.SizedBox(height: 8),
          for (int i = 0; i < accounts.length; i++) ...[
            if (i > 0) pw.SizedBox(height: 8),
            _buildBankDetailRow('Name of Bank:', accounts[i]['bankName']!),
            _buildBankDetailRow('Account Number:', accounts[i]['accountNumber']!),
            if (accounts[i]['accountName']!.isNotEmpty)
              _buildBankDetailRow('Account Name:', accounts[i]['accountName']!),
          ],
        ],
      ),
    );
  }

  static pw.Widget _buildBankDetailRow(String label, String value) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 3),
      child: pw.RichText(
        text: pw.TextSpan(
          children: [
            pw.TextSpan(
              text: '$label ',
              style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold, color: PdfColors.blue900),
            ),
            pw.TextSpan(
              text: value,
              style: const pw.TextStyle(fontSize: 11, color: PdfColors.blue800),
            ),
          ],
        ),
      ),
    );
  }

  static pw.Widget _buildFooter() {
    final now = DateTime.now();
    final dateFormatter = DateFormat('MMMM dd, yyyy');
    final timeFormatter = DateFormat('hh:mm a');

    return pw.Container(
      padding: const pw.EdgeInsets.only(top: 16),
      decoration: const pw.BoxDecoration(
        border: pw.Border(top: pw.BorderSide(color: PdfColors.grey300)),
      ),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(
            'Generated: ${dateFormatter.format(now)} at ${timeFormatter.format(now)}',
            style: const pw.TextStyle(
              fontSize: 9,
              color: PdfColors.grey600,
            ),
          ),
          pw.Text(
            'New Intake Bill - Bursary Manager',
            style: const pw.TextStyle(
              fontSize: 9,
              color: PdfColors.grey600,
            ),
          ),
        ],
      ),
    );
  }
}
