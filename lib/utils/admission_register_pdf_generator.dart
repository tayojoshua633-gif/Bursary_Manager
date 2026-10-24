// lib/utils/admission_register_pdf_generator.dart
// PDF print/export of the Admission Register (Student Management), filtered
// by admission session/term or covering all sessions and terms.

import 'dart:io';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:intl/intl.dart';
import 'pdf_export_helper.dart';

class AdmissionRegisterPdfGenerator {
  static const pageFormat = PdfPageFormat.a4;

  static String studentName(Map<String, dynamic> s) =>
      '${s['surname'] ?? ''} ${s['firstName'] ?? ''} ${s['otherName'] ?? ''}'
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();

  /// Shown for missing values. Plain ASCII: the PDF's built-in Helvetica has
  /// no glyph for an em dash and renders it as a box.
  static const blank = '-';

  static String formatDate(String? value) {
    if (value == null || value.trim().isEmpty) return blank;
    var date = DateTime.tryParse(value.trim());
    // Older records store unpadded dates such as "2010-7-30".
    final loose = RegExp(r'^(\d{4})-(\d{1,2})-(\d{1,2})').firstMatch(value.trim());
    if (date == null && loose != null) {
      date = DateTime(int.parse(loose[1]!), int.parse(loose[2]!), int.parse(loose[3]!));
    }
    return date != null ? DateFormat('dd/MM/yyyy').format(date) : value;
  }

  static String admissionPeriod(Map<String, dynamic> s) {
    final term = (s['admissionTerm'] ?? '').toString();
    final session = (s['admissionSession'] ?? '').toString();
    if (term.isEmpty && session.isEmpty) return blank;
    return [term, session].where((v) => v.isNotEmpty).join(', ');
  }

  static String admittedClass(Map<String, dynamic> s) {
    final className = (s['admittedClassName'] ?? '').toString();
    final armName = (s['admittedArmName'] ?? '').toString();
    if (className.isEmpty) return blank;
    return armName.isNotEmpty ? '$className $armName' : className;
  }

  static String stateLga(Map<String, dynamic> s) {
    final parts = [s['stateOfOrigin'], s['lga']]
        .map((v) => (v ?? '').toString().trim())
        .where((v) => v.isNotEmpty);
    return parts.isEmpty ? blank : parts.join(' / ');
  }

  static String status(Map<String, dynamic> s) {
    if (s['isActive'] != 0) return 'Active';
    final reason = (s['leftReason'] ?? '').toString();
    final left = s['leftDate'] != null && s['leftDate'].toString().isNotEmpty
        ? formatDate(s['leftDate'] as String?)
        : '';
    return ['Left', if (left.isNotEmpty) left, if (reason.isNotEmpty) reason].join(' - ');
  }

  /// "All Sessions & Terms", "2024/2025 - All Terms", "1st Term - All Sessions", ...
  static String filterLabel(String? session, String? term) {
    if (session == null && term == null) return 'All Sessions & Terms';
    return '${term ?? 'All Terms'} - ${session ?? 'All Sessions'}';
  }

  static pw.Document buildDocument({
    required List<Map<String, dynamic>> students,
    required String? session,
    required String? term,
    required Map<String, dynamic> schoolProfile,
  }) {
    final pdf = pw.Document();

    pdf.addPage(
      pw.MultiPage(
        pageFormat: pageFormat.landscape,
        margin: const pw.EdgeInsets.all(24),
        header: (context) => context.pageNumber == 1
            ? pw.SizedBox()
            : pw.Container(
                margin: const pw.EdgeInsets.only(bottom: 6),
                child: pw.Text(
                  'Admission Register - ${filterLabel(session, term)} (continued)',
                  style: pw.TextStyle(fontSize: 8, color: PdfColors.grey700),
                ),
              ),
        build: (context) => [
          _buildHeader(schoolProfile, session, term),
          pw.SizedBox(height: 12),
          _buildSummary(students),
          pw.SizedBox(height: 12),
          _buildTable(students),
        ],
        footer: _buildPageFooter,
      ),
    );

    return pdf;
  }

  static Future<String> generatePdf({
    required List<Map<String, dynamic>> students,
    required String? session,
    required String? term,
    required Map<String, dynamic> schoolProfile,
    required bool saveToDownloads,
  }) async {
    final pdf = buildDocument(
      students: students,
      session: session,
      term: term,
      schoolProfile: schoolProfile,
    );

    final output = await PdfExportDirectoryHelper.resolve(saveToDownloads: saveToDownloads);
    final timestamp = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
    final scope = filterLabel(session, term).replaceAll(RegExp(r'[^A-Za-z0-9]+'), '_');
    final file = File('${output.path}/Admission_Register_${scope}_$timestamp.pdf');
    await file.writeAsBytes(await pdf.save());

    return file.path;
  }

