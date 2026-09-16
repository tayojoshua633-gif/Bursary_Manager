import 'package:intl/intl.dart';

/// Builds the Custom Report as an HTML document, rendered on Android via
/// the platform's native WebView print engine (see
/// `custom_report_pdf_generator.dart`) instead of the pure-Dart `pdf`
/// package. The browser/WebView engine paginates and lays out the content
/// itself, so there's no need to cap row counts or manually manage pages —
/// it handles arbitrarily large tables the same way printing a long webpage
/// does.
class CustomReportHtmlGenerator {
  static String build({
    required DateTime startDate,
    required DateTime endDate,
    required String? term,
    required String? session,
    required Map<String, dynamic> schoolProfile,
    required double cashTotal,
    required double posTotal,
    required double transferTotal,
    required double totalIncome,
    required List<Map<String, dynamic>> paymentDetails,
    required double expenseCashTotal,
    required double expensePosTotal,
    required double expenseTransferTotal,
    required double totalExpenses,
    required List<Map<String, dynamic>> expenseDetails,
    required List<Map<String, dynamic>> stockSummary,
    required List<Map<String, dynamic>> salesDetails,
    required List<Map<String, dynamic>> salesDebtors,
    required double salesCashTotal,
    required double salesPosTotal,
    required double salesTransferTotal,
    required double totalSales,
    required double totalSalesDebt,
    bool includeIncome = true,
    bool includePaymentDetails = true,
    bool includeExpenses = true,
    bool includeStockAndSales = true,
    String reportTabLabel = 'Full Report',
  }) {
    final f = NumberFormat('#,##0.00');
    final showNetIncome = includeIncome && includeExpenses;
    final buf = StringBuffer();

    buf.writeln('<!DOCTYPE html><html><head><meta charset="utf-8">');
    buf.writeln(_styles);
    buf.writeln('</head><body>');

    buf.writeln(_header(schoolProfile, startDate, endDate, term, session, reportTabLabel));

    if (includeIncome) {
      buf.writeln(_incomeSection(
        cashTotal, posTotal, transferTotal, totalIncome, f,
        salesCashTotal, salesPosTotal, salesTransferTotal, totalSales,
      ));
    }

    if (includePaymentDetails && paymentDetails.isNotEmpty) {
      buf.writeln(_paymentDetailsSection(paymentDetails, f));
    }

    if (includeStockAndSales && salesDetails.isNotEmpty) {
      buf.writeln(_salesSummarySection(salesDetails, f));
    }

    if (includeExpenses && expenseDetails.isNotEmpty) {
      buf.writeln(_expensesSection(
        expenseCashTotal, expensePosTotal, expenseTransferTotal,
        totalExpenses, expenseDetails, f,
      ));
    }

    if (showNetIncome) {
      buf.writeln(_netIncomeSection((totalIncome + totalSales) - totalExpenses, f));
    }

    if (includeStockAndSales && stockSummary.isNotEmpty) {
      buf.writeln(_stockSummarySection(stockSummary));
    }

    if (includeStockAndSales && salesDebtors.isNotEmpty) {
      buf.writeln(_salesDebtorsSection(salesDebtors, totalSalesDebt, f));
    }

    buf.writeln(_bankDetails(schoolProfile));
    buf.writeln(_footer());

    buf.writeln('</body></html>');
    return buf.toString();
  }

