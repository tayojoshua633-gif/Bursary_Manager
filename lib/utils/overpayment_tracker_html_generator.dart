import 'package:intl/intl.dart';

/// HTML mirror of OverpaymentTrackerPDFGenerator, rendered via Android's
/// native WebView print pipeline (see custom_report_pdf_generator.dart).
class OverpaymentTrackerHtmlGenerator {
  static String build({
    required String term,
    required String session,
    required Map<String, dynamic> schoolProfile,
    required List<Map<String, dynamic>> overpayments,
  }) {
    final f = NumberFormat('#,##0.00');

    double totalBills = 0, totalPaid = 0, totalOverpaid = 0;
    for (final item in overpayments) {
      totalBills += (item['billAmount'] as num?)?.toDouble() ?? 0.0;
      totalPaid += (item['paidAmount'] as num?)?.toDouble() ?? 0.0;
      totalOverpaid += (item['overpaid'] as num?)?.toDouble() ?? 0.0;
    }

    final schoolName = (schoolProfile['name'] ?? 'School Name').toString();
    final address = (schoolProfile['address'] ?? '').toString();
    final phone = (schoolProfile['phone'] ?? '').toString();
    final email = (schoolProfile['email'] ?? '').toString();

    final rows = StringBuffer();
    for (var i = 0; i < overpayments.length; i++) {
      final item = overpayments[i];
      final surname = item['surname'] ?? '';
      final firstName = item['firstName'] ?? '';
      final admissionNo = item['admissionNo'] ?? '';
      final className = item['className'] ?? 'N/A';
      final armName = item['armName'] ?? 'N/A';
      final billAmount = (item['billAmount'] as num?)?.toDouble() ?? 0.0;
      final paidAmount = (item['paidAmount'] as num?)?.toDouble() ?? 0.0;
      final overpaid = (item['overpaid'] as num?)?.toDouble() ?? 0.0;

      rows.writeln('<tr>'
          '<td class="center">${i + 1}</td>'
          '<td>${_esc(admissionNo)}</td>'
          '<td>${_esc('$surname $firstName')}</td>'
          '<td>${_esc('$className - $armName')}</td>'
          '<td class="right">${f.format(billAmount)}</td>'
          '<td class="right">${f.format(paidAmount)}</td>'
          '<td class="right" style="color:#7B1FA2; font-weight:bold;">${f.format(overpaid)}</td>'
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
  .right { text-align: right; }
  h1 { font-size: 18px; margin: 0; text-align:center; }
  .muted { color: #616161; text-align:center; font-size: 10px; }
  .title-box { border:2px solid #7B1FA2; color:#7B1FA2; border-radius:4px; padding:6px 16px; font-size:16px; font-weight:bold; text-align:center; margin: 10px auto; width: fit-content; }
  .info { text-align:center; font-weight:bold; font-size:12px; }
  .summary-box { border:1px solid #7B1FA2; background:#F3E5F5; border-radius:4px; padding:12px; margin: 16px 0; }
  .summary-title { font-size:14px; font-weight:bold; margin-bottom:8px; }
  .row { display:flex; justify-content:space-between; padding:2px 0; font-size:11px; }
  .row.total { border-top:1px solid #7B1FA2; margin-top:6px; padding-top:6px; font-weight:bold; font-size:12px; color:#7B1FA2; }
  .section-title { font-size:12px; font-weight:bold; margin: 12px 0 8px; }
  table { width:100%; border-collapse: collapse; font-size: 9px; margin-bottom: 16px; }
  th, td { border:1px solid #E1BEE7; padding:5px; }
  th { background:#7B1FA2; color:white; font-weight:bold; }
  tr:nth-child(even) td { background:#FAFAFA; }
  .bank-box { border:1px solid #90CAF9; background:#E3F2FD; border-radius:6px; padding:10px; font-size:9px; margin-bottom:12px; }
  .footer-note { font-size:9px; color:#616161; border-top:1px solid #E0E0E0; padding-top:8px; }
</style>
</head><body>
  <h1>${_esc(schoolName.toUpperCase())}</h1>
  ${address.isNotEmpty ? '<div class="muted">${_esc(address)}</div>' : ''}
  ${(phone.isNotEmpty || email.isNotEmpty) ? '<div class="muted">${[if (phone.isNotEmpty) 'Tel: ${_esc(phone)}', if (email.isNotEmpty) _esc(email)].join(' | ')}</div>' : ''}
  <div class="title-box">OVERPAYMENT TRACKER</div>
  <div class="info">${_esc(term)} - ${_esc(session)}</div>
  <div class="muted">Generated: ${_esc(DateFormat('dd MMM yyyy, hh:mm a').format(DateTime.now()))}</div>

  <div class="summary-box">
    <div class="summary-title">SUMMARY</div>
    <div class="row"><span>Total Students with Overpayments:</span><span>${overpayments.length}</span></div>
    <div class="row"><span>Total Bills:</span><span>N ${f.format(totalBills)}</span></div>
    <div class="row"><span>Total Paid:</span><span>N ${f.format(totalPaid)}</span></div>
    <div class="row total"><span>Total Overpaid:</span><span>N ${f.format(totalOverpaid)}</span></div>
  </div>

  <div class="section-title">STUDENT DETAILS</div>
  <table>
    <thead><tr>
      <th class="center">S/N</th><th>Adm. No</th><th>Student Name</th><th>Class/Arm</th>
      <th class="right">Bill (N)</th><th class="right">Paid (N)</th><th class="right">Overpaid (N)</th>
    </tr></thead>
    <tbody>$rows</tbody>
  </table>

  ${accounts.isEmpty ? '' : '<div class="bank-box"><strong>Bank Account Details:</strong>${accounts.map((a) => '<div>${_esc(a)}</div>').join()}</div>'}

  <div class="footer-note">
    Note: This report shows students who have paid more than their total bill for the current term/session.<br>
    Overpayments may be applied to future terms or refunded as per school policy.
  </div>
</body></html>
''';
  }

  static String _esc(dynamic value) {
    final s = value?.toString() ?? '';
    return s.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;');
  }
}
