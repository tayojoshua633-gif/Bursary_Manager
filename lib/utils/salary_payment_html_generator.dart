import 'package:intl/intl.dart';

/// HTML mirror of SalaryPaymentPDFGenerator, rendered via Android's native
/// WebView print pipeline (see custom_report_pdf_generator.dart).
class SalaryPaymentHtmlGenerator {
  static final _currencyFormat = NumberFormat.currency(symbol: 'N', decimalDigits: 2);

  static String build({
    required List<Map<String, dynamic>> paymentRecords,
    required String month,
    required Map<String, dynamic> schoolProfile,
    required int totalStaff,
    required int paidCount,
    required int unpaidCount,
    required double totalPaidAmount,
    required double totalUnpaidAmount,
  }) {
    final paidRecords = paymentRecords.where((r) => r['isPaid'] == true).toList();
    final unpaidRecords = paymentRecords.where((r) => r['isPaid'] == false).toList();

    final schoolName = (schoolProfile['name'] ?? 'School Name').toString();
    final address = (schoolProfile['address'] ?? '').toString();
    final phone = (schoolProfile['phone'] ?? '').toString();

    String buildTable(List<Map<String, dynamic>> records) {
      final rows = StringBuffer();
      for (var i = 0; i < records.length; i++) {
        final r = records[i];
        rows.writeln('<tr>'
            '<td class="center">${i + 1}</td>'
            '<td>${_esc(r['staffName'] ?? '')}</td>'
            '<td class="center">${_esc(r['staffId'] ?? '')}</td>'
            '<td class="center">${_currencyFormat.format(r['basicSalary'])}</td>'
            '<td class="center" style="color:#2E7D32;">${_currencyFormat.format(r['incentives'])}</td>'
            '<td class="center" style="color:#EF6C00;">${_currencyFormat.format(r['loanDeduction'])}</td>'
            '<td class="center" style="color:#D32F2F;">${_currencyFormat.format(r['penalties'])}</td>'
            '<td class="center" style="color:#1565C0; font-weight:bold;">${_currencyFormat.format(r['netSalary'])}</td>'
            '<td>${_esc(r['bankName'] ?? '-')}</td>'
            '<td class="center">${_esc(r['accountNumber'] ?? '-')}</td>'
            '</tr>');
      }
      return '<table>'
          '<thead><tr>'
          '<th class="center">S/N</th><th>Staff Name</th><th class="center">Staff ID</th>'
          '<th class="center">Basic</th><th class="center">Incentive</th><th class="center">Loan Ded.</th>'
          '<th class="center">Penalty</th><th class="center">Net Salary</th><th>Bank</th><th class="center">Account No.</th>'
          '</tr></thead><tbody>$rows</tbody></table>';
    }

    return '''
<!DOCTYPE html><html><head><meta charset="utf-8">
<style>
  @page { size: A4 landscape; margin: 18px; }
  body { font-family: Helvetica, Arial, sans-serif; color: #1a1a1a; font-size: 10px; margin:0; padding:18px; }
  .center { text-align: center; }
  h1 { font-size: 16px; margin: 0; text-align:center; }
  .muted { color: #616161; text-align:center; font-size: 8px; }
  .title-box { background:#E0F2F1; color:#004D40; border-radius:4px; padding:6px 16px; font-size:13px; font-weight:bold; text-align:center; margin: 10px 0 14px; }
  .summary { border:1px solid #E0E0E0; border-radius:4px; padding:10px; display:flex; justify-content:space-around; margin-bottom:16px; }
  .summary .stat { text-align:center; }
  .summary .label { font-size:8px; color:#616161; }
  .summary .value { font-size:11px; font-weight:bold; }
  .section-title { display:inline-block; color:white; border-radius:4px; padding:5px 12px; font-size:10px; font-weight:bold; margin: 10px 0 8px; }
  table { width:100%; border-collapse: collapse; font-size: 8px; margin-bottom: 16px; }
  th, td { border:1px solid #E0E0E0; padding:5px; }
  th { font-weight:bold; }
  tr:nth-child(even) td { background:#FAFAFA; }
  .footer-row { display:flex; justify-content:space-between; margin-top:20px; font-size:9px; }
</style>
</head><body>
  <h1>${_esc(schoolName.toUpperCase())}</h1>
  ${address.isNotEmpty ? '<div class="muted">${_esc(address)}</div>' : ''}
  ${phone.isNotEmpty ? '<div class="muted">Tel: ${_esc(phone)}</div>' : ''}
  <div class="title-box">SALARY PAYMENT RECORD - ${_esc(month)}</div>

  <div class="summary">
    <div class="stat"><div class="label">Total Staff</div><div class="value">$totalStaff</div></div>
    <div class="stat"><div class="label">Paid</div><div class="value" style="color:#2E7D32;">$paidCount</div></div>
    <div class="stat"><div class="label">Unpaid</div><div class="value" style="color:#D32F2F;">$unpaidCount</div></div>
    <div class="stat"><div class="label">Total Paid</div><div class="value" style="color:#2E7D32;">${_currencyFormat.format(totalPaidAmount)}</div></div>
    <div class="stat"><div class="label">Outstanding</div><div class="value" style="color:#D32F2F;">${_currencyFormat.format(totalUnpaidAmount)}</div></div>
  </div>

  ${paidRecords.isEmpty ? '' : '<div class="section-title" style="background:#388E3C;">PAID STAFF</div>${buildTable(paidRecords)}'}
  ${unpaidRecords.isEmpty ? '' : '<div class="section-title" style="background:#D32F2F;">UNPAID STAFF</div>${buildTable(unpaidRecords)}'}

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
