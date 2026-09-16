import 'package:intl/intl.dart';

/// HTML mirror of StockRecordPDFGenerator, rendered via Android's native
/// WebView print pipeline (see custom_report_pdf_generator.dart).
class StockRecordHtmlGenerator {
  static String build({
    required List<Map<String, dynamic>> stockRecords,
    required Map<String, dynamic> schoolProfile,
  }) {
    final f = NumberFormat('#,##0.00');

    double totalSuppliedValue = 0, totalSoldValue = 0, totalRemainingValue = 0;
    int totalQtySupplied = 0, totalQtySold = 0, totalQtyRemaining = 0;
    for (final record in stockRecords) {
      totalQtySupplied += record['qtySupplied'] as int;
      totalQtySold += record['qtySold'] as int;
      totalQtyRemaining += record['qtyRemaining'] as int;
      totalSuppliedValue += (record['totalSellingValue'] as num).toDouble();
      totalSoldValue += (record['soldValue'] as num).toDouble();
      totalRemainingValue += (record['remainingValue'] as num).toDouble();
    }

    final schoolName = (schoolProfile['name']?.toString() ?? 'School');
    final address = (schoolProfile['address']?.toString() ?? '');
    final phone = (schoolProfile['phone']?.toString() ?? '');
    final email = (schoolProfile['email']?.toString() ?? '');

    final rows = StringBuffer();
    for (var i = 0; i < stockRecords.length; i++) {
      final r = stockRecords[i];
      final qtyRemaining = r['qtyRemaining'] as int;
      rows.writeln('<tr>'
          '<td>${_esc(r['itemName'])}</td>'
          '<td>${_esc(r['supplierName'])}</td>'
          '<td class="center">${r['qtySupplied']}</td>'
          '<td class="center">${r['qtySold']}</td>'
          '<td class="center" style="color:${qtyRemaining > 0 ? '#2E7D32' : '#C62828'}; font-weight:bold;">$qtyRemaining</td>'
          '<td class="center">N${f.format(r['costPrice'])}</td>'
          '<td class="center">N${f.format(r['sellingPrice'])}</td>'
          '<td class="center" style="color:#5D4037; font-weight:bold;">N${f.format(r['remainingValue'])}</td>'
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
  h1 { font-size: 20px; margin: 0; text-align: center; color: #5D4037; }
  .muted { color: #616161; text-align:center; font-size: 9px; }
  hr { border: none; border-top: 2px solid #ccc; margin: 12px 0; }
  .title { font-size: 16px; font-weight:bold; text-align:center; margin-bottom: 6px; }
  .summary-box { border:1px solid #A1887F; background:#EFEBE9; border-radius:5px; padding:14px; display:flex; justify-content:space-around; margin: 16px 0; }
  .summary-item { text-align:center; }
  .summary-item .label { font-size:10px; font-weight:bold; color:#424242; }
  table { width:100%; border-collapse: collapse; font-size: 9px; margin-bottom: 16px; }
  th, td { border:1px solid #BDBDBD; padding:5px; }
  th { background:#D7CCC8; font-weight:bold; }
  tr:nth-child(even) td { background:#FAFAFA; }
  .bank-box { border:1px solid #90CAF9; background:#E3F2FD; border-radius:6px; padding:10px; font-size:9px; margin-top: 12px; }
  .footer-note { text-align:center; font-style: italic; font-size:9px; background:#F5F5F5; border-radius:5px; padding:10px; margin-top: 16px; }
</style>
</head><body>
  <h1>${_esc(schoolName.toUpperCase())}</h1>
  ${address.isNotEmpty ? '<div class="muted">${_esc(address)}</div>' : ''}
  ${(phone.isNotEmpty || email.isNotEmpty) ? '<div class="muted">${[if (phone.isNotEmpty) 'Tel: ${_esc(phone)}', if (email.isNotEmpty) _esc(email)].join(' | ')}</div>' : ''}
  <hr>
  <div class="title">STOCK RECORD REPORT</div>
  <div class="muted">Generated: ${_esc(DateFormat('MMMM d, yyyy - h:mm a').format(DateTime.now()))}</div>

  <div class="summary-box">
    <div class="summary-item"><div class="label">Total Supplied</div><div style="color:#1565C0; font-weight:bold;">$totalQtySupplied units</div><div style="color:#1565C0; font-weight:bold;">N${f.format(totalSuppliedValue)}</div></div>
    <div class="summary-item"><div class="label">Total Sold</div><div style="color:#2E7D32; font-weight:bold;">$totalQtySold units</div><div style="color:#2E7D32; font-weight:bold;">N${f.format(totalSoldValue)}</div></div>
    <div class="summary-item"><div class="label">Remaining Stock</div><div style="color:#E65100; font-weight:bold;">$totalQtyRemaining units</div><div style="color:#E65100; font-weight:bold;">N${f.format(totalRemainingValue)}</div></div>
  </div>

  <table>
    <thead><tr>
      <th>Item Name</th><th>Supplier</th><th class="center">Qty Supplied</th>
      <th class="center">Qty Sold</th><th class="center">Qty Remain</th>
      <th class="center">Cost Price</th><th class="center">Selling Price</th><th class="center">Stock Value</th>
    </tr></thead>
    <tbody>$rows</tbody>
  </table>

  ${accounts.isEmpty ? '' : '<div class="bank-box"><strong>Bank Account Details:</strong>${accounts.map((a) => '<div>${_esc(a)}</div>').join()}</div>'}

  <div class="footer-note">This is a computer-generated document. No signature required.</div>
</body></html>
''';
  }

  static String _esc(dynamic value) {
    final s = value?.toString() ?? '';
    return s.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;');
  }
}
