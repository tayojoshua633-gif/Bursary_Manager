import 'package:intl/intl.dart';

/// HTML report for the Expenses list screen, rendered via Android's native
/// WebView print pipeline (see custom_report_pdf_generator.dart).
class ExpensesHtmlGenerator {
  static String build({
    required List<Map<String, dynamic>> expenses,
    required Map<String, dynamic> schoolProfile,
    String? term,
    String? session,
    String? filterLabel,
  }) {
    final f = NumberFormat('#,##0.00');
    final schoolName = (schoolProfile['name'] ?? 'School Name').toString();
    final address = (schoolProfile['address'] ?? '').toString();
    final phone = (schoolProfile['phone'] ?? '').toString();
    final email = (schoolProfile['email'] ?? '').toString();

    double totalAmount = 0;
    final categoryTotals = <String, double>{};
    for (final e in expenses) {
      final amount = (e['amount'] as num?)?.toDouble() ?? 0.0;
      totalAmount += amount;
      final category = (e['category'] ?? 'Uncategorized').toString();
      final customCategory = e['customCategory'];
      final displayCategory = category == 'Other' && customCategory != null ? 'Other: $customCategory' : category;
      categoryTotals[displayCategory] = (categoryTotals[displayCategory] ?? 0) + amount;
    }

    final categoryChips = categoryTotals.entries
        .map((e) => '<span class="chip">${_esc(e.key)}: N${f.format(e.value)}</span>')
        .join();

    final rows = StringBuffer();
    for (var i = 0; i < expenses.length; i++) {
      final e = expenses[i];
      final category = (e['category'] ?? 'Uncategorized').toString();
      final customCategory = e['customCategory'];
      final displayCategory = category == 'Other' && customCategory != null ? 'Other: $customCategory' : category;
      final date = (e['expenseDate'] ?? '').toString();
      final dateDisplay = date.length >= 10 ? date.substring(0, 10) : date;

      rows.writeln('<tr>'
          '<td class="center">${i + 1}</td>'
          '<td>${_esc(e['description'] ?? '')}</td>'
          '<td>${_esc(displayCategory)}</td>'
          '<td>${_esc(e['recipient'] ?? '')}</td>'
          '<td class="center">${_esc(e['paymentMethod'] ?? '')}</td>'
          '<td class="center">${_esc(dateDisplay)}</td>'
          '<td class="right" style="color:#C62828;">N${f.format(e['amount'])}</td>'
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
  h1 { font-size: 18px; margin: 0; text-align:center; color:#5D4037; }
  .muted { color: #616161; text-align:center; font-size: 10px; }
  hr { border: none; border-top: 2px solid #D7CCC8; margin: 12px 0; }
  .title { font-size: 15px; font-weight:bold; text-align:center; margin-bottom: 6px; }
  .info { text-align:center; font-size: 10px; color:#616161; }
  .summary-box { border:1px solid #D7CCC8; background:#EFEBE9; border-radius:5px; padding:12px; margin: 16px 0; }
  .summary-row { display:flex; justify-content:space-around; margin-bottom:6px; }
  .summary-item { text-align:center; }
  .summary-item .label { font-size:9px; color:#616161; }
  .summary-item .value { font-size:14px; font-weight:bold; }
  .chip { display:inline-block; background:#FFFFFF; border:1px solid #D7CCC8; border-radius:4px; padding:3px 8px; font-size:8px; margin: 4px 4px 0 0; }
  table { width:100%; border-collapse: collapse; font-size: 9px; margin-bottom: 16px; }
  th, td { border:1px solid #D7CCC8; padding:6px; }
  th { background:#D7CCC8; font-weight:bold; }
  tr:nth-child(even) td { background:#FAFAFA; }
  .bank-box { border:1px solid #90CAF9; background:#E3F2FD; border-radius:6px; padding:10px; font-size:9px; }
  .footer-note { text-align:center; font-style: italic; color: #616161; font-size: 9px; margin-top: 16px; }
</style>
</head><body>
  <h1>${_esc(schoolName.toUpperCase())}</h1>
  ${address.isNotEmpty ? '<div class="muted">${_esc(address)}</div>' : ''}
  ${(phone.isNotEmpty || email.isNotEmpty) ? '<div class="muted">${[if (phone.isNotEmpty) 'Tel: ${_esc(phone)}', if (email.isNotEmpty) _esc(email)].join(' | ')}</div>' : ''}
  <hr>
  <div class="title">EXPENSES REPORT</div>
  ${(term != null && session != null) ? '<div class="info">${_esc(term)} | ${_esc(session)}</div>' : ''}
  ${filterLabel != null ? '<div class="info">${_esc(filterLabel)}</div>' : ''}
  <div class="muted">Generated: ${_esc(DateFormat('MMM d, yyyy - h:mm a').format(DateTime.now()))}</div>

  <div class="summary-box">
    <div class="summary-row">
      <div class="summary-item"><div class="label">Total Records</div><div class="value">${expenses.length}</div></div>
      <div class="summary-item"><div class="label">Total Amount</div><div class="value" style="color:#C62828;">N${f.format(totalAmount)}</div></div>
    </div>
    ${categoryTotals.isEmpty ? '' : '<div>$categoryChips</div>'}
  </div>

  <table>
    <thead><tr>
      <th class="center">S/N</th><th>Description</th><th>Category</th><th>Recipient</th>
      <th class="center">Method</th><th class="center">Date</th><th class="right">Amount</th>
    </tr></thead>
    <tbody>$rows</tbody>
  </table>

  ${accounts.isEmpty ? '' : '<div class="bank-box"><strong>Bank Account Details:</strong>${accounts.map((a) => '<div>${_esc(a)}</div>').join()}</div>'}

  <div class="footer-note">This report provides a financial overview of expenses for the selected filter.</div>
</body></html>
''';
  }

  static String _esc(dynamic value) {
    final s = value?.toString() ?? '';
    return s.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;');
  }
}
