import 'package:intl/intl.dart';

/// HTML mirror of DebtorsPDFGenerator, rendered via Android's native
/// WebView print pipeline (see custom_report_pdf_generator.dart).
class DebtorsHtmlGenerator {
  static String build({
    required List<Map<String, dynamic>> debtors,
    required String className,
    required String term,
    required String session,
    required Map<String, dynamic> schoolProfile,
    required String filterType,
    required double minPercentage,
  }) {
    final f = NumberFormat('#,##0.00');
    double totalBills = 0, totalPaid = 0, totalOutstanding = 0;
    for (final d in debtors) {
      totalBills += (d['totalBill'] as num).toDouble();
      totalPaid += (d['totalPaid'] as num).toDouble();
      totalOutstanding += (d['outstanding'] as num).toDouble();
    }

    final schoolName = (schoolProfile['name'] ?? 'School Name').toString();
    final address = (schoolProfile['address'] ?? '').toString();
    final phone = (schoolProfile['phone'] ?? '').toString();
    final email = (schoolProfile['email'] ?? '').toString();

    final filterDesc = filterType == 'all'
        ? 'All students with outstanding balances'
        : 'Students who paid less than ${minPercentage.toStringAsFixed(0)}% of their bills';

    final rows = StringBuffer();
    for (var i = 0; i < debtors.length; i++) {
      final d = debtors[i];
      final outstanding = (d['outstanding'] as num).toDouble();
      final percentPaid = (d['percentPaid'] as num).toDouble();
      rows.writeln('<tr>'
          '<td class="center">${i + 1}</td>'
          '<td class="center">${_esc(d['admissionNo'] ?? '')}</td>'
          '<td>${_esc('${d['surname']} ${d['firstName']}')}</td>'
          '<td class="center">N${f.format((d['totalBill'] as num).toDouble())}</td>'
          '<td class="center">N${f.format((d['totalPaid'] as num).toDouble())}</td>'
          '<td class="center" style="color:#C62828;">N${f.format(outstanding)}</td>'
          '<td class="center">${percentPaid.toStringAsFixed(1)}%</td>'
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
  h1 { font-size: 20px; margin: 0; text-align: center; }
  .muted { color: #616161; text-align:center; font-size: 9px; }
  hr { border: none; border-top: 2px solid #ccc; margin: 12px 0; }
  .title { font-size: 16px; font-weight:bold; text-align:center; margin-bottom: 8px; }
  .period-row { display:flex; justify-content:space-between; font-size: 11px; margin-bottom:4px; }
  .filter-box { border:1px solid #90CAF9; background:#E3F2FD; border-radius:4px; padding:10px; display:flex; justify-content:space-between; align-items:center; margin: 16px 0; }
  .filter-box .badge { background:#FFCDD2; color:#C62828; border-radius:4px; padding:4px 8px; font-weight:bold; font-size:10px; }
  .summary-box { border:1px solid #EF9A9A; background:#FFEBEE; border-radius:4px; padding:12px; margin-bottom:16px; }
  .summary-title { text-align:center; font-weight:bold; font-size:12px; margin-bottom:10px; }
  .summary-row { display:flex; justify-content:space-around; }
  .summary-item { text-align:center; }
  .summary-item .label { font-size:9px; color:#616161; }
  .summary-item .value { font-size:11px; font-weight:bold; }
  table { width:100%; border-collapse: collapse; font-size: 9px; margin-bottom: 16px; }
  th, td { border:1px solid #BDBDBD; padding:6px; }
  th { background:#E0E0E0; font-weight:bold; }
  tr:nth-child(even) td { background:#FAFAFA; }
  .bank-box { border:1px solid #90CAF9; background:#E3F2FD; border-radius:6px; padding:10px; font-size:9px; }
  .footer-note { font-style: italic; color:#616161; font-size:9px; margin-top: 16px; }
</style>
</head><body>
  <h1>${_esc(schoolName.toUpperCase())}</h1>
  ${address.isNotEmpty ? '<div class="muted">${_esc(address)}</div>' : ''}
  ${(phone.isNotEmpty || email.isNotEmpty) ? '<div class="muted">${[if (phone.isNotEmpty) 'Tel: ${_esc(phone)}', if (email.isNotEmpty) _esc(email)].join(' | ')}</div>' : ''}
  <hr>
  <div class="title">DEBTORS LIST</div>
  <div class="period-row"><span>Class: ${_esc(className)}</span><span>Term: ${_esc(term)}</span><span>Session: ${_esc(session)}</span></div>
  <div class="muted" style="text-align:left;">Generated: ${_esc(DateFormat('MMM d, yyyy - h:mm a').format(DateTime.now()))}</div>

  <div class="filter-box">
    <div><strong>Filter Applied:</strong><br>${_esc(filterDesc)}</div>
    <div class="badge">${debtors.length} Debtor${debtors.length != 1 ? 's' : ''}</div>
  </div>

  <div class="summary-box">
    <div class="summary-title">FINANCIAL SUMMARY</div>
    <div class="summary-row">
      <div class="summary-item"><div class="label">Total Bills</div><div class="value" style="color:#1565C0;">N${f.format(totalBills)}</div></div>
      <div class="summary-item"><div class="label">Total Paid</div><div class="value" style="color:#2E7D32;">N${f.format(totalPaid)}</div></div>
      <div class="summary-item"><div class="label">Outstanding</div><div class="value" style="color:#C62828;">N${f.format(totalOutstanding)}</div></div>
    </div>
  </div>

  <table>
    <thead><tr>
      <th class="center">S/N</th><th class="center">Adm. No</th><th>Student Name</th>
      <th class="center">Total Bill</th><th class="center">Paid</th>
      <th class="center">Outstanding</th><th class="center">% Paid</th>
    </tr></thead>
    <tbody>$rows</tbody>
  </table>

  ${accounts.isEmpty ? '' : '<div class="bank-box"><strong>Bank Account Details:</strong>${accounts.map((a) => '<div>${_esc(a)}</div>').join()}</div>'}

  <div class="footer-note">Note: This report shows students with outstanding fee balances. Please follow up with parents/guardians for payment.</div>
</body></html>
''';
  }

  static String _esc(dynamic value) {
    final s = value?.toString() ?? '';
    return s.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;');
  }
}
