import 'package:intl/intl.dart';

/// HTML mirror of StaffPayrollPDFGenerator, rendered via Android's native
/// WebView print pipeline (see custom_report_pdf_generator.dart).
class StaffPayrollHtmlGenerator {
  static final _currencyFormat = NumberFormat.currency(symbol: 'N', decimalDigits: 2);

  static String build({
    required List<Map<String, dynamic>> payrollData,
    required String month,
    required Map<String, dynamic> schoolProfile,
  }) {
    double totalBasicSalary = 0, totalIncentives = 0, totalLoanDeductions = 0, totalPenalties = 0, totalNetSalary = 0;
    for (final staff in payrollData) {
      totalBasicSalary += (staff['basicSalary'] as num).toDouble();
      totalIncentives += (staff['totalIncentives'] as num).toDouble();
      totalLoanDeductions += (staff['loanDeduction'] as num).toDouble();
      totalPenalties += (staff['totalDeductions'] as num).toDouble();
      totalNetSalary += (staff['netSalary'] as num).toDouble();
    }

    final schoolName = (schoolProfile['name'] ?? 'School Name').toString();
    final address = (schoolProfile['address'] ?? '').toString();
    final phone = (schoolProfile['phone'] ?? '').toString();

    final rows = StringBuffer();
    for (var i = 0; i < payrollData.length; i++) {
      final s = payrollData[i];
      rows.writeln('<tr>'
          '<td class="center">${i + 1}</td>'
          '<td>${_esc(s['staffName'] ?? '')}</td>'
          '<td class="center">${_esc(s['staffId'] ?? '')}</td>'
          '<td class="center">${_currencyFormat.format(s['basicSalary'])}</td>'
          '<td class="center" style="color:#388E3C;">${_currencyFormat.format(s['totalIncentives'])}</td>'
          '<td class="center" style="color:#F57C00;">${_currencyFormat.format(s['loanDeduction'])}</td>'
          '<td class="center" style="color:#D32F2F;">${_currencyFormat.format(s['totalDeductions'])}</td>'
          '<td class="center" style="color:#1976D2; font-weight:bold;">${_currencyFormat.format(s['netSalary'])}</td>'
          '<td>${_esc(s['bankName'] ?? '-')}</td>'
          '<td class="center">${_esc(s['accountNumber'] ?? '-')}</td>'
          '</tr>');
    }

    return '''
<!DOCTYPE html><html><head><meta charset="utf-8">
<style>
  @page { size: A4 landscape; margin: 18px; }
  body { font-family: Helvetica, Arial, sans-serif; color: #1a1a1a; font-size: 11px; margin:0; padding:18px; }
  .center { text-align: center; }
  h1 { font-size: 16px; margin: 0; text-align: center; }
  .muted { color: #616161; text-align:center; font-size: 9px; }
  .title-box { background:#E3F2FD; color:#0D47A1; border-radius:4px; padding:8px 16px; font-size:13px; font-weight:bold; text-align:center; margin: 12px 0 16px; }
  .summary { border:1px solid #E0E0E0; border-radius:4px; padding:10px; display:flex; justify-content:space-around; margin-bottom:16px; }
  .summary .stat { text-align:center; }
  .summary .label { font-size:8px; color:#616161; }
  .summary .value { font-size:10px; font-weight:bold; }
  .summary .value.highlight { color:#388E3C; }
  table { width:100%; border-collapse: collapse; font-size: 9px; }
  th, td { border:1px solid #E0E0E0; padding:5px; }
  th { background:#BBDEFB; font-weight:bold; }
  tr:nth-child(even) td { background:#FAFAFA; }
  .footer-row { display:flex; justify-content:space-between; margin-top:24px; font-size:9px; }
</style>
</head><body>
  <h1>${_esc(schoolName.toUpperCase())}</h1>
  ${address.isNotEmpty ? '<div class="muted">${_esc(address)}</div>' : ''}
  ${phone.isNotEmpty ? '<div class="muted">Tel: ${_esc(phone)}</div>' : ''}
  <div class="title-box">STAFF PAYROLL - ${_esc(month)}</div>

  <div class="summary">
    <div class="stat"><div class="label">Staff Count</div><div class="value">${payrollData.length}</div></div>
    <div class="stat"><div class="label">Total Basic</div><div class="value">${_currencyFormat.format(totalBasicSalary)}</div></div>
    <div class="stat"><div class="label">Total Incentives</div><div class="value">${_currencyFormat.format(totalIncentives)}</div></div>
    <div class="stat"><div class="label">Loan Deductions</div><div class="value">${_currencyFormat.format(totalLoanDeductions)}</div></div>
    <div class="stat"><div class="label">Penalties</div><div class="value">${_currencyFormat.format(totalPenalties)}</div></div>
    <div class="stat"><div class="label">Net Payroll</div><div class="value highlight">${_currencyFormat.format(totalNetSalary)}</div></div>
  </div>

  <table>
    <thead><tr>
      <th class="center">S/N</th><th>Staff Name</th><th class="center">Staff ID</th>
      <th class="center">Basic Salary</th><th class="center">Incentives</th>
      <th class="center">Loan Ded.</th><th class="center">Penalties</th>
      <th class="center">Net Salary</th><th>Bank</th><th class="center">Account No.</th>
    </tr></thead>
    <tbody>$rows</tbody>
  </table>

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
