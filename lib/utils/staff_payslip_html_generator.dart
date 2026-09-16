import 'package:intl/intl.dart';

/// HTML mirror of StaffPayslipPDFGenerator, rendered via Android's native
/// WebView print pipeline (see custom_report_pdf_generator.dart).
class StaffPayslipHtmlGenerator {
  static final _currencyFormat = NumberFormat.currency(symbol: 'N', decimalDigits: 2);

  static String build({
    required Map<String, dynamic> staff,
    required String month,
    required Map<String, dynamic> schoolProfile,
  }) {
    final isPerPeriodPay = staff['isPerPeriodPay'] == true;
    final totalPayable = (staff['totalPayable'] as num? ?? staff['netSalary'] as num? ?? 0).toDouble();
    final arrears = (staff['arrears'] as num? ?? 0).toDouble();
    final loanArrears = (staff['loanArrears'] as num? ?? 0).toDouble();

    final schoolName = (schoolProfile['name'] ?? 'School Name').toString();
    final address = (schoolProfile['address'] ?? '').toString();
    final phone = (schoolProfile['phone'] ?? '').toString();

    final earningsRows = StringBuffer();
    if (isPerPeriodPay) {
      earningsRows.writeln(_row(
        'Basic Pay (${_fmtNum((staff['periodsWorked'] as num? ?? 0).toDouble())} periods × ${_currencyFormat.format(staff['periodRate'])})',
        _currencyFormat.format(staff['basicSalary']),
      ));
    } else {
      earningsRows.writeln(_row('Basic Salary', _currencyFormat.format(staff['basicSalary'])));
      earningsRows.writeln(_row('Payment Basis', _basisSummary(staff['payrollBasis'] as Map<String, dynamic>?)));
    }
    earningsRows.writeln(_row('Incentives/Grants', _currencyFormat.format(staff['totalIncentives'])));
    if (arrears > 0) earningsRows.writeln(_row('Salary Arrears (prev. months)', _currencyFormat.format(arrears)));

    final deductionRows = StringBuffer();
    deductionRows.writeln(_row(
      loanArrears > 0 ? 'Loan (this month)' : 'Loan Deduction',
      _currencyFormat.format(staff['loanDeduction']),
    ));
    if (loanArrears > 0) deductionRows.writeln(_row('Loan Arrears (missed months)', _currencyFormat.format(loanArrears)));
    deductionRows.writeln(_row('Penalties', _currencyFormat.format(staff['totalDeductions'])));

    final bankRows = StringBuffer();
    bankRows.writeln(_row('Bank Name', (staff['bankName'] ?? '').toString().isEmpty ? 'Not provided' : staff['bankName']));
    bankRows.writeln(_row('Account Name', (staff['accountName'] ?? '').toString().isEmpty ? 'Not provided' : staff['accountName']));
    bankRows.writeln(_row('Account Number', (staff['accountNumber'] ?? '').toString().isEmpty ? 'Not provided' : staff['accountNumber']));

    return '''
<!DOCTYPE html><html><head><meta charset="utf-8">
<style>
  @page { margin: 24px; }
  body { font-family: Helvetica, Arial, sans-serif; color: #1a1a1a; font-size: 11px; margin:0; padding:24px; }
  h1 { font-size: 15px; margin: 0; text-align: center; }
  .muted { color: #616161; text-align:center; font-size: 9px; }
  .title-box { background:#E3F2FD; color:#0D47A1; border-radius:4px; padding:6px 16px; font-size:12px; font-weight:bold; text-align:center; margin: 10px auto; width: fit-content; }
  .staff-info { border:1px solid #E0E0E0; border-radius:4px; padding:10px; display:flex; justify-content:space-between; align-items:center; margin-bottom:14px; }
  .section { border:1px solid; border-radius:4px; padding:10px; margin-bottom:12px; }
  .section-title { font-size:11px; font-weight:bold; margin-bottom:6px; }
  .row { display:flex; justify-content:space-between; padding:2px 0; font-size:9px; }
  .row .label { color:#616161; }
  .row .value { font-weight:bold; }
  .net-box { background:#E3F2FD; border:1px solid #90CAF9; border-radius:4px; padding:12px; display:flex; justify-content:space-between; align-items:center; margin-bottom:14px; }
  .net-box .label { font-size:13px; font-weight:bold; }
  .net-box .value { font-size:15px; font-weight:bold; color:#0D47A1; }
  .footer-row { display:flex; justify-content:space-between; margin-top:40px; border-top:1px solid #E0E0E0; padding-top:10px; font-size:9px; }
</style>
</head><body>
  <h1>${_esc(schoolName.toUpperCase())}</h1>
  ${address.isNotEmpty ? '<div class="muted">${_esc(address)}</div>' : ''}
  ${phone.isNotEmpty ? '<div class="muted">Tel: ${_esc(phone)}</div>' : ''}
  <div class="title-box">PAYSLIP - ${_esc(month)}</div>

  <div class="staff-info">
    <div>
      <div style="font-weight:bold; font-size:12px;">${_esc(staff['staffName'] ?? '')}</div>
      <div class="muted" style="text-align:left;">Staff ID: ${_esc(staff['staffId'] ?? '')}</div>
    </div>
    <div class="muted">${_esc(staff['isPerPeriodPay'] == true ? 'Per-Period Staff' : (staff['staffType'] ?? ''))}</div>
  </div>

  <div class="section" style="border-color:#388E3C;">
    <div class="section-title" style="color:#388E3C;">Earnings</div>
    $earningsRows
  </div>

  <div class="section" style="border-color:#D32F2F;">
    <div class="section-title" style="color:#D32F2F;">Deductions</div>
    $deductionRows
  </div>

  <div class="net-box">
    <span class="label">${arrears > 0 ? 'Total Payable' : 'Net Pay'}</span>
    <span class="value">${_currencyFormat.format(totalPayable)}</span>
  </div>

  <div class="section" style="border-color:#757575;">
    <div class="section-title" style="color:#616161;">Bank Account Details</div>
    $bankRows
  </div>

  <div class="footer-row">
    <span>Prepared by: _______________________</span>
    <span>Signature: _______________________</span>
  </div>
</body></html>
''';
  }

  static String _row(String label, dynamic value) {
    return '<div class="row"><span class="label">${_esc(label)}</span><span class="value">${_esc(value)}</span></div>';
  }

  static String _fmtNum(double v) => v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(1);

  static String _basisSummary(Map<String, dynamic>? basis) {
    if (basis == null) return 'Full Payment (100%)';
    final type = basis['basisType'] as String? ?? 'full';
    switch (type) {
      case 'percentage':
        final pct = (basis['percentageValue'] as num?)?.toDouble() ?? 100;
        return '${_fmtNum(pct)}% of Salary';
      case 'days':
      case 'weeks':
        final total = (basis['totalUnits'] as num?)?.toDouble() ?? 0;
        final worked = (basis['workedUnits'] as num?)?.toDouble() ?? 0;
        final pct = total > 0 ? (worked / total * 100) : 100;
        final unit = type == 'days' ? 'Working Days' : 'Working Weeks';
        return '${_fmtNum(worked)}/${_fmtNum(total)} $unit (${pct.toStringAsFixed(0)}%)';
      case 'full':
      default:
        return 'Full Payment (100%)';
    }
  }

  static String _esc(dynamic value) {
    final s = value?.toString() ?? '';
    return s.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;');
  }
}
