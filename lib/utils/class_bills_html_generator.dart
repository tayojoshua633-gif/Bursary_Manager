import 'package:intl/intl.dart';

/// HTML mirror of ClassBillsPDFGenerator, rendered via Android's native
/// WebView print pipeline (see custom_report_pdf_generator.dart).
class ClassBillsHtmlGenerator {
  static String build({
    required List<Map<String, dynamic>> studentBills,
    required String term,
    required String session,
    required Map<String, dynamic> schoolProfile,
    String? filterClassName,
  }) {
    final f = NumberFormat('#,##0.00');

    double totalBills = 0, totalPaid = 0, totalOutstanding = 0;
    for (final bill in studentBills) {
      final billAmount = (bill['totalBill'] as num).toDouble();
      final paidAmount = (bill['totalPaid'] as num).toDouble();
      totalBills += billAmount;
      totalPaid += paidAmount;
      totalOutstanding += (billAmount - paidAmount);
    }

    final schoolName = (schoolProfile['name'] ?? 'School Name').toString();
    final address = (schoolProfile['address'] ?? '').toString();
    final phone = (schoolProfile['phone'] ?? '').toString();
    final email = (schoolProfile['email'] ?? '').toString();

    final rows = StringBuffer();
    for (var i = 0; i < studentBills.length; i++) {
      final bill = studentBills[i];
      final surname = bill['surname'] as String;
      final firstName = bill['firstName'] as String;
      final otherName = bill['otherName'] as String?;
      final fullName = '$surname $firstName ${otherName ?? ''}'.trim();

      final className = bill['className'] as String;
      final armName = bill['armName'] as String?;
      final classArm = armName != null ? '$className - $armName' : className;

      final feeItems = (bill['billItems'] as List?) ?? const [];
      final previousBalance = (bill['freshPreviousBalance'] as num?)?.toDouble() ?? 0;
      final feeLines = StringBuffer();
      for (final item in feeItems) {
        feeLines.write('<div class="fee-line"><span>${_esc(item['feeName'] ?? 'Fee Item')}</span>'
            '<span>N${f.format((item['amount'] as num?)?.toDouble() ?? 0)}</span></div>');
      }
      if (previousBalance > 0) {
        feeLines.write('<div class="fee-line" style="color:#F57C00;"><span>Previous Balance (B/F)</span>'
            '<span>N${f.format(previousBalance)}</span></div>');
      }
      final feeCell = feeLines.isEmpty ? '<td class="center">-</td>' : '<td>$feeLines</td>';

      final totalBill = (bill['totalBill'] as num).toDouble();
      final totalPaid0 = (bill['totalPaid'] as num).toDouble();
      final outstanding = totalBill - totalPaid0;

      String status;
      String statusColor;
      if (outstanding <= 0) {
        status = 'Paid';
        statusColor = '#388E3C';
      } else if (totalPaid0 > 0) {
        status = 'Partial';
        statusColor = '#F57C00';
      } else {
        status = 'Unpaid';
        statusColor = '#D32F2F';
      }

      rows.writeln('<tr>'
          '<td class="center">${i + 1}</td>'
          '<td>${_esc(fullName)}</td>'
          '<td>${_esc(classArm)}</td>'
          '$feeCell'
          '<td class="right">N${f.format(totalBill)}</td>'
          '<td class="right">N${f.format(totalPaid0)}</td>'
          '<td class="right">N${f.format(outstanding)}</td>'
          '<td class="center" style="color:$statusColor; font-weight:bold;">$status</td>'
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
  @page { size: A4 landscape; margin: 22px; }
  body { font-family: Helvetica, Arial, sans-serif; color: #1a1a1a; font-size: 11px; margin:0; padding:22px; }
  .center { text-align: center; }
  .right { text-align: right; }
  h1 { font-size: 20px; margin: 0; text-align: center; }
  .muted { color: #616161; text-align:center; font-size: 10px; }
  hr { border: none; border-top: 2px solid #ccc; margin: 14px 0; }
  .title { font-size: 16px; font-weight:bold; text-align:center; margin-bottom: 6px; }
  .info { text-align:center; font-size: 12px; margin-bottom:4px; }
  .summary-box { border:1px solid #BDBDBD; border-radius:4px; padding:12px; display:flex; justify-content:space-around; margin: 16px 0; }
  .summary-item { text-align:center; }
  .summary-item .label { font-size:9px; color:#616161; }
  .summary-item .value { font-size:12px; font-weight:bold; }
  table { width:100%; border-collapse: collapse; font-size: 9px; margin-bottom: 16px; }
  th, td { border:1px solid #BDBDBD; padding:6px; }
  th { background:#E0E0E0; font-weight:bold; }
  tr { page-break-inside: avoid; }
  .fee-line { display:flex; justify-content:space-between; gap:8px; font-size:8px; padding-bottom:1px; }
  .bank-box { border:1px solid #90CAF9; background:#E3F2FD; border-radius:6px; padding:10px; font-size:9px; margin-bottom: 12px; }
  .legend { display:flex; gap:16px; align-items:center; font-size:8px; border-top:1px solid #E0E0E0; padding-top:10px; }
  .legend .swatch { width:8px; height:8px; display:inline-block; margin-right:4px; }
</style>
</head><body>
  <h1>${_esc(schoolName.toUpperCase())}</h1>
  ${address.isNotEmpty ? '<div class="muted">${_esc(address)}</div>' : ''}
  ${(phone.isNotEmpty || email.isNotEmpty) ? '<div class="muted">${[if (phone.isNotEmpty) 'Tel: ${_esc(phone)}', if (email.isNotEmpty) _esc(email)].join(' | ')}</div>' : ''}
  <hr>
  <div class="title">CLASS BILLS REPORT</div>
  <div class="info">${_esc(term)}, ${_esc(session)}</div>
  ${filterClassName != null ? '<div class="info" style="font-weight:bold;">Class: ${_esc(filterClassName)}</div>' : ''}

  <div class="summary-box">
    <div class="summary-item"><div class="label">Total Students</div><div class="value" style="color:#1976D2;">${studentBills.length}</div></div>
    <div class="summary-item"><div class="label">Total Bills</div><div class="value" style="color:#303F9F;">N${f.format(totalBills)}</div></div>
    <div class="summary-item"><div class="label">Total Paid</div><div class="value" style="color:#388E3C;">N${f.format(totalPaid)}</div></div>
    <div class="summary-item"><div class="label">Outstanding</div><div class="value" style="color:${totalOutstanding > 0 ? '#D32F2F' : '#388E3C'};">N${f.format(totalOutstanding)}</div></div>
  </div>

  <table>
    <thead><tr>
      <th class="center">S/N</th><th>Student Name</th><th>Class/Arm</th><th>Fee Items</th>
      <th class="right">Total Bill</th><th class="right">Paid</th>
      <th class="right">Outstanding</th><th class="center">Status</th>
    </tr></thead>
    <tbody>$rows</tbody>
  </table>

  ${accounts.isEmpty ? '' : '<div class="bank-box"><strong>Bank Account Details:</strong>${accounts.map((a) => '<div>${_esc(a)}</div>').join()}</div>'}

  <div class="legend">
    <strong>Legend:</strong>
    <span><span class="swatch" style="background:#388E3C;"></span>Paid - No outstanding balance</span>
    <span><span class="swatch" style="background:#F57C00;"></span>Partial - Some payment made</span>
    <span><span class="swatch" style="background:#D32F2F;"></span>Unpaid - No payment yet</span>
  </div>
  <div class="muted" style="text-align:right; margin-top:8px;">Generated: ${_esc(DateFormat('MMM d, yyyy h:mm a').format(DateTime.now()))}</div>
</body></html>
''';
  }

  static String _esc(dynamic value) {
    final s = value?.toString() ?? '';
    return s.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;');
  }
}