  static pw.Widget _buildHeader(Map<String, dynamic> schoolProfile, String? session, String? term) {
    final schoolName = (schoolProfile['name'] ?? 'School Name').toString();
    final address = (schoolProfile['address'] ?? '').toString();
    final phone = (schoolProfile['phone'] ?? '').toString();
    final email = (schoolProfile['email'] ?? '').toString();

    return pw.Column(
      children: [
        pw.Text(
          schoolName.toUpperCase(),
          style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold),
          textAlign: pw.TextAlign.center,
        ),
        if (address.isNotEmpty) ...[
          pw.SizedBox(height: 3),
          pw.Text(address, style: const pw.TextStyle(fontSize: 9), textAlign: pw.TextAlign.center),
        ],
        if (phone.isNotEmpty || email.isNotEmpty) ...[
          pw.SizedBox(height: 3),
          pw.Text(
            [if (phone.isNotEmpty) 'Tel: $phone', if (email.isNotEmpty) email].join(' | '),
            style: const pw.TextStyle(fontSize: 8),
            textAlign: pw.TextAlign.center,
          ),
        ],
        pw.SizedBox(height: 8),
        pw.Divider(thickness: 2),
        pw.SizedBox(height: 6),
        pw.Text('ADMISSION REGISTER', style: pw.TextStyle(fontSize: 15, fontWeight: pw.FontWeight.bold)),
        pw.SizedBox(height: 4),
        pw.Text(filterLabel(session, term), style: const pw.TextStyle(fontSize: 11)),
        pw.SizedBox(height: 3),
        pw.Text(
          'Generated: ${DateFormat('MMM d, yyyy - h:mm a').format(DateTime.now())}',
          style: pw.TextStyle(fontSize: 8, color: PdfColors.grey700),
        ),
      ],
    );
  }

  static pw.Widget _buildSummary(List<Map<String, dynamic>> students) {
    final male = students.where((s) => s['gender'] == 'Male').length;
    final female = students.where((s) => s['gender'] == 'Female').length;
    final active = students.where((s) => s['isActive'] != 0).length;

    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(vertical: 8, horizontal: 12),
      decoration: pw.BoxDecoration(
        color: PdfColors.teal50,
        border: pw.Border.all(color: PdfColors.teal200),
        borderRadius: pw.BorderRadius.circular(4),
      ),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceAround,
        children: [
          _buildSummaryItem('Total Admitted', '${students.length}'),
          _buildSummaryItem('Male', '$male'),
          _buildSummaryItem('Female', '$female'),
          _buildSummaryItem('Active', '$active'),
          _buildSummaryItem('Left', '${students.length - active}'),
        ],
      ),
    );
  }

  static pw.Widget _buildSummaryItem(String label, String value) {
    return pw.Column(
      children: [
        pw.Text(label, style: pw.TextStyle(fontSize: 8, color: PdfColors.grey700)),
        pw.SizedBox(height: 3),
        pw.Text(value, style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold, color: PdfColors.teal800)),
      ],
    );
  }

  static pw.Widget _buildTable(List<Map<String, dynamic>> students) {
    const headers = [
      'S/N',
      'Adm. No',
      'Student Name',
      'Gender',
      'Date of Birth',
      'Date of Adm.',
      'Term/Session of Adm.',
      'Class Admitted',
      'Parent/Guardian',
      'Phone',
      'Address',
      'State/LGA',
      'Status',
    ];

    return pw.Table(
      border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.5),
      columnWidths: const {
        0: pw.FixedColumnWidth(24),
        1: pw.FixedColumnWidth(70),
        2: pw.FlexColumnWidth(2.0),
        3: pw.FixedColumnWidth(34),
        4: pw.FixedColumnWidth(48),
        5: pw.FixedColumnWidth(48),
        6: pw.FixedColumnWidth(62),
        7: pw.FixedColumnWidth(50),
        8: pw.FlexColumnWidth(1.8),
        9: pw.FixedColumnWidth(56),
        10: pw.FlexColumnWidth(2.2),
        11: pw.FlexColumnWidth(1.2),
        12: pw.FlexColumnWidth(1.3),
      },
      children: [
        pw.TableRow(
          repeat: true,
          decoration: const pw.BoxDecoration(color: PdfColors.grey300),
          children: headers.map(_buildTableHeader).toList(),
        ),
        ...students.asMap().entries.map((entry) {
          final s = entry.value;
          return pw.TableRow(
            decoration: pw.BoxDecoration(color: entry.key.isEven ? PdfColors.white : PdfColors.grey100),
            children: [
              _buildTableCell('${entry.key + 1}'),
              _buildTableCell((s['admissionNo'] ?? '').toString()),
              _buildTableCell(studentName(s), left: true),
              _buildTableCell((s['gender'] ?? '').toString()),
              _buildTableCell(formatDate(s['dob'] as String?)),
              _buildTableCell(formatDate(s['dateOfAdmission'] as String?)),
              _buildTableCell(admissionPeriod(s)),
              _buildTableCell(admittedClass(s)),
              _buildTableCell((s['parentName'] ?? '').toString(), left: true),
              _buildTableCell((s['parentPhone'] ?? '').toString()),
              _buildTableCell((s['address'] ?? '').toString(), left: true),
              _buildTableCell(stateLga(s), left: true),
              _buildTableCell(status(s), left: true),
            ],
          );
        }),
      ],
    );
  }

  static pw.Widget _buildTableHeader(String text) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(4),
      alignment: pw.Alignment.center,
      child: pw.Text(text, style: pw.TextStyle(fontSize: 7, fontWeight: pw.FontWeight.bold), textAlign: pw.TextAlign.center),
    );
  }

  static pw.Widget _buildTableCell(String text, {bool left = false}) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(3),
      alignment: left ? pw.Alignment.centerLeft : pw.Alignment.center,
      child: pw.Text(
        text,
        style: const pw.TextStyle(fontSize: 6.5),
        textAlign: left ? pw.TextAlign.left : pw.TextAlign.center,
      ),
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
