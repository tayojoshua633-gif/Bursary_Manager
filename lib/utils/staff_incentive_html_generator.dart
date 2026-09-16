import 'package:intl/intl.dart';

/// HTML mirror of StaffIncentivePDFGenerator, rendered via Android's native
/// WebView print pipeline (see custom_report_pdf_generator.dart).
class StaffIncentiveHtmlGenerator {
  static final _currencyFormat = NumberFormat.currency(symbol: 'N', decimalDigits: 2);

  static String build({
    required List<Map<String, dynamic>> incentives,
    required String month,
    required Map<String, dynamic> schoolProfile,
    required double totalAmount,
  }) {
    final schoolName = (schoolProfile['name'] ?? 'School Name').toString();
    final address = (schoolProfile['address'] ?? '').toString();
    final phone = (schoolProfile['phone'] ?? '').toString();
    final email = (schoolProfile['email'] ?? '').toString();

    final rows = StringBuffer();
    for (var i = 0; i < incentives.length; i++) {
      final inc = incentives[i];
      rows.writeln('<tr>'
          '<td class="center">${i + 1}</td>'
          '<td>${_esc(inc['staffName'] ?? '')}</td>'
          '<td>${_esc(inc['description'] ?? '')}</td>'
          '<td class="center" style="color:#2E7D32;">${_currencyFormat.format(inc['amount'])}</td>'
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
  @page { margin: 22px; }
  body { font-family: Helvetica, Arial, sans-serif; color: #1a1a1a; font-size: 11px; margin:0; padding:22px; }
  .center { text-align: center; }
  h1 { font-size: 18px; margin: 0; text-align:center; }
  .muted { color: #616161; text-align:center; font-size: 10px; }
  .title-box { background:#E8F5E9; color:#1B5E20; border-radius:4px; padding:8px 20px; font-size:13px; font-weight:bold; text-align:center; margin: 12px 0 16px; }
  .summary-box { border:1px solid #E0E0E0; border-radius:4px; padding:14px; margin-bottom:16px; display:flex; justify-content:space-around; }
  .summary-item { text-align:center; }
  .summary-item .label { font-size:9px; color:#616161; }
  .summary-item .value { font-size:15px; font-weight:bold; }
  table { width:100%; border-collapse: collapse; font-size: 9px; margin-bottom: 16px; }
  th, td { border:1px solid #C8E6C9; padding:6px; }
  th { background:#C8E6C9; font-weight:bold; }
  tr:nth-child(even) td { background:#FAFAFA; }
  .footer-row { display:flex; justify-content:space-between; margin-top:24px; font-size:9px; }
  .bank-box { border:1px solid #90CAF9; background:#E3F2FD; border-radius:6px; padding:10px; font-size:9px; margin-top: 12px; }
</style>
</head><body>
  <h1>${_esc(schoolName.toUpperCase())}</h1>
  ${address.isNotEmpty ? '<div class="muted">${_esc(address)}</div>' : ''}
  ${(phone.isNotEmpty || email.isNotEmpty) ? '<div class="muted">${[if (phone.isNotEmpty) 'Tel: ${_esc(phone)}', if (email.isNotEmpty) _esc(email)].join(' | ')}</div>' : ''}
  <div class="title-box">STAFF INCENTIVES/GRANTS - ${_esc(month)}</div>

  <div class="summary-box">
    <div class="summary-item"><div class="label">Total Records</div><div class="value">${incentives.length}</div></div>
    <div class="summary-item"><div class="label">Total Amount</div><div class="value" style="color:#2E7D32;">${_currencyFormat.format(totalAmount)}</div></div>
  </div>

  <table>
    <thead><tr><th class="center">S/N</th><th>Staff Name</th><th>Description</th><th class="center">Amount</th></tr></thead>
    <tbody>$rows</tbody>
  </table>

  ${accounts.isEmpty ? '' : '<div class="bank-box"><strong>Bank Account Details:</strong>${accounts.map((a) => '<div>${_esc(a)}</div>').join()}</div>'}

  <div class="footer-row">
    <div>Prepared by: _______________________<br><br>Date: _______________________</div>
    <div>Approved by: _______________________<br><br>Signature: _______________________</div>
  </div>
</body></html>
''';
  }

  static String _esc(dynamic value) {
    final s = value?.toString() ?? '';
    return s.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;');
  }
}
