import 'package:intl/intl.dart';

/// HTML mirror of AllClassesNewIntakeBillsPDFGenerator, rendered via
/// Android's native WebView print pipeline (see
/// custom_report_pdf_generator.dart). Each class-type section becomes its
/// own page via CSS page-break, matching the original's one-MultiPage-per-
/// section layout.
class AllClassesNewIntakeBillsHtmlGenerator {
  static String build({
    required String term,
    required String session,
    required Map<String, dynamic> schoolProfile,
    required Map<String, List<Map<String, dynamic>>> classesByType,
    required Map<String, Map<String, dynamic>> classArmBills,
    required List<Map<String, dynamic>> categories,
    required List<Map<String, dynamic>> standaloneItems,
    required Map<int, List<Map<String, dynamic>>> childItemsMap,
  }) {
    final currencyFormat = NumberFormat('#,##0.00', 'en_US');
    final schoolName = (schoolProfile['name'] ?? 'School Name').toString();
    final address = (schoolProfile['address'] ?? '').toString();
    final phone = (schoolProfile['phone'] ?? '').toString();
    final email = (schoolProfile['email'] ?? '').toString();

    final accounts = <String>[];
    for (int i = 1; i <= 3; i++) {
      final bankName = (schoolProfile['bankName$i']?.toString() ?? '');
      final accNum = (schoolProfile['accountNumber$i']?.toString() ?? '');
      final accName = (schoolProfile['accountName$i']?.toString() ?? '');
      if (bankName.isNotEmpty && accNum.isNotEmpty) {
        accounts.add('$bankName - $accNum - $accName');
      }
    }
    final bankBox = accounts.isEmpty
        ? ''
        : '<div class="bank-box"><strong>Bank Account Details:</strong>${accounts.map((a) => '<div>${_esc(a)}</div>').join()}</div>';

    final headerHtml = '''
      <h1>${_esc(schoolName.toUpperCase())}</h1>
      ${address.isNotEmpty ? '<div class="muted">${_esc(address)}</div>' : ''}
      ${(phone.isNotEmpty || email.isNotEmpty) ? '<div class="muted">${[if (phone.isNotEmpty) 'Tel: ${_esc(phone)}', if (email.isNotEmpty) _esc(email)].join(' | ')}</div>' : ''}
      <hr>
      <div class="title">NEW INTAKE BILLS SUMMARY - ALL CLASSES</div>
      <div class="period">Term: ${_esc(term)} | Session: ${_esc(session)}</div>
    ''';

    final sections = StringBuffer();
    for (final entry in classesByType.entries) {
      final sectionTitle = entry.key;
      final classes = entry.value;
      if (classes.isEmpty) continue;

      sections.writeln('<div class="page">');
      sections.writeln(headerHtml);
      sections.writeln('<div class="section-title">New Intake Bills for ${_esc(sectionTitle)} Classes</div>');
      sections.writeln(_buildBillsTable(classes, classArmBills, categories, standaloneItems, childItemsMap, currencyFormat));
      sections.writeln(bankBox);
      sections.writeln('<div class="muted footer-note" style="text-align:right;">Generated: ${_esc(DateFormat('dd/MM/yyyy HH:mm').format(DateTime.now()))}</div>');
      sections.writeln('</div>');
    }

    return '''
<!DOCTYPE html><html><head><meta charset="utf-8">
<style>
  @page { size: A4 landscape; margin: 20px; }
  body { font-family: Helvetica, Arial, sans-serif; color: #1a1a1a; font-size: 10px; margin:0; }
  .page { padding: 20px; page-break-after: always; }
  .page:last-child { page-break-after: auto; }
  .center { text-align: center; }
  h1 { font-size: 16px; margin: 0; text-align:center; }
  .muted { color: #616161; text-align:center; font-size: 8px; }
  hr { border: none; border-top: 2px solid #ccc; margin: 8px 0; }
  .title { font-size: 13px; font-weight:bold; text-align:center; margin: 4px 0; }
  .period { font-size: 9px; font-weight:bold; text-align:center; margin-bottom: 8px; }
  .section-title { background:#E0E0E0; border-radius:4px; padding:6px 10px; font-size:12px; font-weight:bold; margin: 8px 0; }
  table { width:100%; border-collapse: collapse; font-size: 8px; margin-bottom: 12px; }
  th, td { border:1px solid #9E9E9E; padding:4px; }
  th { background:#E0E0E0; font-weight:bold; }
  .group-row td { background:#EEEEEE; font-weight:bold; }
  .group-row.other td { background:#FFF3E0; }
  .child-row td.label { padding-left: 12px; }
  .total-row td { background:#E0E0E0; font-weight:bold; font-size:9px; }
  .bank-box { border:1px solid #90CAF9; background:#E3F2FD; border-radius:6px; padding:10px; font-size:9px; margin-top: 8px; }
  .footer-note { margin-top: 8px; }
</style>
</head><body>
$sections
</body></html>
''';
  }