  static const _styles = '''
<style>
  body { font-family: Helvetica, Arial, sans-serif; color: #1a1a1a; font-size: 12px; margin: 0; padding: 24px; }
  .center { text-align: center; }
  .right { text-align: right; }
  h1 { font-size: 20px; margin: 0; color: #303F9F; text-transform: uppercase; }
  .muted { color: #616161; }
  hr { border: none; border-top: 2px solid #ccc; margin: 14px 0; }
  .section-title { font-size: 15px; font-weight: bold; margin: 22px 0 8px; }
  .summary-box { border: 1px solid; border-radius: 6px; padding: 12px 16px; margin-bottom: 8px; }
  .summary-row { display: flex; justify-content: space-between; margin: 4px 0; }
  .summary-total { font-weight: bold; font-size: 13px; border-top: 1.5px solid; margin-top: 10px; padding-top: 8px; }
  table { width: 100%; border-collapse: collapse; margin-bottom: 14px; font-size: 10.5px; page-break-inside: auto; }
  tr { page-break-inside: avoid; page-break-after: auto; }
  th, td { border: 1px solid; padding: 4px 6px; text-align: left; }
  th { font-weight: bold; }
  .cat-label { font-weight: bold; font-size: 11px; }
  .cat-total { font-size: 9px; color: #616161; }
  .green-box { border-color: #A5D6A7; background: #E8F5E9; }
  .green-total { color: #2E7D32; border-color: #A5D6A7; }
  .orange-box { border-color: #FFCC80; background: #FFF3E0; }
  .orange-total { color: #E65100; border-color: #FFCC80; }
  .blue-box { border-color: #90CAF9; background: #E3F2FD; }
  .blue-total { color: #1565C0; border-color: #90CAF9; }
  .green-th { background: #C8E6C9; border-color: #81C784; }
  .green-td { border-color: #81C784; }
  .teal-th { background: #80CBC4; border-color: #4DB6AC; }
  .teal-td { border-color: #4DB6AC; }
  .orange-th { background: #FFE0B2; border-color: #FFB74D; }
  .orange-td { border-color: #FFB74D; }
  .brown-th { background: #BCAAA4; border-color: #A1887F; }
  .brown-td { border-color: #A1887F; }
  .red-th { background: #EF9A9A; border-color: #E57373; }
  .red-td { border-color: #E57373; }
  .red-total { color: #C62828; border-color: #E57373; }
  .bank-box { border: 1px solid #90CAF9; background: #E3F2FD; border-radius: 6px; padding: 10px; margin-top: 12px; font-size: 10px; }
  .footer-note { text-align: center; font-style: italic; color: #616161; font-size: 10px; margin-top: 20px; }
</style>
''';

  static String _header(
    Map<String, dynamic> schoolProfile,
    DateTime startDate,
    DateTime endDate,
    String? term,
    String? session,
    String reportTabLabel,
  ) {
    final schoolName = (schoolProfile['name'] ?? 'School Name').toString();
    final address = (schoolProfile['address'] ?? '').toString();
    final phone = (schoolProfile['phone'] ?? '').toString();
    final email = (schoolProfile['email'] ?? '').toString();
    final rangeStr =
        '${DateFormat('MMM d, yyyy').format(startDate)} - ${DateFormat('MMM d, yyyy').format(endDate)}';

    return '''
<div class="center">
  <h1>${_esc(schoolName)}</h1>
  ${address.isNotEmpty ? '<div>${_esc(address)}</div>' : ''}
  ${(phone.isNotEmpty || email.isNotEmpty) ? '<div class="muted">${[if (phone.isNotEmpty) 'Tel: ${_esc(phone)}', if (email.isNotEmpty) _esc(email)].join(' | ')}</div>' : ''}
  <hr>
  <div style="font-size:16px; font-weight:bold;">${_esc(reportTabLabel.toUpperCase())}</div>
  <div style="font-weight:bold; margin-top:6px;">Period: ${_esc(rangeStr)}</div>
  ${(term != null && session != null) ? '<div class="muted">Term: ${_esc(term)} | Session: ${_esc(session)}</div>' : ''}
  <div class="muted" style="font-size:9px; margin-top:4px;">Generated: ${_esc(DateFormat('MMMM d, yyyy - h:mm a').format(DateTime.now()))}</div>
</div>
''';
  }

  static String _incomeSection(
    double cashTotal, double posTotal, double transferTotal, double totalIncome, NumberFormat f,
    double salesCashTotal, double salesPosTotal, double salesTransferTotal, double totalSales,
  ) {
    return '''
<div class="section-title" style="color:#2E7D32;">INCOME SUMMARY (SCHOOL FEES &amp; OFFICE SALES)</div>
<div class="summary-box green-box">
  <div class="summary-row"><span>Cash Received (School Fees):</span><span>N ${f.format(cashTotal)}</span></div>
  <div class="summary-row"><span>Cash Received (Office Sales):</span><span>N ${f.format(salesCashTotal)}</span></div>
  <div class="summary-row"><span>POS Received (School Fees):</span><span>N ${f.format(posTotal)}</span></div>
  <div class="summary-row"><span>POS Received (Office Sales):</span><span>N ${f.format(salesPosTotal)}</span></div>
  <div class="summary-row"><span>Transfer Received (School Fees):</span><span>N ${f.format(transferTotal)}</span></div>
  <div class="summary-row"><span>Transfer Received (Office Sales):</span><span>N ${f.format(salesTransferTotal)}</span></div>
  <div class="summary-row summary-total green-total"><span>TOTAL INCOME:</span><span>N ${f.format(totalIncome + totalSales)}</span></div>
</div>
''';
  }

