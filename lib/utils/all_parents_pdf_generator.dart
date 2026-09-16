import 'dart:io';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:intl/intl.dart';
import '../models/parent.dart';
import 'all_parents_html_generator.dart';
import 'native_html_pdf_helper.dart';
import 'pdf_export_helper.dart';

/// Generates the All Parents list report as a PDF. On Android this renders
/// via the native WebView print pipeline (see
/// custom_report_pdf_generator.dart for why); other platforms use the
/// pure-Dart `pdf` package below.
class AllParentsPDFGenerator {
  static Future<String> generateAllParentsPDF({
    required List<Parent> parents,
    required Map<String, dynamic> schoolProfile,
    bool saveToDownloads = false,
  }) async {
    final timestamp = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
    final baseName = 'All_Parents_$timestamp';

    if (Platform.isAndroid) {
      final html = AllParentsHtmlGenerator.build(
        parents: parents,
        schoolProfile: schoolProfile,
      );
      return NativeHtmlPdfHelper.saveHtmlAsPdf(
        html: html,
        baseFileName: baseName,
        saveToDownloads: saveToDownloads,
      );
    }

    final schoolName = schoolProfile['name'] ?? 'School Name';
    final address = schoolProfile['address'] ?? '';
    final phone = schoolProfile['phone'] ?? '';
    final email = schoolProfile['email'] ?? '';

    final pdf = pw.Document();
    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        build: (context) => [
          pw.Column(
            children: [
              pw.Text(
                schoolName.toUpperCase(),
                style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold, color: PdfColors.blue800),
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
              pw.Divider(thickness: 2, color: PdfColors.blue200),
              pw.SizedBox(height: 10),
              pw.Text('ALL PARENTS/GUARDIANS', style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
              pw.SizedBox(height: 6),
              pw.Text('${parents.length} Parents', style: const pw.TextStyle(fontSize: 11, color: PdfColors.grey700)),
              pw.SizedBox(height: 4),
              pw.Text(
                'Generated: ${DateFormat('MMM d, yyyy - h:mm a').format(DateTime.now())}',
                style: pw.TextStyle(fontSize: 9, color: PdfColors.grey700),
              ),
            ],
          ),
          pw.SizedBox(height: 16),
          pw.TableHelper.fromTextArray(
            border: pw.TableBorder.all(color: PdfColors.blue200),
            headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9),
            cellStyle: const pw.TextStyle(fontSize: 8),
            headerDecoration: const pw.BoxDecoration(color: PdfColors.blue100),
            cellAlignments: {
              0: pw.Alignment.center,
              1: pw.Alignment.centerLeft,
              2: pw.Alignment.centerLeft,
              3: pw.Alignment.centerLeft,
              4: pw.Alignment.centerLeft,
              5: pw.Alignment.centerLeft,
            },
            headers: ['S/N', 'Name', 'Phone', 'Email', 'Address', 'Occupation'],
            data: parents.asMap().entries.map((entry) {
              final index = entry.key;
              final p = entry.value;
              return [
                '${index + 1}',
                p.parentName,
                p.phoneNumbers,
                p.emailAddress ?? '-',
                p.homeAddress,
                p.occupation ?? '-',
              ];
            }).toList(),
          ),
        ],
        footer: (context) => pw.Container(
          alignment: pw.Alignment.centerRight,
          margin: const pw.EdgeInsets.only(top: 10),
          child: pw.Text(
            'Page ${context.pageNumber} of ${context.pagesCount}',
            style: pw.TextStyle(fontSize: 8, color: PdfColors.grey600),
          ),
        ),
      ),
    );

    final output = await PdfExportDirectoryHelper.resolve(saveToDownloads: saveToDownloads);
    final file = File('${output.path}/$baseName.pdf');
    await file.writeAsBytes(await pdf.save());
    return file.path;
  }
}
