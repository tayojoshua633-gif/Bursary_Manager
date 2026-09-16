import 'package:intl/intl.dart';
import '../models/staff.dart';

/// HTML mirror of StaffListingPDFGenerator, rendered via Android's native
/// WebView print pipeline (see custom_report_pdf_generator.dart).
class StaffListingHtmlGenerator {
  static final _currencyFormat = NumberFormat.currency(symbol: 'N', decimalDigits: 0);

  static String build({
    required List<Staff> staff,
    required Map<String, dynamic> schoolProfile,
    required String filterType,
    required int totalStaff,
    required int teachingCount,
    required int nonTeachingCount,
    required double totalSalary,
  }) {
    final schoolName = (schoolProfile['name'] ?? 'School Name').toString();
    final address = (schoolProfile['address'] ?? '').toString();
    final phone = (schoolProfile['phone'] ?? '').toString();
    final email = (schoolProfile['email'] ?? '').toString();

    final rows = StringBuffer();
    for (var i = 0; i < staff.length; i++) {
      final s = staff[i];
      rows.writeln('<tr>'
          '<td class="center">${i + 1}</td>'
          '<td class="center">${_esc(s.staffId)}</td>'
          '<td>${_esc(s.fullName)}</td>'
          '<td class="center">${_esc(s.gender)}</td>'
          '<td class="center" style="color:${s.isTeachingStaff ? '#2E7D32' : '#E65100'};">${_esc(s.staffType)}</td>'
          '<td class="center">${_esc(s.phone ?? '-')}</td>'
          '<td class="center">${s.salary > 0 ? _currencyFormat.format(s.salary) : '-'}</td>'
          '</tr>');
    }

    final accounts = <String>[];
    for (int i = 1; i <= 3; i++) {
      final bankName = (schoolProfile['bankName$i']?.toString() ?? '');
      final accNum = (schoolProfile['accountNumber$i']?.toString() ?? '');
      final accName = (schoolProfile['accountName$i']?.toString() ?? '');
      if (bankName.isNotEmpty && accNum.isNotEmpty) {
        accounts.add('$bankName - $accNum - $accName');
      }
    }

    return '''
<!DOCTYPE html><html><head><meta charset="utf-8">
<style>
  @page { size: A4 landscape; margin: 18px; }
  body { font-family: Helvetica, Arial, sans-serif; color: #1a1a1a; font-size: 11px; margin:0; padding:18px; }
  .center { text-align: center; }
  h1 { font-size: 16px; margin: 0; text-align: center; }
  .muted { color: #616161; text-align:center; font-size: 9px; }
  .title-box { background:#ECEFF1; color:#263238; border-radius:4px; padding:8px 16px; font-size:13px; font-weight:bold; text-align:center; margin: 12px 0 16px; }
  .summary { border:1px solid #E0E0E0; border-radius:4px; padding:10px; display:flex; justify-content:space-around; margin-bottom:16px; }
  .summary .stat { text-align:center; }
  .summary .label { font-size:9px; color:#616161; }
  .summary .value { font-size:14px; font-weight:bold; }
  table { width:100%; border-collapse: collapse; font-size: 9px; }
  th, td { border:1px solid #E0E0E0; padding:5px; }
  th { background:#CFD8DC; font-weight:bold; }
  tr:nth-child(even) td { background:#FAFAFA; }
  .footer-row { display:flex; justify-content:space-between; margin-top:24px; font-size:9px; }
  .bank-box { border:1px solid #90CAF9; background:#E3F2FD; border-radius:6px; padding:10px; margin-top:12px; font-size:9px; }
</style>
</head><body>
  <h1>${_esc(schoolName.toUpperCase())}</h1>
  ${address.isNotEmpty ? '<div class="muted">${_esc(address)}</div>' : ''}
  ${(phone.isNotEmpty || email.isNotEmpty) ? '<div class="muted">${[if (phone.isNotEmpty) 'Tel: ${_esc(phone)}', if (email.isNotEmpty) _esc(email)].join(' | ')}</div>' : ''}
  <div class="title-box">STAFF LISTING - ${_esc(filterType)}</div>

  <div class="summary">
    <div class="stat"><div class="label">Total Staff</div><div class="value">$totalStaff</div></div>
    <div class="stat"><div class="label">Teaching Staff</div><div class="value" style="color:#2E7D32;">$teachingCount</div></div>
    <div class="stat"><div class="label">Non-Teaching Staff</div><div class="value" style="color:#E65100;">$nonTeachingCount</div></div>
    <div class="stat"><div class="label">Total Salary</div><div class="value" style="color:#1565C0;">${_currencyFormat.format(totalSalary)}</div></div>
  </div>

  <table>
    <thead><tr>
      <th class="center">S/N</th><th class="center">Staff ID</th><th>Full Name</th>
      <th class="center">Gender</th><th class="center">Staff Type</th>
      <th class="center">Phone</th><th class="center">Salary</th>
    </tr></thead>
    <tbody>$rows</tbody>
  </table>

  <div class="footer-row">
    <div>Prepared by: _______________________<br><br>Date: _______________________</div>
    <div>Approved by: _______________________<br><br>Signature: _______________________</div>
  </div>

  ${accounts.isEmpty ? '' : '<div class="bank-box"><strong>Bank Account Details:</strong>${accounts.map((a) => '<div>${_esc(a)}</div>').join()}</div>'}
</body></html>
''';
  }

  static String _esc(dynamic value) {
    final s = value?.toString() ?? '';
    return s.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;');
  }
}
