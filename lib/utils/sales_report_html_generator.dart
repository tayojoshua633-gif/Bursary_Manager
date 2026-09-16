import 'package:intl/intl.dart';

/// HTML mirror of SalesReportPDFGenerator, rendered via Android's native
/// WebView print pipeline (see custom_report_pdf_generator.dart).
class SalesReportHtmlGenerator {
  static String build({
    required List<Map<String, dynamic>> sales,
    required String date,
    required Map<String, dynamic> schoolProfile,
    required Map<String, dynamic> summary,
    String? term,
    String? session,
  }) {
    final f = NumberFormat('#,##0.00');
    final schoolName = (schoolProfile['name']?.toString() ?? 'School');
    final address = (schoolProfile['address']?.toString() ?? '');
    final phone = (schoolProfile['phone']?.toString() ?? '');
    final email = (schoolProfile['email']?.toString() ?? '');

    final cashTotal = (summary['cashTotal'] as num).toDouble();
    final posTotal = (summary['posTotal'] as num).toDouble();
    final transferTotal = (summary['transferTotal'] as num).toDouble();
    final totalSale = cashTotal + posTotal + transferTotal;

    final rows = StringBuffer();
    for (var i = 0; i < sales.length; i++) {
      final sale = sales[i];
      rows.writeln('<tr>'
          '<td class="center">${i + 1}</td>'
          '<td class="center">${_esc(DateFormat('HH:mm').format(DateTime.parse(sale['saleDate'])))}</td>'
          '<td>${_esc(sale['buyerName'])}</td>'
          '<td>${_esc(sale['itemName'])}</td>'
          '<td class="center">${_esc(sale['quantity'])}</td>'
          '<td class="center">N${f.format(sale['totalAmount'])}</td>'
          '<td class="center">${_esc(sale['paymentMethod'])}</td>'
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
  h1 { font-size: 20px; margin: 0; text-align: center; color: #303F9F; }
  .muted { color: #616161; text-align:center; font-size: 9px; }
  hr { border: none; border-top: 2px solid #ccc; margin: 12px 0; }
  .title { font-size: 16px; font-weight:bold; text-align:center; margin-bottom: 6px; }
  .info { text-align:center; font-size: 11px; margin-bottom: 4px; }
  .breakdown-box { border:1px solid #BDBDBD; border-radius:4px; padding:14px; margin: 18px 0; }
  .breakdown-title { font-weight:bold; font-size:12px; margin-bottom:8px; }
  .breakdown-row { display:flex; justify-content:space-between; padding:6px 0; border-bottom:1px solid #EEE; font-weight:bold; }
  .breakdown-row.total { border-top: 2px solid #999; border-bottom:none; font-size:14px; padding-top:10px; }
  .section-title { font-weight:bold; font-size:14px; margin: 16px 0 8px; }
  table { width:100%; border-collapse: collapse; font-size: 9px; margin-bottom: 16px; }
  th, td { border:1px solid #BDBDBD; padding:5px; }
  th { background:#E0E0E0; font-weight:bold; }
  tr:nth-child(even) td { background:#FAFAFA; }
  .bank-box { border:1px solid #90CAF9; background:#E3F2FD; border-radius:6px; padding:10px; font-size:9px; margin-top: 12px; }
  .footer-note { text-align:center; font-style: italic; font-size:9px; background:#F5F5F5; border-radius:5px; padding:10px; margin-top: 16px; }
</style>
</head><body>
  <h1>${_esc(schoolName.toUpperCase())}</h1>
  ${address.isNotEmpty ? '<div class="muted">${_esc(address)}</div>' : ''}
  ${(phone.isNotEmpty || email.isNotEmpty) ? '<div class="muted">${[if (phone.isNotEmpty) 'Tel: ${_esc(phone)}', if (email.isNotEmpty) _esc(email)].join(' | ')}</div>' : ''}
  <hr>
  <div class="title">DAILY SALES REPORT</div>
  <div class="info">Date: ${_esc(DateFormat('EEEE, MMMM d, yyyy').format(DateTime.parse(date)))}</div>
  ${(term != null && session != null && term.isNotEmpty && session.isNotEmpty) ? '<div class="info">Term: ${_esc(term)} | Session: ${_esc(session)}</div>' : ''}
  <div class="muted">Generated: ${_esc(DateFormat('MMMM d, yyyy - h:mm a').format(DateTime.now()))}</div>

  <div class="breakdown-box">
    <div class="breakdown-title">PAYMENT METHOD BREAKDOWN</div>
    <div class="breakdown-row"><span>Cash</span><span style="color:#2E7D32;">N${f.format(cashTotal)}</span></div>
    <div class="breakdown-row"><span>POS</span><span style="color:#1565C0;">N${f.format(posTotal)}</span></div>
    <div class="breakdown-row"><span>Transfer</span><span style="color:#6A1B9A;">N${f.format(transferTotal)}</span></div>
    <div class="breakdown-row total"><span>Total Sale</span><span style="color:#E64A19;">N${f.format(totalSale)}</span></div>
  </div>

  ${sales.isEmpty ? '' : '''
  <div class="section-title">SALES DETAILS</div>
  <table>
    <thead><tr>
      <th class="center">S/N</th><th class="center">Time</th><th>Buyer</th><th>Item</th>
      <th class="center">Qty</th><th class="center">Amount</th><th class="center">Method</th>
    </tr></thead>
    <tbody>$rows</tbody>
  </table>
  '''}

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
