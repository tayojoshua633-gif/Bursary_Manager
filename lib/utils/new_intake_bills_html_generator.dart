import 'dart:convert';
import 'dart:io';
import 'package:intl/intl.dart';

/// HTML mirror of NewIntakeBillsPDFGenerator, rendered via Android's native
/// WebView print pipeline (see custom_report_pdf_generator.dart).
class NewIntakeBillsHtmlGenerator {
  static Future<String> build({
    required List<Map<String, dynamic>> regularFees,
    required List<Map<String, dynamic>> groupedCategories,
    required List<Map<String, dynamic>> standaloneItems,
    required double grandTotal,
    required String term,
    required String session,
    required String className,
    String? armName,
    required Map<String, dynamic> schoolProfile,
    String title = 'NEW INTAKE BILL',
  }) async {
    final f = NumberFormat('#,##0');
    final schoolName = (schoolProfile['name'] ?? 'School Name').toString();
    final address = (schoolProfile['address'] ?? '').toString();
    final phone = (schoolProfile['phone'] ?? '').toString();
    final email = (schoolProfile['email'] ?? '').toString();

    String? logoDataUri;
    final logoPath = schoolProfile['logoPath']?.toString() ?? '';
    if (logoPath.isNotEmpty) {
      final logoFile = File(logoPath);
      if (await logoFile.exists()) {
        final bytes = await logoFile.readAsBytes();
        final ext = logoPath.toLowerCase().endsWith('.png') ? 'png' : 'jpeg';
        logoDataUri = 'data:image/$ext;base64,${base64Encode(bytes)}';
      }
    }

    int serialNumber = 0;
    final rows = StringBuffer();

    void addSectionHeader(String label) {
      rows.writeln('<tr class="section-row"><td></td><td>${_esc(label)}</td><td></td></tr>');
    }

    void addSubtotal(String label, double total) {
      rows.writeln('<tr class="subtotal-row"><td></td>'
          '<td class="right">${_esc(label)}</td>'
          '<td class="right">${f.format(total)}</td></tr>');
    }

    if (standaloneItems.isNotEmpty) {
      double sectionTotal = 0;
      addSectionHeader('REGISTRATION FEES');
      for (final item in standaloneItems) {
        serialNumber++;
        final name = item['name'] ?? 'Unknown';
        final amount = (item['amount'] as num?)?.toDouble() ?? 0;
        sectionTotal += amount;
        rows.writeln('<tr><td class="center">$serialNumber</td><td>${_esc(name)}</td><td class="right">${f.format(amount)}</td></tr>');
      }
      addSubtotal('Registration Fees Subtotal', sectionTotal);
    }

    if (regularFees.isNotEmpty) {
      double sectionTotal = 0;
      addSectionHeader('CURRENT TERM FEES');
      for (final fee in regularFees) {
        serialNumber++;
        final name = fee['feeItemName'] ?? 'Unknown';
        final amount = (fee['amount'] as num?)?.toDouble() ?? 0;
        sectionTotal += amount;
        rows.writeln('<tr><td class="center">$serialNumber</td><td>${_esc(name)}</td><td class="right">${f.format(amount)}</td></tr>');
      }
      addSubtotal('Current Term Fees Subtotal', sectionTotal);
    }

    for (final category in groupedCategories) {
      final categoryName = (category['categoryName'] ?? 'Unknown').toString();
      final items = category['items'] as List<Map<String, dynamic>>? ?? [];
      final categoryTotal = (category['categoryTotal'] as num?)?.toDouble() ?? 0;
      if (items.isEmpty) continue;

      addSectionHeader(categoryName.toUpperCase());
      for (final item in items) {
        serialNumber++;
        final name = item['name'] ?? 'Unknown';
        final amount = (item['amount'] as num?)?.toDouble() ?? 0;
        rows.writeln('<tr><td class="center">$serialNumber</td><td>${_esc(name)}</td><td class="right">${f.format(amount)}</td></tr>');
      }
      addSubtotal('$categoryName Subtotal', categoryTotal);
    }

    final accounts = <Map<String, String>>[];
    for (int i = 1; i <= 3; i++) {
      final bankName = (schoolProfile['bankName$i']?.toString() ?? '');
      final accNum = (schoolProfile['accountNumber$i']?.toString() ?? '');
      final accName = (schoolProfile['accountName$i']?.toString() ?? '');
      if (bankName.isNotEmpty && accNum.isNotEmpty) {
        accounts.add({'bankName': bankName, 'accountNumber': accNum, 'accountName': accName});
      }
    }
    final bankRows = accounts.map((a) {
      final nameRow = a['accountName']!.isNotEmpty
          ? '<div><strong>Account Name:</strong> ${_esc(a['accountName'])}</div>'
          : '';
      return '<div style="margin-bottom:8px;">'
          '<div><strong>Name of Bank:</strong> ${_esc(a['bankName'])}</div>'
          '<div><strong>Account Number:</strong> ${_esc(a['accountNumber'])}</div>'
          '$nameRow'
          '</div>';
    }).join();

    final now = DateTime.now();

    return '''
<!DOCTYPE html><html><head><meta charset="utf-8">
<style>
  @page { margin: 24px; }
  body { font-family: Helvetica, Arial, sans-serif; color: #1a1a1a; font-size: 12px; margin:0; padding:24px; }
  .center { text-align: center; }
  .right { text-align: right; }
  h1 { font-size: 22px; margin: 0; text-align:center; }
  .muted { color: #616161; text-align:center; font-size: 10px; }
  hr { border: none; border-top: 2px solid #FF5722; margin: 14px 0; }
  .title-box { background:#FBE9E7; border-radius:8px; padding:10px 20px; text-align:center; margin-bottom: 16px; }
  .title-box .title { font-size:18px; font-weight:bold; color:#FF5722; }
  .chips { margin-top:8px; }
  .chip { display:inline-block; border:1px solid #FFAB91; border-radius:4px; padding:4px 12px; font-size:10px; font-weight:bold; background:white; margin: 0 4px; }
  table { width:100%; border-collapse: collapse; font-size: 11px; margin-bottom: 16px; }
  th, td { border:1px solid #E0E0E0; padding:8px; }
  th { background:black; color:white; font-weight:bold; }
  .section-row td { background:#ECEFF1; font-weight:bold; color:#37474F; }
  .subtotal-row td { background:#F5F5F5; font-weight:bold; font-style:italic; }
  .grand-total { border:2px solid #A5D6A7; background:#E8F5E9; border-radius:8px; padding:16px; display:flex; justify-content:space-between; align-items:center; margin-bottom:16px; }
  .grand-total .label { font-size:14px; font-weight:bold; }
  .grand-total .value { font-size:20px; font-weight:bold; color:#388E3C; }
  .bank-box { border:1px solid #90CAF9; background:#E3F2FD; border-radius:6px; padding:12px; font-size:11px; margin-bottom: 16px; color: #0D47A1; }
  .footer-row { display:flex; justify-content:space-between; border-top:1px solid #E0E0E0; padding-top:10px; font-size:9px; color:#616161; }
</style>
</head><body>
  ${logoDataUri != null ? '<div class="center"><img src="$logoDataUri" style="width:60px; height:60px;"></div>' : ''}
  <h1>${_esc(schoolName.toUpperCase())}</h1>
  ${address.isNotEmpty ? '<div class="muted">${_esc(address)}</div>' : ''}
  ${(phone.isNotEmpty || email.isNotEmpty) ? '<div class="muted">${[if (phone.isNotEmpty) 'Tel: ${_esc(phone)}', if (email.isNotEmpty) _esc(email)].join(' | ')}</div>' : ''}
  <hr>
  <div class="title-box">
    <div class="title">${_esc(title)}</div>
    <div class="chips">
      <span class="chip">Class: ${_esc(className)}${armName != null ? ' - ${_esc(armName)}' : ''}</span>
      <span class="chip">${_esc(term)} | ${_esc(session)}</span>
    </div>
  </div>

  <table>
    <thead><tr><th class="center">S/N</th><th>Fee Item</th><th class="right">Amount (N)</th></tr></thead>
    <tbody>$rows</tbody>
  </table>

  <div class="grand-total">
    <span class="label">GRAND TOTAL</span>
    <span class="value">N${f.format(grandTotal)}</span>
  </div>

  ${bankRows.isEmpty ? '' : '<div class="bank-box"><strong>SCHOOL ACCOUNT DETAILS</strong><br><br>$bankRows</div>'}

  <div class="footer-row">
    <span>Generated: ${_esc(DateFormat('MMMM dd, yyyy').format(now))} at ${_esc(DateFormat('hh:mm a').format(now))}</span>
    <span>New Intake Bill - Bursary Manager</span>
  </div>
</body></html>
''';
  }

  static String _esc(dynamic value) {
    final s = value?.toString() ?? '';
    return s.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;');
  }
}
