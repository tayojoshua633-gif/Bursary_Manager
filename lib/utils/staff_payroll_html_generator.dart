import 'package:intl/intl.dart';

/// HTML mirror of StaffPayrollPDFGenerator, rendered via Android's native
/// WebView print pipeline (see custom_report_pdf_generator.dart).
class StaffPayrollHtmlGenerator {
  static final _currencyFormat = NumberFormat.currency(symbol: 'N', decimalDigits: 2);

  /// Loan taken from this salary: this month's repayment plus missed months.
  static double _loanTotal(Map<String, dynamic> staff) =>
      (staff['loanDeduction'] as num).toDouble() + (staff['loanArrears'] as num? ?? 0).toDouble();

  /// Final amount for the month after arrears and any amount owed from a
  /// settled month — matches the Total Payable shown on the payroll card.
  static double _payable(Map<String, dynamic> staff) =>
      (staff['totalPayable'] as num? ?? staff['netSalary'] as num).toDouble();

  static String _statusLabel(Map<String, dynamic> staff) {
    if (staff['paidWithMonth'] != null) return 'Paid with ${staff['paidWithMonth']}';
    if (staff['isSettled'] == true) return 'Settled – owing';
    if (staff['isPaid'] == true) return 'Paid';
    return _payable(staff) < -0.005 ? 'Owing' : 'Not paid';
  }

  static String build({
    required List<Map<String, dynamic>> payrollData,
    required String month,
    required Map<String, dynamic> schoolProfile,
  }) {
    double totalBasicSalary = 0, totalIncentives = 0, totalLoanDeductions = 0, totalPenalties = 0;
    double totalOwingBroughtForward = 0, totalNetSalary = 0, totalStaffOwing = 0;
    for (final staff in payrollData) {
      totalBasicSalary += (staff['basicSalary'] as num).toDouble();
      totalIncentives += (staff['totalIncentives'] as num).toDouble();
      totalLoanDeductions += _loanTotal(staff);
      totalPenalties += (staff['totalDeductions'] as num).toDouble();
      totalOwingBroughtForward += (staff['owingBroughtForward'] as num? ?? 0).toDouble();
      // Net payroll is what is actually paid out — staff who owe get ₦0
      final payable = _payable(staff);
      if (staff['paidWithMonth'] != null) {
        // already counted in the later salary that paid it
      } else if (payable > 0) {
        totalNetSalary += payable;
      } else {
        totalStaffOwing -= payable;
      }
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
          '<td class="center" style="color:#388E3C;">${_currencyFormat.format(s['arrears'] ?? 0)}</td>'
          '<td class="center" style="color:#F57C00;">${_currencyFormat.format(_loanTotal(s))}</td>'
          '<td class="center" style="color:#D32F2F;">${_currencyFormat.format(s['totalDeductions'])}</td>'
          '<td class="center" style="color:#E64A19;">${_currencyFormat.format(s['owingBroughtForward'] ?? 0)}</td>'
          '<td class="center" style="color:${_payable(s) < 0 ? '#D32F2F' : '#1976D2'}; font-weight:bold;">${_currencyFormat.format(_payable(s))}</td>'
          '<td class="center"${s['isSettled'] == true || _payable(s) < -0.005 ? ' style="color:#E64A19;"' : ''}>${_statusLabel(s)}</td>'
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
    ${totalOwingBroughtForward > 0 ? '<div class="stat"><div class="label">Owing B/F</div><div class="value">${_currencyFormat.format(totalOwingBroughtForward)}</div></div>' : ''}
    <div class="stat"><div class="label">Net Payroll</div><div class="value highlight">${_currencyFormat.format(totalNetSalary)}</div></div>
    ${totalStaffOwing > 0 ? '<div class="stat"><div class="label">Owed by Staff</div><div class="value" style="color:#E64A19;">${_currencyFormat.format(totalStaffOwing)}</div></div>' : ''}
  </div>

  <table>
    <thead><tr>
      <th class="center">S/N</th><th>Staff Name</th><th class="center">Staff ID</th>
      <th class="center">Basic Salary</th><th class="center">Incentives</th><th class="center">Arrears</th>
      <th class="center">Loan Ded.</th><th class="center">Penalties</th><th class="center">Owing B/F</th>
      <th class="center">Net Payable</th><th class="center">Status</th><th>Bank</th><th class="center">Account No.</th>
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
