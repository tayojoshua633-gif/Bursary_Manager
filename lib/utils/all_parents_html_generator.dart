import 'package:intl/intl.dart';
import '../models/parent.dart';

/// HTML report for the All Parents screen, rendered via Android's native
/// WebView print pipeline (see custom_report_pdf_generator.dart).
class AllParentsHtmlGenerator {
  static String build({
    required List<Parent> parents,
    required Map<String, dynamic> schoolProfile,
  }) {
    final schoolName = (schoolProfile['name'] ?? 'School Name').toString();
    final address = (schoolProfile['address'] ?? '').toString();
    final phone = (schoolProfile['phone'] ?? '').toString();
    final email = (schoolProfile['email'] ?? '').toString();

    final rows = StringBuffer();
    for (var i = 0; i < parents.length; i++) {
      final p = parents[i];
      rows.writeln('<tr>'
          '<td class="center">${i + 1}</td>'
          '<td>${_esc(p.parentName)}</td>'
          '<td>${_esc(p.phoneNumbers)}</td>'
          '<td>${_esc(p.emailAddress ?? '-')}</td>'
          '<td>${_esc(p.homeAddress)}</td>'
          '<td>${_esc(p.occupation ?? '-')}</td>'
          '</tr>');
    }

    return '''
<!DOCTYPE html><html><head><meta charset="utf-8">
<style>
  @page { margin: 22px; }
  body { font-family: Helvetica, Arial, sans-serif; color: #1a1a1a; font-size: 11px; margin:0; padding:22px; }
  .center { text-align: center; }
  h1 { font-size: 18px; margin: 0; text-align:center; color:#1565C0; }
  .muted { color: #616161; text-align:center; font-size: 10px; }
  hr { border: none; border-top: 2px solid #90CAF9; margin: 12px 0; }
  .title { font-size: 15px; font-weight:bold; text-align:center; margin-bottom: 12px; }
  .count-box { display:inline-block; background:#E3F2FD; color:#0D47A1; border-radius:4px; padding:6px 16px; font-weight:bold; font-size:11px; margin: 0 auto 16px; }
  table { width:100%; border-collapse: collapse; font-size: 9px; }
  th, td { border:1px solid #BBDEFB; padding:6px; }
  th { background:#BBDEFB; font-weight:bold; text-align:left; }
  tr:nth-child(even) td { background:#FAFAFA; }
  .footer-note { text-align: center; font-style: italic; color: #616161; font-size: 9px; margin-top: 16px; }
</style>
</head><body>
  <h1>${_esc(schoolName.toUpperCase())}</h1>
  ${address.isNotEmpty ? '<div class="muted">${_esc(address)}</div>' : ''}
  ${(phone.isNotEmpty || email.isNotEmpty) ? '<div class="muted">${[if (phone.isNotEmpty) 'Tel: ${_esc(phone)}', if (email.isNotEmpty) _esc(email)].join(' | ')}</div>' : ''}
  <hr>
  <div class="title">ALL PARENTS/GUARDIANS</div>
  <div class="center"><span class="count-box">${parents.length} Parents</span></div>
  <div class="muted" style="text-align:right; margin-bottom:8px;">Generated: ${_esc(DateFormat('MMM d, yyyy - h:mm a').format(DateTime.now()))}</div>

  <table>
    <thead><tr>
      <th class="center">S/N</th><th>Name</th><th>Phone</th><th>Email</th><th>Address</th><th>Occupation</th>
    </tr></thead>
    <tbody>$rows</tbody>
  </table>

  <div class="footer-note">This report lists all parents/guardians registered in the system.</div>
</body></html>
''';
  }

  static String _esc(dynamic value) {
    final s = value?.toString() ?? '';
    return s.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;');
  }
}
