import 'package:intl/intl.dart';

/// HTML report for the New Students screen, rendered via Android's native
/// WebView print pipeline (see custom_report_pdf_generator.dart).
class NewStudentsHtmlGenerator {
  static String build({
    required List<Map<String, dynamic>> students,
    required Map<String, dynamic> schoolProfile,
    required String term,
    required String session,
  }) {
    final schoolName = (schoolProfile['name'] ?? 'School Name').toString();
    final address = (schoolProfile['address'] ?? '').toString();
    final phone = (schoolProfile['phone'] ?? '').toString();
    final email = (schoolProfile['email'] ?? '').toString();

    String formatDate(String? dateStr) {
      if (dateStr == null || dateStr.isEmpty) return 'Not recorded';
      try {
        final date = DateTime.parse(dateStr);
        return "${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}";
      } catch (e) {
        return dateStr;
      }
    }

    final rows = StringBuffer();
    for (var i = 0; i < students.length; i++) {
      final s = students[i];
      final fullName = '${s['surname']} ${s['firstName']} ${s['otherName'] ?? ''}'.trim();
      final classArm = '${s['className'] ?? ''}${s['armName'] != null && s['armName'].toString().isNotEmpty ? ' - ${s['armName']}' : ''}';

      rows.writeln('<tr>'
          '<td class="center">${i + 1}</td>'
          '<td>${_esc(s['admissionNo'])}</td>'
          '<td>${_esc(fullName)}</td>'
          '<td>${_esc(classArm)}</td>'
          '<td class="center">${_esc(s['gender'])}</td>'
          '<td class="center">${_esc(formatDate(s['dateOfAdmission']?.toString()))}</td>'
          '<td>${_esc(s['parentName'])}</td>'
          '<td>${_esc(s['parentPhone'])}</td>'
          '</tr>');
    }

    return '''
<!DOCTYPE html><html><head><meta charset="utf-8">
<style>
  @page { size: A4 landscape; margin: 20px; }
  body { font-family: Helvetica, Arial, sans-serif; color: #1a1a1a; font-size: 10px; margin:0; padding:20px; }
  .center { text-align: center; }
  h1 { font-size: 16px; margin: 0; text-align:center; color:#00695C; }
  .muted { color: #616161; text-align:center; font-size: 9px; }
  hr { border: none; border-top: 2px solid #80CBC4; margin: 10px 0; }
  .title { font-size: 14px; font-weight:bold; text-align:center; margin-bottom: 6px; }
  .count-box { display:inline-block; background:#E0F2F1; color:#00695C; border-radius:4px; padding:5px 14px; font-weight:bold; font-size:10px; margin: 0 auto 12px; }
  table { width:100%; border-collapse: collapse; font-size: 9px; }
  th, td { border:1px solid #B2DFDB; padding:5px; }
  th { background:#B2DFDB; font-weight:bold; text-align:left; }
  tr:nth-child(even) td { background:#FAFAFA; }
  .footer-note { text-align: center; font-style: italic; color: #616161; font-size: 9px; margin-top: 14px; }
</style>
</head><body>
  <h1>${_esc(schoolName.toUpperCase())}</h1>
  ${address.isNotEmpty ? '<div class="muted">${_esc(address)}</div>' : ''}
  ${(phone.isNotEmpty || email.isNotEmpty) ? '<div class="muted">${[if (phone.isNotEmpty) 'Tel: ${_esc(phone)}', if (email.isNotEmpty) _esc(email)].join(' | ')}</div>' : ''}
  <hr>
  <div class="title">NEW STUDENTS (CURRENT TERM REGISTRATIONS)</div>
  <div class="center"><span class="count-box">${students.length} Students | ${_esc(term)} - ${_esc(session)}</span></div>
  <div class="muted" style="text-align:right; margin-bottom:8px;">Generated: ${_esc(DateFormat('MMM d, yyyy - h:mm a').format(DateTime.now()))}</div>

  <table>
    <thead><tr>
      <th class="center">S/N</th><th>Adm. No</th><th>Student Name</th><th>Class/Arm</th>
      <th class="center">Gender</th><th class="center">Date of Admission</th><th>Parent Name</th><th>Parent Phone</th>
    </tr></thead>
    <tbody>$rows</tbody>
  </table>

  <div class="footer-note">This report lists students with a registration fee bill for the current term/session.</div>
</body></html>
''';
  }

  static String _esc(dynamic value) {
    final s = value?.toString() ?? '';
    return s.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;');
  }
}