  static String _buildBillsTable(
    List<Map<String, dynamic>> classes,
    Map<String, Map<String, dynamic>> classArmBills,
    List<Map<String, dynamic>> categories,
    List<Map<String, dynamic>> standaloneItems,
    Map<int, List<Map<String, dynamic>>> childItemsMap,
    NumberFormat currencyFormat,
  ) {
    final rows = StringBuffer();

    // Header row
    rows.writeln('<tr><th>Fee Category</th>${classes.map((c) => '<th>${_esc(c['displayName'] ?? '')}</th>').join()}</tr>');

    final classArmRegularTotals = <String, double>{};
    final classArmRegularFees = <String, List<Map<String, dynamic>>>{};
    final classArmStandaloneAmounts = <String, Map<int, double>>{};
    final classArmCategoryChildAmounts = <String, Map<int, Map<int, double>>>{};

    for (final classArm in classes) {
      final classId = classArm['classId'] as int;
      final armId = classArm['armId'] as int?;
      final key = '${classId}_${armId ?? ''}';
      final billData = classArmBills[key] ?? {};

      final regularFees = List<Map<String, dynamic>>.from(billData['regularFees'] ?? []);
      final regularTotal = (billData['regularTotal'] as num?)?.toDouble() ?? 0.0;
      classArmRegularFees[key] = regularFees;
      classArmRegularTotals[key] = regularTotal;

      final specialFees = List<Map<String, dynamic>>.from(billData['specialFees'] ?? []);

      classArmStandaloneAmounts[key] = {};
      for (final standaloneItem in standaloneItems) {
        final itemId = standaloneItem['id'] as int;
        final match = specialFees.firstWhere((fee) => fee['specialFeeItemId'] == itemId, orElse: () => {});
        classArmStandaloneAmounts[key]![itemId] = (match['amount'] as num?)?.toDouble() ?? 0.0;
      }

      classArmCategoryChildAmounts[key] = {};
      for (final category in categories) {
        final categoryId = category['id'] as int;
        classArmCategoryChildAmounts[key]![categoryId] = {};
        final children = childItemsMap[categoryId] ?? [];
        for (final child in children) {
          final childId = child['id'] as int;
          final match = specialFees.firstWhere((fee) => fee['specialFeeItemId'] == childId, orElse: () => {});
          classArmCategoryChildAmounts[key]![categoryId]![childId] = (match['amount'] as num?)?.toDouble() ?? 0.0;
        }
      }
    }

    final allRegularFeeItems = <int, String>{};
    for (final classArm in classes) {
      final classId = classArm['classId'] as int;
      final armId = classArm['armId'] as int?;
      final key = '${classId}_${armId ?? ''}';
      for (final fee in classArmRegularFees[key] ?? []) {
        final feeItemId = fee['feeItemId'] as int;
        allRegularFeeItems.putIfAbsent(feeItemId, () => fee['feeItemName'] ?? 'Unknown');
      }
    }

    final classArmRegularFeeAmounts = <String, Map<int, double>>{};
    for (final classArm in classes) {
      final classId = classArm['classId'] as int;
      final armId = classArm['armId'] as int?;
      final key = '${classId}_${armId ?? ''}';
      classArmRegularFeeAmounts[key] = {};
      for (final fee in classArmRegularFees[key] ?? []) {
        final feeItemId = fee['feeItemId'] as int;
        classArmRegularFeeAmounts[key]![feeItemId] = (fee['amount'] as num?)?.toDouble() ?? 0.0;
      }
    }

    bool hasDefaultBillAmount = classArmRegularTotals.values.any((amount) => amount >= 1.0);
    if (hasDefaultBillAmount && allRegularFeeItems.isNotEmpty) {
      rows.writeln('<tr class="group-row"><td>Default Bill</td>${classes.map((_) => '<td></td>').join()}</tr>');

      for (final entry in allRegularFeeItems.entries) {
        final feeItemId = entry.key;
        final feeItemName = entry.value;
        final hasFeeAmount = classes.any((classArm) {
          final classId = classArm['classId'] as int;
          final armId = classArm['armId'] as int?;
          final key = '${classId}_${armId ?? ''}';
          return (classArmRegularFeeAmounts[key]?[feeItemId] ?? 0.0) >= 1.0;
        });

        if (hasFeeAmount) {
          rows.writeln('<tr class="child-row"><td class="label">-${_esc(feeItemName)}</td>'
              '${classes.map((classArm) {
            final classId = classArm['classId'] as int;
            final armId = classArm['armId'] as int?;
            final key = '${classId}_${armId ?? ''}';
            final amount = classArmRegularFeeAmounts[key]?[feeItemId] ?? 0.0;
            return '<td>N${currencyFormat.format(amount)}</td>';
          }).join()}'
              '</tr>');
        }
      }
    }

    bool hasStandaloneAmount = standaloneItems.any((item) {
      final itemId = item['id'] as int;
      return classes.any((classArm) {
        final classId = classArm['classId'] as int;
        final armId = classArm['armId'] as int?;
        final key = '${classId}_${armId ?? ''}';
        return (classArmStandaloneAmounts[key]?[itemId] ?? 0.0) >= 1.0;
      });
    });

    if (hasStandaloneAmount) {
      rows.writeln('<tr class="group-row other"><td>Other Fees</td>${classes.map((_) => '<td></td>').join()}</tr>');

      for (final standaloneItem in standaloneItems) {
        final itemId = standaloneItem['id'] as int;
        final itemName = standaloneItem['name'] ?? 'Unknown';
        final hasAmount = classes.any((classArm) {
          final classId = classArm['classId'] as int;
          final armId = classArm['armId'] as int?;
          final key = '${classId}_${armId ?? ''}';
          return (classArmStandaloneAmounts[key]?[itemId] ?? 0.0) >= 1.0;
        });

        if (hasAmount) {
          rows.writeln('<tr class="child-row"><td class="label">-${_esc(itemName)}</td>'
              '${classes.map((classArm) {
            final classId = classArm['classId'] as int;
            final armId = classArm['armId'] as int?;
            final key = '${classId}_${armId ?? ''}';
            final amount = classArmStandaloneAmounts[key]?[itemId] ?? 0.0;
            return '<td>N${currencyFormat.format(amount)}</td>';
          }).join()}'
              '</tr>');
        }
      }
    }

    for (final category in categories) {
      final categoryId = category['id'] as int;
      final categoryName = category['name'] ?? 'Unknown Category';
      final children = childItemsMap[categoryId] ?? [];
      if (children.isEmpty) continue;

      final categoryHasAmount = children.any((child) {
        final childId = child['id'] as int;
        return classes.any((classArm) {
          final classId = classArm['classId'] as int;
          final armId = classArm['armId'] as int?;
          final key = '${classId}_${armId ?? ''}';
          return (classArmCategoryChildAmounts[key]?[categoryId]?[childId] ?? 0.0) >= 1.0;
        });
      });
      if (!categoryHasAmount) continue;

      rows.writeln('<tr class="group-row"><td>${_esc(categoryName)}</td>${classes.map((_) => '<td></td>').join()}</tr>');

      for (final child in children) {
        final childId = child['id'] as int;
        final childName = child['name'] ?? 'Unknown';
        final childHasAmount = classes.any((classArm) {
          final classId = classArm['classId'] as int;
          final armId = classArm['armId'] as int?;
          final key = '${classId}_${armId ?? ''}';
          return (classArmCategoryChildAmounts[key]?[categoryId]?[childId] ?? 0.0) >= 1.0;
        });

        if (childHasAmount) {
          rows.writeln('<tr class="child-row"><td class="label">-${_esc(childName)}</td>'
              '${classes.map((classArm) {
            final classId = classArm['classId'] as int;
            final armId = classArm['armId'] as int?;
            final key = '${classId}_${armId ?? ''}';
            final amount = classArmCategoryChildAmounts[key]?[categoryId]?[childId] ?? 0.0;
            return '<td>N${currencyFormat.format(amount)}</td>';
          }).join()}'
              '</tr>');
        }
      }
    }

    rows.writeln('<tr class="total-row"><td>GRAND TOTAL</td>'
        '${classes.map((classArm) {
      final classId = classArm['classId'] as int;
      final armId = classArm['armId'] as int?;
      final key = '${classId}_${armId ?? ''}';
      final billData = classArmBills[key] ?? {};
      final regularTotal = (billData['regularTotal'] as num?)?.toDouble() ?? 0.0;
      final specialTotal = (billData['specialTotal'] as num?)?.toDouble() ?? 0.0;
      return '<td>N${currencyFormat.format(regularTotal + specialTotal)}</td>';
    }).join()}'
        '</tr>');

    return '<table>$rows</table>';
  }

  static String _esc(dynamic value) {
    final s = value?.toString() ?? '';
    return s.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;');
  }
}
