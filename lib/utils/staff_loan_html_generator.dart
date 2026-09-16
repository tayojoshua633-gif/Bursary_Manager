import 'package:intl/intl.dart';

/// HTML mirror of StaffLoanPDFGenerator, rendered via Android's native
/// WebView print pipeline (see custom_report_pdf_generator.dart).
class StaffLoanHtmlGenerator {
  static final _currencyFormat = NumberFormat.currency(symbol: 'N', decimalDigits: 2);

  static String build({
    required List<Map<String, dynamic>> loans,
    required Map<String, dynamic> schoolProfile,
    required String filterStatus,
    required double totalLoans,
    required double totalBalance,
  }) {
    final schoolName = (schoolProfile['name'] ?? 'School Name').toString();
    final address = (schoolProfile['address'] ?? '').toString();
    final phone = (schoolProfile['phone'] ?? '').toString();

    final rows = StringBuffer();
    for (var i = 0; i < loans.length; i++) {
      final loan = loans[i];
      final isActive = loan['status'] == 'Active';
      final amount = (loan['amount'] as num).toDouble();
      final deduction = (loan['deductionPerMonth'] as num).toDouble();
      final monthsRemaining = loan['monthsRemaining'] as int;
      final balance = deduction * monthsRemaining;

      String collectionDate = '-';
      if (loan['collectionDate'] != null && loan['collectionDate'].toString().isNotEmpty) {
        try {
          final date = DateTime.parse(loan['collectionDate']);
          collectionDate = DateFormat('dd/MM/yyyy').format(date);
        } catch (_) {
          collectionDate = loan['collectionDate'].toString();
        }
      }

      rows.writeln('<tr>'
          '<td class="center">${i + 1}</td>'
          '<td>${_esc(loan['staffName'] ?? '')}</td>'
          '<td>${_esc(loan['reason'] ?? '')}</td>'
          '<td class="center">${_currencyFormat.format(amount)}</td>'
          '<td class="center">${_currencyFormat.format(deduction)}</td>'
          '<td class="center">$monthsRemaining</td>'
          '<td class="center" style="color:#D32F2F;">${_currencyFormat.format(balance)}</td>'
          '<td class="center" style="color:${isActive ? '#EF6C00' : '#2E7D32'};">${_esc(loan['status'] ?? '')}</td>'
          '<td class="center">${_esc(collectionDate)}</td>'
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
  body { font-family: Helvetica, Arial, sans-serif; color: #1a1a1a; font-size: 10px; margin:0; padding:18px; }
  .center { text-align: center; }
  h1 { font-size: 16px; margin: 0; text-align:center; }
  .muted { color: #616161; text-align:center; font-size: 8px; }
  .title-box { background:#FFF3E0; color:#E65100; border-radius:4px; padding:6px 16px; font-size:13px; font-weight:bold; text-align:center; margin: 10px 0 14px; }
  .summary { border:1px solid #E0E0E0; border-radius:4px; padding:10px; display:flex; justify-content:space-around; margin-bottom:14px; }
  .summary .stat { text-align:center; }
  .summary .label { font-size:8px; color:#616161; }
  .summary .value { font-size:12px; font-weight:bold; }
  table { width:100%; border-collapse: collapse; font-size: 8px; }
  th, td { border:1px solid #FFE0B2; padding:5px; }
  th { background:#FFE0B2; font-weight:bold; }
  tr:nth-child(even) td { background:#FAFAFA; }
  .bank-box { border:1px solid #90CAF9; background:#E3F2FD; border-radius:6px; padding:10px; font-size:9px; margin-top: 12px; }
  .footer-row { display:flex; justify-content:space-between; margin-top:20px; font-size:9px; }
</style>
</head><body>
  <h1>${_esc(schoolName.toUpperCase())}</h1>
  ${address.isNotEmpty ? '<div class="muted">${_esc(address)}</div>' : ''}
  ${phone.isNotEmpty ? '<div class="muted">Tel: ${_esc(phone)}</div>' : ''}
  <div class="title-box">STAFF LOANS REPORT - ${_esc(filterStatus)}</div>

  <div class="summary">
    <div class="stat"><div class="label">Total Records</div><div class="value">${loans.length}</div></div>
    <div class="stat"><div class="label">Total Loan Amount</div><div class="value" style="color:#EF6C00;">${_currencyFormat.format(totalLoans)}</div></div>
    <div class="stat"><div class="label">Outstanding Balance</div><div class="value" style="color:#D32F2F;">${_currencyFormat.format(totalBalance)}</div></div>
  </div>

  <table>
    <thead><tr>
      <th class="center">S/N</th><th>Staff Name</th><th>Reason</th><th class="center">Loan Amount</th>
      <th class="center">Monthly Ded.</th><th class="center">Months Left</th><th class="center">Balance</th>
      <th class="center">Status</th><th class="center">Collection Date</th>
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
