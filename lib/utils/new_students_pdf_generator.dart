import 'dart:io';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:intl/intl.dart';
import 'new_students_html_generator.dart';
import 'native_html_pdf_helper.dart';
import 'pdf_export_helper.dart';

/// Generates the New Students (current term registrations) list report as a
/// PDF. On Android this renders via the native WebView print pipeline (see
/// custom_report_pdf_generator.dart for why); other platforms use the
/// pure-Dart `pdf` package below.
class NewStudentsPDFGenerator {
  static Future<String> generateNewStudentsPDF({
    required List<Map<String, dynamic>> students,
    required Map<String, dynamic> schoolProfile,
    required String term,
    required String session,
    bool saveToDownloads = false,
  }) async {
    final timestamp = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
    final baseName = 'New_Students_${term.replaceAll(' ', '_')}_$timestamp';

    if (Platform.isAndroid) {
      final html = NewStudentsHtmlGenerator.build(
        students: students,
        schoolProfile: schoolProfile,
        term: term,
        session: session,
      );
      return NativeHtmlPdfHelper.saveHtmlAsPdf(
        html: html,
        baseFileName: baseName,
        saveToDownloads: saveToDownloads,
      );
    }

    String formatDate(String? dateStr) {
      if (dateStr == null || dateStr.isEmpty) return 'Not recorded';
      try {
        final date = DateTime.parse(dateStr);
        return "${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}";
      } catch (e) {
        return dateStr;
      }
    }

    final schoolName = schoolProfile['name'] ?? 'School Name';
    final address = schoolProfile['address'] ?? '';
    final phone = schoolProfile['phone'] ?? '';
    final email = schoolProfile['email'] ?? '';

    final pdf = pw.Document();
    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4.landscape,
        margin: const pw.EdgeInsets.all(24),
        build: (context) => [
          pw.Column(
            children: [
              pw.Text(
                schoolName.toUpperCase(),
                style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold, color: PdfColors.teal800),
                textAlign: pw.TextAlign.center,
              ),
              if (address.isNotEmpty)
                pw.Text(address, style: const pw.TextStyle(fontSize: 9), textAlign: pw.TextAlign.center),
              if (phone.isNotEmpty || email.isNotEmpty)
                pw.Text(
                  [if (phone.isNotEmpty) 'Tel: $phone', if (email.isNotEmpty) email].join(' | '),
                  style: const pw.TextStyle(fontSize: 9),
                  textAlign: pw.TextAlign.center,
                ),
              pw.SizedBox(height: 8),
              pw.Divider(thickness: 2, color: PdfColors.teal200),
              pw.SizedBox(height: 8),
              pw.Text('NEW STUDENTS (CURRENT TERM REGISTRATIONS)',
                  style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold), textAlign: pw.TextAlign.center),
              pw.SizedBox(height: 4),
              pw.Text('${students.length} Students | $term - $session', style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700)),
              pw.SizedBox(height: 2),
              pw.Text(
                'Generated: ${DateFormat('MMM d, yyyy - h:mm a').format(DateTime.now())}',
                style: pw.TextStyle(fontSize: 8, color: PdfColors.grey700),
              ),
            ],
          ),
          pw.SizedBox(height: 14),
          pw.TableHelper.fromTextArray(
            border: pw.TableBorder.all(color: PdfColors.teal200),
            headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 8),
            cellStyle: const pw.TextStyle(fontSize: 7),
            headerDecoration: const pw.BoxDecoration(color: PdfColors.teal100),
            cellAlignments: {
              0: pw.Alignment.center,
              1: pw.Alignment.centerLeft,
              2: pw.Alignment.centerLeft,
              3: pw.Alignment.centerLeft,
              4: pw.Alignment.center,
              5: pw.Alignment.center,
              6: pw.Alignment.centerLeft,
              7: pw.Alignment.centerLeft,
            },
            headers: ['S/N', 'Adm. No', 'Student Name', 'Class/Arm', 'Gender', 'Date of Admission', 'Parent Name', 'Parent Phone'],
            data: students.asMap().entries.map((entry) {
              final index = entry.key;
              final s = entry.value;
              final fullName = '${s['surname']} ${s['firstName']} ${s['otherName'] ?? ''}'.trim();
              final classArm = '${s['className'] ?? ''}${s['armName'] != null && s['armName'].toString().isNotEmpty ? ' - ${s['armName']}' : ''}';
              return [
                '${index + 1}',
                s['admissionNo'],
                fullName,
                classArm,
                s['gender'],
                formatDate(s['dateOfAdmission']?.toString()),
                s['parentName'],
                s['parentPhone'],
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
