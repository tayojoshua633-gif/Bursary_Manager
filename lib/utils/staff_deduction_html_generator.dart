import 'package:intl/intl.dart';

/// HTML mirror of StaffDeductionPDFGenerator, rendered via Android's native
/// WebView print pipeline (see custom_report_pdf_generator.dart).
class StaffDeductionHtmlGenerator {
  static final _currencyFormat = NumberFormat.currency(symbol: 'N', decimalDigits: 2);

  static String build({
    required List<Map<String, dynamic>> deductions,
    required String month,
    required Map<String, dynamic> schoolProfile,
    required double totalAmount,
    required Map<String, double> reasonTotals,
  }) {
    final schoolName = (schoolProfile['name'] ?? 'School Name').toString();
    final address = (schoolProfile['address'] ?? '').toString();
    final phone = (schoolProfile['phone'] ?? '').toString();
    final email = (schoolProfile['email'] ?? '').toString();

    final reasonChips = reasonTotals.entries
        .map((e) => '<span class="chip">${_esc(e.key)}: ${_currencyFormat.format(e.value)}</span>')
        .join();

    final rows = StringBuffer();
    for (var i = 0; i < deductions.length; i++) {
      final ded = deductions[i];
      rows.writeln('<tr>'
          '<td class="center">${i + 1}</td>'
          '<td>${_esc(ded['staffName'] ?? '')}</td>'
          '<td class="center">${_esc(ded['reason'] ?? '')}</td>'
          '<td>${_esc(ded['description'] ?? '-')}</td>'
          '<td class="center">${_esc(ded['date'] ?? '')}</td>'
          '<td class="center" style="color:#D32F2F;">${_currencyFormat.format(ded['amount'])}</td>'
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
  .title-box { background:#FFEBEE; color:#B71C1C; border-radius:4px; padding:8px 20px; font-size:13px; font-weight:bold; text-align:center; margin: 12px 0 16px; }
  .summary-box { border:1px solid #E0E0E0; border-radius:4px; padding:14px; margin-bottom:16px; }
  .summary-row { display:flex; justify-content:space-around; }
  .summary-item { text-align:center; }
  .summary-item .label { font-size:9px; color:#616161; }
  .summary-item .value { font-size:14px; font-weight:bold; }
  .reason-title { font-weight:bold; font-size:9px; margin-top:10px; }
  .chip { display:inline-block; background:#F5F5F5; border-radius:4px; padding:3px 8px; font-size:8px; margin: 4px 4px 0 0; }
  table { width:100%; border-collapse: collapse; font-size: 9px; margin-bottom: 16px; }
  th, td { border:1px solid #FFCDD2; padding:6px; }
  th { background:#FFCDD2; font-weight:bold; }
  tr:nth-child(even) td { background:#FAFAFA; }
  .footer-row { display:flex; justify-content:space-between; margin-top:24px; font-size:9px; }
  .bank-box { border:1px solid #90CAF9; background:#E3F2FD; border-radius:6px; padding:10px; font-size:9px; margin-top: 12px; }
</style>
</head><body>
  <h1>${_esc(schoolName.toUpperCase())}</h1>
  ${address.isNotEmpty ? '<div class="muted">${_esc(address)}</div>' : ''}
  ${(phone.isNotEmpty || email.isNotEmpty) ? '<div class="muted">${[if (phone.isNotEmpty) 'Tel: ${_esc(phone)}', if (email.isNotEmpty) _esc(email)].join(' | ')}</div>' : ''}
  <div class="title-box">STAFF PENALTY/DEDUCTION REPORT - ${_esc(month)}</div>

  <div class="summary-box">
    <div class="summary-row">
      <div class="summary-item"><div class="label">Total Records</div><div class="value">${deductions.length}</div></div>
      <div class="summary-item"><div class="label">Total Amount</div><div class="value" style="color:#D32F2F;">${_currencyFormat.format(totalAmount)}</div></div>
    </div>
    ${reasonTotals.isEmpty ? '' : '<div class="reason-title">Breakdown by Reason:</div><div>$reasonChips</div>'}
  </div>

  <table>
    <thead><tr>
      <th class="center">S/N</th><th>Staff Name</th><th class="center">Reason</th>
      <th>Description</th><th class="center">Date</th><th class="center">Amount</th>
    </tr></thead>
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