  static String _paymentDetailsSection(List<Map<String, dynamic>> paymentDetails, NumberFormat f) {
    final grouped = <String, List<Map<String, dynamic>>>{};
    for (final p in paymentDetails) {
      final cat = (p['paymentFor']?.toString() ?? 'School Fees');
      (grouped[cat] ??= []).add(p);
    }

    final buf = StringBuffer();
    buf.writeln('<div class="section-title">SCHOOL FEES PAYMENT DETAILS (${paymentDetails.length} transactions)</div>');

    grouped.forEach((category, payments) {
      final categoryTotal = payments.fold<double>(0, (sum, p) => sum + ((p['amount'] as num).toDouble()));
      buf.writeln('<div class="cat-label">${_esc(category.toUpperCase())} '
          '<span class="cat-total">— ${payments.length} transaction(s), Total: N ${f.format(categoryTotal)}</span></div>');
      buf.writeln('<table><thead><tr class="green-th">'
          '<th class="green-td">Student Name</th><th class="green-td">Adm No</th>'
          '<th class="green-td">Class/Arm</th><th class="green-td">Method</th>'
          '<th class="green-td right">Amount (N)</th></tr></thead><tbody>');
      for (final p in payments) {
        buf.writeln('<tr>'
            '<td class="green-td">${_esc(p['studentName'])}</td>'
            '<td class="green-td">${_esc(p['admissionNo'])}</td>'
            '<td class="green-td">${_esc('${p['className']} - ${p['armName']}')}</td>'
            '<td class="green-td">${_esc(p['method'])}</td>'
            '<td class="green-td right">${f.format(p['amount'] as num)}</td>'
            '</tr>');
      }
      buf.writeln('</tbody></table>');
    });

    return buf.toString();
  }

  static String _expensesSection(
    double expenseCashTotal, double expensePosTotal, double expenseTransferTotal,
    double totalExpenses, List<Map<String, dynamic>> expenseDetails, NumberFormat f,
  ) {
    final buf = StringBuffer();
    buf.writeln('<div class="section-title" style="color:#E65100;">EXPENSES</div>');
    buf.writeln('<div class="summary-box orange-box">'
        '<div class="summary-row"><span>Cash Paid:</span><span>N ${f.format(expenseCashTotal)}</span></div>'
        '<div class="summary-row"><span>POS Paid:</span><span>N ${f.format(expensePosTotal)}</span></div>'
        '<div class="summary-row"><span>Transfers Paid:</span><span>N ${f.format(expenseTransferTotal)}</span></div>'
        '<div class="summary-row summary-total orange-total"><span>TOTAL EXPENSES:</span><span>N ${f.format(totalExpenses)}</span></div>'
        '</div>');

    buf.writeln('<div style="font-weight:bold; margin:10px 0 6px;">EXPENSES DETAILS (${expenseDetails.length} transactions)</div>');
    buf.writeln('<table><thead><tr class="orange-th">'
        '<th class="orange-td">Description</th><th class="orange-td">Category</th>'
        '<th class="orange-td">Recipient</th><th class="orange-td">Method</th>'
        '<th class="orange-td right">Amount (N)</th></tr></thead><tbody>');
    for (final e in expenseDetails) {
      buf.writeln('<tr>'
          '<td class="orange-td">${_esc(e['description'])}</td>'
          '<td class="orange-td">${_esc(e['category'])}</td>'
          '<td class="orange-td">${_esc(e['recipient'])}</td>'
          '<td class="orange-td">${_esc(e['method'])}</td>'
          '<td class="orange-td right">${f.format(e['amount'] as num)}</td>'
          '</tr>');
    }
    buf.writeln('</tbody></table>');
    return buf.toString();
  }

  static String _netIncomeSection(double netIncome, NumberFormat f) {
    final isPositive = netIncome >= 0;
    return '''
<div class="summary-box blue-box" style="display:flex; justify-content:space-between; align-items:center; font-size:14px; font-weight:bold;">
  <span>NET INCOME (Income - Expenses):</span>
  <span style="color:${isPositive ? '#2E7D32' : '#C62828'}; font-size:16px;">N ${f.format(netIncome)}</span>
</div>
''';
  }

  static String _stockSummarySection(List<Map<String, dynamic>> stockSummary) {
    final buf = StringBuffer();
    buf.writeln('<div class="section-title" style="color:#5D4037;">STOCK SUMMARY</div>');
    buf.writeln('<table><thead><tr class="brown-th">'
        '<th class="brown-td">Item</th><th class="brown-td right">Beginning</th>'
        '<th class="brown-td right">Sold</th><th class="brown-td right">Remaining</th>'
        '</tr></thead><tbody>');
    for (final item in stockSummary) {
      buf.writeln('<tr>'
          '<td class="brown-td">${_esc(item['itemName'])}</td>'
          '<td class="brown-td right">${_esc(item['beginningQuantity'])}</td>'
          '<td class="brown-td right">${_esc(item['qtySold'])}</td>'
          '<td class="brown-td right">${_esc(item['remainingQuantity'])}</td>'
          '</tr>');
    }
    buf.writeln('</tbody></table>');
    return buf.toString();
  }

