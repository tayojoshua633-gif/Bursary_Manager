import 'package:intl/intl.dart';

/// HTML mirror of TermlyReportPDFGenerator, rendered via Android's native
/// WebView print pipeline (see custom_report_pdf_generator.dart). No row
/// caps needed here — native pagination handles arbitrarily long tables.
class TermlyReportHtmlGenerator {
  static String build({
    required String term,
    required String session,
    required Map<String, dynamic> schoolProfile,
    required double cashReceived,
    required double posReceived,
    required double transferReceived,
    required double totalIncome,
    required Map<String, double> expenseCategoryTotals,
    required double expenseCash,
    required double expensePos,
    required double expenseTransfer,
    required double totalExpenses,
    required double netIncome,
    required int totalStudents,
    required int totalDebtors,
    required double totalOutstanding,
    required Map<String, int> newIntakeByClass,
    required int totalNewIntake,
    required int billsPrinted,
    required int receiptsPrinted,
    required int paymentHistoryPrinted,
    required int reprintsPrinted,
    required int totalPrints,
    required List<Map<String, dynamic>> stockSummary,
    required List<Map<String, dynamic>> salesDetails,
    required List<Map<String, dynamic>> salesDebtors,
    required double salesCashTotal,
    required double salesPosTotal,
    required double salesTransferTotal,
    required double totalSales,
    required double totalSalesDebt,
  }) {
    final f = NumberFormat('#,##0.00');
    final schoolName = (schoolProfile['name'] ?? 'School Name').toString();
    final address = (schoolProfile['address'] ?? '').toString();
    final phone = (schoolProfile['phone'] ?? '').toString();
    final email = (schoolProfile['email'] ?? '').toString();

    // ---- items summary for sales (grouped by item) ----
    final itemsSummary = <String, Map<String, dynamic>>{};
    for (final sale in salesDetails) {
      final items = sale['items'] as List<Map<String, dynamic>>? ?? [];
      for (final item in items) {
        final baseItemName = item['itemName'] ?? 'Unknown';
        final isCustomItem = item['isCustomItem'] == true;
        final itemName = isCustomItem ? '$baseItemName [Custom]' : baseItemName;
        final qty = (item['quantity'] as int?) ?? 0;
        final unitPrice = (item['unitPrice'] as double?) ?? 0.0;
        final amount = qty * unitPrice;
        final entry = itemsSummary.putIfAbsent(itemName, () => {'itemName': itemName, 'qtySold': 0, 'totalAmount': 0.0});
        entry['qtySold'] = (entry['qtySold'] as int) + qty;
        entry['totalAmount'] = (entry['totalAmount'] as double) + amount;
      }
    }
    final itemsList = itemsSummary.values.toList();
    final totalSalesAmount = itemsSummary.values.fold(0.0, (sum, item) => sum + (item['totalAmount'] as double));

    final expenseCategoryRows = expenseCategoryTotals.entries
        .map((e) => '<div class="row"><span>${_esc(e.key)}</span><span>N ${f.format(e.value)}</span></div>')
        .join();

    final newIntakeRows = newIntakeByClass.entries
        .map((e) => '<div class="row"><span>${_esc(e.key)}</span><span>${e.value} students</span></div>')
        .join();

    final stockRows = StringBuffer();
    for (final s in stockSummary) {
      stockRows.writeln('<tr><td>${_esc(s['itemName'])}</td><td class="right">${s['beginningQuantity']}</td>'
          '<td class="right">${s['qtySold']}</td><td class="right">${s['remainingQuantity']}</td></tr>');
    }

    final salesRows = StringBuffer();
    for (var i = 0; i < itemsList.length; i++) {
      final item = itemsList[i];
      salesRows.writeln('<tr><td class="center">${i + 1}</td><td>${_esc(item['itemName'])}</td>'
          '<td class="right">${item['qtySold']}</td><td class="right">N${f.format(item['totalAmount'])}</td></tr>');
    }

    final debtorRows = StringBuffer();
    for (final d in salesDebtors) {
      debtorRows.writeln('<tr>'
          '<td>${_esc('${d['buyerName']}${d['buyerType'].toString().isNotEmpty ? ' (${d['buyerType']})' : ''}')}</td>'
          '<td>${_esc(d['itemsPurchased'])}</td>'
          '<td class="right">N${f.format(d['totalAmount'])}</td>'
          '<td class="right">N${f.format(d['totalPaid'])}</td>'
          '<td class="right">N${f.format(d['outstandingBalance'])}</td>'
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
  @page { margin: 24px; }
  body { font-family: Helvetica, Arial, sans-serif; color: #1a1a1a; font-size: 12px; margin:0; padding:24px; }
  .center { text-align: center; }
  .right { text-align: right; }
  h1 { font-size: 20px; margin: 0; color: #303F9F; text-align:center; }
  .muted { color: #616161; text-align:center; font-size: 9px; }
  hr { border: none; border-top: 2px solid #ccc; margin: 14px 0; }
  .title { font-size: 18px; font-weight:bold; text-align:center; margin-bottom: 8px; }
  .period { text-align:center; font-weight:bold; font-size:12px; }
  .section-title { font-size: 15px; font-weight: bold; margin: 20px 0 8px; }
  .summary-box { border:1px solid; border-radius:6px; padding:14px; margin-bottom:8px; }
  .row { display:flex; justify-content:space-between; margin:4px 0; font-size:11px; }
  .total-row { font-weight:bold; font-size:13px; border-top:1.5px solid; margin-top:8px; padding-top:8px; }
  table { width:100%; border-collapse: collapse; margin: 10px 0; font-size: 10.5px; }
  th, td { border:1px solid; padding:4px 6px; text-align:left; }
  th { font-weight:bold; }
  .green-box { border-color: #A5D6A7; background: #E8F5E9; }
  .green-total { color: #2E7D32; border-color: #A5D6A7; }
  .orange-box { border-color: #FFCC80; background: #FFF3E0; }
  .orange-total { color: #E65100; border-color: #FFCC80; }
  .blue-box { border-color: #90CAF9; background: #E3F2FD; }
  .red-box { border-color: #EF9A9A; background: #FFEBEE; }
  .red-total { color: #C62828; border-color: #EF9A9A; }
  .purple-box { border-color: #CE93D8; background: #F3E5F5; }
  .purple-total { color: #6A1B9A; border-color: #CE93D8; }
  .cyan-box { border-color: #80DEEA; background: #E0F7FA; }
  .cyan-total { color: #00838F; border-color: #80DEEA; }
  .brown-th { background:#BCAAA4; border-color:#A1887F; }
  .brown-td { border-color:#A1887F; }
  .teal-th { background:#80CBC4; border-color:#4DB6AC; }
  .teal-td { border-color:#4DB6AC; }
  .red-th { background:#EF9A9A; border-color:#E57373; }
  .red-td { border-color:#E57373; }
  .bank-box { border: 1px solid #90CAF9; background: #E3F2FD; border-radius: 6px; padding: 10px; margin-top: 12px; font-size: 10px; }
  .footer-note { text-align: center; font-style: italic; color: #616161; font-size: 9px; margin-top: 20px; }
</style>
</head><body>
  <h1>${_esc(schoolName.toUpperCase())}</h1>
  ${address.isNotEmpty ? '<div class="muted">${_esc(address)}</div>' : ''}
  ${(phone.isNotEmpty || email.isNotEmpty) ? '<div class="muted">${[if (phone.isNotEmpty) 'Tel: ${_esc(phone)}', if (email.isNotEmpty) _esc(email)].join(' | ')}</div>' : ''}
  <hr>
  <div class="title">TERMLY FINANCIAL REPORT</div>
  <div class="period">Term: ${_esc(term)} &nbsp;&nbsp; Session: ${_esc(session)}</div>
  <div class="muted">Generated: ${_esc(DateFormat('MMMM d, yyyy - h:mm a').format(DateTime.now()))}</div>

  <div class="section-title" style="color:#2E7D32;">INCOME REPORT (TOTAL SCHOOL FEES &amp; OFFICE SALES)</div>
  <div class="summary-box green-box">
    <div class="row"><span>Total Cash Received (School Fees):</span><span>N ${f.format(cashReceived)}</span></div>
    <div class="row"><span>Total Cash Received (Office Sales):</span><span>N ${f.format(salesCashTotal)}</span></div>
    <div class="row"><span>Total POS Received (School Fees):</span><span>N ${f.format(posReceived)}</span></div>
    <div class="row"><span>Total POS Received (Office Sales):</span><span>N ${f.format(salesPosTotal)}</span></div>
    <div class="row"><span>Total Transfer Received (School Fees):</span><span>N ${f.format(transferReceived)}</span></div>
    <div class="row"><span>Total Transfer Received (Office Sales):</span><span>N ${f.format(salesTransferTotal)}</span></div>
    <div class="row total-row green-total"><span>TOTAL INCOME:</span><span>N ${f.format(totalIncome + totalSales)}</span></div>
  </div>

  <div class="section-title" style="color:#E65100;">EXPENSES REPORT</div>
  <div class="summary-box orange-box">
    ${expenseCategoryTotals.isEmpty ? '' : '<strong>By Category:</strong>$expenseCategoryRows<hr>'}
    <strong>By Payment Method:</strong>
    <div class="row"><span>Cash Paid:</span><span>N ${f.format(expenseCash)}</span></div>
    <div class="row"><span>POS Paid:</span><span>N ${f.format(expensePos)}</span></div>
    <div class="row"><span>Transfers Paid:</span><span>N ${f.format(expenseTransfer)}</span></div>
    <div class="row total-row orange-total"><span>TOTAL EXPENSES:</span><span>N ${f.format(totalExpenses)}</span></div>
  </div>

  <div class="summary-box blue-box" style="display:flex; justify-content:space-between; align-items:center; font-size:14px; font-weight:bold; margin-top:16px;">
    <span>NET INCOME (Income - Expenses):</span>
    <span style="color:${netIncome >= 0 ? '#2E7D32' : '#C62828'}; font-size:16px;">N ${f.format(netIncome)}</span>
  </div>

  <div class="section-title" style="color:#C62828;">DEBT REPORT</div>
  <div class="summary-box red-box">
    <div class="row"><span>Total Students:</span><span>$totalStudents</span></div>
    <div class="row"><span>Total Debtors:</span><span>$totalDebtors</span></div>
    <div class="row total-row red-total"><span>Total Outstanding Debt:</span><span>N ${f.format(totalOutstanding)}</span></div>
  </div>

  <div class="section-title" style="color:#6A1B9A;">NEW INTAKE REPORT</div>
  <div class="summary-box purple-box">
    ${newIntakeByClass.isEmpty ? '<div class="center muted">No new students registered this term</div>' : '$newIntakeRows<div class="row total-row purple-total"><span>TOTAL NEW INTAKE:</span><span>$totalNewIntake</span></div>'}
  </div>

  <div class="section-title" style="color:#00838F;">THERMAL PRINTING REPORT</div>
  <div class="summary-box cyan-box">
    <div class="row"><span>Bills Printed:</span><span>$billsPrinted</span></div>
    <div class="row"><span>Receipts Printed:</span><span>$receiptsPrinted</span></div>
    <div class="row"><span>Payment History Printed:</span><span>$paymentHistoryPrinted</span></div>
    <div class="row"><span>Reprints:</span><span>$reprintsPrinted</span></div>
    <div class="row total-row cyan-total"><span>TOTAL PRINTS:</span><span>$totalPrints</span></div>
  </div>

  ${stockSummary.isEmpty ? '' : '''
  <div class="section-title" style="color:#5D4037;">STOCK SUMMARY</div>
  <table><thead><tr class="brown-th"><th class="brown-td">Item</th><th class="brown-td right">Beginning</th><th class="brown-td right">Sold</th><th class="brown-td right">Remaining</th></tr></thead>
  <tbody>$stockRows</tbody></table>
  '''}

  ${itemsList.isEmpty ? '' : '''
  <div class="section-title" style="color:#00796B;">SALES SUMMARY REPORT</div>
  <table><thead><tr class="teal-th"><th class="teal-td center">S/N</th><th class="teal-td">Items</th><th class="teal-td right">Qty Sold</th><th class="teal-td right">Total Amount</th></tr></thead>
  <tbody>$salesRows</tbody></table>
  <div class="row total-row" style="color:#00695C;"><span>TOTAL SALES:</span><span>N${f.format(totalSalesAmount)}</span></div>
  '''}

  ${salesDebtors.isEmpty ? '' : '''
  <div class="section-title" style="color:#C62828;">SALES DEBTORS</div>
  <table><thead><tr class="red-th"><th class="red-td">Buyer</th><th class="red-td">Items</th><th class="red-td right">Total</th><th class="red-td right">Paid</th><th class="red-td right">Balance</th></tr></thead>
  <tbody>$debtorRows</tbody></table>
  <div class="row total-row red-total"><span>TOTAL SALES DEBT:</span><span>N${f.format(totalSalesDebt)}</span></div>
  '''}

  ${accounts.isEmpty ? '' : '<div class="bank-box"><strong>Bank Account Details:</strong>${accounts.map((a) => '<div>${_esc(a)}</div>').join()}</div>'}

  <div class="footer-note">This report provides a comprehensive overview of all financial activities for the term.</div>
</body></html>
''';
  }

  static String _esc(dynamic value) {
    final s = value?.toString() ?? '';
    return s.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;');
  }
}
