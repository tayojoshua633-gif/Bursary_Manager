// lib/utils/family_payment_receipt_pdf_generator.dart

import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

class FamilyReceiptPaymentItem {
  final String studentName;
  final String classDisplay;
  final double amount;

  const FamilyReceiptPaymentItem({
    required this.studentName,
    required this.classDisplay,
    required this.amount,
  });
}

// Builds the exact "Family Payment Receipt" PDF layout used when a family
// payment is first recorded, so a later reprint from history looks identical
// to the original receipt.
class FamilyPaymentReceiptPdfGenerator {
  static pw.Document generate({
    required String schoolName,
    required String schoolAddress,
    required String parentName,
    required String parentPhone,
    required String term,
    required String session,
    required DateTime date,
    required String method,
    required String note,
    required List<FamilyReceiptPaymentItem> items,
    required double totalAmount,
    double? familyTotalBilled,
    double? familyTotalPaid,
    double? familyOutstanding,
  }) {
    final fmt = NumberFormat('#,##0.00');
    final pdf = pw.Document();

    pdf.addPage(pw.Page(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(40),
      build: (pw.Context ctx) {
        return pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Center(
              child: pw.Text(schoolName.toUpperCase(),
                  style: pw.TextStyle(
                      fontSize: 16,
                      fontWeight: pw.FontWeight.bold,
                      color: PdfColors.indigo700)),
            ),
            if (schoolAddress.isNotEmpty)
              pw.Center(
                  child: pw.Text(schoolAddress,
                      style: const pw.TextStyle(
                          fontSize: 9, color: PdfColors.grey700))),
            pw.SizedBox(height: 14),
            pw.Center(
              child: pw.Text('FAMILY PAYMENT RECEIPT',
                  style: pw.TextStyle(
                      fontSize: 18, fontWeight: pw.FontWeight.bold)),
            ),
            pw.SizedBox(height: 6),
            pw.Center(
              child: pw.Text('$term  |  $session',
                  style: const pw.TextStyle(
                      fontSize: 10, color: PdfColors.grey700)),
            ),
            pw.SizedBox(height: 18),
            _pdfInfoRow('Parent', parentName),
            _pdfInfoRow('Phone', parentPhone),
            _pdfInfoRow('Date', DateFormat('dd MMM yyyy').format(date)),
            _pdfInfoRow('Method', method),
            if (note.trim().isNotEmpty) _pdfInfoRow('Note', note.trim()),
            pw.SizedBox(height: 18),
            pw.Text('Payment Breakdown',
                style:
                    pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 11)),
            pw.SizedBox(height: 6),
            pw.TableHelper.fromTextArray(
              headerStyle:
                  pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9),
              cellStyle: const pw.TextStyle(fontSize: 9),
              headerDecoration:
                  const pw.BoxDecoration(color: PdfColors.green100),
              data: [
                ['Student', 'Class', 'Amount Paid'],
                ...items.map((it) => [
                      it.studentName,
                      it.classDisplay,
                      '₦${fmt.format(it.amount)}',
                    ]),
              ],
            ),
            pw.SizedBox(height: 14),
            pw.Container(
              padding: const pw.EdgeInsets.all(10),
              decoration: pw.BoxDecoration(
                border: pw.Border.all(color: PdfColors.green400, width: 2),
                borderRadius:
                    const pw.BorderRadius.all(pw.Radius.circular(5)),
              ),
              child: pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text('TOTAL AMOUNT PAID',
                      style: pw.TextStyle(
                          fontWeight: pw.FontWeight.bold, fontSize: 13)),
                  pw.Text('₦${fmt.format(totalAmount)}',
                      style: pw.TextStyle(
                          fontWeight: pw.FontWeight.bold,
                          fontSize: 14,
                          color: PdfColors.green700)),
                ],
              ),
            ),
            if (familyTotalBilled != null &&
                familyTotalPaid != null &&
                familyOutstanding != null) ...[
              pw.SizedBox(height: 18),
              pw.Text('Family Account Summary',
                  style: pw.TextStyle(
                      fontWeight: pw.FontWeight.bold, fontSize: 11)),
              pw.SizedBox(height: 6),
              pw.Container(
                padding: const pw.EdgeInsets.all(10),
                decoration: pw.BoxDecoration(
                  border: pw.Border.all(color: PdfColors.indigo400),
                  borderRadius:
                      const pw.BorderRadius.all(pw.Radius.circular(5)),
                ),
                child: pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    _pdfSummaryCell('Total Billed', familyTotalBilled, PdfColors.purple700),
                    _pdfSummaryCell('Total Paid', familyTotalPaid, PdfColors.green700),
                    _pdfSummaryCell(
                      'Outstanding',
                      familyOutstanding,
                      familyOutstanding > 0 ? PdfColors.red700 : PdfColors.green700,
                    ),
                  ],
                ),
              ),
            ],
            pw.SizedBox(height: 30),
            pw.Divider(),
            pw.Text(
              'Generated: ${DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now())}',
              style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600),
            ),
          ],
        );
      },
    ));

    return pdf;
  }

  static pw.Widget _pdfSummaryCell(String label, double amount, PdfColor color) =>
      pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.center,
        children: [
          pw.Text(label, style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700)),
          pw.SizedBox(height: 3),
          pw.Text(
            '₦${NumberFormat('#,##0.00').format(amount)}',
            style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: color),
          ),
        ],
      );

  static pw.Widget _pdfInfoRow(String label, String value) => pw.Padding(
        padding: const pw.EdgeInsets.symmetric(vertical: 2),
        child: pw.Row(
          children: [
            pw.SizedBox(
              width: 70,
              child: pw.Text(label,
                  style: const pw.TextStyle(
                      fontSize: 9, color: PdfColors.grey700)),
            ),
            pw.Text(value,
                style:
                    pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold)),
          ],
        ),
      );
}
