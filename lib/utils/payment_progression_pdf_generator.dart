import 'dart:io';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:path_provider/path_provider.dart';
import 'package:intl/intl.dart';

class PaymentProgressionPdfGenerator {
  static final _currency = NumberFormat.currency(symbol: 'N', decimalDigits: 2);
  static final _dateFormat = DateFormat('dd MMM yyyy, hh:mm a');

  static Future<String> generate({
    required List<Map<String, dynamic>> students,
    required String term,
    required String session,
    required String className,
    required String armName,
    required Map<String, dynamic> schoolProfile,
  }) async {
    final pdf = pw.Document();

    final classLabel = armName.isNotEmpty ? '$className ($armName)' : className;
    final generatedAt = _dateFormat.format(DateTime.now());

    // Summary stats
    double totalBill = 0;
    double totalPaid = 0;
    int fullyPaid = 0;
    for (final s in students) {
      totalBill += (s['billTotal'] as num).toDouble();
      totalPaid += (s['totalPaid'] as num).toDouble();
      if ((s['totalPaid'] as num).toDouble() >= (s['billTotal'] as num).toDouble()) {
        fullyPaid++;
      }
    }
    final outstanding = totalBill - totalPaid;
    final avgCoverage = totalBill > 0 ? (totalPaid / totalBill * 100) : 0.0;

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(28),
        build: (context) => [
          _buildHeader(schoolProfile, classLabel, term, session, generatedAt),
          pw.SizedBox(height: 12),
          _buildSummary(
            total: students.length,
            fullyPaid: fullyPaid,
            totalBill: totalBill,
            totalPaid: totalPaid,
            outstanding: outstanding,
            avgCoverage: avgCoverage,
          ),
          pw.SizedBox(height: 16),
          ...students.expand((s) => _buildStudentSection(s)),
        ],
        footer: (ctx) => _buildFooter(ctx),
      ),
    );

    final dir = await getApplicationDocumentsDirectory();
    final ts = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
    final fileName = 'PaymentProgression_${classLabel.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '_')}_$ts.pdf';
    final file = File('${dir.path}/$fileName');
    await file.writeAsBytes(await pdf.save());
    return file.path;
  }

  // ── Header ────────────────────────────────────────────────────────────────

  static pw.Widget _buildHeader(
    Map<String, dynamic> profile,
    String classLabel,
    String term,
    String session,
    String generatedAt,
  ) {
    final schoolName = profile['schoolName']?.toString() ?? 'School';
    final address = profile['address']?.toString() ?? '';
    final phone = profile['phone']?.toString() ?? '';

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.center,
      children: [
        pw.Text(
          schoolName.toUpperCase(),
          style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold),
          textAlign: pw.TextAlign.center,
        ),
        if (address.isNotEmpty)
          pw.Text(address, style: const pw.TextStyle(fontSize: 9), textAlign: pw.TextAlign.center),
        if (phone.isNotEmpty)
          pw.Text('Tel: $phone', style: const pw.TextStyle(fontSize: 9), textAlign: pw.TextAlign.center),
        pw.SizedBox(height: 6),
        pw.Divider(thickness: 1.5),
        pw.SizedBox(height: 4),
        pw.Text(
          'PAYMENT PROGRESSION REPORT',
          style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold),
          textAlign: pw.TextAlign.center,
        ),
        pw.SizedBox(height: 4),
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text('Class: $classLabel', style: const pw.TextStyle(fontSize: 10)),
            pw.Text('$term  |  $session', style: const pw.TextStyle(fontSize: 10)),
            pw.Text('Generated: $generatedAt', style: const pw.TextStyle(fontSize: 9)),
          ],
        ),
        pw.Divider(thickness: 0.5),
      ],
    );
  }

  // ── Summary ───────────────────────────────────────────────────────────────

  static pw.Widget _buildSummary({
    required int total,
    required int fullyPaid,
    required double totalBill,
    required double totalPaid,
    required double outstanding,
    required double avgCoverage,
  }) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(8),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.grey400),
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
        color: PdfColors.grey100,
      ),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceAround,
        children: [
          _summaryCell('Students', '$total'),
          _summaryCell('Fully Paid', '$fullyPaid'),
          _summaryCell('Avg Coverage', '${avgCoverage.toStringAsFixed(1)}%'),
          _summaryCell('Total Billed', _currency.format(totalBill)),
          _summaryCell('Total Collected', _currency.format(totalPaid)),
          _summaryCell('Outstanding', _currency.format(outstanding.clamp(0, double.infinity))),
        ],
      ),
    );
  }

  static pw.Widget _summaryCell(String label, String value) {
    return pw.Column(
      children: [
        pw.Text(value, style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
        pw.Text(label, style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600)),
      ],
    );
  }

  // ── Per-student section ───────────────────────────────────────────────────

  static List<pw.Widget> _buildStudentSection(Map<String, dynamic> student) {
    final surname = student['surname']?.toString() ?? '';
    final firstName = student['firstName']?.toString() ?? '';
    final admissionNo = student['admissionNo']?.toString() ?? '';
    final className = student['className']?.toString() ?? '';
    final armName = student['armName']?.toString() ?? '';
    final billTotal = (student['billTotal'] as num).toDouble();
    final totalPaid = (student['totalPaid'] as num?)?.toDouble() ?? 0.0;
    final outstanding = (billTotal - totalPaid).clamp(0.0, double.infinity);
    final progression = student['progression'] as List<Map<String, dynamic>>? ?? [];

    final coverage = billTotal > 0 ? totalPaid / billTotal : 0.0;
    final coverageColor = coverage >= 1.0
        ? PdfColors.green700
        : coverage >= 0.4
            ? PdfColors.orange700
            : PdfColors.red700;

    final classLabel = armName.isNotEmpty ? '$className ($armName)' : className;

    return [
      pw.SizedBox(height: 8),
      pw.Container(
        padding: const pw.EdgeInsets.all(8),
        decoration: pw.BoxDecoration(
          border: pw.Border.all(color: PdfColors.grey300),
          borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
        ),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            // Student header row
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      '$surname, $firstName',
                      style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold),
                    ),
                    pw.Text(
                      'Adm: $admissionNo  |  $classLabel',
                      style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700),
                    ),
                  ],
                ),
                pw.Container(
                  padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: pw.BoxDecoration(
                    color: coverageColor,
                    borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
                  ),
                  child: pw.Text(
                    '${(coverage * 100).toStringAsFixed(1)}% paid',
                    style: pw.TextStyle(
                      fontSize: 9,
                      color: PdfColors.white,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            pw.SizedBox(height: 6),

            // Fee progression table
            if (progression.isNotEmpty) ...[
              pw.Table(
                border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
                columnWidths: {
                  0: const pw.FixedColumnWidth(24),
                  1: const pw.FlexColumnWidth(3),
                  2: const pw.FlexColumnWidth(2),
                  3: const pw.FlexColumnWidth(1.5),
                  4: const pw.FlexColumnWidth(2),
                },
                children: [
                  // Table header
                  pw.TableRow(
                    decoration: const pw.BoxDecoration(color: PdfColors.grey200),
                    children: [
                      _tableHeaderCell('#'),
                      _tableHeaderCell('Fee Item'),
                      _tableHeaderCell('Amount', alignRight: true),
                      _tableHeaderCell('Status', alignCenter: true),
                      _tableHeaderCell('Covered', alignRight: true),
                    ],
                  ),
                  // Data rows
                  ...List.generate(progression.length, (i) {
                    final item = progression[i];
                    final feeName = item['feeName']?.toString() ?? '';
                    final amount = (item['amount'] as num).toDouble();
                    final covered = (item['covered'] as num).toDouble();
                    final status = item['status']?.toString() ?? '';
                    final statusColor = status == 'Paid'
                        ? PdfColors.green700
                        : status == 'Partly Paid'
                            ? PdfColors.orange700
                            : PdfColors.grey600;

                    return pw.TableRow(children: [
                      _tableCell('${i + 1}'),
                      _tableCell(feeName),
                      _tableCell(_currency.format(amount), alignRight: true),
                      pw.Padding(
                        padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 3),
                        child: pw.Text(
                          status,
                          style: pw.TextStyle(fontSize: 8, color: statusColor),
                          textAlign: pw.TextAlign.center,
                        ),
                      ),
                      _tableCell(_currency.format(covered), alignRight: true),
                    ]);
                  }),
                ],
              ),
            ],

            pw.SizedBox(height: 4),
            // Payment summary row
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.end,
              children: [
                _miniSummaryCell('Bill Total', _currency.format(billTotal)),
                pw.SizedBox(width: 12),
                _miniSummaryCell('Total Paid', _currency.format(totalPaid)),
                pw.SizedBox(width: 12),
                _miniSummaryCell(
                  'Outstanding',
                  _currency.format(outstanding),
                  color: outstanding > 0 ? PdfColors.red700 : PdfColors.green700,
                ),
              ],
            ),
          ],
        ),
      ),
    ];
  }

  // ── Table helpers ─────────────────────────────────────────────────────────

  static pw.Widget _tableHeaderCell(String text, {bool alignRight = false, bool alignCenter = false}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 3),
      child: pw.Text(
        text,
        style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold),
        textAlign: alignRight
            ? pw.TextAlign.right
            : alignCenter
                ? pw.TextAlign.center
                : pw.TextAlign.left,
      ),
    );
  }

  static pw.Widget _tableCell(String text, {bool alignRight = false}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 3),
      child: pw.Text(
        text,
        style: const pw.TextStyle(fontSize: 8),
        textAlign: alignRight ? pw.TextAlign.right : pw.TextAlign.left,
      ),
    );
  }

  static pw.Widget _miniSummaryCell(String label, String value, {PdfColor? color}) {
    return pw.RichText(
      text: pw.TextSpan(
        children: [
          pw.TextSpan(
            text: '$label: ',
            style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700),
          ),
          pw.TextSpan(
            text: value,
            style: pw.TextStyle(
              fontSize: 8,
              fontWeight: pw.FontWeight.bold,
              color: color ?? PdfColors.black,
            ),
          ),
        ],
      ),
    );
  }

  // ── Footer ────────────────────────────────────────────────────────────────

  static pw.Widget _buildFooter(pw.Context context) {
    return pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: [
        pw.Text(
          'Generated by Bursary Manager',
          style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600),
        ),
        pw.Text(
          'Page ${context.pageNumber} of ${context.pagesCount}',
          style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600),
        ),
      ],
    );
  }
}
