import 'package:intl/intl.dart';

/// HTML mirror of VirtualLedgerPDFGenerator, rendered via Android's native
/// WebView print pipeline (see custom_report_pdf_generator.dart).
class VirtualLedgerHtmlGenerator {
  static String build({
    required List<Map<String, dynamic>> ledger,
    required int maxInstalments,
    required String className,
    required String term,
    required String session,
    required Map<String, dynamic> schoolProfile,
  }) {
    final f = NumberFormat('#,##0.00');
    final dateFormat = DateFormat('dd/MM/yy');

    double totalBills = 0, totalPaid = 0;
    int balancedCount = 0;
    for (final row in ledger) {
      totalBills += (row['totalBill'] as num).toDouble();
      totalPaid += (row['totalPaid'] as num).toDouble();
      if (row['remark'] == 'Balanced') balancedCount++;
    }

    final schoolName = (schoolProfile['name'] ?? 'School Name').toString();
    final address = (schoolProfile['address'] ?? '').toString();
    final phone = (schoolProfile['phone'] ?? '').toString();
    final email = (schoolProfile['email'] ?? '').toString();

    final instalmentHeaders = StringBuffer();
    for (int i = 1; i <= maxInstalments; i++) {
      instalmentHeaders.write('<th class="center">P$i</th>');
    }

    final rows = StringBuffer();
    for (var i = 0; i < ledger.length; i++) {
      final row = ledger[i];
      final totalBill = (row['totalBill'] as num).toDouble();
      final totalPaid0 = (row['totalPaid'] as num).toDouble();
      final outstanding = (row['outstanding'] as num).toDouble();
      final instalments = row['instalments'] as List<Map<String, dynamic>>;
      final remark = row['remark'] as String;
      final isBalanced = remark == 'Balanced';

      final instalmentCells = StringBuffer();
      for (int c = 0; c < maxInstalments; c++) {
        if (c < instalments.length) {
          final payment = instalments[c];
          final amount = (payment['amount'] as num).toDouble();
          final dateStr = payment['paymentDate'] as String?;
          String formattedDate = dateStr ?? '';
          if (dateStr != null) {
            final parsed = DateTime.tryParse(dateStr);
            if (parsed != null) formattedDate = dateFormat.format(parsed);
          }
          instalmentCells.write('<td class="center instalment"><div class="idate">${_esc(formattedDate)}</div><div>${f.format(amount)}</div></td>');
        } else {
          instalmentCells.write('<td class="center">-</td>');
        }
      }

      rows.writeln('<tr>'
          '<td class="center">${i + 1}</td>'
          '<td>${_esc('${row['surname']} ${row['firstName']}')}</td>'
          '<td>${_esc('${row['className'] ?? ''}${row['armName'] != null && row['armName'] != '' ? ' - ${row['armName']}' : ''}')}</td>'
          '<td class="center">${f.format(totalBill)}</td>'
          '$instalmentCells'
          '<td class="center" style="color:#2E7D32;">${f.format(totalPaid0)}</td>'
          '<td class="center" style="color:${isBalanced ? '#616161' : '#C62828'};">${f.format(outstanding > 0 ? outstanding : 0)}</td>'
          '<td class="center" style="color:${isBalanced ? '#2E7D32' : '#C62828'}; font-weight:bold;">${_esc(remark)}</td>'
          '</tr>');
    }

    return '''
<!DOCTYPE html><html><head><meta charset="utf-8">
<style>
  @page { size: A4 landscape; margin: 18px; }
  body { font-family: Helvetica, Arial, sans-serif; color: #1a1a1a; font-size: 10px; margin:0; padding:18px; }
  .center { text-align: center; }
  h1 { font-size: 15px; margin: 0; text-align: center; }
  .muted { color: #616161; text-align:center; font-size: 8px; }
  hr { border: none; border-top: 2px solid #ccc; margin: 10px 0; }
  .title { font-size: 13px; font-weight:bold; margin-bottom: 6px; }
  .info-row { display:flex; justify-content:space-between; font-size: 9px; margin-bottom: 10px; }
  .summary-box { border:1px solid #9FA8DA; background:#E8EAF6; border-radius:4px; padding:10px; display:flex; justify-content:space-around; margin-bottom: 14px; }
  .summary-item { text-align:center; }
  .summary-item .label { font-size:8px; color:#616161; }
  .summary-item .value { font-size:10px; font-weight:bold; }
  table { width:100%; border-collapse: collapse; font-size: 7.5px; margin-bottom: 12px; }
  th, td { border:0.5px solid #BDBDBD; padding:3px; }
  th { background:#E0E0E0; font-weight:bold; }
  tr:nth-child(even) td { background:#FAFAFA; }
  .instalment .idate { font-size:6px; color:#616161; }
  .footer-note { font-style: italic; font-size:8px; color:#616161; border-top:1px solid #E0E0E0; padding-top:8px; }
</style>
</head><body>
  <h1>${_esc(schoolName.toUpperCase())}</h1>
  ${address.isNotEmpty ? '<div class="muted">${_esc(address)}</div>' : ''}
  ${(phone.isNotEmpty || email.isNotEmpty) ? '<div class="muted">${[if (phone.isNotEmpty) 'Tel: ${_esc(phone)}', if (email.isNotEmpty) _esc(email)].join(' | ')}</div>' : ''}
  <hr>
  <div class="title">VIRTUAL LEDGER</div>
  <div class="info-row">
    <span>Class: ${_esc(className)}</span><span>Term: ${_esc(term)}</span><span>Session: ${_esc(session)}</span>
    <span class="muted">Generated: ${_esc(DateFormat('MMM d, yyyy - h:mm a').format(DateTime.now()))}</span>
  </div>

  <div class="summary-box">
    <div class="summary-item"><div class="label">Total Bills</div><div class="value" style="color:#1565C0;">N${f.format(totalBills)}</div></div>
    <div class="summary-item"><div class="label">Total Paid</div><div class="value" style="color:#2E7D32;">N${f.format(totalPaid)}</div></div>
    <div class="summary-item"><div class="label">Balanced</div><div class="value" style="color:#00695C;">$balancedCount / ${ledger.length}</div></div>
  </div>

  <table>
    <thead><tr>
      <th class="center">S/N</th><th>Student Name</th><th>Class</th><th class="center">Total Bill</th>
      $instalmentHeaders
      <th class="center">Total Paid</th><th class="center">Outstanding</th><th class="center">Remark</th>
    </tr></thead>
    <tbody>$rows</tbody>
  </table>

  <div class="footer-note">Note: "Remark" indicates whether the student's account is fully balanced (paid in full) or not for the period shown.</div>
</body></html>
''';
  }

  static String _esc(dynamic value) {
    final s = value?.toString() ?? '';
    return s.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;');
  }
}