  static String _salesSummarySection(List<Map<String, dynamic>> salesDetails, NumberFormat f) {
    final buf = StringBuffer();
    buf.writeln('<div class="section-title" style="color:#00796B;">SALES SUMMARY</div>');
    buf.writeln('<table><thead><tr class="teal-th">'
        '<th class="teal-td">S/N</th><th class="teal-td">Item(s) Sold</th>'
        '<th class="teal-td center">Qty</th><th class="teal-td center">Payment Status</th>'
        '<th class="teal-td right">Amount Paid</th><th class="teal-td">Buyer Details</th>'
        '</tr></thead><tbody>');
    for (var i = 0; i < salesDetails.length; i++) {
      final sale = salesDetails[i];
      final items = sale['items'] as List<Map<String, dynamic>>;
      final itemsText = items.map((item) {
        final isCustom = item['isCustomItem'] == true;
        return isCustom
            ? '${item['itemName']} [Custom] (x${item['quantity']})'
            : '${item['itemName']} (x${item['quantity']})';
      }).join(', ');
      final totalPaid = (sale['totalPaid'] as num).toDouble();
      final totalAmount = (sale['totalAmount'] as num).toDouble();
      final outstanding = totalAmount - totalPaid;
      final status = outstanding <= 0 ? 'Paid' : (totalPaid > 0 ? 'Part Payment' : 'Unpaid');

      buf.writeln('<tr>'
          '<td class="teal-td">${i + 1}</td>'
          '<td class="teal-td">${_esc(itemsText)}</td>'
          '<td class="teal-td center">${_esc(sale['totalQtySold'])}</td>'
          '<td class="teal-td center">$status</td>'
          '<td class="teal-td right">${f.format(totalPaid)}</td>'
          '<td class="teal-td">${_esc('${sale['buyerName']} (${sale['buyerType']})')}</td>'
          '</tr>');
    }
    buf.writeln('</tbody></table>');
    return buf.toString();
  }

  static String _salesDebtorsSection(
    List<Map<String, dynamic>> salesDebtors, double totalSalesDebt, NumberFormat f,
  ) {
    final buf = StringBuffer();
    buf.writeln('<div class="section-title" style="color:#C62828;">SALES DEBTORS</div>');
    buf.writeln('<table><thead><tr class="red-th">'
        '<th class="red-td">Buyer</th><th class="red-td">Items</th>'
        '<th class="red-td right">Total</th><th class="red-td right">Paid</th>'
        '<th class="red-td right">Balance</th></tr></thead><tbody>');
    for (final debtor in salesDebtors) {
      buf.writeln('<tr>'
          '<td class="red-td">${_esc('${debtor['buyerName']} (${debtor['buyerType']})')}</td>'
          '<td class="red-td">${_esc(debtor['itemsPurchased'])}</td>'
          '<td class="red-td right">${f.format(debtor['totalAmount'])}</td>'
          '<td class="red-td right">${f.format(debtor['totalPaid'])}</td>'
          '<td class="red-td right">${f.format(debtor['outstandingBalance'])}</td>'
          '</tr>');
    }
    buf.writeln('</tbody></table>');
    buf.writeln('<div class="summary-row summary-total red-total" style="font-size:13px;">'
        '<span>TOTAL SALES DEBT:</span><span>N ${f.format(totalSalesDebt)}</span></div>');
    return buf.toString();
  }

  static String _bankDetails(Map<String, dynamic> schoolProfile) {
    final accounts = <String>[];
    for (int i = 1; i <= 3; i++) {
      final bankName = (schoolProfile['bankName$i']?.toString() ?? '');
      final accNum = (schoolProfile['accountNumber$i']?.toString() ?? '');
      final accName = (schoolProfile['accountName$i']?.toString() ?? '');
      if (bankName.isNotEmpty && accNum.isNotEmpty) {
        accounts.add('$bankName - $accNum - $accName');
      }
    }
    if (accounts.isEmpty) return '';
    final rows = accounts.map((a) => '<div>${_esc(a)}</div>').join();
    return '<div class="bank-box"><strong>Bank Account Details:</strong>$rows</div>';
  }

  static String _footer() {
    return '<div class="footer-note">This report provides a financial overview for the selected date range.</div>';
  }

  static String _esc(dynamic value) {
    final s = value?.toString() ?? '';
    return s
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;');
  }
}
