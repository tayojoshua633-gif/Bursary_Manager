import 'package:intl/intl.dart';
import 'family_payment_receipt_pdf_generator.dart';

/// HTML mirror of FamilyPaymentReceiptPdfGenerator, rendered via Android's
/// native WebView print pipeline (see custom_report_pdf_generator.dart).
class FamilyPaymentReceiptHtmlGenerator {
  static String build({
    required String schoolName,
    required String schoolAddress,
    required String parentName,
    required String parentPhone,
    required String term,
    required String session,
    required DateTime date,
    required String method,
    required String note,
    required List<FamilyReceiptPaymentItem> items,
    required double totalAmount,
    double? familyTotalBilled,
    double? familyTotalPaid,
    double? familyOutstanding,
  }) {
    final fmt = NumberFormat('#,##0.00');

    final rows = items.map((it) => '<tr>'
        '<td>${_esc(it.studentName)}</td>'
        '<td>${_esc(it.classDisplay)}</td>'
        '<td class="right">N${fmt.format(it.amount)}</td>'
        '</tr>').join();

    final hasFamilySummary = familyTotalBilled != null && familyTotalPaid != null && familyOutstanding != null;
    final familySummary = !hasFamilySummary
        ? ''
        : '''
    <div class="section-title">Family Account Summary</div>
    <div class="summary-box">
      <div class="summary-item"><div class="label">Total Billed</div><div class="value" style="color:#6A1B9A;">N${fmt.format(familyTotalBilled)}</div></div>
      <div class="summary-item"><div class="label">Total Paid</div><div class="value" style="color:#388E3C;">N${fmt.format(familyTotalPaid)}</div></div>
      <div class="summary-item"><div class="label">Outstanding</div><div class="value" style="color:${familyOutstanding > 0 ? '#D32F2F' : '#388E3C'};">N${fmt.format(familyOutstanding)}</div></div>
    </div>
    ''';

    return '''
<!DOCTYPE html><html><head><meta charset="utf-8">
<style>
  @page { margin: 30px; }
  body { font-family: Helvetica, Arial, sans-serif; color: #1a1a1a; font-size: 12px; margin:0; padding:30px; }
  .center { text-align: center; }
  .right { text-align: right; }
  h1 { font-size: 16px; margin: 0; color: #303F9F; }
  .muted { color: #616161; font-size: 9px; }
  .title { font-size: 18px; font-weight:bold; margin: 14px 0 4px; }
  .info-row { display:flex; margin: 2px 0; font-size: 9px; }
  .info-row .label { width: 70px; color:#616161; }
  .info-row .value { font-weight:bold; }
  .section-title { font-weight:bold; font-size: 11px; margin: 18px 0 6px; }
  table { width:100%; border-collapse: collapse; font-size: 9px; margin-bottom: 14px; }
  th, td { border:1px solid #E0E0E0; padding:6px; }
  th { background:#C8E6C9; font-weight:bold; text-align:left; }
  .total-box { border:2px solid #A5D6A7; border-radius:5px; padding:10px; display:flex; justify-content:space-between; align-items:center; margin-bottom: 14px; }
  .total-box .label { font-weight:bold; font-size:13px; }
  .total-box .value { font-weight:bold; font-size:14px; color:#388E3C; }
  .summary-box { border:1px solid #9FA8DA; border-radius:5px; padding:10px; display:flex; justify-content:space-around; }
  .summary-item { text-align:center; }
  .summary-item .label { font-size:8px; color:#616161; }
  .summary-item .value { font-size:10px; font-weight:bold; }
  hr { border:none; border-top:1px solid #E0E0E0; margin: 20px 0 8px; }
</style>
</head><body>
  <div class="center">
    <h1>${_esc(schoolName.toUpperCase())}</h1>
    ${schoolAddress.isNotEmpty ? '<div class="muted">${_esc(schoolAddress)}</div>' : ''}
    <div class="title">FAMILY PAYMENT RECEIPT</div>
    <div class="muted">${_esc(term)} | ${_esc(session)}</div>
  </div>

  <div style="margin-top:18px;">
    <div class="info-row"><span class="label">Parent</span><span class="value">${_esc(parentName)}</span></div>
    <div class="info-row"><span class="label">Phone</span><span class="value">${_esc(parentPhone)}</span></div>
    <div class="info-row"><span class="label">Date</span><span class="value">${_esc(DateFormat('dd MMM yyyy').format(date))}</span></div>
    <div class="info-row"><span class="label">Method</span><span class="value">${_esc(method)}</span></div>
    ${note.trim().isNotEmpty ? '<div class="info-row"><span class="label">Note</span><span class="value">${_esc(note.trim())}</span></div>' : ''}
  </div>

  <div class="section-title">Payment Breakdown</div>
  <table>
    <thead><tr><th>Student</th><th>Class</th><th class="right">Amount Paid</th></tr></thead>
    <tbody>$rows</tbody>
  </table>

  <div class="total-box">
    <span class="label">TOTAL AMOUNT PAID</span>
    <span class="value">N${fmt.format(totalAmount)}</span>
  </div>

  $familySummary

  <hr>
  <div class="muted">Generated: ${_esc(DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now()))}</div>
</body></html>
''';
  }

  static String _esc(dynamic value) {
    final s = value?.toString() ?? '';
    return s.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;');
  }
}
